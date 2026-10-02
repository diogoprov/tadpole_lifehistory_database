# Piloto zero: o extrator nos artigos que o grupo ja extraiu a mao para a
# planilha do livro, comparado com a planilha. Plano em docs/piloto-zero.md.
#
# Tudo o que tem dado da planilha (referencia, bancos das rodadas, planilha de
# adjudicacao) fica em `dir_saida`, por padrao "Claude outputs/piloto-zero/",
# que o .gitignore exclui: sao dados ineditos e o repositorio e publico.
#
# Uso (numa sessao com source("R/carregar.R"); carregar_projeto()):
#   cfg <- config::get(file = "config.yml")
#   preparar_piloto_zero(cfg)          # gratis: GROBID, sem modelo
#   rodar_rodada(cfg, 1, limite_usd = 2) # GASTA CREDITO - so com o Diogo pedindo
#   rodar_rodada(cfg, 2)               # idem
#   p <- comparar_piloto()             # gratis: gera adjudicacao.csv
#   resumo_medidas()                   # gratis: escalonamento, contexto, custo
#   concordancia_adjudicada(p$pares, ler_planilha_humana(".../adjudicacao.csv"))

library(purrr)
library(dplyr)
library(stringr)

DIR_PILOTO <- "Claude outputs/piloto-zero"
MAPA_PILOTO <- "inst/piloto_zero_obras.csv"
# Os dois traits com vocabulario fechado (Diogo, 01/10/2026).
TRAITS_PILOTO <- c("eyes_positioning", "snout_shape_lv")

# ---- referencia: a planilha -------------------------------------------------

ler_mapa_piloto <- function(caminho = MAPA_PILOTO) {
  readr::read_csv(caminho, comment = "#", show_col_types = FALSE,
                  col_types = readr::cols(.default = "c", ano = "i"))
}

#' O eventID da planilha, sem os sufixos que marcam ambiente dentro da mesma
#' obra (":temporary", ":permanent" - regra R13 da correcao da planilha).
evento_canonico <- function(eventID) sub(":(temporary|permanent)$", "", eventID)

#' obra_id do piloto: estavel e derivado do eventid, para as rodadas e a
#' comparacao concordarem sem precisar de tabela de ligacao.
obra_id_piloto <- function(eventid) map_chr(eventid, ~ id_de("piloto_zero", .x))

#' Registros da planilha para os traits do piloto, ligados a fonte do mapa.
#' Pura: recebe measurementorfact e taxon ja lidos. Fonte da planilha que nao
#' esta no mapa sai num aviso, nao some.
referencia_planilha <- function(mof, taxon, mapa, traits = TRAITS_PILOTO) {
  r <- mof |>
    filter(measurementType %in% traits) |>
    mutate(eventid = evento_canonico(eventID)) |>
    left_join(select(taxon, taxonID, scientificName), by = "taxonID")
  fora <- setdiff(unique(r$eventid), mapa$eventid)
  if (length(fora)) {
    warning("fonte(s) da planilha fora do mapa do piloto: ", paste(fora, collapse = ", "),
            call. = FALSE)
  }
  r |>
    inner_join(select(mapa, eventid, citacao), by = "eventid") |>
    transmute(eventid, citacao, obra_id = obra_id_piloto(eventid),
              taxon_id = taxonID, especie = scientificName,
              trait_id = measurementType, valor = measurementValue, measurementID)
}

ler_referencia_dwca <- function(dir_dwca = "dwca", mapa = ler_mapa_piloto()) {
  ler <- function(f) readr::read_tsv(file.path(dir_dwca, f), show_col_types = FALSE,
                                     col_types = readr::cols(.default = "c"))
  referencia_planilha(ler("measurementorfact.txt"), ler("taxon.txt"), mapa)
}

# ---- preparacao (gratis) ----------------------------------------------------

