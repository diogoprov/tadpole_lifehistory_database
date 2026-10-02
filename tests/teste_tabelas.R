# Teste das tabelas lidas do PDF e da vaga garantida para tabela entre os
# candidatos.
#
# Sem API, sem GROBID e sem PDF: texto de pagina sintetico, DuckDB em memoria,
# modelo substituido.
#
#   Rscript tests/teste_tabelas.R
#
# O defeito (piloto zero, 02/10/2026): 26 dos 32 pares de Conte et al. (2007)
# ficaram "so planilha". O dado esta na Tabela 3 (uma linha por especie,
# coluna "Snout shape (Lateral)"), mas (1) o GROBID perdeu a tabela, que esta
# em pagina de paisagem - o TEI ficou so com cabecalhos transpostos; (2) tabela
# so era candidata quando nenhum trecho de texto citava a especie; (3) as
# linhas usam abreviacoes ("Sarg") definidas na legenda pelo nome antigo
# ("S. argyreornatus"), e o prompt so levava o nome aceito.

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
tb <- tibble::tibble

pagina_tabela <- paste(
  "The tadpole of Scinax catharinae                                    185",
  "Table 3. Morphological characters of tadpoles from the Scinax catharinae group. Salb – Scinax albicans;",
  "Sarg – S. argyreornatus; Scat – S. catharinae.",
  "Species     TL mm        Snout shape   Snout shape     Eye",
  "           (Gosner's      (Lateral)     (Dorsal)       direction",
  "Salb       26.6 (31)      Rounded        Rounded         DL",
  "Sarg       15.4 (31)      Truncate       Rounded         DL",
  "Scat       27.6 (37)      Rounded        Rounded         DL",
  sep = "\n")
pagina_texto <- paste(
  "Snout shape varies within the group (Table 3). The tadpole of S. argyreornatus",
  "has a truncate snout in lateral view, as shown below.",
  "Table 4. External oral features of tadpoles from the Scinax catharinae group.",
  "Species   Marginal papillae   Tooth row formula",
  "Sarg      Dorsal gap wide     2(2)/3",
  sep = "\n")

# ---------------------------------------------------------------------------
cat("\ntabelas_do_texto_pdf()\n")
t <- tabelas_do_texto_pdf(c(pagina_tabela, pagina_texto), "conte")
checar("uma tabela por legenda no inicio de linha", nrow(t) == 2)
checar("'(Table 3)' no meio do texto nao abre tabela", !any(grepl("^Snout shape varies", t$texto)))
checar("a tabela vem com legenda, cabecalho e as linhas",
       grepl("Sarg – S. argyreornatus", t$texto[1]) && grepl("Snout shape", t$texto[1]) &&
         grepl("Sarg       15.4", t$texto[1]))
checar("a tabela vai ate a proxima legenda ou o fim da pagina",
       !grepl("Table 4", t$texto[1]) && grepl("^Table 4", t$texto[2]))
checar("tipo 'tabela', secao com a legenda, pagina certa",
       all(t$tipo == "tabela") && grepl("^Table 3\\.", t$secao[1]) && identical(t$pagina, c(1L, 2L)))
checar("a linha da especie, copiada com o layout, passa em validar_span()",
       validar_span("Sarg       15.4 (31)      Truncate       Rounded", t$texto[1]) &&
         validar_span("Sarg 15.4 (31) Truncate Rounded", t$texto[1]))
checar("legenda em portugues tambem", nrow(tabelas_do_texto_pdf("Tabela 2. Medidas dos girinos de Physalaemus.\nEspecie  CT", "x")) == 1)

# ---------------------------------------------------------------------------
cat("\nrecuperar_candidatos(): vaga garantida para tabela\n")
con <- DBI::dbConnect(duckdb::duckdb(), ":memory:")
criar_esquema(con)
registrar(con, "alvo", tb(taxon_id = "Sarg", especie = "Ololygon argyreornata"))
registrar(con, "sinonimos", tb(taxon_id = "Sarg", nome_alternativo = "Scinax argyreornatus", fonte = "ASW", doi_obra = NA))
registrar(con, "obra_taxon", tb(obra_id = "conte", taxon_id = "Sarg", fonte = "t"))
mencao <- function(i) sprintf("The snout of Scinax argyreornatus is mentioned in comparison %d, snout snout.", i)
registrar(con, "trechos", bind_rows(
  tb(trecho_id = paste0("x", 1:5), obra_id = "conte", tipo = "texto", secao = "Discussion",
     pagina = NA_integer_, idioma = "en", texto = map_chr(1:5, mencao), ordem = 1:5),
  tb(trecho_id = "tab3", obra_id = "conte", tipo = "tabela", secao = t$secao[1],
     pagina = 1L, idioma = "en", texto = t$texto[1], ordem = 6L)))
trait <- list(trait_id = "snout_shape_lv", termos_busca = "snout")
cand <- recuperar_candidatos(con, "conte", "Sarg", trait, k = 4)
checar("com 5 mencoes no texto, a tabela entra entre os 4", "tab3" %in% cand$trecho_id)
checar("e continuam 4 candidatos", nrow(cand) == 4)
checar("a especie na legenda pelo nome antigo abreviado ('S. argyreornatus') basta",
       "tab3" %in% cand$trecho_id)

# ---------------------------------------------------------------------------
cat("\nagente_valor(): prompt de tabela, sinonimos e nomes do trait\n")
prompts <- character()
com_escalonamento <- function(prompt, ...) { prompts <<- c(prompts, prompt); list(encontrado = FALSE) }
tr_eye <- list(trait_id = "eyes_positioning", nome = "eyes positioning", unidade = NA, tipo = "categorico",
               valores_aceitos = "dorsal;lateral;dorsolateral", nomes_alternativos = "eye direction;direction of the eyes")
invisible(agente_valor(t$texto[1], tr_eye, "Ololygon argyreornata", list(agentes = list()),
                       nomes = c("Ololygon argyreornata", "Scinax argyreornatus"), tipo = "tabela"))
checar("o prompt leva o sinonimo da especie", grepl("Tambem chamada na literatura: Scinax argyreornatus", prompts[1]))
checar("o prompt explica a abreviacao e pede a linha da especie como span",
       grepl("abreviada", prompts[1]) && grepl("linha da especie", prompts[1]))
checar("'eye direction' vai como outro nome do trait", grepl("O trait tambem aparece como: eye direction", prompts[1]))
invisible(agente_valor("Snout rounded.", list(nome = "snout", unidade = NA, tipo = "categorico",
                                              valores_aceitos = "rounded", nomes_alternativos = NA),
                       "Sp", list(agentes = list())))
checar("trecho de texto nao leva a instrucao de tabela", !grepl("O trecho e uma tabela", prompts[2]))
rm(com_escalonamento)

cat("\ninst/traits.csv\n")
trs <- carregar_traits("inst/traits.csv")
checar("eyes_positioning tem 'eye direction' como nome alternativo e termo de busca",
       grepl("eye direction", trs$nomes_alternativos[trs$trait_id == "eyes_positioning"]) &&
         grepl("eye direction", trs$termos_busca[trs$trait_id == "eyes_positioning"]))
DBI::dbDisconnect(con, shutdown = TRUE)

cat(if (falhas == 0) "\ntodos os testes passaram\n\n" else sprintf("\n%d FALHA(S)\n\n", falhas))
quit(status = if (falhas == 0) 0 else 1)
