# Teste de fumaca da BUSCA: UMA especie, da consulta ao PDF.
#
# Companheiro de R/fumaca.R, que cobre a extracao. Este cobre a fase que vem
# antes e que nunca rodou: montar consulta, bater nas APIs, triar, baixar.
#
# A triagem usa o modelo barato (uma chamada por obra, so titulo/ano), e por
# isso ela e OPCIONAL aqui - com triar = FALSE o teste nao gasta um centavo e
# ainda responde a pergunta que importa: a busca acha o artigo certo?
#
# Uso:
#   source("R/fumaca_busca.R")
#   r <- teste_de_fumaca_busca("Physalaemus barrioi")        # de graca
#   r <- teste_de_fumaca_busca("Physalaemus barrioi",
#                              triar = TRUE, baixar_pdf = TRUE)
#   r$obras   # a tabela crua
#
# Depois:
#   limpar_fumaca_busca(abrir_db("girinos.duckdb"), "TESTEBUSCA001")

library(DBI)
library(dplyr)
library(purrr)
library(stringr)

# source() sempre, nao so quando garantir_projeto() falta: uma versao velha
# dele em memoria e exatamente o que deixaria funcao velha passar.
source("R/carregar.R")
garantir_projeto()


#' @param especie nome aceito, como vai para a consulta
#' @param taxon_id identificador; prefixo TESTE para poder apagar depois
#' @param idiomas quais consultas montar; o default vem do config
#' @param triar TRUE chama o agente de triagem (custa; modelo barato)
#' @param baixar_pdf TRUE tenta Unpaywall + download das obras relevantes
#' @param esperado regex de um titulo que VOCE sabe que deveria aparecer; o
#'   teste reporta se ele veio e de qual fonte. E a unica forma de medir a
#'   busca sem conjunto-ouro.
#' @param ouro CSV com colunas obra_id e relevante (sim/nao), preenchido por
#'   humano ANTES de ver a triagem; com triar = TRUE, o teste cruza os dois.
teste_de_fumaca_busca <- function(especie, taxon_id = "TESTEBUSCA001",
                                  idiomas = NULL, triar = FALSE,
                                  baixar_pdf = FALSE, esperado = NULL,
                                  ouro = NULL, config_path = "config.yml") {
  cfg <- config::get(file = config_path)
  idiomas <- idiomas %||% cfg$idiomas
  t0 <- Sys.time()
  con <- abrir_db(cfg$db)
  on.exit(dbDisconnect(con, shutdown = TRUE), add = TRUE)

  registrar(con, "alvo", tibble::tibble(
    taxon_id = taxon_id, especie = especie,
    genero = str_extract(especie, "^\\S+"), epiteto = str_extract(especie, "\\S+$"),
    familia = NA_character_, status_ext_morph = NA_character_,
    status_internal_oral = NA_character_, status_chondrocranium = NA_character_,
    girino_descrito = NA, fonte_lista = "teste_de_fumaca_busca",
    data_lista = Sys.Date()))

  # --- 1. consulta ---------------------------------------------------------
  cat("\n[1/4] Consultas\n")
  consultas <- montar_consultas(tibble::tibble(taxon_id = taxon_id, especie = especie),
                                idiomas)
  walk2(consultas$idioma, consultas$consulta,
        ~ cat(sprintf("  %s: %s\n", .x, .y)))

  # --- 2. busca ------------------------------------------------------------
  cat("\n[2/4] APIs (OpenAlex + Crossref", if (nzchar(cfg$bhl_key %||% "")) "+ BHL" else "", ")\n")
  t_busca <- system.time(obras <- executar_busca(con, consultas, cfg))[["elapsed"]]
  cat(sprintf("  %.1fs | %d obra(s) distinta(s)\n", t_busca, nrow(obras)))
  if (nrow(obras) == 0) {
    cat("  ZERO. Antes de culpar a especie, conferir a consulta acima na\n")
    cat("  interface da OpenAlex: clausula AND demais zera o resultado.\n")
    return(invisible(list(consultas = consultas, obras = obras)))
  }

  por_fonte <- count(obras, fonte)
  cat("  por fonte:", paste(por_fonte$fonte, por_fonte$n, sep = "=", collapse = " | "), "\n")
  cat("  com DOI:", sum(!is.na(obras$doi)), "| com url_pdf:", sum(!is.na(obras$url_pdf)), "\n")

  # --- 3. o que importa: o artigo certo esta na lista? ----------------------
  # A ordem abaixo NAO e ranking de relevancia: e a ordem das consultas
  # (pt, es, en) e, dentro de cada uma, OpenAlex antes de Crossref. Por isso o
  # teste diz se o artigo esperado veio e de qual fonte, nao em que posicao.
  # Com o filtro de binomio no Crossref a lista e curta: imprime ate 40.
  cat("\n[3/4] Obras (ordem das consultas, nao de relevancia)\n")
  for (i in seq_len(min(40, nrow(obras)))) {
    cat(sprintf("  %2d. %-8s %s  %s\n", i, obras$fonte[i], obras$ano[i] %||% "????",
                str_trunc(obras$titulo[i] %||% "(sem titulo)", 80)))
  }
  if (nrow(obras) > 40) cat("  ... e mais", nrow(obras) - 40, "\n")
  pos <- NA_integer_
  if (!is.null(esperado)) {
    hit <- which(str_detect(obras$titulo %||% "", regex(esperado, ignore_case = TRUE)))
    pos <- if (length(hit)) hit[1] else NA_integer_
    cat("\n  esperado (", esperado, "): ",
        if (is.na(pos)) "NAO ENCONTRADO <- a busca nao serve ainda"
        else paste0("encontrado (", obras$fonte[pos], ", ", obras$doi[pos] %||% "sem DOI", ")"),
        "\n", sep = "")
  }

  # --- 4. triagem e PDF (opcionais, custam) --------------------------------
  triado <- NULL; pdfs <- NULL
  if (triar) {
    cat("\n[4/4] Triagem\n")
    triado <- triar_obras(con, obras, cfg)
    if (nrow(triado) > 0) {
      n_regra <- sum(triado$decidido_por == "regra:binomio_no_titulo")
      cat("  ", n_regra, " pela regra do binomio no titulo, ", nrow(triado) - n_regra,
          " pelo modelo | com resumo: ", sum(!is.na(obras$resumo)), " de ", nrow(obras),
          "\n", sep = "")
      # relevante pode ser NA (chamada falhou): conta como "sem resposta", nunca
      # como irrelevante
      cat("  relevantes:", sum(triado$relevante, na.rm = TRUE), "de", nrow(triado),
          "| sem resposta:", sum(is.na(triado$relevante)),
          "| na margem humana:", sum(triado$decidido_por == "fila_humana"), "\n\n")
      tt <- left_join(triado, select(obras, obra_id, titulo), by = "obra_id")
      for (i in seq_len(nrow(tt))) {
        marca <- if (is.na(tt$relevante[i])) "??"
                 else if (tt$decidido_por[i] == "regra:binomio_no_titulo") "+R"
                 else if (tt$relevante[i]) "+ " else "- "
        cat(sprintf("   %s %4s  %s\n", marca,
                    if (is.na(tt$prob[i])) "  - " else sprintf("%.2f", tt$prob[i]),
                    str_trunc(tt$titulo[i] %||% "(sem titulo)", 80)))
      }
      if (!is.null(ouro)) comparar_com_ouro(tt, ouro)
    }
    if (baixar_pdf) {
      cat("\n  Aquisicao\n")
      pdfs <- adquirir_pdfs(con, cfg)
      if (nrow(pdfs) > 0) {
        cat("  ", paste(names(table(pdfs$status)), table(pdfs$status),
                        sep = "=", collapse = " | "), "\n", sep = "")
      }
    }
  } else {
    cat("\n[4/4] Triagem e download: pulados (triar = FALSE).\n")
    cat("  Confira o ranking acima primeiro. Se o artigo certo nao estiver la,\n")
    cat("  triar nao resolve - o problema e na consulta.\n")
  }

  dur <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
  cat(sprintf("\n%.0fs no total\n", dur))
  cat("Confira titulo por titulo: a triagem le titulo, resumo e ano, e e\n")
  cat("nesse material que a decisao de relevancia se resolve ou se perde.\n\n")

  invisible(list(consultas = consultas, obras = obras, triado = triado,
                 pdfs = pdfs, posicao_esperado = pos, segundos = dur))
}

