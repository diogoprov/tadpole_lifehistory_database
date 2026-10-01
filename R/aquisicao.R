# Aquisicao do PDF e do material suplementar (item 6: muito dado de girino so
# existe em apendice). OCR para a literatura antiga.

library(httr2)
library(purrr)
library(dplyr)

#' Unpaywall: melhor localizacao OA do DOI, incluindo links suplementares
#' quando o editor os declara.
localizar_oa <- function(doi, email) {
  if (is.na(doi)) return(list(pdf = NA_character_, sup = NA_character_))
  js <- tryCatch(
    request(paste0("https://api.unpaywall.org/v2/", doi)) |>
      req_url_query(email = email) |> req_perform() |> resp_body_json(),
    error = function(e) NULL)
  if (is.null(js)) return(list(pdf = NA_character_, sup = NA_character_))
  list(pdf = js$best_oa_location$url_for_pdf %||% NA_character_,
       sup = js$best_oa_location$url %||% NA_character_)
}

baixar <- function(url, destino) {
  if (is.na(url)) return(NA_character_)
  ok <- tryCatch({
    request(url) |> req_progress() |>
      req_perform(path = destino)
    TRUE
  }, error = function(e) FALSE)
  if (ok && file.exists(destino) && file.size(destino) > 10000) destino else NA_character_
}

#' Um PDF cujo texto extraido e curto demais e um PDF escaneado: vai para OCR.
precisa_ocr <- function(caminho, min_chars = 2000) {
  txt <- tryCatch(paste(pdftools::pdf_text(caminho), collapse = " "),
                  error = function(e) "")
  nchar(gsub("\\s", "", txt)) < min_chars
}

rodar_ocr <- function(caminho, binario) {
  if (!nzchar(binario) || Sys.which(binario) == "") return(FALSE)
  saida <- sub("\\.pdf$", "_ocr.pdf", caminho)
  st <- system2(binario, c("--language", "por+spa+eng", "--skip-text",
                           shQuote(caminho), shQuote(saida)),
                stdout = FALSE, stderr = FALSE)
  if (st == 0 && file.exists(saida)) {
    file.rename(saida, caminho); TRUE
  } else FALSE
}

adquirir_pdfs <- function(con, cfg) {
  dir.create(cfg$dir_pdf, showWarnings = FALSE, recursive = TRUE)
  pend <- dbGetQuery(con, "
    SELECT o.obra_id, o.doi, o.url_pdf FROM obras o JOIN triagem t USING (obra_id)
     WHERE t.relevante AND o.caminho_pdf IS NULL")

  res <- pmap_dfr(pend, function(obra_id, doi, url_pdf) {
    oa <- localizar_oa(doi, cfg$email)
    destino <- file.path(cfg$dir_pdf, paste0(obra_id, ".pdf"))
    caminho <- baixar(coalesce(url_pdf, oa$pdf), destino)
    ocr <- FALSE
    if (!is.na(caminho) && precisa_ocr(caminho)) ocr <- rodar_ocr(caminho, cfg$ocr)
    tibble::tibble(
      obra_id = obra_id,
      caminho_pdf = caminho, ocr = ocr,
      url_suplementar = oa$sup,
      status = dplyr::case_when(
        is.na(caminho) ~ "sem_pdf",        # fila para pedido aos autores
        ocr            ~ "pdf_ocr",
        TRUE           ~ "pdf_ok"))
  })

  if (nrow(res) > 0) {
    dbWriteTable(con, "tmp_aq", res, temporary = TRUE, overwrite = TRUE)
    dbExecute(con, "
      UPDATE obras SET caminho_pdf = t.caminho_pdf, ocr = t.ocr,
             url_suplementar = t.url_suplementar, status = t.status
        FROM tmp_aq t WHERE obras.obra_id = t.obra_id")
    dbExecute(con, "DROP TABLE tmp_aq")
  }
  res
}

#' Obras sem PDF: lista para pedir aos autores ou buscar no acervo do grupo.
exportar_sem_pdf <- function(con, caminho) {
  d <- dbGetQuery(con, "SELECT obra_id, doi, titulo, ano FROM obras
                         WHERE status = 'sem_pdf' ORDER BY ano")
  readr::write_csv(d, caminho); nrow(d)
}
