# Teste das fichas de especie lidas do PDF (R/fichas.R) e da recuperacao que
# as prefere ao GROBID.
#
# Sem PDF, sem GROBID e sem API: paginas sinteticas no formato de
# pdftools::pdf_data(font_info = TRUE) e DuckDB em memoria.
#
#   Rscript tests/teste_fichas.R
#
# O defeito (conferencia da rodada 3 do piloto zero, 04/10/2026): nas
# monografias o GROBID mistura as duas colunas, perde cabecalho de ficha e
# poe pedaco de descricao ao lado da legenda de outra especie. O modelo
# recebia a ficha errada (frase de outra especie) ou nenhuma (nao achou).

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

# uma linha de palavras; `ital` = quantas palavras do inicio em italico
linha <- function(txt, x, y, ital = 0L, tam = 9) {
  w <- strsplit(txt, " ")[[1]]
  larg <- nchar(w) * 4
  tb(width = larg, height = 10, x = as.integer(x + c(0, cumsum(larg + 2))[seq_along(w)]),
     y = as.integer(y), space = TRUE, text = w,
     font_name = ifelse(seq_along(w) <= ital, "ABC+Times-Italic", "ABC+Times-Roman"), font_size = tam)
}
pagina <- function(...) dplyr::bind_rows(...)

# pagina 1: coluna da esquerda (x = 40) e da direita (x = 310)
p1 <- pagina(
  linha("Boana raniceps Cope 1862", 40, 100, ital = 2),
  linha("Characterization. The snout is rounded in lat-", 40, 112),
  linha("eral view. Eyes small, dorsally positioned.", 40, 124),
  linha("Figure 3. Tadpoles of Scinax similis, snout sloped in lateral view.", 40, 136, tam = 7),
  linha("Boana raniceps tadpoles differ from those of B. lundii.", 40, 148, ital = 2),
  linha("Spiracle sinistral.", 310, 100),
  linha("Scinax similis (Cochran 1952)", 310, 112, ital = 2),
  linha("Characterization. The snout is sloped in lateral view.", 310, 124),
  # mencao sem italico no inicio da linha nao abre ficha
  linha("Boana raniceps Cope 1862 was described from Ibira.", 310, 136),
  linha("DISCUSSION", 310, 148),
  linha("Snout shape varies widely among tadpoles.", 310, 160),
  linha("Here the snout of the margin column is long enough to set the page width ok", 300, 172))
# pagina 2: referencias; binomio em italico ali nao e ficha
p2 <- pagina(
  linha("REFERENCES", 40, 100),
  linha("Leptodactylus troglodytes (Amphibia, Anura). Rev Bras Zool 1: 1-10.", 40, 112, ital = 2),
  linha("Here the snout of the margin column is long enough to set the page width ok", 300, 124))

cat("\nlinhas e fichas\n")
l <- linhas_de_palavras(list(p1, p2))
checar("legenda com fonte menor fica marcada", any(l$menor & grepl("^Figure 3", l$texto)))
fi <- segmentar_fichas(l)
checar("duas fichas: B. raniceps e S. similis", identical(fi$cabecalho,
       c("Boana raniceps Cope 1862", "Scinax similis (Cochran 1952)")))
br <- fi$texto[1]; ss <- fi$texto[2]
checar("coluna da esquerda, depois a da direita: a ficha segue na outra coluna", grepl("Spiracle sinistral", br))
checar("a legenda (fonte menor) nao entra e nao corta a ficha",
       !grepl("Figure 3", br) && grepl("differ from those of B. lundii", br))
checar("binomio seguido de texto corrido nao abre ficha", length(grep("tadpoles differ", fi$cabecalho)) == 0)
checar("palavra partida no fim da linha e juntada", grepl("rounded in lateral view", br))
checar("a ficha seguinte nao leva frase da anterior", !grepl("rounded", ss) && grepl("sloped in lateral view", ss))
checar("mencao sem italico nao abre ficha", nrow(fi) == 2 && grepl("described from Ibira", ss))
checar("titulo em caixa alta fecha a ficha", !grepl("varies widely", ss))
checar("nas referencias nada vira ficha", !any(grepl("troglodytes", fi$cabecalho)))
checar("e_cabecalho(): 'sp.' e hibrido", all(e_cabecalho(c("Elachistocleis sp. (Figures 8B)", "Rhinella crucifer x R. ornata"), TRUE)))
checar("e_cabecalho(): legenda nao", !e_cabecalho("Figure 34. Dendropsophus seniculus", TRUE))

# ---------------------------------------------------------------------------
cat("\nrecuperar_candidatos() prefere a ficha da especie\n")
con <- DBI::dbConnect(duckdb::duckdb(), ":memory:")
criar_esquema(con)
registrar(con, "alvo", tb(taxon_id = c("R", "S", "L"),
                          especie = c("Boana raniceps", "Scinax similis", "Boana lundii")))
registrar(con, "obra_taxon", tb(obra_id = "o", taxon_id = c("R", "S", "L"), fonte = "t"))
# o GROBID com a secao velha: a ficha de S. similis sob "Boana raniceps"
registrar(con, "trechos", tb(
  trecho_id = c("g1", "g2", "g3"), obra_id = "o", tipo = "texto",
  secao = c("Results / Boana raniceps Cope 1862", "Results / Boana raniceps Cope 1862", "Results / Boana lundii"),
  pagina = NA_integer_, idioma = "en",
  texto = c("Characterization. The snout is rounded in lateral view.",
            "Characterization. The snout is sloped in lateral view.",
            "The snout of Boana lundii is rounded in lateral view."),
  ordem = 1:3))
registrar(con, "trechos", tb(trecho_id = paste0("f", 1:2), obra_id = "o", tipo = "ficha",
                             secao = fi$cabecalho, pagina = 1L, idioma = "en", texto = fi$texto, ordem = 4:5))
trait <- list(trait_id = "snout_shape_lv", termos_busca = "snout")
cr <- recuperar_candidatos(con, "o", "R", trait)
checar("com ficha propria, so a ficha vai ao modelo", identical(cr$trecho_id, "f1"))
cs <- recuperar_candidatos(con, "o", "S", trait)
checar("a outra especie recebe a propria ficha, nao o trecho do GROBID sob a secao errada", identical(cs$trecho_id, "f2"))
cl <- recuperar_candidatos(con, "o", "L", trait)
checar("sem ficha, segue o caminho do GROBID", "g3" %in% cl$trecho_id && !any(grepl("^f", cl$trecho_id)))
checar("ficha de outra especie nao entra no caminho do GROBID", !"f1" %in% cl$trecho_id)
DBI::dbDisconnect(con, shutdown = TRUE)

cat(if (falhas == 0) "\ntodos os testes passaram\n\n" else sprintf("\n%d FALHA(S)\n\n", falhas))
quit(status = if (falhas == 0) 0 else 1)
