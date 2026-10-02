# Teste da heranca do nome da especie entre paragrafos (herdar_especie(),
# recuperar_candidatos()) e do TEI sem corpo.
#
# Sem API e sem GROBID: DuckDB em memoria, modelo substituido.
#
#   Rscript tests/teste_heranca.R
#
# O defeito (piloto zero, 02/10/2026): em Pezzuti et al. (2021) o GROBID
# separa a ficha da especie - o nome num paragrafo ("Vitreorana eurygnatha
# (Fig. 9) Specimens examined..."), os caracteres no seguinte (secao
# "Morphology.", sem o nome). recuperar_candidatos() exigia especie e termo
# do trait no mesmo trecho: 68 de 118 pares da obra ficavam sem candidato.
# E o TEI sem corpo de Prado et al. (2009) quebrava com "objeto 'texto' nao
# encontrado".

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

# ---------------------------------------------------------------------------
cat("\nherdar_especie()\n")
#            1      2      3      4      5      6      7      8
e_texto <- c(TRUE,  TRUE,  TRUE,  FALSE, TRUE,  TRUE,  TRUE,  TRUE)
cita    <- c(TRUE,  FALSE, FALSE, FALSE, FALSE, FALSE, FALSE, FALSE)
outra   <- c(FALSE, FALSE, FALSE, FALSE, FALSE, TRUE,  FALSE, FALSE)
a <- herdar_especie(e_texto, cita, outra, max_herda = 3)
checar("o trecho que cita nao herda (e candidato direto)", is.na(a[1]))
checar("os paragrafos seguintes herdam do 1", identical(a[2:3], c(1L, 1L)))
checar("legenda/tabela nao herda e nao conta passo", is.na(a[4]) && identical(a[5], 1L))
checar("outra especie corta a heranca", is.na(a[6]) && is.na(a[7]) && is.na(a[8]))
a <- herdar_especie(rep(TRUE, 6), c(TRUE, rep(FALSE, 5)), rep(FALSE, 6), max_herda = 3)
checar("passado o limite, para de herdar", identical(a, c(NA, 1L, 1L, 1L, NA, NA)))
checar("padrao: 3 paragrafos", formals(herdar_especie)$max_herda == 3)

# ---------------------------------------------------------------------------
cat("\nrecuperar_candidatos() com a ficha de Pezzuti\n")
con <- DBI::dbConnect(duckdb::duckdb(), ":memory:")
criar_esquema(con)
registrar(con, "alvo", tb(taxon_id = c("V", "T"), especie = c("Vitreorana eurygnatha", "Thoropa megatympanum")))
registrar(con, "obra_taxon", tb(obra_id = "pez", taxon_id = c("V", "T"), fonte = "piloto_zero"))
trechos <- tb(
  trecho_id = paste0("p", 1:6), obra_id = "pez", tipo = "texto",
  secao = c("Tadpole descriptions / Centrolenidae", "Tadpole descriptions / Morphology.",
            "Tadpole descriptions / Coloration.", "Tadpole descriptions / Cycloramphidae",
            "Tadpole descriptions / Morphology.", "Discussion"),
  pagina = NA_integer_, idioma = "en",
  texto = c("Vitreorana eurygnatha (Fig. 9) Specimens examined. 10 specimens in stages 28-38.",
            "Body depressed; snout rounded in dorsal view and sloped in lateral view; eyes dorsal.",
            "In preservative, body light brown; eyes dark.",
            "Thoropa megatympanum (Fig. 10) Specimens examined. 8 specimens in stages 30-36.",
            "Body elongated; snout rounded in lateral view; eyes dorsolateral.",
            "Snout shape varies widely among Brazilian tadpoles."),
  ordem = 1:6)
registrar(con, "trechos", trechos)
trait <- list(trait_id = "snout_shape_lv", termos_busca = "snout;focinho")
cv <- recuperar_candidatos(con, "pez", "V", trait)
checar("o paragrafo de morfologia (sem o nome) vira candidato de V. eurygnatha", "p2" %in% cv$trecho_id)
checar("ele leva o paragrafo que nomeia a especie como ancora",
       grepl("^Vitreorana eurygnatha", cv$ancora[cv$trecho_id == "p2"]))
