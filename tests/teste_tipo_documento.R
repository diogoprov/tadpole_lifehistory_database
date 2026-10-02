# Teste da deteccao de poster pela URL da pagina.
#
# Projeto carregado de verdade, banco DuckDB temporario. As APIs sao
# substituidas por respostas fixas, entao roda sem rede.
#
#   Rscript tests/teste_tipo_documento.R
#
# O caso (P. barrioi, 01/10/2026): o poster do F1000Research (2011) chega da
# OpenAlex como type "article" de periodico, e virava fonte primaria no lugar
# da redescricao na Copeia (2012). Poster nunca e fonte primaria (decisao do
# Diogo), e o tipo sai da URL da pagina: https://f1000research.com/posters/853.
# Antes a busca nem guardava essa URL.

if (!dir.exists("R") && dir.exists("../R")) setwd("..")
faltam <- c("duckdb", "ellmer", "config")[!vapply(c("duckdb", "ellmer", "config"),
                                                   requireNamespace, logical(1), quietly = TRUE)]
if (length(faltam)) {
  cat("\n(pulado: faltam os pacotes", paste(faltam, collapse = ", "), ")\n\n"); quit(status = 0)
}
suppressMessages(suppressWarnings({
  source("R/carregar.R"); carregar_projeto("R")
}))

falhas <- 0L
checar <- function(descricao, condicao) {
  cat(if (isTRUE(condicao)) "  ok   " else "  FALHA", descricao, "\n")
  if (!isTRUE(condicao)) falhas <<- falhas + 1L
  invisible(condicao)
}

URL_POSTER <- "https://f1000research.com/posters/853"
DOI_POSTER <- "10.7490/f1000research.853.1"
DOI_ARTIGO <- "10.1643/ch-10-142"

# ---------------------------------------------------------------------------
cat("\ntipo_documento_por_url()\n")
checar("a pagina do poster de P. barrioi e poster",
       identical(tipo_documento_por_url(URL_POSTER), "poster"))
checar("http e www tambem",
       identical(tipo_documento_por_url("http://www.f1000research.com/posters/1"), "poster"))
checar("artigo do F1000Research nao e poster",
       is.na(tipo_documento_por_url("https://f1000research.com/articles/5-123")))
checar("'posters' em outro site nao basta",
       is.na(tipo_documento_por_url("https://example.org/posters/9")))
checar("URL ausente da NA", is.na(tipo_documento_por_url(NA_character_)))
checar("slides do F1000 sao resumo de congresso",
       identical(tipo_documento_por_url("https://f1000research.com/slides/15-957"), "resumo_congresso"))
checar("documents do F1000 sao resumo de congresso",
       identical(tipo_documento_por_url("https://f1000research.com/documents/15-992"), "resumo_congresso"))
checar("todo tipo detectado pela URL e um tipo que nunca e primario",
       all(names(PADROES_URL_TIPO) %in% TIPOS_NUNCA_PRIMARIOS))

# ---------------------------------------------------------------------------
cat("\nbuscar_openalex() guarda a URL da pagina\n")
oa_poster <- list(
  doi = paste0("https://doi.org/", DOI_POSTER),
  title = "Description of the tadpole and advertisement call of Physalaemus barrioi",
  publication_year = 2011L, language = "en", type = "article",
  primary_location = list(landing_page_url = URL_POSTER,
                          source = list(display_name = "F1000Research", type = "journal")),
  best_oa_location = NULL, abstract_inverted_index = NULL)
oa_artigo <- list(
  doi = paste0("https://doi.org/", DOI_ARTIGO),
  title = "Redescription of Physalaemus barrioi (Anura: Leiuperidae)",
  publication_year = 2012L, language = "en", type = "article",
  primary_location = list(landing_page_url = "https://doi.org/10.1643/CH-10-142"),
  best_oa_location = NULL, abstract_inverted_index = NULL)
req_json <- function(url, query, pausa = 0) {
  if (grepl("openalex", url)) list(results = list(oa_poster, oa_artigo), meta = list(next_cursor = NULL))
  else list(message = list(items = list()))
}
r <- buscar_openalex("x", "en", "x@y", max_paginas = 1)
checar("coluna url_pagina presente", "url_pagina" %in% names(r))
checar("a URL do poster vem do primary_location",
       identical(r$url_pagina[r$doi == DOI_POSTER], URL_POSTER))

# ---------------------------------------------------------------------------
cat("\nexecutar_busca() marca o poster, e a fonte primaria fica com o artigo\n")
arq <- tempfile(fileext = ".duckdb")
con <- suppressMessages(abrir_db(arq))
checar("coluna url_pagina entra por ALTER idempotente",
       { criar_esquema(con); "url_pagina" %in% DBI::dbListFields(con, "obras") })