#' Monta o banco-base do piloto: especies, traits, obras com PDF, ligacao
#' obra -> especie (so as especies que a planilha tem naquela obra) e os
#' trechos via GROBID. Nao chama modelo.
#'
#' Banco separado do girinos.duckdb: cada rodada parte de uma copia dele
#' (rodar_rodada), entao uma rodada nao sobrescreve a outra nem pula par que a
#' outra ja extraiu (extracao_id nao tem rodada, e estado_par marcaria o par
#' como 'extraido').
preparar_piloto_zero <- function(cfg, dir_saida = DIR_PILOTO, dir_dwca = "dwca",
                                 mapa = ler_mapa_piloto()) {
  base <- file.path(dir_saida, "base.duckdb")
  if (file.exists(base)) stop(base, " ja existe; apague para refazer a preparacao", call. = FALSE)
  vivo <- tryCatch(httr2::resp_body_string(httr2::req_perform(httr2::req_timeout(
    httr2::request(paste0(cfg$grobid, "/api/isalive")), 10))), error = function(e) "")
  # sem GROBID, estruturar_obras() cai no texto por pagina, sem secoes - e o
  # piloto mede justamente o contexto que depende das secoes
  if (!grepl("true", vivo)) stop("GROBID nao responde em ", cfg$grobid, call. = FALSE)
  dir.create(dir_saida, showWarnings = FALSE, recursive = TRUE)

  mapa <- mutate(mapa, obra_id = obra_id_piloto(eventid),
                 caminho_original = if_else(is.na(arquivo_pdf), NA_character_,
                                            file.path(cfg$dir_pdf, arquivo_pdf)))
  sem_pdf <- filter(mapa, is.na(caminho_original) | !file.exists(caminho_original))
  if (nrow(sem_pdf)) message("sem PDF (fora do piloto): ", paste(sem_pdf$citacao, collapse = "; "))
  com_pdf <- filter(mapa, !obra_id %in% sem_pdf$obra_id)

  ref <- ler_referencia_dwca(dir_dwca, mapa) |> filter(obra_id %in% com_pdf$obra_id)
  readr::write_csv(ref, file.path(dir_saida, "referencia_planilha.csv"))

  traits <- carregar_traits(cfg$traits) |>
    filter(trait_id %in% TRAITS_PILOTO, !is.na(status), status == "fechado")
  if (!setequal(traits$trait_id, TRAITS_PILOTO)) {
    stop("traits do piloto sem vocabulario fechado em ", cfg$traits, call. = FALSE)
  }

  con <- abrir_db(base)
  on.exit(dbDisconnect(con, shutdown = TRUE), add = TRUE)
  registrar(con, "traits", traits |> select(any_of(c(
    "trait_id", "nome", "tipo", "unidade", "estagio_ref", "definicao",
    "valores_aceitos", "min_plausivel", "max_plausivel", "termos_busca"))))

  alvo <- distinct(ref, taxon_id, especie) |>
    mutate(genero = word(especie, 1), epiteto = word(especie, -1), familia = NA_character_,
           fonte_lista = "piloto_zero")
  registrar(con, "alvo", alvo)
  semear_estado_par(con, alvo, traits)

  # Os artigos de 2004-2007 usam nomes antigos; a planilha, os de Frost
  # (2026). Sem sinonimo, a recuperacao nao acha a especie no texto.
  sin <- carregar_sinonimos_curados("inst/sinonimos.csv") |> filter(taxon_id %in% alvo$taxon_id)
  if (file.exists("inst/asw_cache.rds")) {
    sin <- bind_rows(sin, sincronizar_sinonimos(alvo, relatorio = file.path(dir_saida, "asw_ambiguos.csv")))
  } else {
    message("sem inst/asw_cache.rds: so os sinonimos curados entram. Nome antigo no ",
            "artigo pode nao ser achado (rode atualizar_cache_asw(), gratis e lento)")
  }
  if (nrow(sin)) registrar(con, "sinonimos", distinct(sin))

  # copia de trabalho em pdf/<obra_id>.pdf; o arquivo do Diogo nao e tocado
  copia <- file.path(cfg$dir_pdf, paste0(com_pdf$obra_id, ".pdf"))
  walk2(com_pdf$caminho_original, copia, ~ if (!file.exists(.y)) file.copy(.x, .y))
  registrar(con, "obras", tibble::tibble(
    obra_id = com_pdf$obra_id, doi = com_pdf$doi, titulo = com_pdf$citacao, ano = com_pdf$ano,
    idioma = NA_character_, fonte = "piloto_zero", url_pdf = NA_character_,
    url_suplementar = NA_character_, caminho_pdf = normalizePath(copia), ocr = FALSE,
    status = "pdf_manual"))
  registrar(con, "obra_taxon", distinct(ref, obra_id, taxon_id) |> mutate(fonte = "piloto_zero"))

  estruturar_obras(con, cfg)
  trechos <- dbGetQuery(con, "SELECT obra_id, tipo, secao, texto FROM trechos")
  pares <- count(distinct(ref, obra_id, taxon_id), obra_id, name = "n_especies")
  resumo <- com_pdf |>
    select(obra_id, citacao) |>
    left_join(pares, by = "obra_id") |>
    mutate(n_trechos = map_int(obra_id, ~ sum(trechos$obra_id == .x)),
           fonte_contexto = map_chr(obra_id, ~ trechos_de_contexto(filter(trechos, obra_id == .x))$fonte))
  readr::write_csv(resumo, file.path(dir_saida, "preparacao.csv"))
  resumo
}

