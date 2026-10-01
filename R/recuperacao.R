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
aliases_de <- function(con, taxon_id) {
  a <- dbGetQuery(con, sprintf("SELECT especie FROM alvo WHERE taxon_id = '%s'", taxon_id))$especie
  s <- dbGetQuery(con, sprintf("SELECT nome_alternativo FROM sinonimos WHERE taxon_id = '%s'", taxon_id))$nome_alternativo
  c(a, s)
}

#' Abreviacao de genero ("H. raniceps") e regra de ouro em taxonomia antiga.
padrao_especie <- function(nomes) {
  partes <- str_split(nomes, " ")
  abrev <- map_chr(partes, ~ if (length(.x) >= 2)
    paste0(str_sub(.x[1], 1, 1), "\\.?\\s+", .x[2]) else .x[1])
  paste0("(", paste(c(nomes, abrev), collapse = "|"), ")")
}

#' Candidatos para um par (obra, taxon, trait): trecho que cita a especie e
#' contem algum termo do trait, ordenado por BM25.
recuperar_candidatos <- function(con, obra_id, taxon_id, trait, k = 4) {
  trechos <- dbGetQuery(con, sprintf(
    "SELECT trecho_id, tipo, secao, pagina, idioma, texto FROM trechos WHERE obra_id = '%s'", obra_id))
  if (nrow(trechos) == 0) return(trechos)

  nomes <- aliases_de(con, taxon_id)
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

  cand <- trechos |>
    filter(str_detect(onde, regex(padrao_especie(nomes), ignore_case = TRUE)),
           str_detect(texto, regex(paste(termos, collapse = "|"), ignore_case = TRUE)))

  # Tabela quase sempre carrega o dado sem repetir o nome da especie no corpo
  # do texto: mantemos as tabelas da obra como candidatas de segunda linha.
  if (nrow(cand) == 0) {
    cand <- filter(trechos, tipo == "tabela",
                   str_detect(texto, regex(paste(termos, collapse = "|"), ignore_case = TRUE)))
  }
  if (nrow(cand) == 0) return(cand)

  cand |>
    mutate(escore = bm25(texto, paste(c(nomes, termos), collapse = " "))) |>
    arrange(desc(escore)) |>
    head(k)
}
