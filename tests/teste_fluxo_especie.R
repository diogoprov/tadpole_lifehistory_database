# Teste de integracao: da obra com PDF ao registro validado, para UMA especie.
#
# Banco DuckDB de verdade e o projeto carregado de verdade (carregar_projeto).
# So o GROBID e o modelo sao substituidos, entao roda sem rede e sem custo.
# Pula se faltar duckdb, ellmer ou config.
#
#   Rscript tests/teste_fluxo_especie.R
#
# O que ele trava:
#   - extrair_tudo() so cruza especie com obra ligada a ela em obra_taxon (o
#     CROSS JOIN antigo extrairia P. barrioi de uma obra sobre outra especie
#     que cita P. barrioi de passagem);
#   - duas mencoes do mesmo valor na mesma obra viram um registro so;
#   - obra relevante sem PDF aparece no relatorio e nao quebra nada;
#   - limpar_fumaca_busca() apaga o que o teste gravou, inclusive trechos e
#     extracoes, e nao toca nos PDFs.

if (!dir.exists("R") && dir.exists("../R")) setwd("..")
faltam <- c("duckdb", "ellmer", "config")[!vapply(c("duckdb", "ellmer", "config"),
                                                   requireNamespace, logical(1), quietly = TRUE)]
if (length(faltam)) {
  cat("\n(pulado: faltam os pacotes", paste(faltam, collapse = ", "), ")\n\n"); quit(status = 0)
}

suppressMessages(suppressWarnings({
  source("R/carregar.R"); carregar_projeto("R")
}))

falhas <- 0L
checar <- function(descricao, condicao) {
  cat(if (isTRUE(condicao)) "  ok   " else "  FALHA", descricao, "\n")
  if (!isTRUE(condicao)) falhas <<- falhas + 1L
  invisible(condicao)
}

# --- ambiente temporario: config, traits, banco -----------------------------
d <- tempfile("fluxo_"); dir.create(d); dir.create(file.path(d, "pdf"))
readr::write_csv(tibble::tibble(
  trait_id = "snout_shape_lv", nome = "Snout shape in lateral view", tipo = "categorico",
  unidade = NA, estagio_ref = NA, definicao = "forma do focinho em vista lateral",
  valores_aceitos = "rounded;truncate;acuminate", min_plausivel = NA, max_plausivel = NA,
  termos_busca = "snout;focinho", status = "fechado"), file.path(d, "traits.csv"))
writeLines(c(
  "default:",
  sprintf('  db: "%s"', file.path(d, "t.duckdb")),
  sprintf('  traits: "%s"', file.path(d, "traits.csv")),
  sprintf('  dir_pdf: "%s"', file.path(d, "pdf")),
  sprintf('  dir_tei: "%s"', file.path(d, "tei")),
  '  grobid: "http://127.0.0.1:9"', '  ocr: ""', '  encoder_local: ""',
  '  prompt_versao: "teste"', '  limiar_llm: 0.9',
  '  agentes:',
  '    triagem:  {provedor: "anthropic", modelo: "claude-haiku-4-5-20251001"}',
  '    valor:    {provedor: "anthropic", modelo: "claude-sonnet-5-5"}',
  '    contexto: {provedor: "anthropic", modelo: "claude-sonnet-5-5"}',
  '    forte:    {provedor: "anthropic", modelo: "claude-opus-5-5"}'), file.path(d, "config.yml"))
cfgp <- file.path(d, "config.yml")

con <- suppressMessages(abrir_db(file.path(d, "t.duckdb")))
registrar(con, "alvo", tibble::tibble(
  taxon_id = c("TB", "TE"), especie = c("Physalaemus barrioi", "Physalaemus erikae")))
obras <- tibble::tibble(
  obra_id = c("red", "comp", "outra", "sempdf"),
  titulo  = c("Redescription of Physalaemus barrioi", "The tadpole of P. erikae, with comparisons",
              "Natural history of Physalaemus erikae", "Poster sem PDF"),
  status  = c("pdf_manual", "pdf_ok", "pdf_ok", "sem_pdf"),
  caminho_pdf = c(file.path(d, "pdf", c("red.pdf", "comp.pdf", "outra.pdf")), NA))
registrar(con, "obras", obras)
registrar(con, "triagem", tibble::tibble(obra_id = obras$obra_id, relevante = TRUE,
                                         decidido_por = "teste"))
# "outra" e ligada SO a P. erikae - mas o texto dela cita P. barrioi
registrar(con, "obra_taxon", tibble::tibble(
  obra_id = c("red", "comp", "sempdf", "outra"), taxon_id = c("TB", "TB", "TB", "TE"),
  fonte = "busca"))
dbDisconnect(con, shutdown = TRUE)

