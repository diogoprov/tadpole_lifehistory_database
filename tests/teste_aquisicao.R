# Teste do download de PDF.
#
# Roda sem rede: usa arquivos locais e um endereco que recusa conexao.
#
#   Rscript tests/teste_aquisicao.R
#
# O defeito (teste de fumaca da busca, P. barrioi, 01/10/2026): baixar()
# gravava direto em pdf/ e aceitava qualquer coisa acima de 10 KB. Ficaram em
# pdf/ duas paginas HTML de ~1 KB da BioOne e um arquivo de 0 byte da Brill,
# todos com extensao .pdf.

suppressMessages({ library(httr2) })
if (!dir.exists("R") && dir.exists("../R")) setwd("..")
e <- new.env()
suppressMessages(eval(parse(text = paste(readLines("R/aquisicao.R", warn = FALSE), collapse = "\n")), envir = e))

falhas <- 0L
checar <- function(descricao, condicao) {
  cat(if (isTRUE(condicao)) "  ok   " else "  FALHA", descricao, "\n")
  if (!isTRUE(condicao)) falhas <<- falhas + 1L
  invisible(condicao)
}
d <- tempfile(); dir.create(d)
escreve <- function(nome, conteudo) {
  p <- file.path(d, nome)
  if (is.raw(conteudo)) writeBin(conteudo, p) else writeLines(conteudo, p)
  p
}

cat("\ne_pdf(): reconhece PDF pelo cabecalho, nao pelo tamanho\n")
checar("PDF de verdade", e$e_pdf(escreve("ok.pdf", "%PDF-1.5\n%...")))
checar("pagina HTML de bloqueio (o caso da BioOne)",
       !e$e_pdf(escreve("bioone.pdf", "<html style=\"height:100%\"><head>...")))
checar("arquivo de 0 byte (o caso da Brill)", !e$e_pdf(escreve("brill.pdf", raw(0))))
checar("HTML grande, acima dos 10 KB do criterio antigo",
       !e$e_pdf(escreve("grande.pdf", c("<!DOCTYPE html>", strrep("x", 20000)))))
checar("cabecalho depois de lixo inicial (a especificacao admite)",
       e$e_pdf(escreve("bom.pdf", c(strrep(" ", 100), "%PDF-1.4"))))
checar("arquivo inexistente", !e$e_pdf(file.path(d, "nao_existe.pdf")))

cat("\nbaixar(): falha nao deixa arquivo no destino\n")
destino <- file.path(d, "destino.pdf")
r <- e$baixar("http://127.0.0.1:9/artigo.pdf", destino)
checar("devolve NA", is.na(r))
checar("nao cria o arquivo em pdf/", !file.exists(destino))
checar("URL ausente devolve NA", is.na(e$baixar(NA_character_, destino)))

cat("\nexportar_sem_pdf() leva o link de acesso aberto\n")
aq <- paste(readLines("R/aquisicao.R", warn = FALSE), collapse = "\n")
checar("coluna link_acesso_aberto", grepl("AS link_acesso_aberto", aq))

