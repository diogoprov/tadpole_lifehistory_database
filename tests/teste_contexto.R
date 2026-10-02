# Teste de onde o agente de contexto le: secao de Metodos achatada pelo
# GROBID e obra sem secao de Metodos (nota curta, poster).
#
# Roda sem API e sem GROBID: TEI sintetico e o modelo substituido.
#
#   Rscript tests/teste_contexto.R
#
# Os defeitos (P. barrioi, 01/10/2026), 5 de 8 obras sem contexto:
# 1. B. ahenea, stone frog e a tese de 2009: o GROBID devolve "MATERIALS AND
#    METHODS" como div sem paragrafo e as subsecoes como divs irmas.
#    tei_para_trechos() marcava cada paragrafo so com o titulo imediato
#    ("Study area"), e nenhum trecho casava com method|metodo|material.
# 2. Pseudopaludicola (nota curta) e o poster nao tem cabecalho de Metodos;
#    o estagio esta no texto ("Two Stage 36 ...", "estagios 35 a 37").

suppressMessages({ library(dplyr); library(purrr); library(stringr); library(xml2) })
if (!dir.exists("R") && dir.exists("../R")) setwd("..")
if (!requireNamespace("ellmer", quietly = TRUE)) {
  cat("\n(pulado: falta ellmer)\n\n"); quit(status = 0)
}

e <- new.env()
e$id_de <- function(...) substr(digest::digest(paste0(...), algo = "xxhash64"), 1, 16)
for (f in c("R/parse.R", "R/agentes.R")) {
  suppressMessages(eval(parse(text = paste(readLines(f, warn = FALSE), collapse = "\n")), envir = e))
}
e$detectar_idioma <- function(txt) NA_character_

falhas <- 0L
checar <- function(descricao, condicao) {
  cat(if (isTRUE(condicao)) "  ok   " else "  FALHA", descricao, "\n")
  if (!isTRUE(condicao)) falhas <<- falhas + 1L
  invisible(condicao)
}

# ---------------------------------------------------------------------------
cat("\nsecoes_com_principal(): a sequencia da tese de 2009\n")
s <- e$secoes_com_principal(
  c(NA, "INTRODUCTION", "METHODS", "Study site", "Sampling procedures",
    "RESULTS", "DISCUSSION", "2. Material and Methods", "2.1. Study site", "4. Discussion"),
  c(4, 1, 0, 1, 2, 6, 11, 0, 1, 13))
checar("div sem titulo continua sem secao", is.na(s[1]))
checar("subsecao herda METHODS", s[4] == "METHODS / Study site" && s[5] == "METHODS / Sampling procedures")
checar("RESULTS com paragrafos NAO herda METHODS", s[6] == "RESULTS")
checar("DISCUSSION fica sozinha", s[7] == "DISCUSSION")
checar("numeracao '2.' tambem e secao principal",
       s[8] == "2. Material and Methods" && s[9] == "2. Material and Methods / 2.1. Study site")
checar("'4. Discussion' fecha a secao de Metodos", s[10] == "4. Discussion")
s <- e$secoes_com_principal(c("MATERIAIS E MÉTODOS", "Área de estudo", "RESULTADOS", "Morfologia externa"),
                            c(0, 2, 0, 3))
checar("em portugues: subsecao herda MATERIAIS E METODOS",
       s[2] == "MATERIAIS E MÉTODOS / Área de estudo")
checar("em portugues: RESULTADOS vazio vira o novo principal", s[4] == "RESULTADOS / Morfologia externa")

# ---------------------------------------------------------------------------
cat("\ntei_para_trechos() com a estrutura achatada do GROBID (B. ahenea)\n")
tei <- tempfile(fileext = ".tei.xml")
p <- function(txt) sprintf("<p>%s</p>", txt)
div <- function(head, ...) sprintf('<div xmlns="http://www.tei-c.org/ns/1.0"><head>%s</head>%s</div>', head, paste(c(...), collapse = ""))
writeLines(paste0(
  '<TEI xmlns="http://www.tei-c.org/ns/1.0"><text><body>',
  div("INTRODUCTION", p("The genus Bokermannohyla was erected to accommodate the species of the circumcincta group.")),
  div("MATERIALS AND METHODS"),
  div("Study area", p("We carried out field work in the Serra da Bocaina National Park, Sao Paulo state.")),
  div("Description of the larva", p("The description is based on 13 larvae in stage 37 (Gosner, 1960), fixed in formalin.")),
  div("RESULTS"),
  div("External larval morphology", p("In Gosner larval stage 37, body ovoid in dorsal view, depressed in lateral view.")),
  '</body></text></TEI>'), tei)
