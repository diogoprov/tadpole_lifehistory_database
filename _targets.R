# Orquestracao com {targets}: cada etapa so re-roda se a entrada dela mudou.
# Num pipeline que vai rodar por meses, em rodadas, isso e o que impede
# re-baixar PDF e re-chamar modelo a cada execucao.
#
# Uso:  targets::tar_make()        roda o que esta desatualizado
#       targets::tar_visnetwork()  mostra o grafo

library(targets)
tar_option_set(
  packages = c("DBI", "duckdb", "dplyr", "purrr", "stringr", "tidyr",
               "httr2", "xml2", "readr", "jsonlite", "digest", "ellmer", "rlang"),
  format = "rds"
)
tar_source("R")

cfg <- config::get(file = "config.yml")

list(
  tar_target(config_arquivo, "config.yml", format = "file"),

  # --- entrada -------------------------------------------------------------
  tar_target(con, abrir_db(cfg$db), cue = tar_cue(mode = "always")),

  tar_target(bt5, ler_species_json(cfg$lista_alvo$url)),

  tar_target(alvo, {
    a <- carregar_lista_alvo(bt5, cfg$lista_alvo$apenas_descritos)
    registrar(con, "alvo", a); a
  }),

  # corpus-semente: a bibliografia que a propria BT 5.0 ja compilou
  tar_target(referencias, {
    r <- carregar_referencias(bt5)
    registrar(con, "referencias", r); r
  }),
  tar_target(semente, if (isTRUE(cfg$lista_alvo$semear_corpus))
    semear_corpus(con, referencias) else 0L),

  # sinonimia: cache da ASW e atualizado a mao com atualizar_cache_asw(alvo),
  # porque leva 10-15 min. Aqui so lemos o cache e juntamos aos curados.
  tar_target(sinonimos, {
    s <- dplyr::bind_rows(
      if (file.exists(cfg$sinonimia$cache_asw))
        sincronizar_sinonimos(alvo, cfg$sinonimia$cache_asw) else NULL,
      carregar_sinonimos_curados(cfg$sinonimia$curados))
    registrar(con, "sinonimos", s); s
  }),

  tar_target(traits, {
    t <- carregar_traits(cfg$traits)
    registrar(con, "traits", t); t
  }),

  tar_target(pares, semear_estado_par(con, alvo, traits)),

  # --- 1. busca ------------------------------------------------------------
  tar_target(taxa_rodada, {
    pares; priorizar_taxa(con, cfg$taxa_por_rodada)
  }),
  tar_target(consultas, montar_consultas(taxa_rodada, cfg$idiomas)),
  tar_target(obras, executar_busca(con, consultas, cfg)),
  tar_target(triado, triar_obras(con, obras, cfg)),
  tar_target(fila_triagem, exportar_fila_triagem(con, "revisao/triagem_margem.csv")),

  # --- 2. aquisicao e preparo ---------------------------------------------
  # inclui as obras-semente da BT 5.0, que ja entram como relevantes
  tar_target(pdfs, { triado; semente; adquirir_pdfs(con, cfg) }),
  tar_target(sem_pdf, exportar_sem_pdf(con, "revisao/sem_pdf.csv")),
  tar_target(estruturado, { pdfs; estruturar_obras(con, cfg) }),

  # --- 3. extracao ---------------------------------------------------------
  tar_target(extracoes, { estruturado; extrair_tudo(con, traits, cfg) }),

  # --- 4. validacao e revisao ---------------------------------------------
  tar_target(plausibilidade, { extracoes; checar_plausibilidade(con, traits) }),
  # Vem antes de marcar_fonte_secundaria() e de calibrar_limiares(): as duas
  # agrupam por valor, nao por par, e nao enxergam dois trechos da mesma obra
  # dizendo coisas diferentes.
  tar_target(reconciliacao, { plausibilidade; reconciliar_internas(con, traits) }),
  tar_target(fontes, { reconciliacao; marcar_fonte_secundaria(con) }),
  tar_target(ouro_planilhas,
             preparar_ouro(con, c("revisorA", "revisorB"), cfg$fracao_ouro, "revisao/ouro")),
  # importar_ouro() e importar_revisao() sao chamadas a mao depois que as
  # planilhas voltam preenchidas - o pipeline para aqui de proposito.
  tar_target(limiares, { fontes; calibrar_limiares(con, traits, cfg$precisao_alvo) }),
  tar_target(aprovacao, { limiares; aplicar_limiares(con) }),
  tar_target(fila_revisao,
             { aprovacao; exportar_revisao(con, "revisao/fila_revisao.csv", cfg$fracao_auditoria) }),

  # --- saida ---------------------------------------------------------------
  tar_target(treino, exportar_treino(con, "modelo/treino.csv")),
  tar_target(dwc, { aprovacao; escrever_dwc(con, "dwc", traits) }),
  tar_target(metricas, { dwc; relatorio_metricas(con, traits, "dwc/metricas.rds") }),
  tar_target(rodada_fechada, { dwc; fechar_rodada(con) })
)
