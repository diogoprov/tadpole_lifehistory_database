# Teste do registro da obra no teste de fumaca.
#
# Sem rede, sem GROBID e sem modelo: so a montagem da linha de 'obras'.
#
#   Rscript tests/teste_fumaca.R
#
# O defeito (visto em 01/10/2026): teste_de_fumaca() gravava a obra com
# ano = NA. Conte et al. (2007), TESTE001, ficou assim, e
# marcar_fonte_secundaria() deixou os dois registros dela com origem_valor
# vazia, porque nao tinha ano para comparar. Decisao do Diogo: o teste de
# fumaca grava o ano.

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
erro <- function(expr) inherits(try(expr, silent = TRUE), "try-error")

pdf <- tempfile(fileext = ".pdf"); writeLines("%PDF-1.4", pdf)

# ---------------------------------------------------------------------------
cat("\nobra_de_fumaca()\n")
o <- obra_de_fumaca(pdf, 2007)
checar("o ano e gravado", identical(o$ano, 2007L))
checar("DOI ausente fica NA", is.na(o$doi))
checar("DOI informado e gravado",
       identical(obra_de_fumaca(pdf, 2007, doi = "10.0/x")$doi, "10.0/x"))
checar("ano como texto numerico e aceito", identical(obra_de_fumaca(pdf, "2007")$ano, 2007L))
checar("ano NA e recusado", erro(obra_de_fumaca(pdf, NA)))
checar("ano nao numerico e recusado", erro(obra_de_fumaca(pdf, "s.d.")))
checar("ano fracionario e recusado", erro(obra_de_fumaca(pdf, 2007.5)))
checar("ano no futuro e recusado",
       erro(obra_de_fumaca(pdf, as.integer(format(Sys.Date(), "%Y")) + 1L)))
checar("mais de um ano e recusado", erro(obra_de_fumaca(pdf, c(2007, 2008))))
checar("as colunas sao as que 'obras' tem",
       all(names(o) %in% c("obra_id", "doi", "titulo", "ano", "idioma", "fonte", "url_pdf",
                           "url_suplementar", "caminho_pdf", "ocr", "status")))

cat("\nteste_de_fumaca()\n")
checar("ano e argumento obrigatorio (sem padrao)",
       "ano" %in% names(formals(teste_de_fumaca)) &&
         identical(formals(teste_de_fumaca)$ano, quote(expr = )))
# config inexistente: se o erro de ano nao viesse antes, o erro seria de config
msg <- tryCatch(teste_de_fumaca(pdf, "Scinax catharinae", ano = NA,
                                config_path = tempfile(fileext = ".yml")),
                error = conditionMessage)
checar("ano invalido para antes de abrir config ou banco", grepl("ano invalido", msg))

cat("\ncom o ano, a fonte primaria e decidida\n")
d <- decidir_fonte_primaria(tibble::tibble(
  extracao_id = "c1", taxon_id = "TESTE001", trait_id = "snout_shape_lv",
  valor_num = NA_real_, valor_cat = "rounded",
  span_verbatim = "Snout rounded in lateral view.",
  ano = obra_de_fumaca(pdf, 2007)$ano, doi = NA_character_, tipo_documento = NA_character_))
checar("obra do teste de fumaca, sozinha no grupo, e primaria", identical(d$origem, "primaria"))

unlink(pdf)
cat(if (falhas == 0) "\ntodos os testes passaram\n\n" else sprintf("\n%d FALHA(S)\n\n", falhas))
quit(status = if (falhas == 0) 0 else 1)
