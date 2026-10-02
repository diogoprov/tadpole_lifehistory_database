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

#' Uma consulta por especie x idioma: o binomio mais os termos de girino, e
#' nada mais.
#'
#' Os `termos_busca` do trait NAO entram aqui, e isso foi medido, nao suposto.
#' Em 01/10/2026 testei a consulta antiga contra a OpenAlex: com a terceira
#' clausula AND dos 33 termos anatomicos ela devolve ZERO resultados para
#' Physalaemus barrioi; sem ela, devolve 23, e o primeiro e exatamente
#' "Redescription of Physalaemus barrioi". Com dois termos so ela devolve 7,
#' e o artigo certo nao esta entre eles. Uma virgula dentro de um termo
#' ("focinho, vista lateral") tambem zera a busca.
#'
#' A razao e conceitual, nao de sintaxe: termo de trait serve para achar o
#' PARAGRAFO dentro do PDF (recuperar_candidatos()), nao para achar o ARTIGO.
#' Um artigo que descreve o girino da especie e relevante mesmo que o resumo
#' nao diga "snout" - e resumo de artigo de descricao quase nunca diz. Quem
#' decide relevancia e triar_obras(), que le titulo, periodico e ano.
montar_consultas <- function(taxa, idiomas) {
  tidyr::expand_grid(taxon_id = taxa$taxon_id, idioma = idiomas) |>
    left_join(taxa, by = "taxon_id") |>
    mutate(consulta = sprintf('"%s" AND (%s)', especie, TERMOS_GIRINO[idioma]))
}

# ---- tipos de registro aceitos -----------------------------------------------
#
# Lista do que ENTRA, nao do que sai. Um tipo novo que a API passe a usar fica
# de fora ate alguem decidir incluir - o erro barato e perder um registro de
# tipo estranho, nao pagar triagem por ele.
#
# Por que filtrar na API e nao deixar para a triagem: cada registro que chega
# custa uma chamada de triagem. Em 01/10/2026, para Physalaemus barrioi, 4 dos
# 8 primeiros resultados do Crossref eram `dataset` - projetos do MorphoBank
# (10.7934/p544, p725, p840) e fichas da IUCN Red List (10.2305/iucn...). Um
# deles tem o MESMO titulo do artigo ("Redescription of Physalaemus barrioi"),
# entao nem a triagem por titulo separaria com seguranca.
#
# Vocabularios conferidos nos endpoints /types de cada API em 01/10/2026.
# Ficaram de fora de proposito: anais de congresso (conference-paper,
# proceedings-article), verbetes (reference-entry), data papers, e tudo que e
# metadado de publicacao (errata, editorial, peer-review, component...).
TIPOS_OPENALEX <- c("article", "review", "book", "book-chapter",
                    "dissertation", "preprint", "report")
TIPOS_CROSSREF <- c("journal-article", "book", "book-chapter", "book-part",
                    "book-section", "edited-book", "monograph",
                    "dissertation", "posted-content", "report")

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
      search = consulta, `per-page` = 200, cursor = cursor, mailto = email,
      filter = paste0("type:", paste(TIPOS_OPENALEX, collapse = "|"))))
    res <- js$results %||% list()
    if (length(res) == 0) break
    saida[[i]] <- map_dfr(res, ~ tibble::tibble(
      doi    = sub("^https://doi.org/", "", .x$doi %||% NA_character_),
      titulo = .x$title %||% NA_character_,
      ano    = .x$publication_year %||% NA_integer_,
      idioma = .x$language %||% idioma,
      url_pdf = .x$best_oa_location$pdf_url %||% NA_character_,
      url_pagina = .x$primary_location$landing_page_url %||% NA_character_,
      resumo = resumo_openalex(.x$abstract_inverted_index),
      fonte  = "openalex"))
    cursor <- js$meta$next_cursor %||% NA_character_
    if (is.na(cursor)) break
  }
  bind_rows(saida)
}

buscar_crossref <- function(consulta, email) {
  js <- req_json("https://api.crossref.org/works", list(
    query.bibliographic = consulta, rows = 100, mailto = email,
    filter = paste0("type:", TIPOS_CROSSREF, collapse = ",")))
  map_dfr(js$message$items %||% list(), ~ tibble::tibble(
    doi    = .x$DOI %||% NA_character_,
    titulo = (.x$title %||% list(NA_character_))[[1]],
    ano    = (.x$issued$`date-parts`[[1]] %||% list(NA_integer_))[[1]],
    idioma = .x$language %||% NA_character_,
    url_pdf = NA_character_,
    url_pagina = .x$resource$primary$URL %||% NA_character_,
    resumo = limpar_resumo(.x$abstract %||% NA_character_),
    fonte  = "crossref"))
}

