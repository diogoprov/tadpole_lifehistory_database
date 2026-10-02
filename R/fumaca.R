# Teste de fumaca: UM artigo, UMA especie, ponta a ponta.
#
# Nao e o piloto. O piloto mede desempenho; este aqui so responde "a cadeia
# inteira funciona de verdade?" - GROBID, trechos, recuperacao, agente de
# contexto, agente de valor, validacao de span, gravacao no banco.
#
# De proposito NAO passa pelo {targets} nem pela fase de busca: queremos um
# PDF escolhido a dedo, nao a internet inteira.
#
# Uso:
#   source("R/fumaca.R")
#   r <- teste_de_fumaca("pdf/conte2007.pdf",
#                        especie  = "Scinax catharinae", ano = 2007,
#                        taxon_id = "TESTE001")
#   r$extracoes   # a tabela crua
#
# Depois de olhar os registros, para apagar o que o teste gravou:
#   limpar_fumaca(abrir_db("girinos.duckdb"), "TESTE001")

library(DBI)
library(dplyr)
library(purrr)
library(stringr)

# fumaca.R e diagnostico.R sao pontos de entrada: podem ser chamados com um
# source() solto, sem o {targets} ter carregado o resto de R/.
# source() sempre, nao so quando garantir_projeto() falta: uma versao velha
# dele em memoria e exatamente o que deixaria funcao velha passar.
source("R/carregar.R")
garantir_projeto()


#' A linha de 'obras' do teste de fumaca. O ano e obrigatorio: sem ele,
#' marcar_fonte_secundaria() nao tem como comparar a obra com as outras e o
#' registro fica com origem_valor vazia - foi o que aconteceu com Conte et al.
#' (2007), TESTE001, gravada com ano = NA (visto em 01/10/2026).
obra_de_fumaca <- function(pdf, ano, doi = NA_character_) {
  ano_int <- suppressWarnings(as.integer(ano))
  if (length(ano) != 1 || is.na(ano_int) || ano_int != ano ||
      ano_int < 1700 || ano_int > as.integer(format(Sys.Date(), "%Y"))) {
    stop("ano invalido: '", paste(ano, collapse = ", "),
         "'. Informe o ano de publicacao da obra (ex.: ano = 2007).", call. = FALSE)
  }
  tibble::tibble(
    obra_id = id_de(normalizePath(pdf)), doi = doi, titulo = basename(pdf),
    ano = ano_int, idioma = NA_character_, fonte = "teste_de_fumaca",
    url_pdf = NA_character_, url_suplementar = NA_character_,
    caminho_pdf = normalizePath(pdf), ocr = FALSE, status = "estruturada")
}

