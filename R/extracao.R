# Extracao. Tres regras inegociaveis:
#   (1) todo valor volta com a frase literal que o sustenta (item 3);
#   (2) o encoder local faz o volume e o LLM so entra no que ficou dificil,
#       com modelo e prompt gravados em cada linha (item 12);
#   (3) o contexto da medida vem dos Metodos do artigo, nao da mesma frase do
#       valor (item 7) - por isso o agente de contexto roda uma vez por obra.

library(purrr)
library(dplyr)
library(stringr)

normalizar <- function(x) str_squish(tolower(x %||% ""))

#' O span tem que existir, letra por letra, no trecho. E a unica barreira
#' automatica contra valor inventado - e a que decide se a linha entra.
validar_span <- function(span, texto) {
  if (is.null(span) || is.na(span) || !nzchar(span)) return(FALSE)
  str_detect(normalizar(texto), fixed(normalizar(span)))
}

# ---- caminho local ----------------------------------------------------------

encoder <- local({
  mod <- NULL
  function(cfg) {
    if (is.null(mod)) {
      reticulate::source_python("python/encoder.py")
      mod <<- carregar_modelo(cfg$encoder_local)   # definida em encoder.py
    }
    mod
  }
})

classificar_local <- function(textos, trait, cfg) {
  m <- encoder(cfg)
  out <- prever_categorico(m, textos, trait$trait_id)   # encoder.py
  tibble::tibble(classe = out$classe, prob = out$prob)
}

# ---- contexto por obra ------------------------------------------------------

#' Le os Metodos uma vez e guarda. Custa uma chamada por artigo, nao por valor.
obter_contexto <- function(con, obra_id, cfg) {
  ja <- dbGetQuery(con, sprintf(
    "SELECT * FROM contexto_obra WHERE obra_id = '%s'", obra_id))
  if (nrow(ja) == 1) return(as.list(ja))

  ctx <- agente_contexto(con, obra_id, cfg)
  linha <- tibble::tibble(
    obra_id = obra_id,
    estagio = ctx$estagio %||% NA_character_,
    temperatura_c = as.numeric(ctx$temperatura_c %||% NA),
    ambiente = ctx$ambiente %||% NA_character_,
    n = as.integer(ctx$n %||% NA),
    dispersao = ctx$dispersao %||% NA_character_,
    span_verbatim = ctx$span_verbatim %||% NA_character_,
    escalonado = isTRUE(ctx$escalonado), data = Sys.time(),
    # agente_contexto() devolve NULL so quando nao ha nada para ler
    fonte_contexto = ctx$fonte_contexto %||% "nenhum")
  registrar(con, "contexto_obra", linha)
  as.list(linha)
}

# ---- roteamento -------------------------------------------------------------

#' Categorico: encoder local primeiro; agente de valor so abaixo do limiar.
#' Numerico: sempre o agente de valor, com escalonamento.
extrair_par <- function(con, obra_id, taxon_id, trait, cfg) {
  cand <- recuperar_candidatos(con, obra_id, taxon_id, trait)
  if (nrow(cand) == 0) return(tibble::tibble())
  especie <- dbGetQuery(con, sprintf("SELECT especie FROM alvo WHERE taxon_id='%s'", taxon_id))$especie
  ctx <- obter_contexto(con, obra_id, cfg)
  nomes <- aliases_de(con, taxon_id, obra_id)

  pmap_dfr(cand, function(trecho_id, tipo, secao, pagina, idioma, texto, escore,
                          ordem = NA, ancora = NA_character_, ...) {
    extrator <- NA_character_; modelo <- NA_character_; out <- NULL

    if (trait$tipo == "categorico" && nzchar(cfg$encoder_local)) {
      loc <- tryCatch(classificar_local(texto, trait, cfg), error = function(e) NULL)
      if (!is.null(loc) && !is.na(loc$prob[1]) && loc$prob[1] >= cfg$limiar_llm) {
        # O encoder da a classe, mas nao da a frase-fonte: o span vem de uma
        # busca literal pelo termo da classe no trecho. Sem achar, nao entra.
        alvo_txt <- str_extract(texto, regex(paste0("[^.]*", loc$classe[1], "[^.]*\\."),
                                             ignore_case = TRUE))
        if (!is.na(alvo_txt)) {
          out <- list(valor_cat = loc$classe[1], span_verbatim = alvo_txt,
                      confianca = loc$prob[1], escalonado = FALSE)
          extrator <- "encoder_local"; modelo <- basename(cfg$encoder_local)
        }
      }
    }

    if (is.null(out)) {
      # a frase-fonte tem de estar no trecho (validar_span abaixo); a ancora so
      # diz ao modelo de quem e a ficha quando o trecho nao nomeia a especie
      out <- agente_valor(texto, trait, especie, cfg, ancora = ancora, nomes = nomes, tipo = tipo)
      registrar(con, "chamadas_valor", tibble::tibble(
        obra_id = obra_id, taxon_id = taxon_id, trait_id = trait$trait_id,
        trecho_id = trecho_id, escalonado = isTRUE(out$escalonado),
        encontrado = isTRUE(out$encontrado), data = Sys.time()))
      if (is.null(out) || !isTRUE(out$encontrado)) return(tibble::tibble())
      extrator <- if (isTRUE(out$escalonado)) "llm_escalonado" else "llm"
      modelo <- if (isTRUE(out$escalonado)) cfg$agentes$forte$modelo
                else cfg$agentes$valor$modelo
    }

    registro_extracao(obra_id, trecho_id, taxon_id, trait, out, ctx, pagina, texto, extrator, modelo, cfg)
  })
}