#' A OpenAlex nao devolve o resumo como texto, e sim como indice invertido
#' (palavra -> posicoes), por questao de licenca. Remontar e so ordenar as
#' palavras pela posicao.
resumo_openalex <- function(inv) {
  if (is.null(inv) || length(inv) == 0) return(NA_character_)
  pos <- unlist(inv, use.names = FALSE)
  palavra <- rep(names(inv), lengths(inv))
  paste(palavra[order(pos)], collapse = " ")
}

#' O Crossref, quando tem resumo, manda em JATS XML (<jats:p>...</jats:p>).
limpar_resumo <- function(x) {
  if (is.null(x) || length(x) == 0 || is.na(x)) return(NA_character_)
  x <- stringr::str_squish(stringr::str_replace_all(x, "<[^>]+>", " "))
  if (nzchar(x)) x else NA_character_
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
    url_pagina = NA_character_, resumo = NA_character_, fonte = "bhl"))
}

# ---- execucao ---------------------------------------------------------------

#' Roda todas as fontes para um lote de consultas, grava obras + busca_log e
#' marca os pares buscados. Retorna as obras novas.
#' O titulo cita a especie (nome aceito ou sinonimo, por extenso ou com o
#' genero abreviado)? Tags HTML saem antes: o Crossref devolve titulos como
#' "<i>Physalaemus</i> <i>barrioi</i>", e o binomio partido nao casaria.
titulo_cita_especie <- function(titulos, nomes) {
  limpo <- titulos |>
    stringr::str_replace_all("<[^>]+>", " ") |>
    stringr::str_squish()
  padrao <- paste0("\\b", padrao_especie(nomes), "\\b")
  stringr::str_detect(dplyr::coalesce(limpo, ""),
                      stringr::regex(padrao, ignore_case = TRUE))
}

