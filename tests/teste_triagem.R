# Teste da interpretacao da triagem.
#
# Roda sem API: simula o tibble que parallel_chat_structured() devolve.
#
#   Rscript tests/teste_triagem.R
#
# O defeito (teste de fumaca da busca, 01/10/2026): triar_obras() tratava a
# resposta como lista de respostas e iterava com map_lgl(res, ~ .x$relevante).
# Mas o ellmer devolve um tibble - uma linha por obra, uma coluna por campo -,
# entao o map percorria as COLUNAS e estourava com "$ operator is invalid for
# atomic vectors" logo no indice 1, de nome "relevante".
#
# E um segundo defeito, silencioso: isTRUE() transformava resposta ausente em
# FALSE, e a obra sumia como "irrelevante" sem ninguem saber.

suppressMessages({ library(dplyr); library(purrr); library(tibble) })
if (!dir.exists("R") && dir.exists("../R")) setwd("..")

e <- new.env()
eval(parse(text = paste(readLines("R/triagem.R", warn = FALSE), collapse = "\n")), envir = e)
interpretar <- e$interpretar_triagem

falhas <- 0L
checar <- function(descricao, condicao) {
  cat(if (isTRUE(condicao)) "  ok   " else "  FALHA", descricao, "\n")
  if (!isTRUE(condicao)) falhas <<- falhas + 1L
  invisible(condicao)
}

ids <- c("o1", "o2", "o3")

cat("\nformato real do ellmer: tibble, uma linha por obra\n")
res <- tibble(relevante = c(TRUE, FALSE, TRUE),
              prob = c(0.95, 0.05, 0.50),
              justificativa = c("descreve o girino", "trata de vocalizacao", "lista faunistica"))
d <- interpretar(res, ids, "haiku")
checar("o formato antigo de leitura quebrava (era o defeito)",
       inherits(tryCatch(map_lgl(res, ~ isTRUE(.x$relevante)), error = identity), "error"))
checar("uma linha por obra", nrow(d) == 3)
checar("relevante lido por linha", identical(d$relevante, c(TRUE, FALSE, TRUE)))
checar("prob lida por linha", identical(d$prob, c(0.95, 0.05, 0.50)))
checar("alta confianca: decide o agente", d$decidido_por[1] == "agente:haiku")
checar("baixa confianca: decide o agente", d$decidido_por[2] == "agente:haiku")
checar("na margem (0,35-0,75): vai para humano", d$decidido_por[3] == "fila_humana")

cat("\nchamada que falhou NAO vira irrelevante\n")
res_err <- tibble(relevante = c(TRUE, NA, FALSE), prob = c(0.9, NA, 0.1),
                  justificativa = c("ok", NA, "ok"),
                  .error = list(NULL, simpleError("HTTP 529 overloaded"), NULL))
d <- interpretar(res_err, ids, "haiku")
checar("relevante fica NA, nao FALSE", is.na(d$relevante[2]))
checar("vai para a fila humana", d$decidido_por[2] == "fila_humana")
checar("o motivo do erro fica registrado", grepl("529", d$justificativa[2]))
checar("as outras obras nao sao afetadas",
       d$relevante[1] && !d$relevante[3] && all(d$decidido_por[c(1, 3)] == "agente:haiku"))

cat("\nresposta vazia sem coluna .error (falha de parse)\n")
res_vazio <- tibble(relevante = c(NA, TRUE, FALSE), prob = c(NA, 0.9, 0.1),
                    justificativa = c(NA, "ok", "ok"))
d <- interpretar(res_vazio, ids, "haiku")
checar("relevante NA e fila humana",
       is.na(d$relevante[1]) && d$decidido_por[1] == "fila_humana")
checar("justificativa explica", grepl("resposta vazia", d$justificativa[1]))

cat("\nprob ausente com resposta presente\n")
res_semprob <- tibble(relevante = c(TRUE, TRUE, FALSE), prob = c(NA, 0.9, 0.1),
                      justificativa = c("ok", "ok", "ok"))
d <- interpretar(res_semprob, ids, "haiku")
checar("vai para humano (sem prob nao ha como saber a margem)",
       d$decidido_por[1] == "fila_humana")
checar("decidido_por nunca fica NA", !any(is.na(d$decidido_por)))

cat("\nguardas\n")
checar("numero de linhas diferente do numero de obras e erro",
       inherits(tryCatch(interpretar(res, c("o1", "o2"), "haiku"), error = identity), "error"))
checar("lista em vez de tibble e erro (nao interpreta errado em silencio)",
       inherits(tryCatch(interpretar(list(list(relevante = TRUE)), "o1", "haiku"),
                         error = identity), "error"))

cat("\nagente_triagem() pede on_error = \"continue\"\n")
ag <- paste(readLines("R/agentes.R", warn = FALSE), collapse = "\n")
checar("sem isso, o primeiro erro interrompe as obras restantes",
       grepl('on_error = "continue"', ag))

