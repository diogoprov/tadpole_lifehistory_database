# Armazenamento unico do pipeline: um arquivo DuckDB.
# Toda etapa le e escreve aqui; nada de estado em RDS solto.

library(DBI)
library(duckdb)

abrir_db <- function(caminho) {
  con <- dbConnect(duckdb::duckdb(), dbdir = caminho, read_only = FALSE)
  criar_esquema(con)
  con
}

criar_esquema <- function(con) {
  ddl <- c(
    # lista-alvo: unica fonte dos nomes aceitos (Brazilian Tadpoles 5.0).
    # taxon_id = o campo 'id' do proprio species.json.
    "CREATE TABLE IF NOT EXISTS alvo (
       taxon_id VARCHAR PRIMARY KEY, especie VARCHAR, genero VARCHAR,
       epiteto VARCHAR, familia VARCHAR,
       status_ext_morph VARCHAR, status_internal_oral VARCHAR,
       status_chondrocranium VARCHAR, girino_descrito BOOLEAN,
       fonte_lista VARCHAR, data_lista DATE)",

    # bibliografia ja catalogada na BT 5.0: o corpus-semente
    "CREATE TABLE IF NOT EXISTS referencias (
       taxon_id VARCHAR, carater VARCHAR, autor VARCHAR, ano INTEGER,
       titulo VARCHAR, periodico VARCHAR, doi VARCHAR, raw VARCHAR)",

    # sinonimos: ASW (via AmphiNom) + o que o grupo curar a mao.
    # amarra o nome como aparece no artigo antigo ao taxon_id da lista-alvo.
    "CREATE TABLE IF NOT EXISTS sinonimos (
       taxon_id VARCHAR, nome_alternativo VARCHAR, fonte VARCHAR)",

    # definicoes de trait (ja prontas pelo grupo)
    "CREATE TABLE IF NOT EXISTS traits (
       trait_id VARCHAR PRIMARY KEY, nome VARCHAR, tipo VARCHAR,
       unidade VARCHAR, estagio_ref VARCHAR, definicao VARCHAR,
       valores_aceitos VARCHAR, min_plausivel DOUBLE, max_plausivel DOUBLE,
       termos_busca VARCHAR)",

    # item 10: estado de cada par especie x trait. Sem esta tabela nao da
    # para distinguir "procurado e nao existe" de "nunca procurado".
    "CREATE TABLE IF NOT EXISTS estado_par (
       taxon_id VARCHAR, trait_id VARCHAR,
       estado VARCHAR,            -- nao_buscado | buscado_sem_dado | extraido | revisado
       data_atualizacao TIMESTAMP,
       PRIMARY KEY (taxon_id, trait_id))",

    "CREATE TABLE IF NOT EXISTS busca_log (
       busca_id VARCHAR PRIMARY KEY, taxon_id VARCHAR, fonte VARCHAR,
       idioma VARCHAR, consulta VARCHAR, data TIMESTAMP, n_resultados INTEGER)",

    "CREATE TABLE IF NOT EXISTS obras (
       obra_id VARCHAR PRIMARY KEY, doi VARCHAR, titulo VARCHAR, ano INTEGER,
       idioma VARCHAR, fonte VARCHAR, url_pdf VARCHAR, url_suplementar VARCHAR,
       caminho_pdf VARCHAR, ocr BOOLEAN, status VARCHAR)",

    # Por que esta obra entrou: para QUAL especie ela foi achada. Sem esta
    # tabela a ligacao se perde - 'obras' nao tem taxon_id, e tanto
    # executar_busca() quanto semear_corpus() deduplicam por obra. Ai
    # extrair_tudo() so pode cruzar toda obra com todo par pendente, o que
    # (a) custa 376 x 48 x n_obras chamadas no piloto e (b) deixa extrair um
    # caractere para a especie X de um artigo que e sobre a especie Y.
    "CREATE TABLE IF NOT EXISTS obra_taxon (
       obra_id VARCHAR, taxon_id VARCHAR,
       fonte VARCHAR,             -- busca | bt5_refs | manual
       PRIMARY KEY (obra_id, taxon_id))",

    "CREATE TABLE IF NOT EXISTS triagem (
       obra_id VARCHAR PRIMARY KEY, relevante BOOLEAN, prob DOUBLE,
       justificativa VARCHAR, decidido_por VARCHAR, data TIMESTAMP)",

    # trechos: texto corrido, tabelas e legendas em fluxos separados (item 6)
    "CREATE TABLE IF NOT EXISTS trechos (
       trecho_id VARCHAR PRIMARY KEY, obra_id VARCHAR, tipo VARCHAR,
       secao VARCHAR, pagina INTEGER, idioma VARCHAR, texto VARCHAR)",

    # item 3: span_verbatim NOT NULL - registro sem frase-fonte nao entra.
    # item 7: contexto na mesma linha do valor.
    # item 12: extrator/modelo/prompt gravados com cada valor.
    "CREATE TABLE IF NOT EXISTS extracoes (
       extracao_id VARCHAR PRIMARY KEY, obra_id VARCHAR, trecho_id VARCHAR,
       taxon_id VARCHAR, nome_no_artigo VARCHAR, trait_id VARCHAR,
       valor_num DOUBLE, valor_cat VARCHAR, unidade VARCHAR,
       estagio VARCHAR, temperatura_c DOUBLE, ambiente VARCHAR,
       n INTEGER, dispersao VARCHAR, pagina INTEGER,
       span_verbatim VARCHAR NOT NULL, confianca DOUBLE,
       extrator VARCHAR, modelo_versao VARCHAR, prompt_versao VARCHAR,
       origem_valor VARCHAR,       -- primaria | secundaria (item 8)
       fonte_primaria_doi VARCHAR,
       -- conflito: a mesma obra deu dois valores para o mesmo par
       -- (especie, trait); nao e aprovavel por limiar, vai para humano
       status VARCHAR,             -- bruto | rejeitado | conflito | aprovado | corrigido
       motivo_rejeicao VARCHAR, data TIMESTAMP)",

    # contexto de medida lido uma vez por artigo, na secao de Metodos
    "CREATE TABLE IF NOT EXISTS contexto_obra (
       obra_id VARCHAR PRIMARY KEY, estagio VARCHAR, temperatura_c DOUBLE,
       ambiente VARCHAR, n INTEGER, dispersao VARCHAR, span_verbatim VARCHAR,
       escalonado BOOLEAN, data TIMESTAMP)",

    "CREATE TABLE IF NOT EXISTS revisao (
       extracao_id VARCHAR, revisor VARCHAR, veredito VARCHAR,
       valor_corrigido VARCHAR, comentario VARCHAR, data TIMESTAMP)",

    # item 5: dupla extracao cega. Uma linha por (obra, taxon, trait, revisor).
    "CREATE TABLE IF NOT EXISTS ouro (
       obra_id VARCHAR, taxon_id VARCHAR, trait_id VARCHAR, revisor VARCHAR,
       valor VARCHAR, unidade VARCHAR, span_verbatim VARCHAR, data TIMESTAMP)",

    # decisao: 'automatica' (limiar atinge a precisao alvo) ou
    # 'revisao_integral' (nenhum limiar atinge: o trait nao sai da maquina)
    "CREATE TABLE IF NOT EXISTS limiares (
       trait_id VARCHAR PRIMARY KEY, limiar DOUBLE, precisao DOUBLE,
       recall DOUBLE, n_ouro INTEGER, decisao VARCHAR, data TIMESTAMP)"
  )
  purrr::walk(ddl, ~ dbExecute(con, .x))

  # Colunas acrescentadas depois que ja havia banco em uso. CREATE TABLE IF NOT
  # EXISTS nao mexe em tabela existente, entao a coluna nova entra por ALTER -
  # idempotente, e o banco antigo continua valendo sem ser recriado.
  #   resumo (01/10/2026): a triagem passou a ler titulo + resumo. So pelo
  #   titulo ela perdeu 4 de 9 obras relevantes no teste de P. barrioi, entre
  #   elas a propria redescricao da especie.
  dbExecute(con, "ALTER TABLE obras ADD COLUMN IF NOT EXISTS resumo VARCHAR")
  invisible(con)
}

# id estavel e reproduzivel a partir do conteudo, para o pipeline poder
# ser re-rodado sem duplicar linha.
id_de <- function(...) {
  substr(digest::digest(paste0(...), algo = "xxhash64"), 1, 16)
}

registrar <- function(con, tabela, df) {
  if (nrow(df) == 0) return(invisible(0L))
  dbWriteTable(con, "tmp_reg", df, temporary = TRUE, overwrite = TRUE)
  cols <- paste(names(df), collapse = ", ")
  # OR REPLACE nas tabelas com PK; nas demais, append simples.
  pk <- dbGetQuery(con, sprintf(
    "SELECT count(*) n FROM duckdb_constraints()
      WHERE table_name = '%s' AND constraint_type = 'PRIMARY KEY'", tabela))$n
  verbo <- if (pk > 0) "INSERT OR REPLACE INTO" else "INSERT INTO"
  n <- dbExecute(con, sprintf("%s %s (%s) SELECT %s FROM tmp_reg",
                              verbo, tabela, cols, cols))
  dbExecute(con, "DROP TABLE IF EXISTS tmp_reg")
  invisible(n)
}
