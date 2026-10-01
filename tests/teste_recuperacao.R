# Teste de regressao da recuperacao.
#
# Roda sem API, sem GROBID e sem banco: so parse.R e recuperacao.R sobre um
# TEI sintetico. Serve para o bug de 01/10/2026 nao voltar.
#
#   Rscript tests/teste_recuperacao.R
#
# O bug: a especie era procurada so no TEXTO do trecho. Num artigo de
# descricao, o paragrafo diagnostico nao repete o binomio - quem carrega o
# nome e o cabecalho da secao. O unico paragrafo com os caracteres era, por
# isso, descartado.

suppressMessages({
  library(dplyr); library(stringr); library(purrr); library(digest)
})
# roda a partir da raiz do projeto
if (!dir.exists("R") && dir.exists("../R")) setwd("..")
if (!exists("id_de", mode = "function"))
  id_de <- function(...) substr(digest::digest(paste0(...), algo = "xxhash64"), 1, 16)
source("R/parse.R"); source("R/recuperacao.R")

falhas <- 0L
checar <- function(descricao, condicao) {
  cat(if (isTRUE(condicao)) "  ok   " else "  FALHA", descricao, "\n")
  if (!isTRUE(condicao)) falhas <<- falhas + 1L
  invisible(condicao)
}

tei <- "inst/exemplo/regressao_secao.tei.xml"
tr <- tei_para_trechos(tei, "exemplo")

cat("\nestrutura do TEI\n")
checar("tres trechos de texto", nrow(tr) == 3)
checar("secao de Metodos identificada",
       any(str_detect(tolower(na.omit(tr$secao)), "method")))
checar("secao de descricao carrega o nome da especie no cabecalho",
       any(str_detect(na.omit(tr$secao), "Exemplaria ficta")))
checar("o paragrafo diagnostico NAO repete o binomio (e a premissa do teste)",
       !any(str_detect(tr$texto[str_detect(tr$texto, "dorsally positioned")],
                       "Exemplaria")))

cat("\nrecuperacao\n")
nomes <- "Exemplaria ficta"
termos <- c("eyes", "eye")
seleciona <- function(onde) {
  tr |> filter(str_detect(onde, regex(padrao_especie(nomes), ignore_case = TRUE)),
               str_detect(texto, regex(paste(termos, collapse = "|"), ignore_case = TRUE)))
}
so_texto <- seleciona(tr$texto)
com_secao <- seleciona(paste(ifelse(is.na(tr$secao), "", tr$secao), tr$texto))

checar("procurando so no texto, o paragrafo diagnostico se perde (o bug)",
       !any(str_detect(so_texto$texto, "dorsally positioned")))
checar("procurando tambem no cabecalho, ele entra (a correcao)",
       any(str_detect(com_secao$texto, "dorsally positioned")))
checar("a correcao nao traz o artigo inteiro", nrow(com_secao) < nrow(tr))

cat("\n", if (falhas == 0) "todos os testes passaram\n\n" else
    paste0(falhas, " teste(s) falharam\n\n"), sep = "")
if (falhas > 0) quit(status = 1)
