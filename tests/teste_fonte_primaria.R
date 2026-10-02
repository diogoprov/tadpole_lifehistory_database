# Teste do rastreio da fonte primaria.
#
# Parte pura sem banco; parte de banco num DuckDB temporario. Sem rede.
#
#   Rscript tests/teste_fonte_primaria.R
#
# O caso (P. barrioi, 01/10/2026): snout_shape_lv = rounded num poster do
# F1000Research (2011) e na redescricao da especie na Copeia (2012). A regra
# "o mais antigo e o primario" fazia o poster virar fonte primaria e o artigo
# revisado por pares, secundaria. Decisao do Diogo: poster e resumo de
# congresso nunca sao fonte primaria.

suppressMessages({ library(dplyr); library(tibble); library(DBI) })
if (!dir.exists("R") && dir.exists("../R")) setwd("..")

e <- new.env()
for (f in c("R/db.R", "R/validacao.R")) {
  suppressMessages(eval(parse(text = paste(readLines(f, warn = FALSE), collapse = "\n")), envir = e))
}

falhas <- 0L
checar <- function(descricao, condicao) {
  cat(if (isTRUE(condicao)) "  ok   " else "  FALHA", descricao, "\n")
  if (!isTRUE(condicao)) falhas <<- falhas + 1L
  invisible(condicao)
}

DOI_POSTER <- "10.7490/f1000research.853.1"
DOI_ARTIGO <- "10.1643/ch-10-142"

ext <- function(id, ano, doi, tipo_documento = NA_character_, cat = "rounded",
                span = "Snout rounded in dorsal and lateral views.") {
  tibble(extracao_id = id, taxon_id = "TB", trait_id = "snout_shape_lv",
         valor_num = NA_real_, valor_cat = cat, span_verbatim = span,
         ano = as.integer(ano), doi = doi, tipo_documento = tipo_documento)
}
o <- function(d, id) d$origem[d$extracao_id == id]
fp <- function(d, id) d$fonte_primaria_doi[d$extracao_id == id]

# ---------------------------------------------------------------------------
cat("\ndecidir_fonte_primaria(): o caso de P. barrioi\n")
d <- e$decidir_fonte_primaria(bind_rows(
  ext("poster", 2011, DOI_POSTER, "poster", span = "Focinho arredondado, aparato oral anteroventral."),
  ext("artigo", 2012, DOI_ARTIGO)))
checar("o artigo de 2012 e a fonte primaria", o(d, "artigo") == "primaria")
checar("o poster de 2011, mais antigo, fica secundario", o(d, "poster") == "secundaria")
checar("o poster aponta para o artigo", identical(fp(d, "poster"), DOI_ARTIGO))
checar("o artigo nao aponta para ninguem", is.na(fp(d, "artigo")))

cat("\nresumo de congresso tem a mesma regra\n")
d <- e$decidir_fonte_primaria(bind_rows(
  ext("resumo", 2010, NA_character_, "resumo_congresso"),
  ext("artigo", 2012, DOI_ARTIGO)))
checar("resumo de 2010 secundario", o(d, "resumo") == "secundaria")
checar("artigo de 2012 primario", o(d, "artigo") == "primaria")

cat("\no resto da regra nao mudou\n")
d <- e$decidir_fonte_primaria(bind_rows(
  ext("velho", 2005, "10.0/velho"), ext("novo", 2012, DOI_ARTIGO)))
checar("entre obras comuns, a mais antiga continua primaria", o(d, "velho") == "primaria")
checar("a mais nova continua secundaria, apontando para a antiga",
       o(d, "novo") == "secundaria" && identical(fp(d, "novo"), "10.0/velho"))
d <- e$decidir_fonte_primaria(ext("cita", 2012, DOI_ARTIGO,
                                  span = "Snout rounded (Bokermann, 1967)."))
checar("frase com citacao continua secundaria", o(d, "cita") == "secundaria")
d <- e$decidir_fonte_primaria(bind_rows(
  ext("poster", 2011, DOI_POSTER, "poster"), ext("outro", 2012, DOI_ARTIGO, cat = "truncate")))
checar("valor diferente e outro grupo: o artigo com 'truncate' e primario",
       o(d, "outro") == "primaria")

cat("\nso poster no grupo\n")
d <- e$decidir_fonte_primaria(ext("poster", 2011, DOI_POSTER, "poster"))
checar("poster sozinho nao vira primario", o(d, "poster") == "secundaria")
checar("e fica sem fonte primaria para apontar", is.na(fp(d, "poster")))

# ---------------------------------------------------------------------------
cat("\nmarcar_fonte_secundaria() no banco\n")
if (!requireNamespace("duckdb", quietly = TRUE)) {
  cat("  (pulado: falta duckdb)\n")
} else {
  arq <- tempfile(fileext = ".duckdb")
  con <- dbConnect(duckdb::duckdb(), arq)
  e$criar_esquema(con)
  checar("coluna tipo_documento entra por ALTER idempotente",
         { e$criar_esquema(con); "tipo_documento" %in% dbListFields(con, "obras") })
  dbAppendTable(con, "obras", data.frame(
    obra_id = c("6b12a7c91b66108e", "51e5eab495f0da63"), doi = c(DOI_POSTER, DOI_ARTIGO),
    ano = c(2011L, 2012L)))
  dbAppendTable(con, "extracoes", data.frame(
    extracao_id = c("x_poster", "x_artigo"), obra_id = c("6b12a7c91b66108e", "51e5eab495f0da63"),
    taxon_id = "TB", trait_id = "snout_shape_lv", valor_cat = "rounded",
    span_verbatim = c("Focinho arredondado, aparato oral anteroventral.",
                      "Snout rounded in dorsal and lateral views."),
    status = "bruto"))

  e$marcar_tipo_documento(con, "6b12a7c91b66108e", "poster")
  e$marcar_fonte_secundaria(con)
  r <- dbGetQuery(con, "SELECT extracao_id, origem_valor, fonte_primaria_doi FROM extracoes")
  checar("no banco, o artigo e primario",
         r$origem_valor[r$extracao_id == "x_artigo"] == "primaria")
  checar("no banco, o poster e secundario e aponta para o artigo",
         r$origem_valor[r$extracao_id == "x_poster"] == "secundaria" &&
           identical(r$fonte_primaria_doi[r$extracao_id == "x_poster"], DOI_ARTIGO))

  checar("tipo desconhecido e recusado",
         inherits(try(e$marcar_tipo_documento(con, "6b12a7c91b66108e", "Poster"), silent = TRUE),
                  "try-error"))
  checar("obra inexistente e recusada",
         inherits(try(e$marcar_tipo_documento(con, "naoexiste", "poster"), silent = TRUE),
                  "try-error"))
  e$marcar_tipo_documento(con, "6b12a7c91b66108e", NA_character_)
  checar("tipo = NA desfaz a marca",
         is.na(dbGetQuery(con, "SELECT tipo_documento FROM obras WHERE obra_id = '6b12a7c91b66108e'")[[1]]))
  dbDisconnect(con, shutdown = TRUE); unlink(arq)
}

cat(if (falhas == 0) "\ntodos os testes passaram\n\n" else sprintf("\n%d FALHA(S)\n\n", falhas))
quit(status = if (falhas == 0) 0 else 1)
