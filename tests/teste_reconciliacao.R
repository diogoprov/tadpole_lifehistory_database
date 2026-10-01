# Teste da reconciliacao dentro da obra.
#
# Roda sem API, sem GROBID e sem banco: so a parte pura de validacao.R.
#
#   Rscript tests/teste_reconciliacao.R
#
# O caso que originou isto: no teste de fumaca de 01/10/2026, Conte et al.
# (2007) rendeu snout_shape_lv = rounded DUAS vezes - uma do paragrafo de
# descricao, outra da comparacao na Discussao. Como extracao_id inclui o
# trecho_id, as duas persistem, e nada a jusante as reconciliava:
# escrever_dwc() emitiria duas medidas, calibrar_limiares() contaria o par
# duas vezes, e se os valores divergissem ninguem seria avisado.

suppressMessages({ library(dplyr); library(tibble) })
if (!dir.exists("R") && dir.exists("../R")) setwd("..")

# le so o necessario: as funcoes puras, sem abrir conexao
e <- new.env()
eval(parse(text = paste(readLines("R/validacao.R", warn = FALSE), collapse = "\n")),
     envir = e)
valores_divergem <- e$valores_divergem
decidir_reconciliacao <- e$decidir_reconciliacao

falhas <- 0L
checar <- function(descricao, condicao) {
  cat(if (isTRUE(condicao)) "  ok   " else "  FALHA", descricao, "\n")
  if (!isTRUE(condicao)) falhas <<- falhas + 1L
  invisible(condicao)
}

reg <- function(id, obra, taxon, trait, cat = NA_character_, num = NA_real_,
                conf = 0.5, tipo = "categorico") {
  tibble(extracao_id = id, obra_id = obra, taxon_id = taxon, trait_id = trait,
         valor_num = num, valor_cat = cat, confianca = conf, tipo = tipo)
}

st <- function(d, id) d$novo_status[d$extracao_id == id]
mo <- function(d, id) d$motivo[d$extracao_id == id]

# ---------------------------------------------------------------------------
cat("\nvalores_divergem()\n")
checar("uma categoria so nao divege",
       !valores_divergem(NA, c("rounded", "rounded"), "categorico", 0.05))
checar("caixa e espaco nao fazem divergencia",
       !valores_divergem(NA, c("Rounded", " rounded"), "categorico", 0.05))
checar("categorias diferentes divergem",
       valores_divergem(NA, c("rounded", "truncate"), "categorico", 0.05))
checar("numeros dentro da tolerancia nao divergem",
       !valores_divergem(c(32.10, 32.15), NA, "numerico", 0.05))
checar("numeros fora da tolerancia divergem",
       valores_divergem(c(0.5, 3.0), NA, "numerico", 0.05))
checar("um numero so nao diverge",
       !valores_divergem(c(32.1, NA), NA, "numerico", 0.05))

# ---------------------------------------------------------------------------
cat("\nregistro unico fica intacto\n")
d <- decidir_reconciliacao(reg("a1", "o1", "t1", "snout_shape_lv", cat = "rounded"))
checar("segue bruto", st(d, "a1") == "bruto")
checar("sem motivo", is.na(mo(d, "a1")))

# ---------------------------------------------------------------------------
cat("\ndois trechos concordando (o caso real do Conte et al. 2007)\n")
d <- decidir_reconciliacao(bind_rows(
  reg("desc", "o1", "t1", "snout_shape_lv", cat = "rounded", conf = 0.90),
  reg("disc", "o1", "t1", "snout_shape_lv", cat = "rounded", conf = 0.96)))
checar("sobra exatamente um bruto", sum(d$novo_status == "bruto") == 1)
checar("o que fica e o de maior confianca", st(d, "disc") == "bruto")
checar("o outro sai como duplicado", mo(d, "desc") == "duplicado_na_obra")
checar("duplicado nao e conflito", !any(d$novo_status == "conflito"))