# ---------------------------------------------------------------------------
# Revisao de 01/10/2026: binomio no titulo entra direto; triagem le o resumo
# ---------------------------------------------------------------------------
suppressMessages({ library(stringr) })
for (f in c("R/recuperacao.R", "R/busca.R"))
  eval(parse(text = paste(readLines(f, warn = FALSE), collapse = "\n")), envir = e)

cat("\nregra: binomio da especie-alvo no titulo\n")
obras <- tibble(obra_id = c("red", "canopy", "erikae", "revisao"),
                titulo = c("Redescription of Physalaemus barrioi (Anura: Leiuperidae)",
                           "Canopy cover and structural complexity affect the phylogenetic composition",
                           "The Tadpole of Physalaemus erikae Cruz and Pimenta, 2004",
                           "Tadpoles of Physalaemus barrioi and P. erikae compared"))
pares <- tibble(obra_id = c("red", "canopy", "erikae", "revisao", "revisao"),
                taxon_id = c("TB", "TB", "TB", "TB", "TE"))
nomes <- list(TB = "Physalaemus barrioi", TE = "Physalaemus erikae")
m <- e$marcar_binomio(obras, pares, nomes)
checar("a redescricao de P. barrioi entra direto", m[1])
checar("titulo sem o binomio vai para o modelo", !m[2])
checar("P. erikae ligada so a P. barrioi vai para o modelo (nome de outra especie)", !m[3])
checar("obra ligada a duas especies entra se citar qualquer uma", m[4])
checar("sem vinculo nenhum, nada entra direto",
       !any(e$marcar_binomio(obras, pares[0, ], nomes)))

cat("\ntriar_obras(): regra antes do modelo\n")
chamadas <- NULL
st <- new.env(parent = e)
st$binomio_alvo_no_titulo <- function(con, obras) obras$obra_id == "red"
st$agente_triagem <- function(obras, cfg) {
  chamadas <<- obras$obra_id
  tibble(relevante = c(TRUE, FALSE, TRUE), prob = c(.9, .1, .9), justificativa = "x")
}
st$registrar <- function(...) invisible(0L)
tr <- e$triar_obras; environment(tr) <- st
d <- tr(NULL, obras, list(agentes = list(triagem = list(modelo = "haiku"))))
checar("o modelo NAO recebe a obra da regra", !"red" %in% chamadas && length(chamadas) == 3)
checar("a obra da regra sai relevante, marcada como regra",
       d$relevante[d$obra_id == "red"] && d$decidido_por[d$obra_id == "red"] == "regra:binomio_no_titulo")
checar("todas as obras saem triadas", setequal(d$obra_id, obras$obra_id))
st$agente_triagem <- function(obras, cfg) stop("HTTP 401 chave invalida")
avisos <- character()
d <- withCallingHandlers(tr(NULL, obras, list(agentes = list(triagem = list(modelo = "haiku")))),
                         warning = function(w) { avisos <<- c(avisos, conditionMessage(w)); invokeRestart("muffleWarning") })
checar("falha do modelo mostra o motivo real no aviso", any(grepl("401", avisos)))
checar("e a regra continua valendo mesmo com o modelo fora", identical(d$obra_id, "red"))

cat("\nresumo\n")
inv <- list(Tadpoles = list(0L), of = list(1L, 4L), "P." = list(2L), barrioi = list(3L), Bocaina = list(5L))
checar("OpenAlex: indice invertido remontado na ordem",
       e$resumo_openalex(inv) == "Tadpoles of P. barrioi of Bocaina")
checar("OpenAlex: sem resumo vira NA", is.na(e$resumo_openalex(NULL)))
checar("Crossref: JATS sem tags",
       e$limpar_resumo("<jats:p>The tadpole of <jats:italic>P. barrioi</jats:italic>.</jats:p>") ==
         "The tadpole of P. barrioi .")
checar("Crossref: vazio vira NA", is.na(e$limpar_resumo("<jats:p> </jats:p>")))

cat("\nprompt de triagem\n")
ag <- paste(readLines("R/agentes.R", warn = FALSE), collapse = "\n")
checar("o prompt leva o resumo", grepl("Resumo: %s", ag, fixed = TRUE))
checar("proibe conhecimento proprio (o erro da distribuicao inventada)",
       grepl("Nao use conhecimento proprio", ag))
checar("na duvida, fica com a obra", grepl("Na duvida, marque relevante", ag))

cat("\nbanco\n")
db <- paste(readLines("R/db.R", warn = FALSE), collapse = "\n")
checar("coluna resumo entra por ALTER idempotente (banco antigo continua valendo)",
       grepl("ALTER TABLE obras ADD COLUMN IF NOT EXISTS resumo", db))
bu <- paste(readLines("R/busca.R", warn = FALSE), collapse = "\n")
checar("o resumo e gravado em obras", grepl("caminho_pdf, ocr, status, resumo", bu, fixed = TRUE))

cat("\n", if (falhas == 0) "todos os testes passaram\n\n" else
    paste0(falhas, " teste(s) falharam\n\n"), sep = "")
if (falhas > 0) quit(status = 1)
