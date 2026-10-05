# Teste da extracao pela API de lotes (R/lote.R).
#
# Sem API: o lote (batch_chat_structured), o contexto e a contagem de tokens
# sao substituidos. DuckDB em memoria.
#
#   Rscript tests/teste_lote.R
#
# O que garante (04/10/2026, quando o modo lote foi criado): mesmo prompt e
# mesmo registro do modo normal; um lote por trait; escalonamento so dos
# pedidos sem span, com o reforco e o modelo forte; erro de lote para a rodada
# sem gravar nada (principio 1: erro nunca vira "nao encontrado"); limite de
# gasto conferido antes de mandar; custo gravado com o desconto do lote.

suppressMessages({ library(dplyr); library(tibble) })
if (!dir.exists("R") && dir.exists("../R")) setwd("..")
suppressMessages(suppressWarnings({ source("R/carregar.R"); carregar_projeto("R") }))

falhas <- 0L
checar <- function(descricao, condicao) {
  cat(if (isTRUE(condicao)) "  ok   " else "  FALHA", descricao, "\n")
  if (!isTRUE(condicao)) falhas <<- falhas + 1L
  invisible(condicao)
}

novo_banco <- function() {
  con <- suppressMessages(abrir_db(":memory:"))
  registrar(con, "alvo", tibble(taxon_id = c("A", "B"), especie = c("Genus alpha", "Genus beta")))
  registrar(con, "obras", tibble(obra_id = "o1", doi = "10.0/o1"))
  registrar(con, "obra_taxon", tibble(obra_id = "o1", taxon_id = c("A", "B"), fonte = "teste"))
  registrar(con, "trechos", tibble(
    trecho_id = c("t1", "t2"), obra_id = "o1", tipo = "texto", secao = NA_character_, pagina = 1L,
    idioma = "en", ordem = 1:2,
    texto = c("Genus alpha. Snout rounded in lateral view. Eyes dorsal.",
              "Genus beta. Snout sloped in lateral view. Eyes lateral.")))
  registrar(con, "estado_par", tidyr::crossing(taxon_id = c("A", "B"), trait_id = c("snout_shape_lv", "eyes_positioning")) |>
              mutate(estado = "nao_buscado", data_atualizacao = Sys.time()))
  con
}
traits <- tibble(trait_id = c("snout_shape_lv", "eyes_positioning"), nome = c("Snout shape", "Eyes"),
                 tipo = "categorico", unidade = NA_character_, termos_busca = c("snout", "eyes"),
                 valores_aceitos = c("rounded;sloped", "dorsal;lateral"), status = "fechado",
                 nomes_alternativos = NA_character_, regra_extracao = NA_character_)
cfg <- list(encoder_local = "", prompt_versao = "t",
            agentes = list(valor = list(provedor = "anthropic", modelo = "claude-sonnet-5-5"),
                           forte = list(provedor = "anthropic", modelo = "claude-opus-5-5")))

# simulacoes ---------------------------------------------------------------------
lotes <- list()
criar_chat <- function(spec, sistema) list(modelo = spec$modelo, sistema = sistema)
obter_contexto <- function(con, obra_id, cfg) list(estagio = "25", temperatura_c = NA, ambiente = NA, n = NA, dispersao = NA)
uso_tokens <- function() tibble(provider = character(), model = character(), input = numeric(), output = numeric())
custo_tokens <- function(antes, depois) tibble(model = character(), input = numeric(), output = numeric(), usd = numeric())
resposta <- "normal"
batch_chat_structured <- function(chat, prompts, path, type, include_tokens = FALSE, ...) {
  lotes[[length(lotes) + 1]] <<- list(modelo = chat$modelo, prompts = unlist(prompts), path = path)
  p <- unlist(prompts)
  snout <- grepl("Trait: Snout", p)
  alpha <- grepl("Especie: Genus alpha", p)
  forte <- grepl("Releia com atencao", p)
  d <- tibble(
    encontrado = !(alpha & !snout) | forte,
    valor_cat = ifelse(snout, ifelse(alpha, "rounded", "sloped"), ifelse(alpha, "dorsal", "lateral")),
    unidade = NA_character_, nome_no_artigo = NA_character_, confianca = 0.9,
    # alpha x olhos: sem span no modelo barato (escalona); o forte acha
    span_verbatim = ifelse(alpha & !snout & !forte, NA_character_,
                           ifelse(snout, ifelse(alpha, "Snout rounded in lateral view.", "Snout sloped in lateral view."),
                                  ifelse(alpha, "Eyes dorsal.", "Eyes lateral."))),
    input_tokens = 1000L, output_tokens = 100L, cached_input_tokens = 0L)
  if (resposta == "falha") d$encontrado[1] <- NA
  d
}

