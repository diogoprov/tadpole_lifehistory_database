# Aquisicao do PDF e do material suplementar (item 6: muito dado de girino so
# existe em apendice). OCR para a literatura antiga.

library(httr2)
library(purrr)
library(dplyr)

#' Unpaywall: melhor localizacao OA do DOI, incluindo links suplementares
#' quando o editor os declara.
#' `erro`: a chamada falhou (rede, 5xx). 404 nao e erro: e DOI que o Unpaywall
#' nao conhece (ex.: Zenodo), ou seja, sem copia aberta conhecida. Antes
#' (ate 03/10/2026) qualquer falha virava NA e a obra ia para "sem_pdf"
#' (principio 1).
localizar_oa <- function(doi, email) {
  nada <- list(pdf = NA_character_, sup = NA_character_, erro = NA_character_)
  if (is.na(doi)) return(nada)
  resp <- tryCatch(
    request(paste0("https://api.unpaywall.org/v2/", doi)) |>
      req_url_query(email = email) |> req_error(is_error = function(r) FALSE) |> req_perform(),
    error = function(e) e)
  if (inherits(resp, "error")) return(modifyList(nada, list(erro = conditionMessage(resp))))
  if (resp_status(resp) == 404) return(nada)
  if (resp_status(resp) >= 400) return(modifyList(nada, list(erro = paste("HTTP", resp_status(resp)))))
  js <- resp_body_json(resp)
  list(pdf = js$best_oa_location$url_for_pdf %||% NA_character_,
       sup = js$best_oa_location$url %||% NA_character_, erro = NA_character_)
}

#' Baixa para um arquivo temporario e so copia para pdf/ se for PDF de verdade.
#'
#' Antes baixava direto no destino e aceitava qualquer coisa acima de 10 KB. No
#' teste de P. barrioi (01/10/2026) isso deixou em pdf/ tres arquivos falsos:
#' duas paginas HTML de ~1 KB da BioOne (bloqueio a download automatico) e um
#' arquivo de 0 byte da Brill (erro HTTP no meio do caminho) - todos com
#' extensao .pdf. O status ficava certo (sem_pdf), mas o lixo ficava no disco.
#' E um HTML maior que 10 KB (pagina do artigo em vez do arquivo) teria passado
#' como pdf_ok e so quebraria no GROBID.
baixar <- function(url, destino) {
  if (is.na(url)) return(NA_character_)
  tmp <- tempfile(fileext = ".pdf")
  on.exit(unlink(tmp), add = TRUE)
  ok <- tryCatch({
    request(url) |> req_progress() |> req_perform(path = tmp)
    TRUE
  }, error = function(e) FALSE)
  if (!ok || !e_pdf(tmp)) return(NA_character_)
  file.copy(tmp, destino, overwrite = TRUE)
  destino
}

#' O cabecalho "%PDF-" tem de aparecer no primeiro KB (a especificacao admite
#' lixo antes dele, mas nao depois). Tamanho nao serve de criterio.
e_pdf <- function(caminho) {
  if (!file.exists(caminho) || file.size(caminho) == 0) return(FALSE)
  inicio <- readBin(caminho, "raw", n = 1024)
  length(grepRaw(charToRaw("%PDF-"), inicio, fixed = TRUE)) > 0
}