# ---- rodada (GASTA CREDITO) -------------------------------------------------

#' Uma rodada completa, num banco proprio (copia do base). Percorre os pares
#' (obra, especie, trait) direto, sem estado_par: com estado_par, a primeira
#' obra que extraisse um par o marcaria 'extraido' e as outras obras com a
#' mesma especie seriam puladas.
#'
#' Mede tempo e custo por obra (tabela custo_obra) e para se o acumulado
#' passar de `limite_usd` - regra de parada do plano: US$ 2 na rodada 1.
rodar_rodada <- function(cfg, n, dir_saida = DIR_PILOTO, limite_usd = 5) {
  base <- file.path(dir_saida, "base.duckdb")
  destino <- file.path(dir_saida, sprintf("rodada_%d.duckdb", n))
  if (!file.exists(base)) stop("rode preparar_piloto_zero() antes", call. = FALSE)
  if (file.exists(destino)) stop(destino, " ja existe; a rodada nao e refeita por cima", call. = FALSE)
  file.copy(base, destino)

  con <- abrir_db(destino)
  on.exit(dbDisconnect(con, shutdown = TRUE), add = TRUE)
  dbExecute(con, "CREATE TABLE IF NOT EXISTS custo_obra (
    obra_id VARCHAR, modelo VARCHAR, input DOUBLE, output DOUBLE, usd DOUBLE, segundos DOUBLE)")
  traits <- carregar_traits(cfg$traits) |> filter(trait_id %in% TRAITS_PILOTO)
  pares <- dbGetQuery(con, "SELECT obra_id, taxon_id FROM obra_taxon ORDER BY obra_id, taxon_id")

  gasto <- 0
  for (ob in unique(pares$obra_id)) {
    t0 <- Sys.time(); uso0 <- uso_tokens()
    for (tx in pares$taxon_id[pares$obra_id == ob]) {
      for (i in seq_len(nrow(traits))) {
        ext <- extrair_par(con, ob, tx, as.list(traits[i, ]), cfg)
        if (nrow(ext)) registrar(con, "extracoes", ext)
      }
    }
    c_ob <- custo_tokens(uso0, uso_tokens())
    # obra sem nenhuma chamada (nenhum trecho candidato) ainda registra o tempo
    if (nrow(c_ob) == 0) c_ob <- tibble::tibble(model = NA_character_, input = 0, output = 0, usd = 0)
    seg <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
    registrar(con, "custo_obra", tibble::tibble(
      obra_id = ob, modelo = c_ob$model, input = c_ob$input, output = c_ob$output,
      usd = c_ob$usd, segundos = seg))
    gasto <- gasto + sum(c_ob$usd, na.rm = TRUE)
    message(sprintf("rodada %d | %s | US$ %.4f | %.0f s | acumulado US$ %.4f",
                    n, ob, sum(c_ob$usd, na.rm = TRUE), seg, gasto))
    if (any(is.na(c_ob$usd))) warning("modelo sem preco em PRECO_MILHAO: custo subestimado", call. = FALSE)
    if (gasto > limite_usd) {
      stop(sprintf("limite de US$ %.2f passado (US$ %.4f) na rodada %d; parado depois de %s",
                   limite_usd, gasto, n, ob), call. = FALSE)
    }
  }
  checar_plausibilidade(con, traits)
  reconciliar_internas(con, traits)
  invisible(gasto)
}