# ---------------------------------------------------------------------------
cat("\nlote normal\n")
con <- novo_banco()
ext <- suppressMessages(extrair_tudo_lote(con, traits, cfg, tempfile()))
valor <- Filter(function(l) l$modelo == "claude-sonnet-5-5", lotes)
forte <- Filter(function(l) l$modelo == "claude-opus-5-5", lotes)
checar("um lote por trait no modelo barato", length(valor) == 2)
checar("o prompt e o mesmo do modo normal (prompt_valor())",
       any(unlist(lapply(valor, `[[`, "prompts")) ==
             prompt_valor("Genus alpha. Snout rounded in lateral view. Eyes dorsal.",
                          as.list(traits[1, ]), "Genus alpha", NA_character_, "Genus alpha", "texto")))
checar("so o pedido sem span escalona, com o reforco, no modelo forte",
       length(forte) == 1 && length(forte[[1]]$prompts) == 1 &&
         grepl("Especie: Genus alpha", forte[[1]]$prompts) && grepl("Releia com atencao", forte[[1]]$prompts))
checar("4 registros bruto, com o span conferido no trecho", nrow(ext) == 4 && all(ext$status == "bruto"))
checar("o escalonado sai como llm_escalonado, com o modelo forte",
       ext$extrator[ext$taxon_id == "A" & ext$trait_id == "eyes_positioning"] == "llm_escalonado" &&
         ext$modelo_versao[ext$taxon_id == "A" & ext$trait_id == "eyes_positioning"] == "claude-opus-5-5")
checar("uma chamada registrada por pedido", DBI::dbGetQuery(con, "SELECT count(*) n FROM chamadas_valor")$n == 4)
checar("estado_par vira 'extraido'", all(DBI::dbGetQuery(con, "SELECT estado FROM estado_par")$estado == "extraido"))
cu <- DBI::dbGetQuery(con, "SELECT * FROM custo_extracao")
# Sonnet: 4 pedidos x (1000 x 2 + 100 x 10) / 1e6 x 0,5; Opus: 1 x (1000 x 4 + 100 x 20) / 1e6 x 0,5
checar("custo gravado com o desconto do lote",
       isTRUE(all.equal(sum(cu$usd), (4 * (1000 * 2 + 100 * 10) + 1 * (1000 * 4 + 100 * 20)) / 1e6 * 0.5)))
checar("rodar de novo nao refaz nada (pares ja chamados)",
       nrow(suppressMessages(extrair_tudo_lote(con, traits, cfg, tempfile()))) == 0)
DBI::dbDisconnect(con, shutdown = TRUE)

cat("\nerro no lote nao vira 'nao encontrado'\n")
con <- novo_banco(); lotes <- list(); resposta <- "falha"
msg <- tryCatch({ suppressMessages(extrair_tudo_lote(con, traits, cfg, tempfile())); "nao parou" }, error = conditionMessage)
checar("resposta ilegivel para a rodada", grepl("sem resposta legivel", msg))
checar("e nada e gravado", DBI::dbGetQuery(con, "SELECT count(*) n FROM chamadas_valor")$n == 0 &&
         DBI::dbGetQuery(con, "SELECT count(*) n FROM extracoes")$n == 0)
DBI::dbDisconnect(con, shutdown = TRUE)

cat("\nlimite de gasto antes de mandar\n")
con <- novo_banco(); lotes <- list(); resposta <- "normal"
msg <- tryCatch({ suppressMessages(extrair_tudo_lote(con, traits, cfg, tempfile(), limite_usd = 1e-9)); "nao parou" },
                error = conditionMessage)
checar("estimativa acima do limite para antes de enviar", grepl("passa do limite", msg) && length(lotes) == 0)
checar("estimar_custo_lote(): metade do preco cheio",
       isTRUE(all.equal(estimar_custo_lote(strrep("a", 3500), "", "claude-sonnet-5-5", saida = 100),
                        (1000 * 2 + 100 * 10) / 1e6 * 0.5)))
checar("modelo sem preco: estimativa NA (nao passa no limite)", is.na(estimar_custo_lote("a", "", "modelo-x")))
DBI::dbDisconnect(con, shutdown = TRUE)

cat(if (falhas == 0) "\ntodos os testes passaram\n\n" else sprintf("\n%d FALHA(S)\n\n", falhas))
quit(status = if (falhas == 0) 0 else 1)
