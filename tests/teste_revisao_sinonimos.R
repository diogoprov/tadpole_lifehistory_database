# Teste da revisao humana dos sinonimos ambiguos (R/revisao_sinonimos.R).
#
# Sem banco e sem API: tabelas sinteticas.
#
#   Rscript tests/teste_revisao_sinonimos.R
#
# Por que (04/10/2026): 304 sinonimos ficaram de fora da sinonimia automatica
# porque podem levar dado de uma especie para outra. A decisao e do Diogo; o
# codigo so junta a evidencia e le a decisao de volta para inst/sinonimos.csv,
# sem deixar passar decisao fora da lista nem "so nesta obra" sem a obra.

suppressMessages({ library(dplyr); library(purrr); library(stringr); library(tibble) })
if (!dir.exists("R") && dir.exists("../R")) setwd("..")
suppressMessages(suppressWarnings({ source("R/carregar.R"); carregar_projeto("R") }))

falhas <- 0L
checar <- function(descricao, condicao) {
  cat(if (isTRUE(condicao)) "  ok   " else "  FALHA", descricao, "\n")
  if (!isTRUE(condicao)) falhas <<- falhas + 1L
  invisible(condicao)
}

cat("\nevidencia_sinonimos()\n")
revisar <- tibble(
  taxon_id = c("tt", "rm", "bb", "xx"),
  especie = c("Trachycephalus typhonius", "Rhinella margaritifera", "Boana boans", "Genus nada"),
  nome_alternativo = c("Bufo typhonius", "Bufo typhonius", "Hypsiboas boans", NA),
  motivo = c("sinonimo de mais de uma especie da lista", "sinonimo de mais de uma especie da lista",
             "sinonimo de mais de uma especie da lista", "nome nao achado na ASW"))
textos <- tibble(obra_id = c("o1", "o2", "o3"), titulo = c("Obra um", "Obra dois", "Obra tres"),
                 texto = c("The tadpole of Bufo typhonius (now Trachycephalus) has a rounded snout.",
                           "Toads such as bufo typhonius were collected.", "Nothing here."))
ot <- tibble(obra_id = c("o1", "o3"), taxon_id = c("tt", "bb"))
ev <- evidencia_sinonimos(revisar, textos, ot)
tt <- ev[ev$especie == "Trachycephalus typhonius", ]
checar("conta as obras em que o nome aparece (sem diferenciar caixa)", tt$n_obras == 2)
checar("e quantas sao obras ligadas a propria especie", tt$n_obras_da_especie == 1 &&
         ev$n_obras_da_especie[ev$especie == "Rhinella margaritifera"] == 0)
checar("o exemplo vem da obra ligada a especie", grepl("^Obra um", tt$exemplo) && grepl("Bufo typhonius", tt$exemplo))
checar("aponta as outras especies com o mesmo nome", tt$outras_especies == "Rhinella margaritifera")
checar("o que tem evidencia na propria especie vem primeiro", ev$especie[1] == "Trachycephalus typhonius")
checar("nome ausente do corpus fica com zero e sem exemplo",
       ev$n_obras[ev$especie == "Boana boans"] == 0 && is.na(ev$exemplo[ev$especie == "Boana boans"]))
checar("linha sem nome (nao achado na ASW) passa sem quebrar", ev$n_obras[ev$especie == "Genus nada"] == 0)

cat("\ndecisoes_sinonimos()\n")
rev <- tibble(especie = c("A a", "B b", "C c", "D d"), nome_alternativo = c("X a", "Y b", "Z c", "W d"),
              decisao = c("global", "so_nesta_obra", "nao_entra", NA), doi_obra = c(NA, "10.1/ABC", NA, NA),
              nota = c(NA, "nome antigo so nesta obra", NA, NA))
d <- decisoes_sinonimos(rev, "Diogo B. Provete", "04/10/2026")
checar("so global e so_nesta_obra entram; em branco e nao_entra ficam de fora", identical(d$especie, c("A a", "B b")))
checar("doi_obra so em so_nesta_obra, em minusculas", is.na(d$doi_obra[1]) && d$doi_obra[2] == "10.1/abc")
checar("a fonte registra quem decidiu, quando e a nota",
       grepl("^Diogo B. Provete, 04/10/2026: revisao", d$fonte[2]) && grepl("nome antigo so nesta obra", d$fonte[2]))
checar("decisao fora da lista para com o nome",
       grepl("X a", tryCatch(decisoes_sinonimos(mutate(rev, decisao = c("talvez", NA, NA, NA)), "x"), error = conditionMessage)))
checar("so_nesta_obra sem doi_obra para",
       grepl("Y b", tryCatch(decisoes_sinonimos(mutate(rev, doi_obra = NA), "x"), error = conditionMessage)))

if (requireNamespace("openxlsx2", quietly = TRUE) && requireNamespace("readxl", quietly = TRUE)) {
  cat("\naplicar_revisao_sinonimos()\n")
  cur <- tempfile(fileext = ".csv")
  writeLines(c("# comentario", "especie,nome_alternativo,doi_obra,fonte", "A a,X a,,ja estava"), cur)
  xl <- tempfile(fileext = ".xlsx")
  openxlsx2::write_xlsx(list(revisao = as.data.frame(rev)), xl)
  nov <- aplicar_revisao_sinonimos(xl, "Diogo B. Provete", cur)
  lido <- readr::read_csv(cur, comment = "#", show_col_types = FALSE, col_types = readr::cols(.default = "c"))
  checar("acrescenta so o que ainda nao estava no csv", nrow(nov) == 1 && nrow(lido) == 2 && lido$nome_alternativo[2] == "Y b")
  checar("aplicar de novo nao duplica", nrow(aplicar_revisao_sinonimos(xl, "Diogo B. Provete", cur)) == 0)
  unlink(c(cur, xl))
}

cat(if (falhas == 0) "\ntodos os testes passaram\n\n" else sprintf("\n%d FALHA(S)\n\n", falhas))
quit(status = if (falhas == 0) 0 else 1)