#' Cruza a triagem do agente com a classificacao humana, feita ANTES e sem ver
#' o que o modelo disse. O erro que importa e o falso negativo: obra relevante
#' que o agente descartou some da base sem ninguem saber. Falso positivo so
#' custa um download e um GROBID a mais.
comparar_com_ouro <- function(tt, ouro) {
  delim <- if (grepl(";", readLines(ouro, n = 1, warn = FALSE))) ";" else ","
  h <- readr::read_delim(ouro, delim = delim, show_col_types = FALSE,
                         col_types = readr::cols(.default = "c")) |>
    transmute(obra_id, humano = tolower(trimws(relevante)) %in% c("sim", "s", "yes", "y"),
              marcado = tolower(trimws(relevante)) %in% c("sim", "s", "yes", "y", "nao", "não", "n", "no"))
  x <- inner_join(tt, filter(h, marcado), by = "obra_id")
  com_resp <- filter(x, !is.na(relevante))
  vp <- sum(com_resp$relevante & com_resp$humano)
  fn <- sum(!com_resp$relevante & com_resp$humano)
  fp <- sum(com_resp$relevante & !com_resp$humano)
  vn <- sum(!com_resp$relevante & !com_resp$humano)
  cat("\n  --- contra a classificacao humana (", nrow(x), " obras em comum) ---\n", sep = "")
  cat(sprintf("  concordancia: %d de %d | sensibilidade: %d/%d | especificidade: %d/%d\n",
              vp + vn, nrow(com_resp), vp, vp + fn, vn, vn + fp))
  cat(sprintf("  falsos negativos (humano sim, agente nao): %d  <- obra perdida\n", fn))
  cat(sprintf("  falsos positivos (humano nao, agente sim): %d  <- so custo\n", fp))
  if (sum(is.na(x$relevante)) > 0)
    cat("  sem resposta do agente:", sum(is.na(x$relevante)), "\n")
  disc <- filter(com_resp, relevante != humano)
  for (i in seq_len(nrow(disc))) {
    cat(sprintf("   %s humano=%s agente=%s (%.2f)  %s\n",
                if (disc$humano[i]) "FN" else "FP",
                if (disc$humano[i]) "sim" else "nao", if (disc$relevante[i]) "sim" else "nao",
                disc$prob[i], str_trunc(disc$titulo[i] %||% "", 70)))
    cat("        ", str_trunc(disc$justificativa[i] %||% "", 100), "\n")
  }
  invisible(x)
}

