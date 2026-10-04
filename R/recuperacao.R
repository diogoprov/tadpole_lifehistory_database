# Recuperacao: escolhe os trechos que valem uma chamada de modelo.
# Sem isto o pipeline manda o artigo inteiro para o LLM e o custo explode.
# BM25 local, deterministico, sem API.

library(purrr)
library(dplyr)
library(stringr)

tokenizar <- function(x) {
  x |> tolower() |> str_replace_all("[^\\p{L}\\p{N}]+", " ") |>
    str_squish() |> str_split(" ")
}

bm25 <- function(docs, consulta, k1 = 1.2, b = 0.75) {
  toks <- tokenizar(docs)
  dl <- map_int(toks, length)
  avgdl <- mean(dl)
  q <- unique(unlist(tokenizar(consulta)))
  n <- length(toks)
  df <- map_int(q, ~ sum(map_lgl(toks, function(d) .x %in% d)))
  idf <- log(1 + (n - df + 0.5) / (df + 0.5))
  map_dbl(seq_len(n), function(i) {
    tf <- map_int(q, ~ sum(toks[[i]] == .x))
    sum(idf * (tf * (k1 + 1)) / (tf + k1 * (1 - b + b * dl[i] / avgdl)))
  })
}

#' Nomes pelos quais a especie pode aparecer no artigo: o nome aceito da
#' lista-alvo mais os sinonimos que o grupo curou. Nao ha consulta externa.
#' Nome aceito + sinonimos. Sem `obra_id`, so os sinonimos globais; com ele,
#' tambem os que valem so naquela obra (sinonimos.doi_obra = DOI da obra).
aliases_de <- function(con, taxon_id, obra_id = NULL) {
  a <- dbGetQuery(con, sprintf("SELECT especie FROM alvo WHERE taxon_id = '%s'", taxon_id))$especie
  s <- if (is.null(obra_id)) {
    dbGetQuery(con, "SELECT nome_alternativo FROM sinonimos WHERE taxon_id = ? AND doi_obra IS NULL",
               params = list(taxon_id))$nome_alternativo
  } else {
    dbGetQuery(con, "
      SELECT nome_alternativo FROM sinonimos
       WHERE taxon_id = ?
         AND (doi_obra IS NULL OR lower(doi_obra) = (SELECT lower(doi) FROM obras WHERE obra_id = ?))",
      params = list(taxon_id, obra_id))$nome_alternativo
  }
  unique(c(a, s))
}

#' Abreviacao de genero ("H. raniceps") e regra de ouro em taxonomia antiga.
#' O nome entra escapado e a abreviacao so sai de epiteto de verdade.
#' 04/10/2026: o sinonimo "Elachistocleis sp." (Rossa-Feres & Nomura 2006)
#' virava "E\.?\s+sp." - o ponto casava qualquer letra, e "the species" e
#' "the spiracle" passavam a citar E. cesarii em todo trecho da obra.
padrao_especie <- function(nomes) {
  partes <- str_split(nomes, " ")
  abrev <- map_chr(partes, ~ if (length(.x) >= 2 && str_detect(.x[2], "^[a-z-]{3,}$") &&
                                   !.x[2] %in% c("cf", "aff", "sp", "spp"))
    paste0(str_sub(.x[1], 1, 1), "\\.?\\s+", .x[2]) else NA_character_)
  paste0("\\b(", paste(c(str_escape(nomes), na.omit(abrev)), collapse = "|"), ")")
}

#' Quais trechos herdam a especie de um paragrafo anterior.
#'
#' Em monografia, o GROBID separa a ficha da especie: o nome num paragrafo,
#' os caracteres no seguinte, sem o nome. Pezzuti et al. (2021), medido em
#' 02/10/2026:
#'   [Tadpole descriptions / Centrolenidae] "Vitreorana eurygnatha (Fig. 9)
#'      Specimens examined. 10 specimens in stages 28-38 ..."
#'   [Tadpole descriptions / Morphology.]   "... snout rounded ..." (sem nome)
#' 68 de 118 pares (especie, trait) dessa obra ficavam sem nenhum candidato.
#'
#' Regra: um trecho de texto herda a especie do ultimo trecho de texto que a
#' nomeia, ate aparecer outra especie da obra ou passarem `max_herda`
#' trechos. 3 por medida (02/10/2026, pares sem candidato em Pezzuti):
#' 0 -> 68, 3 -> 8, 6 -> 7, 10 -> 6; de 3 para 6 sao +23 chamadas por 1 par.
#' Pura: recebe, na ordem do documento, se cada trecho e texto, se
#' cita a especie e se cita outra; devolve o indice do trecho-ancora (NA =
#' nao herda). Trecho que cita a propria especie nao herda: e candidato direto.
herdar_especie <- function(e_texto, cita, cita_outra, max_herda = 3) {
  ancora <- rep(NA_integer_, length(cita))
  atual <- NA_integer_; passos <- 0L
  for (i in seq_along(cita)) {
    if (!e_texto[i]) next
    if (cita[i]) { atual <- i; passos <- 0L; next }
    if (cita_outra[i]) { atual <- NA_integer_; next }
    if (!is.na(atual)) {
      passos <- passos + 1L
      if (passos <= max_herda) ancora[i] <- atual else atual <- NA_integer_
    }
  }
  ancora
}