#' @param pdf caminho do PDF
#' @param especie nome como aparece na lista-alvo
#' @param ano ano de publicacao da obra (obrigatorio; ver obra_de_fumaca())
#' @param taxon_id identificador; use um prefixo TESTE para poder apagar depois
#' @param aliases outros nomes sob os quais a especie aparece no artigo
#' @param doi DOI da obra, se houver
#' @param config_path config.yml
teste_de_fumaca <- function(pdf, especie, ano, taxon_id = "TESTE001",
                            aliases = character(), doi = NA_character_,
                            config_path = "config.yml") {
  stopifnot(file.exists(pdf))
  # antes de qualquer gravacao no banco: ano errado para aqui
  obra <- obra_de_fumaca(pdf, ano, doi)
  cfg <- config::get(file = config_path)
  t0 <- Sys.time()
  con <- abrir_db(cfg$db)
  on.exit(dbDisconnect(con, shutdown = TRUE), add = TRUE)

  traits <- readr::read_csv(cfg$traits, show_col_types = FALSE) |>
    filter(!is.na(status), status == "fechado")
  if (nrow(traits) == 0) stop("nenhum trait com status = 'fechado' em ", cfg$traits)
  cat("traits fechados:", paste(traits$trait_id, collapse = ", "), "\n")

  # --- 1. o minimo de estado que extrair_par() espera encontrar no banco ----
  obra_id <- obra$obra_id
  registrar(con, "alvo", tibble::tibble(
    taxon_id = taxon_id, especie = especie,
    genero = str_extract(especie, "^\\S+"), epiteto = str_extract(especie, "\\S+$"),
    familia = NA_character_, status_ext_morph = NA_character_,
    status_internal_oral = NA_character_, status_chondrocranium = NA_character_,
    girino_descrito = TRUE, fonte_lista = "teste_de_fumaca",
    data_lista = Sys.Date()))
  if (length(aliases) > 0) {
    registrar(con, "sinonimos", tibble::tibble(
      taxon_id = taxon_id, nome_alternativo = aliases, fonte = "teste_de_fumaca"))
  }
  registrar(con, "traits", traits |> select(any_of(c(
    "trait_id", "nome", "tipo", "unidade", "estagio_ref", "definicao",
    "valores_aceitos", "min_plausivel", "max_plausivel", "termos_busca"))))
  registrar(con, "obras", obra)

  # --- 2. PDF -> TEI -> trechos --------------------------------------------
  cat("\n[1/3] GROBID\n")
  dir.create(cfg$dir_tei, showWarnings = FALSE, recursive = TRUE)
  tei <- file.path(cfg$dir_tei, paste0(obra_id, ".tei.xml"))
  t_grobid <- system.time(grobid_tei(pdf, cfg$grobid, tei))[["elapsed"]]
  trechos <- tei_para_trechos(tei, obra_id)
  registrar(con, "trechos", trechos)
  cat(sprintf("  %.1fs | %d trechos (%s)\n", t_grobid, nrow(trechos),
              paste(sprintf("%d %s", table(trechos$tipo), names(table(trechos$tipo))),
                    collapse = ", ")))
  secoes <- unique(na.omit(trechos$secao))
  cat("  secoes:", paste(str_trunc(secoes, 34), collapse = " | "), "\n")
  tem_metodos <- any(str_detect(tolower(secoes), "method|metodo|material"))
  cat("  secao de Metodos identificada:", tem_metodos,
      if (!tem_metodos) " <- o agente de contexto nao vai ter o que ler" else "", "\n")

  # --- 3. extracao ----------------------------------------------------------
  cat("\n[2/3] Contexto (le os Metodos uma vez)\n")
  ctx <- tryCatch(obter_contexto(con, obra_id, cfg), error = function(e) {
    cat("  falhou:", conditionMessage(e), "\n"); NULL })
  if (!is.null(ctx)) {
    cat(sprintf("  estagio=%s | ambiente=%s | temp=%s | n=%s\n",
                ctx$estagio %||% "-", ctx$ambiente %||% "-",
                ctx$temperatura_c %||% "-", ctx$n %||% "-"))
    cat("  span:", str_trunc(str_squish(ctx$span_verbatim %||% "-"), 150), "\n")
  }

  cat("\n[3/3] Valores\n")
  ext <- map_dfr(seq_len(nrow(traits)), function(i) {
    tr <- as.list(traits[i, ])
    cand <- recuperar_candidatos(con, obra_id, taxon_id, tr)
    cat(sprintf("  %-18s %d trecho(s) candidato(s)\n", tr$trait_id, nrow(cand)))
    e <- extrair_par(con, obra_id, taxon_id, tr, cfg)
    if (nrow(e) > 0) registrar(con, "extracoes", e)
    e
  })

  # --- 4. o que importa: olhar registro por registro ------------------------
  cat("\n--- registros extraidos ---\n")
  if (nrow(ext) == 0) {
    cat("  nenhum. Nao e necessariamente erro: pode ser que o artigo nao traga\n")
    cat("  esses caracteres, ou que a recuperacao nao tenha achado o trecho.\n")
  } else {
    for (i in seq_len(nrow(ext))) {
      v <- ext$valor_cat[i] %||% as.character(ext$valor_num[i])
      cat(sprintf("\n  [%s] %s = %s\n", ext$status[i], ext$trait_id[i], v))
      cat(sprintf("     extrator: %s (%s) | confianca: %s\n",
                  ext$extrator[i], ext$modelo_versao[i], ext$confianca[i]))
      cat("     span: ", str_trunc(str_squish(ext$span_verbatim[i]), 200), "\n", sep = "")
      if (!is.na(ext$motivo_rejeicao[i]))
        cat("     REJEITADO: ", ext$motivo_rejeicao[i], "\n", sep = "")
    }
  }

  dur <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
  cat(sprintf("\n%.0fs no total | %d registro(s), %d aprovado(s) no span\n",
              dur, nrow(ext), sum(ext$status == "bruto")))
  cat("Confira cada span acima contra o PDF antes de confiar em qualquer numero.\n\n")

  invisible(list(obra_id = obra_id, trechos = trechos, contexto = ctx,
                 extracoes = ext, segundos = dur))
}

#' Apaga o que o teste gravou, para a base nao comecar suja.
limpar_fumaca <- function(con, taxon_id = "TESTE001") {
  n <- c(
    extracoes = dbExecute(con, sprintf("DELETE FROM extracoes WHERE taxon_id='%s'", taxon_id)),
    alvo      = dbExecute(con, sprintf("DELETE FROM alvo WHERE taxon_id='%s'", taxon_id)),
    sinonimos = dbExecute(con, sprintf("DELETE FROM sinonimos WHERE taxon_id='%s'", taxon_id)),
    obras     = dbExecute(con, "DELETE FROM obras WHERE fonte='teste_de_fumaca'"))
  cat("linhas apagadas:", paste(names(n), n, sep = "=", collapse = " | "), "\n")
  invisible(n)
}

`%||%` <- function(x, y) if (is.null(x) || length(x) == 0 || all(is.na(x))) y else x
