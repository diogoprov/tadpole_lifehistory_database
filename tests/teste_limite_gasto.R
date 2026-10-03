# Teste do limite de gasto em extrair_tudo().
#
# Roda sem API: extrair_par() e a contagem de tokens sao substituidos.
#
#   Rscript tests/teste_limite_gasto.R
#
# O defeito (03/10/2026, antes da primeira extracao no corpus da BT 5):
# extrair_tudo() nao tinha limite de gasto. O limite conferido a cada par so
# existia em rodar_rodada(), do piloto zero, criado depois de a rodada 3
# gastar US$ 2,36 com limite de US$ 2.

suppressMessages({ library(dplyr); library(tibble) })
if (!dir.exists("R") && dir.exists("../R")) setwd("..")
suppressMessages(suppressWarnings({ source("R/carregar.R"); carregar_projeto("R") }))

falhas <- 0L
checar <- function(descricao, condicao) {
  cat(if (isTRUE(condicao)) "  ok   " else "  FALHA", descricao, "\n")
  if (!isTRUE(condicao)) falhas <<- falhas + 1L
  invisible(condicao)
}

con <- suppressMessages(abrir_db(":memory:"))
registrar(con, "trechos", tibble(trecho_id = "t1", obra_id = "o1", tipo = "texto", texto = "x"))
registrar(con, "obra_taxon", tibble(obra_id = "o1", taxon_id = c("A", "B", "C"), fonte = "teste"))
registrar(con, "estado_par", tibble(taxon_id = c("A", "B", "C"), trait_id = "snout_shape_lv",
                                    estado = "nao_buscado", data_atualizacao = Sys.time()))
traits <- tibble(trait_id = "snout_shape_lv")

# cada par custa US$ 0,30; limite de US$ 0,50 -> para no segundo par
n_chamadas <- 0L
extrair_par <- function(con, obra_id, taxon_id, trait, cfg) {
  n_chamadas <<- n_chamadas + 1L
  tibble(extracao_id = paste0("e", n_chamadas), obra_id = obra_id, taxon_id = taxon_id,
         trait_id = trait$trait_id, span_verbatim = "x", status = "bruto")
}
uso_tokens <- function() tibble(provider = "a", model = "m", input = n_chamadas, output = 0)
custo_tokens <- function(antes, depois) tibble(model = "m", input = depois$input - antes$input,
                                               output = 0, usd = (depois$input - antes$input) * 0.30)

cat("\nextrair_tudo(): limite conferido a cada par\n")
msg <- tryCatch({ extrair_tudo(con, traits, list(), limite_usd = 0.5); "nao parou" },
                error = conditionMessage)
checar("para quando passa do limite", grepl("limite de US\\$ 0[.]50 passado", msg))
checar("para no par que passou (2 chamadas, nao 3)", n_chamadas == 2L)
checar("a mensagem diz onde parou", grepl("parado em o1", msg))
checar("o que ja foi extraido fica gravado",
       DBI::dbGetQuery(con, "SELECT count(*) n FROM extracoes")$n == 2)

cat("\nsem limite, roda tudo\n")
n_chamadas <- 0L; invisible(DBI::dbExecute(con, "DELETE FROM extracoes"))
invisible(DBI::dbExecute(con, "UPDATE estado_par SET estado = 'nao_buscado'"))
invisible(extrair_tudo(con, traits, list()))
checar("os 3 pares", n_chamadas == 3L)

# Rodada de 03/10/2026: parou por erro (HTTP 400) depois de US$ 2,01. Par
# processado sem valor encontrado continua 'nao_buscado' em estado_par, entao
# rodar de novo refazia (e pagava de novo) todos eles. O que ja foi chamado
# fica em chamadas_valor e e pulado.
cat("\nretomada: par ja chamado nao e refeito\n")
n_chamadas <- 0L; invisible(DBI::dbExecute(con, "DELETE FROM extracoes"))
invisible(DBI::dbExecute(con, "UPDATE estado_par SET estado = 'nao_buscado'"))
registrar(con, "chamadas_valor", tibble(obra_id = "o1", taxon_id = c("A", "B"), trait_id = "snout_shape_lv",
                                        trecho_id = "t1", escalonado = FALSE, encontrado = FALSE,
                                        data = Sys.time()))
invisible(extrair_tudo(con, traits, list()))
checar("so o par ainda nao chamado (C)", n_chamadas == 1L)

DBI::dbDisconnect(con, shutdown = TRUE)
cat(if (falhas == 0) "\ntodos os testes passaram\n\n" else sprintf("\n%d FALHA(S)\n\n", falhas))
quit(status = if (falhas == 0) 0 else 1)