checar("a morfologia da especie seguinte nao entra", !"p5" %in% cv$trecho_id)
ct <- recuperar_candidatos(con, "pez", "T", trait)
checar("a outra especie pega a propria morfologia", "p5" %in% ct$trecho_id && !"p2" %in% ct$trecho_id)
checar("a Discussao, depois de outra especie, nao herda", !"p6" %in% cv$trecho_id)
checar("trecho que cita a especie fica sem ancora",
       all(is.na(recuperar_candidatos(con, "pez", "V", list(trait_id = "x", termos_busca = "specimens"))$ancora)))

invisible(DBI::dbExecute(con, "UPDATE trechos SET ordem = NULL"))
avisou <- FALSE
invisible(withCallingHandlers(recuperar_candidatos(con, "pez", "V", trait),
                    warning = function(w) { avisou <<- grepl("sem ordem", conditionMessage(w)); invokeRestart("muffleWarning") }))
checar("trecho sem ordem avisa (nao perde o par calado)", avisou)
invisible(DBI::dbExecute(con, "UPDATE trechos SET ordem = CAST(substr(trecho_id, 2) AS INTEGER)"))

# ---------------------------------------------------------------------------
cat("\nextrair_par(): ancora no prompt, frase-fonte so do trecho\n")
prompts <- character()
span_do_modelo <- "snout rounded in dorsal view"   # frase do proprio trecho
com_escalonamento <- function(prompt, ...) {
  prompts <<- c(prompts, prompt)
  list(encontrado = TRUE, valor_cat = "rounded", confianca = 0.9, escalonado = FALSE,
       span_verbatim = span_do_modelo)
}
agente_contexto <- function(...) NULL
registrar(con, "obras", tb(obra_id = "pez", doi = "10.0/pez"))
ext <- extrair_par(con, "pez", "V", list(trait_id = "snout_shape_lv", tipo = "categorico",
                                        nome = "Snout shape", unidade = NA, termos_busca = "snout",
                                        valores_aceitos = "rounded;sloped"),
                   list(encoder_local = "", agentes = list(valor = list(modelo = "s"), forte = list(modelo = "o")),
                        prompt_versao = "t"))
p2 <- prompts[grepl("Body depressed", prompts)]
checar("o prompt do trecho herdado traz o paragrafo-ancora", length(p2) == 1 && grepl("Vitreorana eurygnatha \\(Fig. 9\\)", p2))
checar("e avisa que a ancora e so contexto", grepl("so contexto", p2))
checar("o registro do trecho herdado passa no span (frase do proprio trecho)",
       any(ext$trecho_id == "p2" & ext$status == "bruto"))
# um modelo que copia a frase da ancora: a frase nao esta no trecho, o span reprova
span_do_modelo <- "Specimens examined. 10 specimens"
ext2 <- extrair_par(con, "pez", "V", list(trait_id = "snout_shape_lv", tipo = "categorico",
                                         nome = "Snout shape", unidade = NA, termos_busca = "snout",
                                         valores_aceitos = "rounded;sloped"),
                    list(encoder_local = "", agentes = list(valor = list(modelo = "s"), forte = list(modelo = "o")),
                         prompt_versao = "t"))
checar("frase copiada da ancora e rejeitada (validar_span so olha o trecho)",
       ext2$status[ext2$trecho_id == "p2"] == "rejeitado")
rm(com_escalonamento, agente_contexto)
DBI::dbDisconnect(con, shutdown = TRUE)

# ---------------------------------------------------------------------------
cat("\nTEI sem corpo (Prado et al. 2009)\n")
tei <- tempfile(fileext = ".tei.xml")
writeLines('<TEI xmlns="http://www.tei-c.org/ns/1.0"><teiHeader/><text><body/></text></TEI>', tei)
msg <- tryCatch(tei_para_trechos(tei, "x"), error = conditionMessage)
checar("para com o motivo (nao 'objeto texto nao encontrado')", grepl("TEI sem texto no corpo", msg))
unlink(tei)

cat(if (falhas == 0) "\ntodos os testes passaram\n\n" else sprintf("\n%d FALHA(S)\n\n", falhas))
quit(status = if (falhas == 0) 0 else 1)
