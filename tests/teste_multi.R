# Teste da extracao de varios traits numa chamada (extrair_par_multi(),
# agente_valor_multi()).
#
# Sem API: criar_chat() e o contexto sao substituidos. DuckDB em memoria.
#
#   Rscript tests/teste_multi.R
#
# Por que (04/10/2026): com as fichas, a mesma ficha e candidata para todos
# os traits da especie, e cada trait custava uma chamada com o mesmo texto.
# Com 48 traits o custo do pipeline e o numero de chamadas.

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
registrar(con, "alvo", tibble(taxon_id = "A", especie = "Genus alpha"))
registrar(con, "obras", tibble(obra_id = "o1", doi = "10.0/o1"))
registrar(con, "obra_taxon", tibble(obra_id = "o1", taxon_id = "A", fonte = "teste"))
ficha <- paste("Genus alpha (Fig. 1) Characterization. Snout rounded in lateral view. Eyes dorsal.",
               strrep("Spiracle sinistral. ", 25))
registrar(con, "trechos", tibble(
  trecho_id = c("f1", "g1"), obra_id = "o1", tipo = c("ficha", "texto"),
  secao = c("Genus alpha (Fig. 1)", NA), pagina = 1L, idioma = "en", ordem = 1:2,
  texto = c(ficha, "Results. Genus alpha: snout rounded in lateral view.")))
traits <- tibble(trait_id = c("snout_shape_lv", "eyes_positioning"), nome = c("Snout shape", "Eyes"),
                 tipo = "categorico", unidade = NA_character_, termos_busca = c("snout", "eyes"),
                 valores_aceitos = c("rounded;sloped", "dorsal;lateral"), status = "fechado",
                 nomes_alternativos = NA_character_, regra_extracao = NA_character_, definicao = "")
cfg <- list(encoder_local = "", prompt_versao = "t",
            agentes = list(valor = list(provedor = "anthropic", modelo = "barato"),
                           forte = list(provedor = "anthropic", modelo = "forte")))

chamadas <- list()
olhos_sem_span <- FALSE
erro_api <- FALSE
criar_chat <- function(spec, sistema) list(chat_structured = function(prompt, type) {
  chamadas[[length(chamadas) + 1]] <<- list(modelo = spec$modelo, prompt = prompt)
  if (erro_api) stop("HTTP 400")
  snout <- list(encontrado = TRUE, valor_cat = "rounded", span_verbatim = "Snout rounded in lateral view.", confianca = 0.9)
  olhos <- list(encontrado = TRUE, valor_cat = "dorsal",
                span_verbatim = if (olhos_sem_span && spec$modelo == "barato") NA_character_ else "Eyes dorsal.", confianca = 0.9)
  if (grepl("Traits pedidos", prompt)) list(snout_shape_lv = snout, eyes_positioning = olhos)
  else if (grepl("Trait: Eyes", prompt)) olhos else snout
})
obter_contexto <- function(con, obra_id, cfg) list(estagio = NA, temperatura_c = NA, ambiente = NA, n = NA, dispersao = NA)

cat("\nficha candidata para os dois traits\n")
ext <- extrair_par_multi(con, "o1", "A", traits, cfg)
checar("a ficha vai ao modelo uma vez, com os dois traits", length(chamadas) == 1 &&
         grepl("snout_shape_lv", chamadas[[1]]$prompt) && grepl("eyes_positioning", chamadas[[1]]$prompt))
checar("o trecho do GROBID nao entra (a especie tem ficha)", !any(grepl("^Results", ext$span_verbatim)))
checar("um registro por trait, com o span conferido na ficha", nrow(ext) == 2 && all(ext$status == "bruto") &&
         setequal(ext$trait_id, traits$trait_id))
checar("extrator registra o modo multi", all(ext$extrator == "llm_multi"))
checar("uma chamada gravada por (trait, trecho)", DBI::dbGetQuery(con, "SELECT count(*) n FROM chamadas_valor")$n == 2)

cat("\nescalonamento por trait\n")
chamadas <- list(); olhos_sem_span <- TRUE
ext2 <- extrair_par_multi(con, "o1", "A", traits, cfg)
checar("o trait sem span e refeito so, no modelo forte, com o reforco",
       length(chamadas) == 2 && chamadas[[2]]$modelo == "forte" &&
         grepl("Trait: Eyes", chamadas[[2]]$prompt) && grepl("Releia com atencao", chamadas[[2]]$prompt) &&
         !grepl("Traits pedidos", chamadas[[2]]$prompt))
checar("o escalonado sai como llm_escalonado, o outro como llm_multi",
       ext2$extrator[ext2$trait_id == "eyes_positioning"] == "llm_escalonado" &&
         ext2$extrator[ext2$trait_id == "snout_shape_lv"] == "llm_multi")

cat("\ntrecho de um trait so segue o caminho de sempre\n")
chamadas <- list(); olhos_sem_span <- FALSE
ext3 <- extrair_par_multi(con, "o1", "A", traits[1, ], cfg)
checar("prompt de um trait (o mesmo do modo normal)", length(chamadas) == 1 &&
         !grepl("Traits pedidos", chamadas[[1]]$prompt) && grepl("Trait: Snout shape", chamadas[[1]]$prompt))

cat("\nerro de API nao vira 'nao encontrado'\n")
erro_api <- TRUE
msg <- tryCatch({ extrair_par_multi(con, "o1", "A", traits, cfg); "nao parou" }, error = conditionMessage)
checar("para a rodada com a mensagem da API", grepl("chamada ao modelo falhou", msg) && grepl("HTTP 400", msg))
DBI::dbDisconnect(con, shutdown = TRUE)

cat(if (falhas == 0) "\ntodos os testes passaram\n\n" else sprintf("\n%d FALHA(S)\n\n", falhas))
quit(status = if (falhas == 0) 0 else 1)