tr <- e$tei_para_trechos(tei, "ahenea")
met <- filter(tr, str_detect(tolower(coalesce(secao, "")), "method"))
checar("os paragrafos das subsecoes de Metodos ficam em Metodos", nrow(met) == 2)
checar("o titulo da subsecao continua no nome da secao",
       any(met$secao == "MATERIALS AND METHODS / Study area"))
checar("o paragrafo de Resultados nao entra em Metodos",
       !any(str_detect(met$texto, "body ovoid")))
sel <- e$trechos_de_contexto(tr)
checar("o agente de contexto le os Metodos", sel$fonte == "metodos" && length(sel$textos) == 2)

# ---------------------------------------------------------------------------
cat("\ntrechos_de_contexto(): obra sem secao de Metodos\n")
nota <- tibble::tibble(
  tipo = c("texto", "texto", "texto", "legenda"),
  secao = NA_character_,
  texto = c("The small toad-like frogs of the Neotropical genus Pseudopaludicola comprise seventeen species.",
            "Two Stage 36 and two Stage 39 tadpoles of P. falcipes (MLP.A-3836) were examined.",
            "The backstage of this study is long.",
            "Figure 2. Stage 39 larva."))
sel <- e$trechos_de_contexto(nota)
checar("nota curta: cai nos trechos que citam Stage", sel$fonte == "estagio")
checar("so o paragrafo do estagio entra", identical(sel$textos, nota$texto[2]))
checar("'backstage' nao conta como stage", !any(str_detect(sel$textos, "backstage")))
checar("legenda de figura nao entra", !any(str_detect(sel$textos, "^Figure")))
poster <- tibble::tibble(tipo = "texto", secao = "Morfologia externa",
                         texto = c("Os girinos sao descritos com base em 24 exemplares entre os estágios 35 a 37.",
                                   "O corpo do girino e ovoide em vista dorsal."))
sel <- e$trechos_de_contexto(poster)
checar("poster em portugues: 'estagios' conta", sel$fonte == "estagio" && length(sel$textos) == 1)
checar("secao de Metodos tem precedencia sobre a busca por estagio",
       e$trechos_de_contexto(bind_rows(
         nota, tibble::tibble(tipo = "texto", secao = "Material and methods", texto = "Tadpoles were fixed.")))$fonte == "metodos")
sel <- e$trechos_de_contexto(tibble::tibble(tipo = "texto", secao = "Canto", texto = "O canto tem uma nota."))
checar("sem Metodos e sem estagio: nenhum", sel$fonte == "nenhum" && length(sel$textos) == 0)

# ---------------------------------------------------------------------------
cat("\nagente_contexto() usa a busca por estagio\n")
enviado <- NULL
e$dbGetQuery <- function(con, sql) nota
e$com_escalonamento <- function(prompt, ...) { enviado <<- prompt; list(estagio = "36-39") }
r <- e$agente_contexto(NULL, "pseudo", list(agentes = list()))
checar("a nota recebe contexto (antes: NULL)", !is.null(r))
checar("o prompt leva o paragrafo do estagio", str_detect(enviado, "Two Stage 36"))
checar("o prompt nao chama o texto de 'Metodos'", !str_detect(enviado, "^Metodos:"))
enviado <- NULL
e$dbGetQuery <- function(con, sql) tibble::tibble(tipo = "texto", secao = "Canto", texto = "O canto tem uma nota.")
checar("sem nada para ler, nao chama o modelo",
       is.null(e$agente_contexto(NULL, "x", list(agentes = list()))) && is.null(enviado))

unlink(tei)
cat(if (falhas == 0) "\ntodos os testes passaram\n\n" else sprintf("\n%d FALHA(S)\n\n", falhas))
quit(status = if (falhas == 0) 0 else 1)
