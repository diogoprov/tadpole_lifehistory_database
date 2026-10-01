# Busca da literatura: multilingue (item 9), com priorizacao por cobertura
# (item 14) e registro dos negativos (item 10).

library(httr2)
library(purrr)
library(dplyr)

# ---- priorizacao ------------------------------------------------------------

#' Especies com menos traits preenchidos entram primeiro na proxima rodada.
priorizar_taxa <- function(con, n) {
  dbGetQuery(con, "
    SELECT a.taxon_id, a.especie,
           sum(CASE WHEN e.estado IN ('extraido','revisado') THEN 1 ELSE 0 END) AS cobertos,
           sum(CASE WHEN e.estado = 'nao_buscado' THEN 1 ELSE 0 END)            AS pendentes
      FROM alvo a JOIN estado_par e USING (taxon_id)
     GROUP BY 1, 2
     HAVING pendentes > 0
     ORDER BY cobertos ASC, pendentes DESC") |>
    head(n) |>
    as_tibble()
}

# ---- consultas --------------------------------------------------------------

TERMOS_GIRINO <- c(
  pt = "girino OR larva OR \"desenvolvimento larval\"",
  es = "renacuajo OR larva OR \"desarrollo larval\"",
  en = "tadpole OR larva OR \"larval development\""
)

#' Uma consulta por especie x idioma. Os termos do trait vem do dicionario que
#' o grupo ja definiu (coluna termos_busca, separada por ';').
montar_consultas <- function(taxa, traits, idiomas) {
  termos_trait <- traits$termos_busca |>
    strsplit(";") |> unlist() |> trimws() |> unique()
  tidyr::expand_grid(taxon_id = taxa$taxon_id, idioma = idiomas) |>
    left_join(taxa, by = "taxon_id") |>
    mutate(consulta = sprintf('"%s" AND (%s)', especie, TERMOS_GIRINO[idioma]),
           termos_trait = paste(termos_trait, collapse = " OR "))
}

# ---- fontes -----------------------------------------------------------------

req_json <- function(url, query, pausa = 0.2) {
  Sys.sleep(pausa)
  resp <- request(url) |>
    req_url_query(!!!query) |>
    req_user_agent("girinos-traits (pipeline de mobilizacao de traits)") |>
    req_retry(max_tries = 3) |>
    req_perform()
  resp_body_json(resp)
}

buscar_openalex <- function(consulta, idioma, email, max_paginas = 3) {
  cursor <- "*"; saida <- list()
  for (i in seq_len(max_paginas)) {
    js <- req_json("https://api.openalex.org/works", list(
      search = consulta, `per-page` = 200, cursor = cursor, mailto = email))
    res <- js$results %||% list()
    if (length(res) == 0) break
    saida[[i]] <- map_dfr(res, ~ tibble::tibble(
      doi    = sub("^https://doi.org/", "", .x$doi %||% NA_character_),
      titulo = .x$title %||% NA_character_,
      ano    = .x$publication_year %||% NA_integer_,
      idioma = .x$language %||% idioma,
      url_pdf = .x$best_oa_location$pdf_url %||% NA_character_,
      fonte  = "openalex"))
    cursor <- js$meta$next_cursor %||% NA_character_
    if (is.na(cursor)) break
  }
  bind_rows(saida)
}

buscar_crossref <- function(consulta, email) {
  js <- req_json("https://api.crossref.org/works", list(
    query.bibliographic = consulta, rows = 100, mailto = email))
  map_dfr(js$message$items %||% list(), ~ tibble::tibble(
    doi    = .x$DOI %||% NA_character_,
    titulo = (.x$title %||% list(NA_character_))[[1]],
    ano    = (.x$issued$`date-parts`[[1]] %||% list(NA_integer_))[[1]],
    idioma = .x$language %||% NA_character_,
    url_pdf = NA_character_,
    fonte  = "crossref"))
}

#' BHL: literatura antiga, muitas vezes a unica descricao existente.
#' ATENCAO: confira op/parametros na documentacao corrente da API v3 antes de
#' ligar esta fonte; a chamada abaixo segue o formato api3?op=...&apikey=...
buscar_bhl <- function(consulta, chave) {
  if (!nzchar(chave)) return(tibble::tibble())
  js <- req_json("https://www.biodiversitylibrary.org/api3", list(
    op = "PublicationSearch", searchterm = consulta, searchtype = "F",
    apikey = chave, format = "json"))
  map_dfr(js$Result %||% list(), ~ tibble::tibble(
    doi = NA_character_, titulo = .x$Title %||% NA_character_,
    ano = suppressWarnings(as.integer(.x$Date %||% NA)),
    idioma = NA_character_, url_pdf = .x$ItemUrl %||% NA_character_,
    fonte = "bhl"))
}

# ---- execucao ---------------------------------------------------------------

#' Roda todas as fontes para um lote de consultas, grava obras + busca_log e
#' marca os pares buscados. Retorna as obras novas.
executar_busca <- function(con, consultas, cfg) {
  resultados <- pmap(consultas, function(taxon_id, idioma, especie, consulta,
                                         termos_trait, ...) {
    q <- paste(consulta, "AND", paste0("(", termos_trait, ")"))
    obras <- bind_rows(
      buscar_openalex(q, idioma, cfg$email),
      buscar_crossref(q, cfg$email),
      buscar_bhl(q, cfg$bhl_key)
    )
    registrar(con, "busca_log", tibble::tibble(
      busca_id = id_de(taxon_id, idioma, q), taxon_id = taxon_id,
      fonte = "openalex+crossref+bhl", idioma = idioma, consulta = q,
      data = Sys.time(), n_resultados = nrow(obras)))
    if (nrow(obras) == 0) return(tibble::tibble())
    obras |> mutate(taxon_id = taxon_id)
  })

  obras <- bind_rows(resultados)
  if (nrow(obras) == 0) return(obras)

  obras <- obras |>
    mutate(chave = coalesce(doi, tolower(titulo))) |>
    filter(!is.na(chave)) |>
    distinct(chave, .keep_all = TRUE) |>
    mutate(obra_id = map_chr(chave, id_de),
           url_suplementar = NA_character_, caminho_pdf = NA_character_,
           ocr = FALSE, status = "encontrada")

  registrar(con, "obras", select(obras, obra_id, doi, titulo, ano, idioma,
                                 fonte, url_pdf, url_suplementar,
                                 caminho_pdf, ocr, status))
  obras
}

#' Item 10: depois de buscar, todo par que continuou sem extracao vira
#' 'buscado_sem_dado'. E o que separa ausencia de dado de ausencia de busca.
fechar_rodada <- function(con) {
  dbExecute(con, "
    UPDATE estado_par SET estado = 'buscado_sem_dado', data_atualizacao = now()
     WHERE estado = 'nao_buscado'
       AND taxon_id IN (SELECT DISTINCT taxon_id FROM busca_log)")
}
