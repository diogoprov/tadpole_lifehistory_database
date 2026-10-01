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

#' Apaga o que o teste gravou.
limpar_fumaca_busca <- function(con, taxon_id = "TESTEBUSCA001") {
  obras <- dbGetQuery(con, sprintf(
    "SELECT obra_id FROM obra_taxon WHERE taxon_id = '%s'", taxon_id))$obra_id
  lista <- if (length(obras)) paste0("('", paste(obras, collapse = "','"), "')") else "('')"
  n <- c(
    obra_taxon = dbExecute(con, sprintf("DELETE FROM obra_taxon WHERE taxon_id='%s'", taxon_id)),
    busca_log  = dbExecute(con, sprintf("DELETE FROM busca_log WHERE taxon_id='%s'", taxon_id)),
    alvo       = dbExecute(con, sprintf("DELETE FROM alvo WHERE taxon_id='%s'", taxon_id)),
    # so as obras que ficaram orfas: outra especie pode compartilhar a obra
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
