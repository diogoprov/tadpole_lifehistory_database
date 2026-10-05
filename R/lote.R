# Extracao pela API de lotes (Message Batches): 50% do preco, resposta em ate
# 24 h. Pedido do Diogo em 04/10/2026, depois da estimativa de custo do
# pipeline inteiro (48 traits, ~US$ 600-700 no modo normal).
#
# Mesmo resultado que extrair_tudo(): o prompt vem de prompt_valor() e o
# registro de registro_extracao(), os dois usados tambem pelo modo normal. A
# diferenca e a ordem: monta todos os pedidos, manda um lote por trait (o tipo
# da resposta depende do trait), espera, e o escalonamento vira um segundo
# lote, so com os pedidos que voltaram sem span (como com_escalonamento()).
#
# Erro nunca vira "nao encontrado" (principio 1). No ellmer 0.5.0, pedido que
# falha na API volta com .error, mas resposta que nao da para ler vira so um
# aviso e uma linha toda NA. Como `encontrado` e obrigatorio no tipo, linha
# com encontrado NA e falha: a rodada para antes de gravar qualquer coisa. O
# arquivo .json de cada lote guarda as respostas; rodar de novo retoma sem
# pagar de novo.
#
# O limite de gasto e conferido ANTES de mandar o lote, por estimativa (o
# lote nao da para interromper no meio, como o modo normal faz a cada par).

library(purrr)
library(dplyr)
library(stringr)

DESCONTO_LOTE <- 0.5

#' Custo estimado de um lote, em US$: ~3,5 caracteres por token de entrada e
#' `saida` tokens por resposta, ao preco do modelo com o desconto do lote.
#' Pura. Modelo sem preco em PRECO_MILHAO para a conta (NA nao passa no
#' limite).
estimar_custo_lote <- function(prompts, sistema, modelo, saida = 250) {
  p <- PRECO_MILHAO[[modelo]]
  if (is.null(p)) return(NA_real_)
  entrada <- sum((nchar(prompts) + nchar(sistema)) / 3.5)
  (entrada * p[1] + length(prompts) * saida * p[2]) / 1e6 * DESCONTO_LOTE
}

#' Confere as respostas de um lote: para em pedido com erro ou sem resposta
#' legivel. Pura.
checar_lote <- function(res, n, rotulo) {
  if (!is.data.frame(res) || nrow(res) != n) {
    stop(rotulo, ": o lote devolveu ", if (is.data.frame(res)) nrow(res) else 0,
         " respostas para ", n, " pedidos", call. = FALSE)
  }
  falhou <- is.na(res$encontrado)
  if (".error" %in% names(res)) falhou <- falhou | !map_lgl(res$.error, is.null)
  if (any(falhou)) {
    stop(rotulo, ": ", sum(falhou), " de ", n, " pedidos sem resposta legivel (linhas ",
         paste(head(which(falhou), 10), collapse = ", "), "). Nada foi gravado; ",
         "rodar de novo retoma do arquivo do lote.", call. = FALSE)
  }
  invisible(res)
}

#' Um lote por trait. `jobs`: trait_id e prompt. Devolve `jobs` com as
#' colunas da resposta e os tokens.
rodar_lotes <- function(jobs, spec, traits, dir_lote, rotulo) {
  if (!nrow(jobs)) return(jobs)
  map_dfr(split(jobs, jobs$trait_id), function(j) {
    trait <- as.list(filter(traits, trait_id == j$trait_id[1])[1, ])
    caminho <- file.path(dir_lote, paste0(rotulo, "_", trait$trait_id, ".json"))
    res <- batch_chat_structured(criar_chat(spec, SISTEMA_VALOR), as.list(j$prompt),
                                 path = caminho, type = tipo_valor(trait), include_tokens = TRUE)
    checar_lote(res, nrow(j), paste0(rotulo, " / ", trait$trait_id))
    res$.error <- NULL
    bind_cols(j, select(as_tibble(res), -any_of(names(j))))
  })
}