#' O titulo da secao ainda vale para o trecho, para UMA especie? Vale da
#' primeira secao que a nomeia ate o primeiro cabecalho de ficha depois dela
#' (`cabecalho`: texto que comeca com nome de especie da obra, ou secao nova
#' que nomeia outra especie). Por especie, e nao por titulo: em Rossa-Feres &
#' Nomura (2006) "Physalaemus centralis" reaparece em secoes separadas por
#' outras fichas (04/10/2026). Pura; tudo na ordem do documento.
secao_vale <- function(cita_secao, cabecalho, ordem) {
  o <- order(ordem)
  cs <- cita_secao[o]; cab <- cabecalho[o]
  vale <- logical(length(ordem))
  if (!any(cs)) return(vale)
  primeiro <- which(cs)[1]
  corte <- which(cab & seq_along(cab) >= primeiro)[1]
  vale[o] <- cs & seq_along(cs) < (if (is.na(corte)) Inf else corte)
  vale
}

#' O texto do trecho comeca com um destes nomes (cabecalho de ficha)? Pura.
comeca_com <- function(texto, nomes) {
  if (!length(nomes)) return(rep(FALSE, length(texto)))
  str_detect(str_squish(texto), regex(paste0("^", padrao_especie(nomes), "(?![[:alpha:]])"), ignore_case = TRUE))
}

#' Linha de chave de identificacao: pontilhado de 10 ou mais pontos, ou de
#' reticencias ("......", corpus da BT 5, 04/10/2026). Pura.
e_chave <- function(texto) str_detect(texto, "(\\.\\s?){10,}|(\u2026\\s?){3,}")