registrar(con, "alvo", tibble::tibble(taxon_id = "TB", especie = "Physalaemus barrioi"))
cfg <- list(email = "x@y", bhl_key = "")
consultas <- tibble::tibble(taxon_id = "TB", idioma = "en", especie = "Physalaemus barrioi",
                            consulta = '"Physalaemus barrioi"')
obras <- suppressMessages(executar_busca(con, consultas, cfg))
tipos <- DBI::dbGetQuery(con, "SELECT doi, url_pagina, tipo_documento FROM obras")
checar("a URL foi gravada", identical(tipos$url_pagina[tipos$doi == DOI_POSTER], URL_POSTER))
checar("o poster foi marcado como poster",
       identical(tipos$tipo_documento[tipos$doi == DOI_POSTER], "poster"))
checar("o artigo ficou sem tipo", is.na(tipos$tipo_documento[tipos$doi == DOI_ARTIGO]))

id_poster <- obras$obra_id[obras$doi == DOI_POSTER]
id_artigo <- obras$obra_id[obras$doi == DOI_ARTIGO]
DBI::dbAppendTable(con, "extracoes", data.frame(
  extracao_id = c("x_poster", "x_artigo"), obra_id = c(id_poster, id_artigo),
  taxon_id = "TB", trait_id = "snout_shape_lv", valor_cat = "rounded",
  span_verbatim = c("Focinho arredondado, aparato oral anteroventral.",
                    "Snout rounded in dorsal and lateral views."),
  status = "bruto"))
invisible(marcar_fonte_secundaria(con))
fp <- DBI::dbGetQuery(con, "SELECT extracao_id, origem_valor, fonte_primaria_doi FROM extracoes")
checar("de ponta a ponta: o artigo de 2012 e primario",
       fp$origem_valor[fp$extracao_id == "x_artigo"] == "primaria")
checar("de ponta a ponta: o poster de 2011 e secundario e aponta para o artigo",
       fp$origem_valor[fp$extracao_id == "x_poster"] == "secundaria" &&
         identical(fp$fonte_primaria_doi[fp$extracao_id == "x_poster"], DOI_ARTIGO))

cat("\na marca manual tem precedencia\n")
marcar_tipo_documento(con, id_artigo, "resumo_congresso")
invisible(suppressMessages(executar_busca(con, consultas, cfg)))
checar("busca de novo nao apaga a marca manual",
       identical(DBI::dbGetQuery(con, sprintf(
         "SELECT tipo_documento FROM obras WHERE obra_id = '%s'", id_artigo))[[1]], "resumo_congresso"))
marcar_tipo_documento(con, id_poster, NA_character_)
invisible(DBI::dbExecute(con, sprintf("UPDATE obras SET url_pagina = NULL WHERE obra_id = '%s'", id_poster)))

# ---------------------------------------------------------------------------
cat("\npreencher_url_pagina(): obras gravadas antes de a busca guardar a URL\n")
invisible(DBI::dbExecute(con, "UPDATE obras SET url_pagina = NULL"))
registrar(con, "obras", tibble::tibble(obra_id = "semoa", doi = "10.0/naoexiste", titulo = "x"))
chamadas <- character()
mock <- function(req) {
  chamadas <<- c(chamadas, req$url)
  if (grepl("naoexiste", req$url, fixed = TRUE)) return(httr2::response(status_code = 404))
  url <- if (grepl("f1000research", req$url, fixed = TRUE)) URL_POSTER else "https://doi.org/10.1643/CH-10-142"
  httr2::response_json(body = list(primary_location = list(landing_page_url = url)))
}
httr2::with_mocked_responses(mock, suppressMessages(preencher_url_pagina(con, "x@y", pausa = 0)))
p <- DBI::dbGetQuery(con, "SELECT obra_id, url_pagina, tipo_documento FROM obras")
checar("uma consulta por obra com DOI", length(chamadas) == 3)
checar("a URL do poster foi preenchida", identical(p$url_pagina[p$obra_id == id_poster], URL_POSTER))
checar("e o poster foi marcado", identical(p$tipo_documento[p$obra_id == id_poster], "poster"))
checar("DOI que a OpenAlex nao conhece (404) fica sem URL, sem parar",
       is.na(p$url_pagina[p$obra_id == "semoa"]))

mock_500 <- function(req) httr2::response(status_code = 500)
err <- try(httr2::with_mocked_responses(mock_500, suppressMessages(
  preencher_url_pagina(con, "x@y", pausa = 0))), silent = TRUE)
checar("erro de API para (nao vira 'sem URL')", inherits(err, "try-error"))

DBI::dbDisconnect(con, shutdown = TRUE); unlink(arq)

cat(if (falhas == 0) "\ntodos os testes passaram\n\n" else sprintf("\n%d FALHA(S)\n\n", falhas))
quit(status = if (falhas == 0) 0 else 1)