#' Extrai pela API de lotes os pares pendentes (ou `pares`, com obra_id,
#' taxon_id e trait_id). `dir_lote`: onde ficam os arquivos dos lotes.
extrair_tudo_lote <- function(con, traits, cfg, dir_lote, limite_usd = Inf, pares = NULL) {
  if (nzchar(cfg$encoder_local %||% "")) stop("o modo lote nao usa o encoder local", call. = FALSE)
  if (is.null(pares)) pares <- pares_pendentes(con)
  dir.create(dir_lote, showWarnings = FALSE, recursive = TRUE)

  jobs <- pmap_dfr(pares, function(obra_id, taxon_id, trait_id) {
    trait <- as.list(filter(traits, trait_id == !!trait_id)[1, ])
    cand <- recuperar_candidatos(con, obra_id, taxon_id, trait)
    if (!nrow(cand)) return(NULL)
    especie <- dbGetQuery(con, "SELECT especie FROM alvo WHERE taxon_id = ?", params = list(taxon_id))$especie
    nomes <- aliases_de(con, taxon_id, obra_id)
    anc <- if ("ancora" %in% names(cand)) cand$ancora else rep(NA_character_, nrow(cand))
    tibble::tibble(obra_id = obra_id, taxon_id = taxon_id, trait_id = trait_id,
                   trecho_id = cand$trecho_id, pagina = cand$pagina, texto = cand$texto,
                   prompt = pmap_chr(list(cand$texto, anc, cand$tipo),
                                     function(tx, a, tp) prompt_valor(tx, trait, especie, a, nomes, tp)))
  })
  if (!nrow(jobs)) return(tibble::tibble())

  estimado <- estimar_custo_lote(jobs$prompt, SISTEMA_VALOR, cfg$agentes$valor$modelo)
  message(sprintf("lote: %d pedidos em %d pares; custo estimado US$ %.2f (sem o escalonamento)",
                  nrow(jobs), nrow(distinct(jobs, obra_id, taxon_id, trait_id)), estimado))
  if (is.na(estimado) || estimado > limite_usd) {
    stop(sprintf("custo estimado (US$ %.2f) passa do limite de US$ %.2f; nada foi enviado",
                 estimado, limite_usd), call. = FALSE)
  }

  # contexto da obra: uma chamada por obra, no modo normal (sao poucas)
  uso0 <- uso_tokens()
  ctx <- map(set_names(unique(jobs$obra_id)), ~ obter_contexto(con, .x, cfg))
  custo_ctx <- custo_tokens(uso0, uso_tokens())

  r1 <- rodar_lotes(jobs, cfg$agentes$valor, traits, dir_lote, "valor")
  esc <- is.na(r1$span_verbatim)
  r2 <- rodar_lotes(mutate(select(r1[esc, ], all_of(names(jobs))), prompt = paste0(prompt, "\n\n", REFORCO_VALOR)),
                    cfg$agentes$forte, traits, dir_lote, "forte")
  final <- bind_rows(mutate(r1[!esc, ], escalonado = FALSE), mutate(r2, escalonado = TRUE))

  registrar(con, "chamadas_valor", transmute(final, obra_id, taxon_id, trait_id, trecho_id,
                                             escalonado, encontrado = encontrado %in% TRUE, data = Sys.time()))
  achou <- filter(final, encontrado %in% TRUE)
  ext <- pmap_dfr(achou, function(...) {
    r <- list(...)
    trait <- as.list(filter(traits, trait_id == r$trait_id)[1, ])
    modelo <- if (r$escalonado) cfg$agentes$forte$modelo else cfg$agentes$valor$modelo
    registro_extracao(r$obra_id, r$trecho_id, r$taxon_id, trait, r, ctx[[r$obra_id]], r$pagina, r$texto,
                      if (r$escalonado) "llm_escalonado" else "llm", modelo, cfg)
  })
  if (nrow(ext)) {
    registrar(con, "extracoes", ext)
    walk2(ext$taxon_id[ext$status == "bruto"], ext$trait_id[ext$status == "bruto"],
          ~ atualizar_estado_par(con, .x, .y, "extraido"))
  }

  # custo: tokens do lote a metade do preco, mais o contexto no preco cheio
  tok <- bind_rows(mutate(r1, modelo = cfg$agentes$valor$modelo), mutate(r2, modelo = cfg$agentes$forte$modelo)) |>
    group_by(model = modelo) |>
    summarise(input = sum(input_tokens), output = sum(output_tokens), .groups = "drop")
  preco <- function(m, k) map_dbl(m, ~ (PRECO_MILHAO[[.x]] %||% c(NA_real_, NA_real_))[k])
  tok$usd <- (tok$input * preco(tok$model, 1) + tok$output * preco(tok$model, 2)) / 1e6 * DESCONTO_LOTE
  custo <- bind_rows(tok, select(custo_ctx, any_of(c("model", "input", "output", "usd"))))
  registrar_custo_extracao(con, custo, nrow(distinct(jobs, obra_id, taxon_id, trait_id)), FALSE)
  message(sprintf("lote: %d pedidos, %d escalonados, %d registros; US$ %.4f",
                  nrow(final), sum(final$escalonado), nrow(ext), sum(custo$usd, na.rm = TRUE)))
  invisible(ext)
}