#' Candidatos para um par (obra, taxon, trait): trecho que cita a especie (ou
#' que a herda de um paragrafo anterior - herdar_especie()) e contem algum
#' termo do trait, ordenado por BM25. A coluna `ancora` traz o paragrafo que
#' nomeia a especie quando o trecho a herdou (NA quando o trecho a cita).
recuperar_candidatos <- function(con, obra_id, taxon_id, trait, k = 4) {
  trechos <- dbGetQuery(con, sprintf(
    "SELECT trecho_id, tipo, secao, pagina, idioma, texto, ordem FROM trechos WHERE obra_id = '%s'", obra_id))
  if (nrow(trechos) == 0) return(trechos)

  nomes <- aliases_de(con, taxon_id, obra_id)
  termos <- str_split(trait$termos_busca, ";")[[1]] |> str_trim()
  tem_termo <- function(tx) str_detect(tx, regex(paste(termos, collapse = "|"), ignore_case = TRUE))

  # Ficha da especie lida do PDF (R/fichas.R), quando a obra tem: vai so ela.
  # Medido em 04/10/2026 nos 131 pares conferidos do piloto: a frase com o
  # valor certo estava na ficha em 117, contra 94 nos candidatos do GROBID.
  fichas <- trechos[trechos$tipo == "ficha", ]
  trechos <- trechos[trechos$tipo != "ficha", ]
  propria <- fichas[comeca_com(fichas$secao, nomes) & tem_termo(fichas$texto) & ficha_util(fichas$texto), ]
  if (nrow(propria)) {
    return(propria |>
      mutate(ancora = NA_character_, escore = bm25(texto, paste(c(nomes, termos), collapse = " "))) |>
      arrange(desc(escore)) |>
      head(k))
  }
  if (nrow(trechos) == 0) return(trechos)

  # A especie e procurada no titulo da secao JUNTO com o texto, nao so no
  # texto. Num artigo de descricao de especie o paragrafo diagnostico quase
  # nunca repete o binomio - quem carrega o nome e o cabecalho:
  #
  #   secao: "Description of the tadpole of Scinax catharinae"
  #   texto: "External morphology. (...) Snout rounded in dorsal and lateral
  #           views. Eyes large, dorsally positioned, dorsolaterally directed."
  #
  # Procurando so no texto, esse paragrafo - o unico do artigo que traz os
  # caracteres - era descartado, e sobravam as mencoes de passagem da Discussao.
  # Conferido no TEI real de Conte et al. (2007) em 01/10/2026.
  #
  # Mas o titulo da secao pode ficar velho. Em Santos et al. (2023) e
  # Rossa-Feres & Nomura (2006) o GROBID repete o nome de uma especie como
  # secao por varias fichas seguidas: a ficha de Trachycephalus typhonius fica
  # sob "Scinax squalirostris". Na rodada 3 do piloto, conferida em
  # 04/10/2026, isso mandava ao modelo a ficha vizinha (frase de outra
  # especie) e cortava a heranca da ficha certa (nao achou). Por isso o titulo
  # da secao so vale, para cada especie, ate o proximo cabecalho de ficha
  # (paragrafo que COMECA com nome de especie da obra) - secao_vale().
  outras <- dbGetQuery(con, "SELECT taxon_id FROM obra_taxon WHERE obra_id = ? AND taxon_id <> ?",
                       params = list(obra_id, taxon_id))$taxon_id
  nomes_por_outra <- map(outras, ~ setdiff(aliases_de(con, .x, obra_id), nomes))
  sec <- ifelse(is.na(trechos$secao), "", trechos$secao)
  sem_ordem <- anyNA(trechos$ordem)
  ordem <- if (sem_ordem) seq_len(nrow(trechos)) else trechos$ordem
  inicio <- comeca_com(trechos$texto, c(nomes, unlist(nomes_por_outra)))
  # secao nova (diferente da do trecho anterior) que nomeia esta especie
  sec_nova <- function(hit) { o <- order(ordem); a <- sec[o]; nova <- logical(length(a))
    nova[o] <- hit[o] & a != c("", head(a, -1)); nova }
  sec_hit <- function(nm) str_detect(sec, regex(padrao_especie(nm), ignore_case = TRUE))
  hit_outras <- map(nomes_por_outra, ~ if (length(.x)) sec_hit(.x) else rep(FALSE, nrow(trechos)))
  hit_alvo <- sec_hit(nomes)
  todos_hit <- reduce(hit_outras, `|`, .init = hit_alvo)
  # trecho que cita a especie `nm`: no texto, ou na secao enquanto ela vale
  cita_de <- function(nm, hit_proprio) {
    vale <- if (sem_ordem) hit_proprio
            else secao_vale(hit_proprio, inicio | sec_nova(todos_hit & !hit_proprio), ordem)
    list(texto = str_detect(trechos$texto, regex(padrao_especie(nm), ignore_case = TRUE)), secao = vale)
  }
  ca <- cita_de(nomes, hit_alvo)
  trechos$cita <- ca$texto | ca$secao

  # heranca do nome (herdar_especie()). Trecho sem ordem (gravado antes de
  # 02/10/2026) nao herda: avisa, em vez de perder o par calado.
  trechos$ancora <- NA_character_
  if (sem_ordem) {
    warning("trechos sem ordem na obra ", obra_id, ": rode reestruturar_de_tei()", call. = FALSE)
  } else {
    cita_outra <- reduce(seq_along(nomes_por_outra), function(acc, j) {
      if (!length(nomes_por_outra[[j]])) return(acc)
      co <- cita_de(nomes_por_outra[[j]], hit_outras[[j]])
      acc | co$texto | co$secao
    }, .init = rep(FALSE, nrow(trechos)))
    o <- order(trechos$ordem)
    anc <- herdar_especie(trechos$tipo[o] == "texto", trechos$cita[o], cita_outra[o])
    trechos$ancora[o] <- trechos$texto[o][anc]
  }

  cand <- trechos |>
    filter(cita | !is.na(ancora),
           str_detect(texto, regex(paste(termos, collapse = "|"), ignore_case = TRUE))) |>
    select(-cita)
  # Chave de identificacao (linhas com pontilhado: "eyes lateral ......... 6")
  # so entra se nao houver outro trecho. Ela contrasta especies na mesma
  # linha, e o modelo tirava dela o valor da especie errada: na rodada 3, em
  # Rossa-Feres & Nomura (2006), a chave era o unico candidato de 12 pares, e
  # dela vieram frases de outra especie (conferencia de 04/10/2026).
  chave <- e_chave(cand$texto)
  if (any(!chave)) cand <- cand[!chave, ]

  # Tabela quase sempre carrega o dado sem repetir o nome da especie no corpo
  # do texto: mantemos as tabelas da obra como candidatas de segunda linha.
  if (nrow(cand) == 0) {
    cand <- filter(trechos, tipo == "tabela",
                   str_detect(texto, regex(paste(termos, collapse = "|"), ignore_case = TRUE))) |>
      select(-cita)
  }
  if (nrow(cand) == 0) return(cand)

  cand <- cand |>
    mutate(escore = bm25(texto, paste(c(nomes, termos), collapse = " "))) |>
    arrange(desc(escore))
  # Vaga garantida para tabela que cita a especie. Tabela comparativa repete
  # o nome uma vez (na legenda, as vezes abreviado) e perde no BM25 para
  # mencoes de passagem no texto. Em Conte et al. (2007) a Tabela 3 traz
  # "Snout shape (Lateral)" das 16 especies do grupo, e 26 dos 32 pares da
  # obra ficaram "so planilha" no piloto zero (02/10/2026).
  top <- head(cand, k)
  tab <- filter(cand, tipo == "tabela")
  if (nrow(tab) && !any(top$tipo == "tabela")) top <- bind_rows(head(top, k - 1), head(tab, 1))
  top
}