# ---- comparacao (gratis) ----------------------------------------------------

#' Os quatro casos do plano, para um par (artigo, especie, trait).
#' Valores comparados sem caixa e sem espaco extra; varios valores de um lado
#' viram conjunto.
classificar_par <- function(planilha, modelo) {
  norm <- function(x) unique(str_squish(tolower(x[!is.na(x) & nzchar(x)])))
  p <- norm(planilha); m <- norm(modelo)
  if (!length(p) && !length(m)) return(NA_character_)
  if (!length(m)) return("so_planilha")
  if (!length(p)) return("so_modelo")
  if (setequal(p, m)) "igual" else "diverge"
}

#' Registros validos do modelo numa rodada: o span bateu (nao 'rejeitado') e
#' nao foi colapsado pela reconciliacao.
extracoes_da_rodada <- function(caminho) {
  con <- dbConnect(duckdb::duckdb(), caminho, read_only = TRUE)
  on.exit(dbDisconnect(con, shutdown = TRUE), add = TRUE)
  dbGetQuery(con, "
    SELECT e.obra_id, e.taxon_id, e.trait_id, e.valor_cat, e.span_verbatim,
           t.secao, e.status, e.extrator
      FROM extracoes e LEFT JOIN trechos t USING (trecho_id)
     WHERE e.status <> 'rejeitado'")
}

#' Um par por (obra, especie, trait) presente na planilha ou no modelo, com o
#' caso. Pura.
comparar_pares <- function(ref, modelo) {
  chave <- c("obra_id", "taxon_id", "trait_id")
  p <- ref |> group_by(across(all_of(chave))) |>
    summarise(valor_planilha = paste(sort(unique(valor)), collapse = " | "),
              vp = list(valor), .groups = "drop")
  m <- modelo |> group_by(across(all_of(chave))) |>
    summarise(valor_modelo = paste(sort(unique(valor_cat)), collapse = " | "),
              vm = list(valor_cat),
              span = paste(unique(span_verbatim), collapse = " || "),
              secao = paste(unique(na.omit(secao)), collapse = " || "), .groups = "drop")
  full_join(p, m, by = chave) |>
    mutate(caso = map2_chr(vp, vm, ~ classificar_par(.x %||% character(), .y %||% character()))) |>
    filter(!is.na(caso)) |>
    select(-vp, -vm)
}

#' Variacao entre rodadas: o par deu o mesmo conjunto de valores (ou nada nas
#' duas)? Pura.
estabilidade_rodadas <- function(r1, r2, pares) {
  conj <- function(r, o, t, tr) {
    v <- r$valor_cat[r$obra_id == o & r$taxon_id == t & r$trait_id == tr]
    sort(unique(str_squish(tolower(v[!is.na(v)]))))
  }
  pares |>
    distinct(obra_id, taxon_id, trait_id) |>
    mutate(estavel = pmap_lgl(list(obra_id, taxon_id, trait_id),
                              ~ identical(conj(r1, ..1, ..2, ..3), conj(r2, ..1, ..2, ..3))))
}

#' Compara a(s) rodada(s) com a planilha e escreve a planilha de adjudicacao
#' (so os pares que nao sao 'igual'), separada por ';' para o Excel em
#' portugues. Colunas veredito/causa/nota ficam vazias para o Diogo.
comparar_piloto <- function(dir_saida = DIR_PILOTO, rodadas = 1:2, mapa = ler_mapa_piloto()) {
  ref <- readr::read_csv(file.path(dir_saida, "referencia_planilha.csv"), show_col_types = FALSE,
                         col_types = readr::cols(.default = "c"))
  arq <- file.path(dir_saida, sprintf("rodada_%d.duckdb", rodadas))
  if (!file.exists(arq[1])) stop("falta ", arq[1], call. = FALSE)
  r <- map(arq[file.exists(arq)], extracoes_da_rodada)

  universo <- distinct(ref, obra_id, taxon_id)  # o modelo so roda nesses pares
  pares <- comparar_pares(ref, semi_join(r[[1]], universo, by = c("obra_id", "taxon_id"))) |>
    left_join(distinct(ref, obra_id, citacao), by = "obra_id") |>
    left_join(distinct(ref, taxon_id, especie), by = "taxon_id")
  if (length(r) >= 2) {
    pares <- left_join(pares, estabilidade_rodadas(r[[1]], r[[2]], pares),
                       by = c("obra_id", "taxon_id", "trait_id"))
  }

  if (!"estavel" %in% names(pares)) pares$estavel <- NA
  resumo <- pares |>
    group_by(trait_id) |>
    summarise(n = n(), igual = sum(caso == "igual"), diverge = sum(caso == "diverge"),
              so_planilha = sum(caso == "so_planilha"), so_modelo = sum(caso == "so_modelo"),
              concordancia_crua = igual / n, estaveis = mean(estavel), .groups = "drop")

  adj <- pares |>
    filter(caso != "igual") |>
    transmute(citacao, especie, trait_id, caso, valor_planilha, valor_modelo, span, secao,
              obra_id, taxon_id, veredito = "", causa = "", nota = "")
  readr::write_excel_csv2(adj, file.path(dir_saida, "adjudicacao.csv"), na = "")
  readr::write_csv(pares, file.path(dir_saida, "pares.csv"))
  readr::write_csv(resumo, file.path(dir_saida, "resumo_concordancia.csv"))
  list(pares = pares, resumo = resumo, n_adjudicar = nrow(adj))
}

#' Veredito do Diogo: modelo | planilha | ambos | nenhum. Concordancia
#' adjudicada = o modelo esta certo (igual, 'modelo' ou 'ambos'). Para se
#' faltar veredito ou houver valor fora da lista: adjudicacao incompleta nao
#' vira numero.
VEREDITOS <- c("modelo", "planilha", "ambos", "nenhum")

concordancia_adjudicada <- function(pares, adjudicacao) {
  adj <- mutate(adjudicacao, veredito = str_squish(tolower(veredito)))
  ruins <- adj$veredito[is.na(adj$veredito) | !adj$veredito %in% VEREDITOS]
  if (length(ruins)) {
    stop(length(ruins), " par(es) sem veredito valido (aceitos: ",
         paste(VEREDITOS, collapse = ", "), ")", call. = FALSE)
  }
  pares |>
    left_join(select(adj, obra_id, taxon_id, trait_id, veredito),
              by = c("obra_id", "taxon_id", "trait_id")) |>
    mutate(m_ok = caso == "igual" | veredito %in% c("modelo", "ambos"),
           p_ok = caso == "igual" | veredito %in% c("planilha", "ambos")) |>
    group_by(trait_id) |>
    # erros_do_modelo antes das medias: summarise() reaproveita nome ja resumido
    summarise(n = n(), erros_do_modelo = sum(!m_ok), concordancia_crua = mean(caso == "igual"),
              modelo_certo = mean(m_ok), planilha_certa = mean(p_ok), .groups = "drop")
}

#' Medidas 3 a 5 do plano, por rodada: escalonamento (chamadas_valor),
#' contexto (contexto_obra) e custo/tempo (custo_obra).
resumo_medidas <- function(dir_saida = DIR_PILOTO, rodadas = 1:2) {
  arq <- file.path(dir_saida, sprintf("rodada_%d.duckdb", rodadas))
  map2_dfr(rodadas[file.exists(arq)], arq[file.exists(arq)], function(n, caminho) {
    con <- dbConnect(duckdb::duckdb(), caminho, read_only = TRUE)
    on.exit(dbDisconnect(con, shutdown = TRUE), add = TRUE)
    ch <- dbGetQuery(con, "SELECT obra_id, escalonado, encontrado FROM chamadas_valor")
    ctx <- dbGetQuery(con, "SELECT obra_id, fonte_contexto, estagio FROM contexto_obra")
    cu <- dbGetQuery(con, "SELECT obra_id, sum(usd) usd, max(segundos) segundos FROM custo_obra GROUP BY 1")
    ch |>
      group_by(obra_id) |>
      summarise(chamadas = n(), escalonadas = sum(escalonado),
                escalonadas_que_acharam = sum(escalonado & encontrado), .groups = "drop") |>
      full_join(ctx, by = "obra_id") |>
      full_join(cu, by = "obra_id") |>
      mutate(rodada = n, .before = 1)
  }) |>
    (\(d) { readr::write_csv(d, file.path(dir_saida, "medidas.csv")); d })()
}