executar_busca <- function(con, consultas, cfg) {
  resultados <- pmap(consultas, function(taxon_id, idioma, especie, consulta, ...) {
    q <- consulta
    # O Crossref so entra se o TITULO citar a especie. Ele ignora os operadores
    # booleanos e ranqueia por palavra solta sobre titulo, autor e periodico -
    # nao le resumo nem texto. Entao um registro sem o binomio no titulo nao
    # tem evidencia nenhuma de ser sobre a especie: so bateu em "Physalaemus"
    # OU em "tadpole". Medido em 01/10/2026 para P. barrioi: das 195 obras do
    # Crossref (ja filtradas por tipo), 1 cita o binomio no titulo - e e o
    # artigo certo, 10.1643/ch-10-142. As outras 194 sao girinos de outras
    # especies, que a triagem (que nao sabe a especie-alvo) aprovaria e o
    # obra_taxon ligaria a P. barrioi.
    #
    # Binomio, nao so epiteto: "barrioi" sozinho deixaria passar Leptodactylus
    # barrioi e Apostolepis barrioi (uma serpente).
    #
    # A OpenAlex NAO passa por este filtro: ela casa a frase exata no resumo e
    # no texto, e por isso traz com razao obras sem o nome no titulo (listas
    # faunisticas, descricoes de especies proximas que comparam com esta).
    cr <- buscar_crossref(q, cfg$email)
    if (nrow(cr) > 0) cr <- cr[titulo_cita_especie(cr$titulo, aliases_de(con, taxon_id)), ]
    obras <- bind_rows(
      buscar_openalex(q, idioma, cfg$email),
      cr,
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
    mutate(obra_id = map_chr(chave, id_de))

  # A ligacao obra -> taxon sai ANTES do distinct: a mesma obra pode ter sido
  # achada para mais de uma especie (artigo de genero, revisao, lista
  # faunistica), e deduplicar por obra_id apagaria todos os vinculos menos um.
  registrar(con, "obra_taxon",
            distinct(obras, obra_id, taxon_id) |> mutate(fonte = "busca"))

  # O distinct fica com a PRIMEIRA ocorrencia, e ela pode ser do Crossref, que
  # quase nunca tem resumo, enquanto a OpenAlex trouxe o mesmo artigo com
  # resumo (foi o caso da redescricao de P. barrioi: a consulta em portugues
  # achou primeiro no Crossref). Entao o resumo vem de qualquer ocorrencia.
  obras <- obras |>
    group_by(obra_id) |>
    mutate(resumo = { r <- resumo[!is.na(resumo)]; if (length(r)) r[1] else NA_character_ },
           url_pagina = { u <- url_pagina[!is.na(url_pagina)]; if (length(u)) u[1] else NA_character_ }) |>
    ungroup() |>
    distinct(obra_id, .keep_all = TRUE) |>
    mutate(url_suplementar = NA_character_, caminho_pdf = NA_character_,
           ocr = FALSE, status = "encontrada")

  registrar(con, "obras", select(obras, obra_id, doi, titulo, ano, idioma,
                                 fonte, url_pdf, url_suplementar,
                                 caminho_pdf, ocr, status, resumo, url_pagina))
  marcar_tipo_por_url(con)
  obras
}

# ---- tipo de documento pela URL da pagina -----------------------------------
#
# Decisao do Diogo (01/10/2026): poster e resumo de congresso nunca sao fonte
# primaria, e o tipo e detectado pela URL. Os metadados nao servem: a OpenAlex
# classifica o poster de P. barrioi no F1000Research como type "article" de
# periodico, e o DOI dele (10.7490/f1000research.853.1) da 404. So a pagina diz
# que e poster: https://f1000research.com/posters/853.
#
# Lista do que se conferiu, nao um palpite geral: "/posters/" solto pegaria
# qualquer site que use a palavra no caminho. Padrao novo entra quando aparecer
# um caso conferido na pagina da editora.
#
# /slides/ e /documents/ do F1000 (apresentacoes e documentos de congresso, no
# mesmo prefixo de DOI 10.7490 dos posteres) contam como resumo de congresso:
# decisao do Diogo, 01/10/2026. Paginas conferidas no mesmo dia:
# f1000research.com/slides/15-957 e f1000research.com/documents/15-992.
PADROES_URL_TIPO <- c(
  poster           = "^https?://(www\\.)?f1000research\\.com/posters/",
  resumo_congresso = "^https?://(www\\.)?f1000research\\.com/(slides|documents)/"
)

#' Tipo de documento pela URL da pagina, ou NA se nenhum padrao casa.
tipo_documento_por_url <- function(urls) {
  map_chr(urls, function(u) {
    if (is.na(u)) return(NA_character_)
    casa <- names(PADROES_URL_TIPO)[stringr::str_detect(u, stringr::regex(PADROES_URL_TIPO, ignore_case = TRUE))]
    if (length(casa)) casa[1] else NA_character_
  })
}

#' Marca tipo_documento das obras cuja URL casa com um padrao. So preenche o
#' que esta vazio: a marca manual (marcar_tipo_documento()) tem precedencia.
marcar_tipo_por_url <- function(con) {
  o <- dbGetQuery(con, "
    SELECT obra_id, url_pagina FROM obras
     WHERE tipo_documento IS NULL AND url_pagina IS NOT NULL")
  if (nrow(o) == 0) return(invisible(0L))
  o$tipo <- tipo_documento_por_url(o$url_pagina)
  o <- o[!is.na(o$tipo), ]
  walk2(o$obra_id, o$tipo, ~ dbExecute(con,
    "UPDATE obras SET tipo_documento = ? WHERE obra_id = ?", params = list(.y, .x)))
  if (nrow(o)) message("tipo_documento pela URL: ", paste(o$obra_id, o$tipo, sep = "=", collapse = ", "))
  invisible(nrow(o))
}

#' Preenche url_pagina das obras registradas antes de a busca guardar a URL,
#' pela OpenAlex (por DOI; gratis, sem modelo), e roda marcar_tipo_por_url().
#' Obra sem DOI fica sem URL: o id da OpenAlex nao foi guardado.
#' DOI que a OpenAlex nao conhece (404) fica sem URL; outro erro para.
preencher_url_pagina <- function(con, email, pausa = 1) {
  o <- dbGetQuery(con, "SELECT obra_id, doi FROM obras WHERE url_pagina IS NULL AND doi IS NOT NULL")
  if (nrow(o) == 0) return(invisible(tibble::tibble()))
  o$url_pagina <- map_chr(o$doi, function(doi) {
    Sys.sleep(pausa)
    resp <- request(paste0("https://api.openalex.org/works/doi:", doi)) |>
      req_url_query(select = "primary_location", mailto = email) |>
      req_user_agent("girinos-traits (pipeline de mobilizacao de traits)") |>
      req_retry(max_tries = 3) |>
      req_error(is_error = function(r) resp_status(r) >= 400 && resp_status(r) != 404) |>
      req_perform()
    if (resp_status(resp) == 404) return(NA_character_)
    resp_body_json(resp)$primary_location$landing_page_url %||% NA_character_
  })
  com_url <- o[!is.na(o$url_pagina), ]
  walk2(com_url$obra_id, com_url$url_pagina, ~ dbExecute(con,
    "UPDATE obras SET url_pagina = ? WHERE obra_id = ?", params = list(.y, .x)))
  marcar_tipo_por_url(con)
  invisible(o)
}

#' Item 10: depois de buscar, todo par que continuou sem extracao vira
#' 'buscado_sem_dado'. E o que separa ausencia de dado de ausencia de busca.
fechar_rodada <- function(con) {
  dbExecute(con, "
    UPDATE estado_par SET estado = 'buscado_sem_dado', data_atualizacao = now()
     WHERE estado = 'nao_buscado'
       AND taxon_id IN (SELECT DISTINCT taxon_id FROM busca_log)")
}
