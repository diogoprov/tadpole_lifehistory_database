# Estruturacao: PDF -> TEI (GROBID) -> trechos.
# Texto corrido, tabelas e legendas viram tipos distintos de trecho (item 6).
# O idioma e detectado e guardado; a extracao roda no idioma original (item 9).

library(xml2)
library(purrr)
library(dplyr)

TEI_NS <- c(tei = "http://www.tei-c.org/ns/1.0")

grobid_tei <- function(pdf, servidor, destino) {
  resp <- httr2::request(paste0(servidor, "/api/processFulltextDocument")) |>
    httr2::req_body_multipart(
      input = curl::form_file(pdf),
      consolidateHeader = "1",
      segmentSentences = "1") |>
    httr2::req_timeout(300) |>
    httr2::req_perform()
  writeBin(httr2::resp_body_raw(resp), destino)
  destino
}

detectar_idioma <- function(txt) {
  if (!requireNamespace("cld3", quietly = TRUE)) return(NA_character_)
  cld3::detect_language(substr(txt, 1, 5000))
}

#' TEI -> data frame de trechos. Paragrafo e a unidade de texto; cada tabela
#' (conteudo + legenda) e um trecho unico, para a tabela nao ser picada.
tei_para_trechos <- function(tei_path, obra_id) {
  doc <- read_xml(tei_path)

  paragrafos <- xml_find_all(doc, "//tei:body//tei:div", TEI_NS) |>
    map_dfr(function(div) {
      secao <- xml_text(xml_find_first(div, "./tei:head", TEI_NS))
      xml_find_all(div, "./tei:p", TEI_NS) |>
        map_chr(xml_text) |>
        (\(p) tibble::tibble(tipo = "texto", secao = secao %||% NA_character_,
                             texto = p))()
    })

  tabelas <- xml_find_all(doc, "//tei:figure[@type='table']", TEI_NS) |>
    map_dfr(~ tibble::tibble(
      tipo = "tabela",
      secao = xml_text(xml_find_first(.x, ".//tei:head", TEI_NS)) %||% NA_character_,
      texto = paste(xml_text(xml_find_first(.x, ".//tei:figDesc", TEI_NS)) %||% "",
                    xml_text(.x))))

  legendas <- xml_find_all(doc, "//tei:figure[not(@type='table')]//tei:figDesc", TEI_NS) |>
    map_dfr(~ tibble::tibble(tipo = "legenda", secao = NA_character_,
                             texto = xml_text(.x)))

  bind_rows(paragrafos, tabelas, legendas) |>
    filter(!is.na(texto), nchar(texto) > 40) |>
    mutate(obra_id = obra_id,
           pagina = NA_integer_,
           idioma = map_chr(texto, detectar_idioma),
           trecho_id = map2_chr(obra_id, texto, id_de)) |>
    select(trecho_id, obra_id, tipo, secao, pagina, idioma, texto)
}

#' Fallback quando o GROBID nao esta de pe: pagina inteira como trecho.
#' Perde a separacao de tabela - use so para destravar, nao como padrao.
pdf_para_trechos <- function(pdf, obra_id) {
  paginas <- pdftools::pdf_text(pdf)
  tibble::tibble(obra_id = obra_id, tipo = "texto", secao = NA_character_,
                 pagina = seq_along(paginas), texto = paginas) |>
    filter(nchar(texto) > 40) |>
    mutate(idioma = map_chr(texto, detectar_idioma),
           trecho_id = map2_chr(obra_id, pagina, id_de)) |>
    select(trecho_id, obra_id, tipo, secao, pagina, idioma, texto)
}

estruturar_obras <- function(con, cfg) {
  dir.create(cfg$dir_tei, showWarnings = FALSE, recursive = TRUE)
  pend <- dbGetQuery(con, "
    SELECT obra_id, caminho_pdf FROM obras
     WHERE caminho_pdf IS NOT NULL
       AND obra_id NOT IN (SELECT DISTINCT obra_id FROM trechos)")

  pmap_dfr(pend, function(obra_id, caminho_pdf) {
    tei <- file.path(cfg$dir_tei, paste0(obra_id, ".tei.xml"))
    trechos <- tryCatch({
      if (!file.exists(tei)) grobid_tei(caminho_pdf, cfg$grobid, tei)
      tei_para_trechos(tei, obra_id)
    }, error = function(e) {
      warning("GROBID falhou em ", obra_id, ": ", conditionMessage(e))
      pdf_para_trechos(caminho_pdf, obra_id)
    })
    registrar(con, "trechos", trechos)
    # idioma predominante do documento
    dbExecute(con, sprintf(
      "UPDATE obras SET idioma = '%s' WHERE obra_id = '%s'",
      names(sort(table(trechos$idioma), decreasing = TRUE))[1] %||% "NA", obra_id))
    tibble::tibble(obra_id = obra_id, n_trechos = nrow(trechos))
  })
}