cat("\n  (sem este passo seriam 2 linhas de MeasurementOrFact para a mesma\n")
cat("   medida, e o par entraria 2x no denominador da precisao)\n")

# ---------------------------------------------------------------------------
cat("\ndois trechos divergindo: ninguem passa\n")
d <- decidir_reconciliacao(bind_rows(
  reg("x1", "o1", "t1", "snout_shape_lv", cat = "rounded", conf = 0.96),
  reg("x2", "o1", "t1", "snout_shape_lv", cat = "truncate", conf = 0.70)))
checar("os dois viram conflito", all(d$novo_status == "conflito"))
checar("o de maior confianca NAO e promovido", st(d, "x1") == "conflito")
checar("motivo registrado", all(d$motivo == "conflito_interno_na_obra"))
checar("nenhum bruto sobra", !any(d$novo_status == "bruto"))

# ---------------------------------------------------------------------------
cat("\nconflito numerico respeita a tolerancia\n")
d <- decidir_reconciliacao(bind_rows(
  reg("n1", "o1", "t1", "depth", num = 0.50, conf = 0.9, tipo = "numerico"),
  reg("n2", "o1", "t1", "depth", num = 0.51, conf = 0.8, tipo = "numerico")))
checar("0,50 e 0,51 sao o mesmo valor: duplicado, nao conflito",
       mo(d, "n2") == "duplicado_na_obra")
d <- decidir_reconciliacao(bind_rows(
  reg("n3", "o1", "t1", "depth", num = 0.50, conf = 0.9, tipo = "numerico"),
  reg("n4", "o1", "t1", "depth", num = 3.00, conf = 0.8, tipo = "numerico")))
checar("0,50 e 3,00 divergem", all(d$novo_status == "conflito"))

# ---------------------------------------------------------------------------
cat("\nos grupos nao se contaminam\n")
d <- decidir_reconciliacao(bind_rows(
  reg("g1", "o1", "t1", "eyes_positioning", cat = "dorsal",    conf = 0.85),
  reg("g2", "o2", "t1", "eyes_positioning", cat = "lateral",   conf = 0.80),
  reg("g3", "o1", "t2", "eyes_positioning", cat = "dorsal",    conf = 0.80),
  reg("g4", "o1", "t1", "snout_shape_lv",   cat = "rounded",   conf = 0.90)))
checar("obra diferente nao e conflito", st(d, "g1") == "bruto" && st(d, "g2") == "bruto")
checar("taxon diferente nao e conflito", st(d, "g3") == "bruto")
checar("trait diferente nao e conflito", st(d, "g4") == "bruto")
checar("os quatro seguem brutos", all(d$novo_status == "bruto"))

# ---------------------------------------------------------------------------
cat("\ndesempate deterministico quando a confianca empata\n")
d1 <- decidir_reconciliacao(bind_rows(
  reg("bbb", "o1", "t1", "x", cat = "rounded", conf = 0.8),
  reg("aaa", "o1", "t1", "x", cat = "rounded", conf = 0.8)))
d2 <- decidir_reconciliacao(bind_rows(
  reg("aaa", "o1", "t1", "x", cat = "rounded", conf = 0.8),
  reg("bbb", "o1", "t1", "x", cat = "rounded", conf = 0.8)))
checar("a ordem de entrada nao muda o resultado",
       identical(st(d1, "aaa"), st(d2, "aaa")))
checar("fica o menor extracao_id", st(d1, "aaa") == "bruto")

# ---------------------------------------------------------------------------
cat("\nconfianca ausente nao ganha a disputa\n")
d <- decidir_reconciliacao(bind_rows(
  reg("semconf", "o1", "t1", "x", cat = "rounded", conf = NA_real_),
  reg("comconf", "o1", "t1", "x", cat = "rounded", conf = 0.60)))
checar("fica o registro que tem confianca", st(d, "comconf") == "bruto")

cat("\n", if (falhas == 0) "todos os testes passaram\n\n" else
    paste0(falhas, " teste(s) falharam\n\n"), sep = "")
if (falhas > 0) quit(status = 1)