# --- substitutos: GROBID e modelo --------------------------------------------
TRECHOS <- tibble::tribble(
  ~obra_id, ~secao,                                          ~texto,
  "red",   "Material and methods",                          "Tadpoles in stages 25-38 (Gosner, 1960) were measured.",
  "red",   "Description of the tadpole of Physalaemus barrioi", "Body ovoid. Snout rounded in lateral view.",
  "red",   "Discussion",                                    "The snout of P. barrioi is rounded in lateral view, unlike P. erikae.",
  "comp",  "Discussion",                                    "Physalaemus erikae has a truncate snout, whereas P. barrioi has a rounded snout.",
  "outra", "Results",                                       "Physalaemus barrioi snout rounded, as in all species of the group.")
estruturar_obras <- function(con, cfg) {
  pend <- dbGetQuery(con, "SELECT obra_id FROM obras WHERE caminho_pdf IS NOT NULL
                             AND obra_id NOT IN (SELECT DISTINCT obra_id FROM trechos)")
  t <- dplyr::filter(TRECHOS, obra_id %in% pend$obra_id) |>
    dplyr::mutate(trecho_id = paste0(obra_id, "_", dplyr::row_number()), tipo = "texto",
                  pagina = 1L, idioma = "en", ordem = dplyr::row_number())
  registrar(con, "trechos", dplyr::select(t, trecho_id, obra_id, tipo, secao, pagina, idioma, texto, ordem))
  dplyr::count(t, obra_id, name = "n_trechos")
}
agente_contexto <- function(con, obra_id, cfg)
  list(estagio = "Gosner 25-38", ambiente = "campo", n = NULL,
       span_verbatim = "Tadpoles in stages 25-38 (Gosner, 1960)", escalonado = FALSE)
CHAMADAS <- character()
agente_valor <- function(texto, trait, especie, cfg, ...) {
  CHAMADAS <<- c(CHAMADAS, texto)
  frase <- regmatches(texto, regexpr("[^.]*rounded[^.]*\\.?", texto))
  if (!length(frase)) return(list(encontrado = FALSE))
  list(encontrado = TRUE, valor_cat = "rounded", span_verbatim = frase,
       confianca = 0.9, nome_no_artigo = especie, escalonado = FALSE)
}

# --- roda --------------------------------------------------------------------
cat("\nteste_de_fumaca_extracao(), saida resumida:\n")
saida <- capture.output(r <- teste_de_fumaca_extracao("TB", config_path = cfgp))
cat(paste0("    | ", grep("obras relevantes|sem PDF|registro\\(s\\)|reconciliacao", saida, value = TRUE)),
    sep = "\n")

cat("\nverificacoes\n")
ex <- r$extracoes
checar("a obra ligada so a P. erikae NAO foi usada para P. barrioi (sem CROSS JOIN)",
       !"outra" %in% ex$obra_id)
checar("o modelo nunca viu o texto da obra 'outra'",
       !any(grepl("as in all species of the group", CHAMADAS)))
checar("extraiu da redescricao e da obra comparativa", setequal(unique(ex$obra_id), c("red", "comp")))
checar("as duas mencoes 'rounded' da redescricao viraram um registro so",
       sum(ex$obra_id == "red" & ex$status == "bruto") == 1 &&
       sum(ex$obra_id == "red" & ex$motivo_rejeicao %in% "duplicado_na_obra") == 1)
checar("o estagio veio dos Metodos (contexto herdado)",
       all(ex$estagio[ex$status == "bruto"] == "Gosner 25-38"))
checar("todo span existe no trecho", all(nchar(ex$span_verbatim) > 0))
checar("a obra sem PDF aparece no relatorio", any(grepl("sem PDF: Poster sem PDF", saida)))
checar("sem chamadas reais, custo vazio", nrow(r$custo) == 0)

cat("\nlimpar_fumaca_busca()\n")
con <- suppressMessages(abrir_db(file.path(d, "t.duckdb")))
invisible(capture.output(limpar_fumaca_busca(con, "TB")))
q <- function(sql) dbGetQuery(con, sql)$n
checar("extracoes de P. barrioi apagadas", q("SELECT count(*) n FROM extracoes WHERE taxon_id='TB'") == 0)
checar("trechos das obras orfas apagados",
       q("SELECT count(*) n FROM trechos WHERE obra_id IN ('red','comp')") == 0)
checar("a obra de P. erikae continua intacta (outra especie)",
       q("SELECT count(*) n FROM trechos WHERE obra_id = 'outra'") == 1 &&
       q("SELECT count(*) n FROM obras WHERE obra_id = 'outra'") == 1)
dbDisconnect(con, shutdown = TRUE)

cat("\n", if (falhas == 0) "todos os testes passaram\n\n" else
    paste0(falhas, " teste(s) falharam\n\n"), sep = "")
if (falhas > 0) quit(status = 1)
