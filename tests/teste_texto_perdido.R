# Teste do texto do PDF que o GROBID perdeu (R/texto_perdido.R).
#
# Sem PDF, sem GROBID e sem API: linhas sinteticas no formato de
# linhas_de_palavras() e DuckDB em memoria.
#
#   Rscript tests/teste_texto_perdido.R
#
# O defeito (06/10/2026): em Santos et al. (2018), *Adelphobates
# galactonotus* (Zootaxa, Correspondence), o TEI do GROBID comeca em
# "anterolaterally. Nares small"; a introducao, os metodos e o comeco da
# descricao ("Snout rounded in dorsal and lateral views. Eyes small ...
# dorsally positioned") nao estavam em nenhum trecho, e a extracao daria
# "nao encontrado" sem erro nenhum.

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

# linhas como as de linhas_de_palavras(): x0 = 56 e a margem; 74, recuo de
# primeira linha de paragrafo
L <- function(texto, x0 = 56, pagina = 1L, coluna = 1L, menor = FALSE)
  tibble::tibble(pagina = pagina, coluna = coluna, x0 = x0, texto = texto, ital2 = FALSE,
                 fonte = if (menor) 8 else 10, menor = menor)
linhas <- dplyr::bind_rows(
  L("The tadpole of Adelphobates galactonotus (Steindachner, 1864)"),
  L("1 Laboratorio de Herpetologia, Universidade Federal de Goias", menor = TRUE),
  L("Adelphobates galactonotus (Steindachner 1864) is an endemic Brazilian frog, and can", x0 = 74),
  L("be found throughout Para, Maranhao, Mato Grosso and Tocantins states."),
  L("Tadpoles of A. galactonotus were collected in an ombrophilous forest fragment,", x0 = 74),
  L("during February 2015 at Araguaina municipality, Tocantins State, Brazil."),
  L("External morphology. Body depressed, rounded in dorsal view and globular in", x0 = 74),
  L("lateral view. Snout rounded in dorsal and lateral views (Fig. 1A, B). Eyes small"),
  L("(ED/BH = 0.09-0.11mm), dorsally positioned, and di-"),
  L("rected anterolaterally. Nares small, oval, dorsally positioned (Fig. 1D)."),
  L("287"),
  L("Oral disc anteroventral, laterally emarginate; row of elongated marginal", x0 = 74),
  L("papillae uniseriate ventrally."),
  L("References", x0 = 74),
  L("Altig, R. & McDiarmid, R.W. (1999) Body plan: development and morphology of anuran tadpoles."))
# o que o GROBID entregou: so a partir de "rected anterolaterally"
tei <- c("rected anterolaterally. Nares small, oval, dorsally positioned (Fig. 1D). 287 Oral disc anteroventral, laterally emarginate; row of elongated marginal papillae uniseriate ventrally.")

cat("\nparagrafos_perdidos()\n")
pp <- paragrafos_perdidos(linhas, tei, min_chars = 40)
checar("acha os paragrafos que nao estao nos trechos", nrow(pp) == 4)
checar("o recuo de primeira linha separa os paragrafos",
       startsWith(pp$texto[2], "Adelphobates galactonotus") && startsWith(pp$texto[4], "External morphology"))
checar("a descricao perdida volta",
       any(grepl("Snout rounded in dorsal and lateral views", pp$texto)) &&
         any(grepl("dorsally positioned, and di", pp$texto)))
checar("o que o GROBID ja tem nao se repete", !any(grepl("Oral disc", pp$texto)) &&
         !any(grepl("^rected", pp$texto)))
checar("linha de fonte menor (afiliacao, legenda) fica de fora", !any(grepl("Laboratorio", pp$texto)))
checar("as Referencias ficam de fora", !any(grepl("Altig", pp$texto)))
checar("a pagina vem junto", all(pp$pagina == 1L))
checar("trechos cobrindo tudo: nada perdido",
       nrow(paragrafos_perdidos(linhas[1:13, ], paste(linhas$texto, collapse = " "))) == 0)
checar("ligadura do PDF (fi) nao conta como texto perdido",
       nrow(paragrafos_perdidos(L("the specimens were ﬁxed in formalin and preserved in alcohol"),
                                "the specimens were fixed in formalin and preserved in alcohol", min_chars = 10)) == 0)
# medido no corpus (06/10/2026): a chave da monografia de 2020 ("Eyes
# positioned laterally (Fig. ...) ............ 2") entrava como texto perdido e
# virava o unico candidato de 28 pares; chave e fonte de frase de outra especie
checar("chave de identificacao perdida fica de fora",
       nrow(paragrafos_perdidos(L("(1b) Eyes positioned laterally (Fig. 3) \u2026\u2026\u2026\u2026\u2026 Lithobates palmipes, snout rounded in lateral view"),
                                "", min_chars = 10)) == 0)
checar("paragrafo curto demais (cabeco de pagina) fica de fora",
       nrow(paragrafos_perdidos(L("TADPOLE OF ADELPHOBATES GALACTONOTUS Zootaxa 4422"), "")) == 0)

cat("\ncom o banco: a recuperacao acha a descricao perdida\n")
con <- DBI::dbConnect(duckdb::duckdb(), ":memory:")
criar_esquema(con)
invisible(DBI::dbExecute(con, "INSERT INTO obra_taxon (obra_id, taxon_id) VALUES ('o1', 'adelphobates_galactonotus')"))
invisible(DBI::dbExecute(con, "INSERT INTO alvo (taxon_id, especie) VALUES ('adelphobates_galactonotus', 'Adelphobates galactonotus')"))
base <- tibble::tibble(trecho_id = "t1", obra_id = "o1", tipo = "texto", secao = NA_character_, pagina = NA_integer_,
                       idioma = "en", texto = tei, ordem = 1L)
registrar(con, "trechos", base)
olhos <- list(trait_id = "eyes_positioning", termos_busca = "eyes;eye")
checar("antes: a frase dos olhos nao esta entre os candidatos",
       !any(grepl("dorsally positioned, and", recuperar_candidatos(con, "o1", "adelphobates_galactonotus", olhos)$texto)))
novos <- com_texto_perdido(base, NA_character_, "o1", linhas = linhas)
checar("com_texto_perdido() acrescenta trechos de texto com ordem depois dos existentes",
       nrow(novos) > nrow(base) && all(novos$tipo[-1] == "texto") && min(novos$ordem[-1]) > 1L)
registrar_novos(con, "trechos", novos)
cand <- recuperar_candidatos(con, "o1", "adelphobates_galactonotus", olhos)
checar("depois: a frase dos olhos esta entre os candidatos (herda o nome do paragrafo anterior)",
       any(grepl("dorsally positioned, and", cand$texto)))
checar("rodar de novo nao acrescenta nada",
       nrow(com_texto_perdido(DBI::dbGetQuery(con, "SELECT * FROM trechos"), NA_character_, "o1", linhas = linhas)) ==
         nrow(DBI::dbGetQuery(con, "SELECT * FROM trechos")))
DBI::dbDisconnect(con, shutdown = TRUE)

cat(if (falhas == 0) "\ntodos os testes passaram\n\n" else sprintf("\n%d FALHA(S)\n\n", falhas))
quit(status = if (falhas == 0) 0 else 1)