# ---------------------------------------------------------------------------
# Depois da busca: GROBID + extracao nas obras que a busca ligou a especie.
# ---------------------------------------------------------------------------

#' Fecha a especie de ponta a ponta usando as funcoes do PROPRIO pipeline
#' (estruturar_obras, extrair_tudo, checar_plausibilidade,
#' reconciliar_internas) - nao as do teste de fumaca da extracao, que pega um
#' PDF escolhido a dedo. Aqui as obras sao as que a busca achou, a triagem
#' aprovou e a aquisicao (automatica ou manual) trouxe.
#'
#' Mede o custo: tokens por modelo e uma estimativa em dolar.
#'
#' Uso, depois de teste_de_fumaca_busca() e importar_pdfs_manuais():
#'   e <- teste_de_fumaca_extracao("TESTEBUSCA001")
teste_de_fumaca_extracao <- function(taxon_id = "TESTEBUSCA001", config_path = "config.yml") {
  cfg <- config::get(file = config_path)
  t0 <- Sys.time(); uso0 <- uso_tokens()
  con <- abrir_db(cfg$db)
  on.exit(dbDisconnect(con, shutdown = TRUE), add = TRUE)

  alvo <- dbGetQuery(con, sprintf("SELECT * FROM alvo WHERE taxon_id = '%s'", taxon_id))
  if (nrow(alvo) != 1) stop("taxon_id ", taxon_id, " nao esta em alvo: rode teste_de_fumaca_busca() antes")
  traits <- carregar_traits(cfg$traits) |> filter(!is.na(status), status == "fechado")
  registrar(con, "traits", traits |> select(any_of(c(
    "trait_id", "nome", "tipo", "unidade", "estagio_ref", "definicao",
    "valores_aceitos", "min_plausivel", "max_plausivel", "termos_busca"))))
  semear_estado_par(con, alvo, traits)
  cat("\n", alvo$especie, " | traits fechados: ", paste(traits$trait_id, collapse = ", "), "\n", sep = "")

  obras <- dbGetQuery(con, sprintf("
    SELECT o.obra_id, o.titulo, o.status, o.caminho_pdf
      FROM obras o JOIN obra_taxon ot USING (obra_id) JOIN triagem t USING (obra_id)
     WHERE ot.taxon_id = '%s' AND t.relevante", taxon_id))
  com_pdf <- filter(obras, !is.na(caminho_pdf))
  cat(sprintf("obras relevantes: %d | com PDF: %d (%s)\n", nrow(obras), nrow(com_pdf),
              paste(names(table(com_pdf$status)), table(com_pdf$status), sep = "=", collapse = ", ")))
  sem <- filter(obras, is.na(caminho_pdf))
  for (i in seq_len(nrow(sem))) cat("   sem PDF:", str_trunc(sem$titulo[i], 70), "\n")

  # --- 1. GROBID -------------------------------------------------------------
  cat("\n[1/3] GROBID\n")
  t_g <- system.time(est <- estruturar_obras(con, cfg))[["elapsed"]]
  tr <- dbGetQuery(con, sprintf("
    SELECT t.obra_id, count(*) AS n,
           sum(CASE WHEN lower(t.secao) LIKE '%%method%%' OR lower(t.secao) LIKE '%%metodo%%'
                     OR lower(t.secao) LIKE '%%material%%' THEN 1 ELSE 0 END) AS n_metodos
      FROM trechos t JOIN obra_taxon ot USING (obra_id)
     WHERE ot.taxon_id = '%s' GROUP BY 1", taxon_id))
  tr <- left_join(select(com_pdf, obra_id, titulo), tr, by = "obra_id")
  cat(sprintf("  %.0fs | %d obra(s) processada(s) agora\n", t_g, nrow(est)))
  for (i in seq_len(nrow(tr))) {
    cat(sprintf("  %4s trechos | Metodos: %-3s | %s\n", coalesce(as.character(tr$n[i]), "0"),
                if (coalesce(tr$n_metodos[i], 0) > 0) "sim" else "NAO",
                str_trunc(tr$titulo[i], 62)))
  }

  # --- 2. extracao -----------------------------------------------------------
  cat("\n[2/3] Extracao (contexto + valor, so pares (obra, especie) ligados pela busca)\n")
  t_e <- system.time(ext <- extrair_tudo(con, traits, cfg))[["elapsed"]]
  cat(sprintf("  %.0fs | %d registro(s)\n", t_e, nrow(ext)))

  # --- 3. validacao ----------------------------------------------------------
  cat("\n[3/3] Validacao\n")
  pl <- checar_plausibilidade(con, traits)
  rc <- reconciliar_internas(con, traits)
  if (nrow(pl)) cat("  plausibilidade:", paste(pl$motivo, pl$n, sep = "=", collapse = " | "), "\n")
  if (nrow(rc)) cat("  reconciliacao:", paste(rc$motivo, rc$n, sep = "=", collapse = " | "), "\n")
  if (!nrow(pl) && !nrow(rc)) cat("  nada a apontar\n")

  final <- dbGetQuery(con, sprintf("
    SELECT e.obra_id, o.titulo, e.trait_id, e.valor_cat, e.valor_num, e.unidade, e.status,
           e.motivo_rejeicao, e.confianca, e.extrator, e.nome_no_artigo, e.estagio,
           e.span_verbatim
      FROM extracoes e JOIN obras o USING (obra_id)
     WHERE e.taxon_id = '%s' ORDER BY o.titulo, e.trait_id", taxon_id))
  cat("\n--- registros, por obra ---\n")
  if (nrow(final) == 0) cat("  nenhum\n")
  for (ob in unique(final$obra_id)) {
    f <- filter(final, obra_id == ob)
    cat("\n  ", str_trunc(f$titulo[1], 90), "\n", sep = "")
    for (i in seq_len(nrow(f))) {
      v <- coalesce(f$valor_cat[i], paste(f$valor_num[i], coalesce(f$unidade[i], "")))
      cat(sprintf("    [%s%s] %s = %s | conf %s | nome no artigo: %s | estagio: %s\n",
                  f$status[i], if (!is.na(f$motivo_rejeicao[i])) paste0(": ", f$motivo_rejeicao[i]) else "",
                  f$trait_id[i], v, format(round(f$confianca[i], 2)), coalesce(f$nome_no_artigo[i], "-"),
                  coalesce(f$estagio[i], "-")))
      cat("      \"", str_trunc(str_squish(f$span_verbatim[i]), 150), "\"\n", sep = "")
    }
  }

  # --- custo -----------------------------------------------------------------
  dur <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
  custo <- custo_tokens(uso0, uso_tokens())
  cat(sprintf("\n%.0fs no total\n", dur))
  if (nrow(custo)) {
    for (i in seq_len(nrow(custo)))
      cat(sprintf("  %-28s entrada %7.0f | saida %6.0f tokens | ~US$ %s\n", custo$model[i],
                  custo$input[i], custo$output[i],
                  if (is.na(custo$usd[i])) "?" else formatC(custo$usd[i], format = "f", digits = 4)))
    cat(sprintf("  total estimado: US$ %.4f (precos de 30/09/2026, docs/infraestrutura.md)\n",
                sum(custo$usd, na.rm = TRUE)))
  }
  cat("Confira cada span contra o PDF: e o unico jeito de saber se o valor veio do artigo.\n\n")
  invisible(list(obras = obras, trechos = tr, extracoes = final, custo = custo, segundos = dur))
}

# US$ por milhao de tokens (entrada, saida, leitura de cache). Fonte:
# documentacao de modelos da Anthropic consultada em 30/09/2026 (ver
# docs/infraestrutura.md); leitura de cache conferida em 04/10/2026 (0,1x a
# entrada; 0,05x no Opus 5.5). Modelo fora da lista sai com custo "?" em vez
# de um numero inventado.
PRECO_MILHAO <- list(
  "claude-haiku-4-5-20251001" = c(1, 5, 0.10),
  "claude-sonnet-5-5"         = c(2, 10, 0.20),
  "claude-opus-5-5"           = c(4, 20, 0.20))

#' Tokens acumulados na sessao. 04/10/2026: a leitura de cache
#' (cached_input) ficava de fora, e o custo do modo normal saia por baixo -
#' o prefixo repetido (sistema e esquema) e lido do cache em quase toda
#' chamada; em Conte et al. (2007), ~93 mil tokens na rodada 6.
uso_tokens <- function() {
  u <- suppressMessages(ellmer::token_usage())
  if (is.null(u) || nrow(u) == 0)
    return(tibble::tibble(provider = character(), model = character(),
                          input = numeric(), output = numeric(), cached_input = numeric()))
  u <- tibble::as_tibble(u)
  if (!"cached_input" %in% names(u)) u$cached_input <- 0
  u[, c("provider", "model", "input", "output", "cached_input")]
}

#' token_usage() e acumulado da sessao: o custo da rodada e a diferenca.
custo_tokens <- function(antes, depois) {
  if (!"cached_input" %in% names(antes)) antes$cached_input <- numeric(nrow(antes))
  if (!"cached_input" %in% names(depois)) depois$cached_input <- numeric(nrow(depois))
  d <- full_join(depois, antes, by = c("provider", "model"), suffix = c("", ".0")) |>
    mutate(input = coalesce(input, 0) - coalesce(input.0, 0),
           output = coalesce(output, 0) - coalesce(output.0, 0),
           cached_input = coalesce(cached_input, 0) - coalesce(cached_input.0, 0)) |>
    filter(input > 0 | output > 0 | cached_input > 0) |>
    select(provider, model, input, output, cached_input)
  d$usd <- map2_dbl(d$model, seq_len(nrow(d)), function(m, i) {
    p <- PRECO_MILHAO[[m]]
    if (is.null(p)) NA_real_ else (d$input[i] * p[1] + d$output[i] * p[2] + d$cached_input[i] * p[3]) / 1e6
  })
  d
}

#' Apaga o que o teste gravou - da busca e da extracao.
limpar_fumaca_busca <- function(con, taxon_id = "TESTEBUSCA001") {
  obras <- dbGetQuery(con, sprintf(
    "SELECT obra_id FROM obra_taxon WHERE taxon_id = '%s'", taxon_id))$obra_id
  lista <- if (length(obras)) paste0("('", paste(obras, collapse = "','"), "')") else "('')"
  n <- c(
    extracoes  = dbExecute(con, sprintf("DELETE FROM extracoes WHERE taxon_id='%s'", taxon_id)),
    estado_par = dbExecute(con, sprintf("DELETE FROM estado_par WHERE taxon_id='%s'", taxon_id)),
    obra_taxon = dbExecute(con, sprintf("DELETE FROM obra_taxon WHERE taxon_id='%s'", taxon_id)),
    busca_log  = dbExecute(con, sprintf("DELETE FROM busca_log WHERE taxon_id='%s'", taxon_id)),
    alvo       = dbExecute(con, sprintf("DELETE FROM alvo WHERE taxon_id='%s'", taxon_id)),
    # so as obras que ficaram orfas: outra especie pode compartilhar a obra.
    # Os PDFs em pdf/ NAO sao apagados.
    trechos = dbExecute(con, sprintf(
      "DELETE FROM trechos WHERE obra_id IN %s
         AND obra_id NOT IN (SELECT obra_id FROM obra_taxon)", lista)),
    contexto = dbExecute(con, sprintf(
      "DELETE FROM contexto_obra WHERE obra_id IN %s
         AND obra_id NOT IN (SELECT obra_id FROM obra_taxon)", lista)),
    triagem = dbExecute(con, sprintf(
      "DELETE FROM triagem WHERE obra_id IN %s
         AND obra_id NOT IN (SELECT obra_id FROM obra_taxon)", lista)),
    obras = dbExecute(con, sprintf(
      "DELETE FROM obras WHERE obra_id IN %s
         AND obra_id NOT IN (SELECT obra_id FROM obra_taxon)", lista)))
  cat("linhas apagadas:", paste(names(n), n, sep = "=", collapse = " | "), "\n")
  invisible(n)
}

`%||%` <- function(x, y) if (is.null(x) || length(x) == 0 || all(is.na(x))) y else x
