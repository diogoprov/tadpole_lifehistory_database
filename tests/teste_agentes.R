# Teste do escalonamento e da montagem do chat.
#
# Roda sem API: os modelos sao substituidos por objetos que respondem ou
# falham como a API real.
#
#   Rscript tests/teste_agentes.R
#
# O defeito (teste de P. barrioi, 01/10/2026): com temperature = 0, o Sonnet
# 5.5 e o Opus 5.5 responderam HTTP 400 em toda chamada. com_escalonamento()
# engolia o erro e devolvia NULL, que seguia como "nao encontrado": a rodada
# terminou com "0 registros" em 8 obras, sem nenhum aviso.

suppressMessages({ library(purrr) })
if (!dir.exists("R") && dir.exists("../R")) setwd("..")
e <- new.env()
suppressMessages(eval(parse(text = paste(readLines("R/agentes.R", warn = FALSE), collapse = "\n")),
                      envir = e))

falhas <- 0L
checar <- function(descricao, condicao) {
  cat(if (isTRUE(condicao)) "  ok   " else "  FALHA", descricao, "\n")
  if (!isTRUE(condicao)) falhas <<- falhas + 1L
  invisible(condicao)
}
erro_de <- function(expr) tryCatch({ force(expr); NULL }, error = conditionMessage)

# modelo simulado: por nome, devolve resposta ou falha como a API
CHAMADOS <- character()
comportamento <- list()
e$criar_chat <- function(spec, sistema) {
  list(chat_structured = function(p, type) {
    CHAMADOS <<- c(CHAMADOS, spec$modelo)
    r <- comportamento[[spec$modelo]]
    if (is.character(r)) stop(r) else r
  })
}
barato <- list(provedor = "anthropic", modelo = "sonnet")
forte  <- list(provedor = "anthropic", modelo = "opus")
esc <- function() e$com_escalonamento("p", NULL, "s", barato, forte, "span_verbatim")
ERRO400 <- "HTTP 400 Bad Request. `temperature` is deprecated for this model."

cat("\no caso real: os dois modelos recusam a chamada\n")
comportamento <- list(sonnet = ERRO400, opus = ERRO400)
m <- erro_de(esc())
checar("a rodada PARA (antes devolvia NULL = 'nao encontrado')", !is.null(m))
checar("a mensagem traz o motivo da API", grepl("temperature", m %||% ""))
checar("e diz qual modelo falhou", grepl("sonnet", m %||% "") && grepl("opus", m %||% ""))

cat("\nbarato falha, forte responde\n")
CHAMADOS <- character()
comportamento <- list(sonnet = ERRO400, opus = list(encontrado = TRUE, span_verbatim = "x"))
avisos <- character()
r <- withCallingHandlers(esc(), warning = function(w) { avisos <<- c(avisos, conditionMessage(w)); invokeRestart("muffleWarning") })
checar("usa a resposta do forte", isTRUE(r$encontrado) && isTRUE(r$escalonado))
checar("mas avisa que o barato falhou", any(grepl("barato falhou", avisos)))

cat("\nbarato responde sem o campo critico, forte falha\n")
comportamento <- list(sonnet = list(encontrado = FALSE, span_verbatim = NA), opus = ERRO400)
checar("para tambem: um modelo forte quebrado e erro de configuracao",
       !is.null(erro_de(esc())))

cat("\ncaminhos normais (sem erro)\n")
CHAMADOS <- character()
comportamento <- list(sonnet = list(encontrado = TRUE, span_verbatim = "Snout rounded."))
r <- esc()
checar("resposta completa do barato: nao escala", !isTRUE(r$escalonado) && identical(CHAMADOS, "sonnet"))
comportamento <- list(sonnet = list(encontrado = FALSE, span_verbatim = NA),
                      opus = list(encontrado = FALSE, span_verbatim = NA))
r <- esc()
checar("os dois respondem 'nao encontrado': devolve isso, sem erro",
       identical(r$encontrado, FALSE) && isTRUE(r$escalonado))

cat("\ncriar_chat(): temperatura so quando o config pede\n")
if (requireNamespace("ellmer", quietly = TRUE)) {
  suppressMessages(library(ellmer))
  Sys.setenv(ANTHROPIC_API_KEY = Sys.getenv("ANTHROPIC_API_KEY", "sk-ant-teste-sem-rede"))
  f <- new.env()
  for (x in parse("R/agentes.R"))
    if (is.call(x) && identical(x[[1]], as.name("<-")) && identical(as.character(x[[2]]), "criar_chat"))
      eval(x, envir = f)
  p_de <- function(spec) f$criar_chat(spec, "s")$get_model_object()@params
  checar("com temperatura: 0 (o Haiku aceita)",
         identical(p_de(list(provedor = "anthropic", modelo = "claude-haiku-4-5-20251001",
                             temperatura = 0))$temperature, 0))
  checar("sem temperatura: o parametro nem e enviado (Sonnet/Opus 5.5)",
         is.null(p_de(list(provedor = "anthropic", modelo = "claude-sonnet-5-5"))$temperature))
} else cat("  (pulado: ellmer ausente)\n")

# Rodada 3 do piloto (conferida em 04/10/2026): 32 de 136 frases eram de outra
# especie ou de outro trabalho. O sistema do agente de valor tem de dizer isso.
cat("\nsistema do agente de valor\n")
checar("so vale o que o trecho descreve desta especie", grepl("DESTA especie", e$SISTEMA_VALOR))
checar("ignora o que outro trabalho descreveu", grepl("outro trabalho", e$SISTEMA_VALOR))

cat("\n", if (falhas == 0) "todos os testes passaram\n\n" else
    paste0(falhas, " teste(s) falharam\n\n"), sep = "")
if (falhas > 0) quit(status = 1)
