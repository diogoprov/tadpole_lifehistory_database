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
padrao_especie <- function(nomes) {
  partes <- str_split(nomes, " ")
  abrev <- map_chr(partes, ~ if (length(.x) >= 2)
    paste0(str_sub(.x[1], 1, 1), "\\.?\\s+", .x[2]) else .x[1])
  paste0("(", paste(c(nomes, abrev), collapse = "|"), ")")
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
  onde <- paste(ifelse(is.na(trechos$secao), "", trechos$secao), trechos$texto)
  trechos$cita <- str_detect(onde, regex(padrao_especie(nomes), ignore_case = TRUE))

  # heranca do nome (herdar_especie()). Trecho sem ordem (gravado antes de
  # 02/10/2026) nao herda: avisa, em vez de perder o par calado.
  trechos$ancora <- NA_character_
  if (anyNA(trechos$ordem)) {
    warning("trechos sem ordem na obra ", obra_id, ": rode reestruturar_de_tei()", call. = FALSE)
  } else {
    outras <- dbGetQuery(con, "SELECT taxon_id FROM obra_taxon WHERE obra_id = ? AND taxon_id <> ?",
                         params = list(obra_id, taxon_id))$taxon_id
    nomes_outras <- setdiff(unlist(map(outras, ~ aliases_de(con, .x, obra_id))), nomes)
    cita_outra <- if (length(nomes_outras)) {
      str_detect(onde, regex(padrao_especie(nomes_outras), ignore_case = TRUE))
    } else rep(FALSE, nrow(trechos))
    o <- order(trechos$ordem)
    anc <- herdar_especie(trechos$tipo[o] == "texto", trechos$cita[o], cita_outra[o])
    trechos$ancora[o] <- trechos$texto[o][anc]
  }

  cand <- trechos |>
    filter(cita | !is.na(ancora),
           str_detect(texto, regex(paste(termos, collapse = "|"), ignore_case = TRUE))) |>
    select(-cita)

  # Tabela quase sempre carrega o dado sem repetir o nome da especie no corpo
  # do texto: mantemos as tabelas da obra como candidatas de segunda linha.
  if (nrow(cand) == 0) {
    cand <- filter(trechos, tipo == "tabela",
                   str_detect(texto, regex(paste(termos, collapse = "|"), ignore_case = TRUE))) |>
      select(-cita)
  }
  if (nrow(cand) == 0) return(cand)

  cand |>
    mutate(escore = bm25(texto, paste(c(nomes, termos), collapse = " "))) |>
    arrange(desc(escore)) |>
    head(k)
}