#' Uma linha de extracoes a partir da resposta do agente (`out`). O span e
#' conferido contra o trecho aqui, nos dois modos (normal e lote).
registro_extracao <- function(obra_id, trecho_id, taxon_id, trait, out, ctx, pagina, texto,
                              extrator, modelo, cfg) {
  ok <- validar_span(out$span_verbatim, texto)
  tibble::tibble(
    extracao_id = id_de(obra_id, trecho_id, taxon_id, trait$trait_id, extrator),
    obra_id = obra_id, trecho_id = trecho_id, taxon_id = taxon_id,
    nome_no_artigo = out$nome_no_artigo %||% NA_character_,
    trait_id = trait$trait_id,
    valor_num = if (trait$tipo == "numerico") as.numeric(out$valor_num %||% NA) else NA_real_,
    valor_cat = if (trait$tipo == "categorico") as.character(out$valor_cat %||% NA) else NA_character_,
    unidade = out$unidade %||% NA_character_,
    # contexto herdado dos Metodos do artigo (item 7)
    estagio = ctx$estagio, temperatura_c = ctx$temperatura_c,
    ambiente = ctx$ambiente, n = ctx$n, dispersao = ctx$dispersao,
    pagina = pagina,
    span_verbatim = out$span_verbatim %||% "",
    confianca = as.numeric(out$confianca %||% NA),
    extrator = extrator, modelo_versao = modelo,
    prompt_versao = cfg$prompt_versao,
    origem_valor = "primaria", fonte_primaria_doi = NA_character_,
    status = if (ok) "bruto" else "rejeitado",
    motivo_rejeicao = if (ok) NA_character_ else "span_nao_encontrado_no_trecho",
    data = Sys.time())
}

#' Percorre os pares pendentes das obras ja estruturadas.
#'
#' O JOIN em obra_taxon e o que mantem o custo finito: so (obra, taxon) que a
#' busca de fato associou. Antes isto era um CROSS JOIN entre toda obra com
#' trechos e todo par pendente - no piloto, 376 especies x 48 traits x
#' n_obras. E nao era so custo: como recuperar_candidatos() cai nas tabelas da
#' obra quando nenhum trecho cita a especie, o agente de valor era chamado
#' para a especie X em cima de tabela de artigo sobre a especie Y.
#' `limite_usd`: o gasto e conferido depois de cada par e a rodada para ao
#' passar (03/10/2026). Antes so rodar_rodada(), do piloto zero, tinha limite.
extrair_tudo <- function(con, traits, cfg, limite_usd = Inf) {
  pend <- pares_pendentes(con)

  uso0 <- uso_tokens()
  # o custo e gravado em custo_extracao ao sair, inclusive quando a rodada
  # para no limite ou por erro (04/10/2026)
  feito <- new.env(); feito$pares <- 0L; feito$ok <- FALSE
  on.exit(registrar_custo_extracao(con, custo_tokens(uso0, uso_tokens()), feito$pares, !feito$ok), add = TRUE)
  out <- pmap_dfr(pend, function(obra_id, taxon_id, trait_id) {
    feito$pares <- feito$pares + 1L
    trait <- as.list(filter(traits, trait_id == !!trait_id)[1, ])
    ext <- extrair_par(con, obra_id, taxon_id, trait, cfg)
    if (nrow(ext) > 0) {
      registrar(con, "extracoes", ext)
      if (any(ext$status == "bruto")) atualizar_estado_par(con, taxon_id, trait_id, "extraido")
    }
    gasto <- sum(custo_tokens(uso0, uso_tokens())$usd, na.rm = TRUE)
    if (gasto > limite_usd)
      stop(sprintf("limite de US$ %.2f passado (US$ %.4f); parado em %s, especie %s, trait %s",
                   limite_usd, gasto, obra_id, taxon_id, trait_id), call. = FALSE)
    ext
  })
  feito$ok <- TRUE
  out
}

#' Uma linha por modelo em custo_extracao (ou uma linha zerada, se nada foi
#' chamado). `custo`: saida de custo_tokens().
registrar_custo_extracao <- function(con, custo, pares, parou) {
  if (!nrow(custo)) custo <- tibble::tibble(model = NA_character_, input = 0, output = 0, usd = 0)
  registrar(con, "custo_extracao", tibble::tibble(
    data = Sys.time(), modelo = custo$model, input = custo$input, output = custo$output,
    usd = custo$usd, pares = as.integer(pares), parou = parou))
}


#' Pares (obra, especie, trait) ainda nao chamados: o que extrair_tudo() e
#' extrair_tudo_lote() percorrem.
pares_pendentes <- function(con) {
  dbGetQuery(con, "
    SELECT DISTINCT t.obra_id, ot.taxon_id, e.trait_id
      FROM trechos t
      JOIN obra_taxon ot USING (obra_id)
      JOIN estado_par e  ON e.taxon_id = ot.taxon_id
     WHERE e.estado IN ('nao_buscado','buscado_sem_dado')
       -- retomada (03/10/2026): par sem valor continua 'nao_buscado', entao
       -- sem isto rodar de novo refazia e pagava de novo cada par ja chamado
       AND NOT EXISTS (SELECT 1 FROM chamadas_valor c
                        WHERE c.obra_id = t.obra_id AND c.taxon_id = ot.taxon_id
                          AND c.trait_id = e.trait_id)")
}
