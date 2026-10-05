# Teste da sinonimia tirada das tabelas do AmphiNom (sinonimos_amphinom()).
#
# Roda sem rede e sem o AmphiNom: tabelas sinteticas no formato do pacote
# (asw_synonyms: species, synonyms; asw_taxonomy: species, ...).
#
#   Rscript tests/teste_sinonimos.R
#
# O defeito (piloto zero, 01/10/2026): sem sinonimo, 33 de 138 especies nao
# apareciam no texto da propria obra (Conte et al. 2007 usa Scinax, a
# planilha Ololygon). E dois riscos vistos ao trazer os sinonimos:
# - grafia: a planilha tem "Ololygon flavoguttata", a ASW "flavoguttatus";
# - trinomio: "Leptodactylus ocellatus var. bonairensis" (sinonimo de
#   L. luctator) vira "L. ocellatus" em padrao_especie(), binomio que a ASW
#   lista sob L. bolivianus - dado de uma especie iria para outra.

suppressMessages({ library(dplyr); library(purrr); library(stringr); library(tibble) })
if (!dir.exists("R") && dir.exists("../R")) setwd("..")
e <- new.env()
for (f in c("R/sinonimia.R", "R/recuperacao.R")) {
  suppressMessages(eval(parse(text = paste(readLines(f, warn = FALSE), collapse = "\n")), envir = e))
}

falhas <- 0L
checar <- function(descricao, condicao) {
  cat(if (isTRUE(condicao)) "  ok   " else "  FALHA", descricao, "\n")
  if (!isTRUE(condicao)) falhas <<- falhas + 1L
  invisible(condicao)
}

tax <- tibble(species = c("Ololygon catharinae", "Ololygon flavoguttatus", "Leptodactylus luctator",
                          "Leptodactylus bolivianus", "Leptodactylus fuscus", "Trachycephalus typhonius",
                          "Pithecopus hypochondrialis", "Pithecopus azureus"))
syn <- tribble(
  ~species,                    ~synonyms,
  "Ololygon catharinae",       "Ololygon catharinae",
  "Ololygon catharinae",       "Scinax catharinae",
  "Ololygon catharinae",       "Hyla catharinae simplex",
  "Ololygon catharinae",       "Hyla catharinae",
  "Ololygon flavoguttatus",    "Scinax flavoguttatus",
  "Leptodactylus luctator",    "Leptodactylus ocellatus var. bonairensis",
  "Leptodactylus luctator",    "Rana luctator",
  "Leptodactylus bolivianus",  "Leptodactylus ocellatus",
  "Leptodactylus fuscus",      "Rana typhonia",
  "Trachycephalus typhonius",  "Rana typhonia",
  "Trachycephalus typhonius",  "Hyla venulosa",
  "Pithecopus azureus",        "Pithecopus hypochondrialis azureus")
alvo <- tibble(taxon_id = paste0("T", 1:7),
               especie = c("Ololygon catharinae", "Ololygon flavoguttata", "Leptodactylus luctator",
                           "Leptodactylus fuscus", "Trachycephalus typhonius", "Pithecopus azureus",
                           "Specie inexistens"))
r <- e$sinonimos_amphinom(alvo, syn = syn, tax = tax)
s <- function(id) r$sinonimos$nome_alternativo[r$sinonimos$taxon_id == id]
rv <- function(id) r$revisar$nome_alternativo[r$revisar$taxon_id == id]

cat("\nsinonimos que entram\n")
checar("Scinax catharinae entra para Ololygon catharinae", "Scinax catharinae" %in% s("T1"))
checar("o proprio nome nao vira sinonimo", !"Ololygon catharinae" %in% s("T1"))
checar("trinomio cujo binomio e sinonimo da propria especie entra",
       "Hyla catharinae simplex" %in% s("T1"))
checar("todo sinonimo leva a fonte com a versao do pacote",
       all(str_detect(r$sinonimos$fonte, "^ASW via AmphiNom")))

cat("\ngrafia (concordancia de genero)\n")
checar("'flavoguttata' casa com 'flavoguttatus' da ASW", "Scinax flavoguttatus" %in% s("T2"))
checar("o nome da ASW tambem vira sinonimo", "Ololygon flavoguttatus" %in% s("T2"))

cat("\no que vai para revisao, e nao entra\n")
checar("trinomio 'L. ocellatus var. bonairensis' nao entra para L. luctator",
       !"Leptodactylus ocellatus var. bonairensis" %in% s("T3") &&
         "Leptodactylus ocellatus var. bonairensis" %in% rv("T3"))
checar("o sinonimo simples de L. luctator entra", "Rana luctator" %in% s("T3"))
checar("'Rana typhonia', sinonimo de duas especies da lista, nao entra em nenhuma",
       !"Rana typhonia" %in% c(s("T4"), s("T5")) && "Rana typhonia" %in% rv("T4") && "Rana typhonia" %in% rv("T5"))
checar("binomio que e especie valida diferente nao entra",
       !"Pithecopus hypochondrialis azureus" %in% s("T6") && "Pithecopus hypochondrialis azureus" %in% rv("T6"))
checar("nome fora da ASW vai para revisao",
       any(r$revisar$taxon_id == "T7" & r$revisar$motivo == "nome nao achado na ASW"))

cat("\no efeito na recuperacao: o padrao nao casa 'L. ocellatus'\n")
pad <- e$padrao_especie(c("Leptodactylus luctator", s("T3")))
checar("texto com 'L. ocellatus' nao e atribuido a L. luctator",
       !str_detect("Tadpoles of L. ocellatus were collected.", regex(pad, ignore_case = TRUE)))