# ---------------------------------------------------------------------------
# importar_pdfs_manuais(): precisa de DuckDB; pula se o pacote nao estiver
# ---------------------------------------------------------------------------
if (requireNamespace("duckdb", quietly = TRUE)) {
  suppressMessages({ library(DBI); library(dplyr); library(purrr) })
  suppressMessages(eval(parse(text = paste(readLines("R/db.R", warn = FALSE), collapse = "\n")),
                        envir = e))
  for (nm in ls(e)) assign(nm, get(nm, envir = e))

  cat("\nbanco: coluna resumo por ALTER, idempotente\n")
  dbf <- file.path(d, "t.duckdb")
  con <- suppressMessages(abrir_db(dbf)); dbDisconnect(con, shutdown = TRUE)
  con <- suppressMessages(abrir_db(dbf))   # segunda abertura: o ALTER nao pode quebrar
  checar("obras tem a coluna resumo", "resumo" %in% dbListFields(con, "obras"))

  dir_pdf <- file.path(d, "pdf"); dir.create(dir_pdf)
  cfg <- list(dir_pdf = dir_pdf, ocr = "")
  um_pdf <- function(caminho) { grDevices::pdf(caminho); plot.new(); text(.5, .5, "girino"); grDevices::dev.off() }
  um_pdf(file.path(dir_pdf, "Redescricao P barrioi (copia).pdf"))
  um_pdf(file.path(d, "fora_da_pasta.pdf"))
  um_pdf(file.path(dir_pdf, "evangelistai.pdf"))
  writeLines("<html>bloqueado</html>", file.path(dir_pdf, "falso.pdf"))
  md5_antes <- tools::md5sum(file.path(dir_pdf, "Redescricao P barrioi (copia).pdf"))

  registrar(con, "obras", tibble(
    obra_id = c("o1", "o2", "o3", "o4", "o5"),
    doi = c("10.1643/ch-10-142", "10.1/b", "10.1670/12-116", "10.1/d", "10.1/e"),
    titulo = paste("obra", 1:5), status = "sem_pdf"))

  cat("\nexportar_sem_pdf()\n")
  csv <- file.path(d, "revisao", "sem_pdf.csv")
  n <- suppressMessages(exportar_sem_pdf(con, csv))
  plan <- readr::read_csv(csv, show_col_types = FALSE, col_types = readr::cols(.default = "c"))
  checar("exporta as 5 obras sem PDF", n == 5 && nrow(plan) == 5)
  checar("traz a coluna arquivo, vazia", "arquivo" %in% names(plan) && all(is.na(plan$arquivo)))

  cat("\nimportar_pdfs_manuais(), planilha salva pelo Excel (ponto e virgula)\n")
  # por obra_id, nao por posicao: exportar_sem_pdf() ordena por ano, e aqui
  # todos os anos estao vazios, entao a ordem das linhas e arbitraria
  arq <- c(o1 = "Redescricao P barrioi (copia).pdf",   # nome livre, com espaco
           o2 = "falso.pdf",                            # HTML com extensao .pdf
           o3 = "evangelistai.pdf",                     # id estragado: acha pelo DOI
           o4 = file.path(d, "fora_da_pasta.pdf"),      # caminho completo
           o5 = "nao_existe.pdf")
  plan$arquivo <- unname(arq[plan$obra_id])
  plan$obra_id[plan$obra_id == "o3"] <- "5.44658E+14"
  readr::write_delim(plan, csv, delim = ";")
  res <- importar_pdfs_manuais(con, csv, cfg)
  st <- dbGetQuery(con, "SELECT obra_id, status, caminho_pdf FROM obras ORDER BY obra_id")
  checar("nome livre: registrada como pdf_manual", st$status[st$obra_id == "o1"] == "pdf_manual")
  checar("copiada para pdf/<obra_id>.pdf", file.exists(file.path(dir_pdf, "o1.pdf")))
  checar("o arquivo original continua la, intacto",
         tools::md5sum(file.path(dir_pdf, "Redescricao P barrioi (copia).pdf")) == md5_antes)
  checar("HTML com extensao .pdf e recusado", st$status[st$obra_id == "o2"] == "sem_pdf")
  checar("id estragado pelo Excel: obra achada pelo DOI",
         st$status[st$obra_id == "o3"] == "pdf_manual")
  checar("caminho completo fora de pdf/ funciona", st$status[st$obra_id == "o4"] == "pdf_manual")
  checar("arquivo inexistente: fica sem_pdf e o motivo e reportado",
         st$status[st$obra_id == "o5"] == "sem_pdf" &&
         grepl("nao encontrado", res$problema[res$arquivo == "nao_existe.pdf"]))
  checar("o GROBID enxerga as registradas (caminho_pdf preenchido)",
         sum(!is.na(st$caminho_pdf)) == 3)

  # adquirir_pdfs(), antes de rodar nas 666 obras semeadas da BT 5 (03/10/2026):
  # (a) erro na chamada ao Unpaywall virava NA e a obra ia para "sem_pdf", a
  #     fila de pedido manual, como se nao houvesse copia aberta (principio 1);
  # (b) sem ocrmypdf instalado, rodar_ocr() desistia calado e o PDF escaneado
  #     saia "pdf_ok", e o GROBID receberia quase nada de texto.
  cat("\nadquirir_pdfs: erro nao vira 'sem_pdf'; escaneado sem OCR nao vira 'pdf_ok'\n")
  dbExecute(con, "INSERT INTO obras (obra_id, doi, status) VALUES
                  ('a1', '10.1/erro', 'encontrada'), ('a2', '10.1/escaneado', 'encontrada'),
                  ('a3', '10.5281/zenodo.1', 'encontrada')")
  dbExecute(con, "INSERT INTO triagem (obra_id, relevante) VALUES ('a1', TRUE), ('a2', TRUE), ('a3', TRUE)")
  dbExecute(con, "DELETE FROM triagem WHERE obra_id NOT IN ('a1', 'a2', 'a3')")
  orig <- mget(c("req_perform", "baixar", "precisa_ocr"), envir = e, ifnotfound = list(NULL, NULL, NULL))
  e$req_perform <- function(req, ...) {
    if (grepl("erro", req$url)) stop("HTTP 503 Service Unavailable")
    # DOI que o Unpaywall nao conhece (ex.: Zenodo): 404, e isso e "nao achou"
    if (grepl("zenodo", req$url)) return(httr2::response(status_code = 404L))
    httr2::response(status_code = 200L, headers = list(`Content-Type` = "application/json"),
                    body = charToRaw('{"best_oa_location":{"url_for_pdf":"https://x.org/a.pdf","url":"https://x.org/a"}}'))
  }
  e$baixar <- function(url, destino) { if (is.na(url)) return(NA_character_); um_pdf(destino); destino }
  e$precisa_ocr <- function(caminho, min_chars = 2000) TRUE
  res_aq <- e$adquirir_pdfs(con, cfg)
  st_aq <- dbGetQuery(con, "SELECT obra_id, status, caminho_pdf FROM obras WHERE obra_id IN ('a1', 'a2', 'a3')")
  checar("erro do Unpaywall: status 'erro', nao 'sem_pdf'", st_aq$status[st_aq$obra_id == "a1"] == "erro")
  checar("obra com erro continua sem caminho_pdf (entra na proxima rodada)",
         is.na(st_aq$caminho_pdf[st_aq$obra_id == "a1"]))
  checar("escaneado sem OCR disponivel: 'precisa_ocr', nao 'pdf_ok'",
         st_aq$status[st_aq$obra_id == "a2"] == "precisa_ocr")
  checar("DOI que o Unpaywall nao conhece (404): 'sem_pdf', nao 'erro'",
         st_aq$status[st_aq$obra_id == "a3"] == "sem_pdf")
  for (nm in names(orig)) if (is.null(orig[[nm]])) rm(list = nm, envir = e) else assign(nm, orig[[nm]], envir = e)
  dbDisconnect(con, shutdown = TRUE)
} else cat("\n(importar_pdfs_manuais: pulado, pacote duckdb ausente)\n")

cat("\n", if (falhas == 0) "todos os testes passaram\n\n" else
    paste0(falhas, " teste(s) falharam\n\n"), sep = "")
if (falhas > 0) quit(status = 1)