#' Um PDF cujo texto extraido e curto demais e um PDF escaneado: vai para OCR.
#' Sem o pdftools nao ha como saber: devolve FALSE com aviso, em vez de tratar
#' todo PDF como escaneado (o erro virava texto vazio, e texto vazio "precisa
#' de OCR").
precisa_ocr <- function(caminho, min_chars = 2000) {
  if (!requireNamespace("pdftools", quietly = TRUE)) {
    warning("pdftools ausente: nao foi possivel checar se o PDF e escaneado ",
            "(install.packages('pdftools'))", call. = FALSE)
    return(FALSE)
  }
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
    ocr <- FALSE; escaneado <- FALSE
    if (!is.na(caminho) && precisa_ocr(caminho)) {
      escaneado <- TRUE
      ocr <- rodar_ocr(caminho, cfg$ocr)
    }
    tibble::tibble(
      obra_id = obra_id,
      caminho_pdf = caminho, ocr = ocr,
      url_suplementar = oa$sup,
      status = dplyr::case_when(
        is.na(caminho) & !is.na(oa$erro) ~ "erro",   # tenta de novo na proxima rodada
        is.na(caminho) ~ "sem_pdf",        # fila para pedido aos autores
        escaneado & !ocr ~ "precisa_ocr",  # sem ocrmypdf: nao e pdf_ok
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
#' Leva o link de acesso aberto quando existe: varias obras "sem_pdf" sao de
#' acesso aberto e so bloqueiam download automatico (BioOne, Brill) - abrem
#' normalmente no navegador.
#'
#' A coluna `arquivo` vai vazia: quem conseguir o PDF poe o arquivo em pdf/
#' (com o nome que quiser) e escreve o nome ali. Depois,
#' importar_pdfs_manuais() registra.
exportar_sem_pdf <- function(con, caminho) {
  d <- dbGetQuery(con, "SELECT obra_id, doi, titulo, ano,
                                coalesce(url_pdf, url_suplementar) AS link_acesso_aberto
                           FROM obras
                          WHERE status = 'sem_pdf' ORDER BY ano")
  d$arquivo <- ""
  dir.create(dirname(caminho), showWarnings = FALSE, recursive = TRUE)
  readr::write_csv(d, caminho); nrow(d)
}

#' Registra PDFs obtidos a mao: pela biblioteca, pelo autor, pelo navegador
#' quando a editora bloqueia download automatico (BioOne, Brill).
#'
#' Le a planilha de exportar_sem_pdf() com a coluna `arquivo` preenchida. Para
#' cada linha: confere que e PDF de verdade, COPIA para pdf/<obra_id>.pdf (o
#' seu arquivo original nao e tocado - nem renomeado, nem passado por OCR) e
#' marca a obra como `pdf_manual`. Dai em diante ela segue como qualquer outra:
#' estruturar_obras() so precisa de caminho_pdf preenchido.
#'
#' `arquivo` pode ser so o nome (procurado em pdf/) ou um caminho completo.
#'
#' Se o Excel tiver estragado o obra_id (id hexadecimal como "5446582e0056744"
#' vira numero em notacao cientifica), a obra e achada pelo DOI.
importar_pdfs_manuais <- function(con, caminho, cfg) {
  h <- ler_planilha_humana(caminho)
  if (!"arquivo" %in% names(h)) stop("a planilha precisa da coluna 'arquivo'")
  h <- h[!is.na(h$arquivo) & nzchar(trimws(h$arquivo)), ]
  if (nrow(h) == 0) {
    message("nenhuma linha com 'arquivo' preenchido em ", caminho)
    return(invisible(tibble::tibble()))
  }
  obras <- dbGetQuery(con, "SELECT obra_id, doi FROM obras")
  if (!"doi" %in% names(h)) h$doi <- NA_character_

  res <- map_dfr(seq_len(nrow(h)), function(i) {
    falha <- function(motivo) tibble::tibble(
      obra_id = h$obra_id[i], arquivo = h$arquivo[i], caminho_pdf = NA_character_,
      ocr = NA, problema = motivo)
    oid <- h$obra_id[i]
    if (!oid %in% obras$obra_id) {
      por_doi <- obras$obra_id[!is.na(obras$doi) & !is.na(h$doi[i]) &
                                 tolower(obras$doi) == tolower(trimws(h$doi[i]))]
      if (length(por_doi) == 0) return(falha("obra_id e DOI nao encontrados no banco"))
      oid <- por_doi[1]
    }
    arq <- trimws(h$arquivo[i])
    origem <- if (file.exists(arq)) arq else file.path(cfg$dir_pdf, arq)
    if (!file.exists(origem)) return(falha(paste("arquivo nao encontrado:", origem)))
    if (!e_pdf(origem)) return(falha("o arquivo nao e PDF (cabecalho %PDF ausente)"))

    destino <- file.path(cfg$dir_pdf, paste0(oid, ".pdf"))
    if (normalizePath(origem) != normalizePath(destino, mustWork = FALSE)) {
      file.copy(origem, destino, overwrite = TRUE)
    }
    ocr <- if (precisa_ocr(destino)) rodar_ocr(destino, cfg$ocr) else FALSE
    tibble::tibble(obra_id = oid, arquivo = arq, caminho_pdf = destino,
                   ocr = ocr, problema = NA_character_)
  })

  ok <- res[is.na(res$problema), ]
  if (nrow(ok) > 0) {
    dbWriteTable(con, "tmp_man", transmute(ok, obra_id, caminho_pdf, ocr),
                 temporary = TRUE, overwrite = TRUE)
    dbExecute(con, "
      UPDATE obras SET caminho_pdf = t.caminho_pdf, ocr = t.ocr, status = 'pdf_manual'
        FROM tmp_man t WHERE obras.obra_id = t.obra_id")
    dbExecute(con, "DROP TABLE tmp_man")
  }
  cat(sprintf("PDFs registrados: %d | com problema: %d\n", nrow(ok), sum(!is.na(res$problema))))
  for (i in which(!is.na(res$problema)))
    cat("  ", res$arquivo[i], "->", res$problema[i], "\n")
  invisible(res)
}

#' Planilha que passou pela mao de alguem: o Excel em portugues salva CSV com
#' ponto e virgula. Tudo como texto, para nao virar numero o que e id.
ler_planilha_humana <- function(caminho) {
  delim <- if (grepl(";", readLines(caminho, n = 1, warn = FALSE))) ";" else ","
  readr::read_delim(caminho, delim = delim, show_col_types = FALSE,
                    col_types = readr::cols(.default = "c"), na = c("", "NA"))
}