checar("texto com 'Scinax catharinae' e atribuido a O. catharinae",
       str_detect("The tadpole of Scinax catharinae", regex(e$padrao_especie(c("Ololygon catharinae", s("T1"))))))

# ---------------------------------------------------------------------------
# Sinonimos curados (inst/sinonimos.csv), 01/10/2026: em Rossa-Feres & Nomura
# (2006), "Pseudis paradoxa" e P. platensis e "Elachistocleis sp." e
# E. cesarii (Diogo). Como sinonimos globais, levariam para essas especies o
# dado de P. paradoxa (valida) e de qualquer Elachistocleis sem nome.
cat("\ncarregar_sinonimos_curados()\n")
csv <- tempfile(fileext = ".csv")
writeLines(c("# comentario", "especie,nome_alternativo,doi_obra,fonte",
             "Pseudis platensis,Pseudis paradoxa,10.1590/S1676-06032006000100014,Diogo",
             "Trachycephalus typhonius,Phrynohyas venulosa,,Diogo",
             "Especie fora da lista,Nomen antiquum,,Diogo"), csv)
alvo_c <- tibble(taxon_id = c("Anura160", "Anura152"), especie = c("Pseudis platensis", "Trachycephalus typhonius"))
cur <- e$carregar_sinonimos_curados(csv, alvo_c)
checar("o taxon_id sai do nome aceito", identical(cur$taxon_id[cur$nome_alternativo == "Pseudis paradoxa"], "Anura160"))
checar("especie fora da lista-alvo nao entra", !"Nomen antiquum" %in% cur$nome_alternativo)
checar("doi_obra vazio vira NA (global)", is.na(cur$doi_obra[cur$nome_alternativo == "Phrynohyas venulosa"]))
checar("doi_obra fica em minusculas", cur$doi_obra[cur$nome_alternativo == "Pseudis paradoxa"] == "10.1590/s1676-06032006000100014")
checar("o arquivo do projeto carrega", {
  a <- tibble(taxon_id = "x", especie = "Pseudis platensis")
  nrow(e$carregar_sinonimos_curados("inst/sinonimos.csv", a)) == 1 })

if (requireNamespace("duckdb", quietly = TRUE)) {
  cat("\naliases_de(): sinonimo restrito a uma obra\n")
  for (f in c("R/db.R")) suppressMessages(eval(parse(text = paste(readLines(f, warn = FALSE), collapse = "\n")), envir = e))
  con <- DBI::dbConnect(duckdb::duckdb(), ":memory:")
  e$criar_esquema(con)
  DBI::dbAppendTable(con, "alvo", data.frame(taxon_id = "Anura160", especie = "Pseudis platensis"))
  DBI::dbAppendTable(con, "obras", data.frame(obra_id = c("rf2006", "outra"),
                                              doi = c("10.1590/S1676-06032006000100014", "10.0/outra")))
  DBI::dbAppendTable(con, "sinonimos", as.data.frame(bind_rows(
    filter(cur, taxon_id == "Anura160"),
    tibble(taxon_id = "Anura160", nome_alternativo = "Pseudis paradoxus platensis", fonte = "ASW", doi_obra = NA))))
  checar("na obra certa (DOI em outra caixa), o nome antigo entra",
         "Pseudis paradoxa" %in% e$aliases_de(con, "Anura160", "rf2006"))
  checar("em outra obra, nao entra", !"Pseudis paradoxa" %in% e$aliases_de(con, "Anura160", "outra"))
  checar("sem obra (busca, triagem), nao entra", !"Pseudis paradoxa" %in% e$aliases_de(con, "Anura160"))
  checar("o sinonimo global entra em qualquer obra",
         "Pseudis paradoxus platensis" %in% e$aliases_de(con, "Anura160", "outra") &&
           "Pseudis paradoxus platensis" %in% e$aliases_de(con, "Anura160"))
  DBI::dbDisconnect(con, shutdown = TRUE)
}
unlink(csv)

# ---------------------------------------------------------------------------
# 04/10/2026: o _targets.R so lia um cache da ASW que nunca existiu, e o banco
# principal ficou com 2 sinonimos. Agora usa carregar_sinonimos(), que so grava
# os que ainda nao estao no banco (a tabela nao tem chave primaria).
cat("\nsinonimos no pipeline\n")
ex <- tibble(taxon_id = "T1", nome_alternativo = "Scinax catharinae")
novos <- e$sinonimos_novos(tibble(taxon_id = c("T1", "T1", "T2"), nome_alternativo = c("Scinax catharinae", "Hyla catharinae", "Scinax catharinae"),
                                  fonte = "x", doi_obra = NA_character_), ex)
checar("sinonimos_novos(): so o que ainda nao esta no banco (mesmo taxon e nome)",
       nrow(novos) == 2 && !any(novos$taxon_id == "T1" & novos$nome_alternativo == "Scinax catharinae"))
tg <- paste(readLines("_targets.R", warn = FALSE), collapse = "\n")
checar("o _targets.R carrega os sinonimos com carregar_sinonimos() (AmphiNom + curados)",
       grepl("carregar_sinonimos\\(con, alvo", tg) && !grepl("cache_asw", tg))

cat(if (falhas == 0) "\ntodos os testes passaram\n\n" else sprintf("\n%d FALHA(S)\n\n", falhas))
quit(status = if (falhas == 0) 0 else 1)
