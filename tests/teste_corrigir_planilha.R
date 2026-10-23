# Teste da R18 (decisoes de vocabulario) na correcao da planilha do livro.
#
# Sem API, sem GROBID e sem planilha: abas sinteticas no formato de ler_aba().
#
#   Rscript tests/teste_corrigir_planilha.R
#
# O defeito (22/10/2026): a R18 so olhava measurementType/measurementValue.
# Na aba Habitat o caractere e a propria coluna, entao uma decisao sobre
# Habitat_type no inst/vocabulario_decisoes.csv era ignorada em silencio. Sem
# lugar para registrar, a Denise editou 53 celulas de Habitat direto na
# planilha corrigida, e essas edicoes sumiriam na proxima vez que a planilha
# fosse regerada.

if (!dir.exists("R") && dir.exists("../R")) setwd("..")
suppressMessages(suppressWarnings({
  source("R/migrar_planilha.R"); source("R/corrigir_planilha.R")
}))

falhas <- 0L
checar <- function(descricao, condicao) {
  cat(if (isTRUE(condicao)) "  ok   " else "  FALHA", descricao, "\n")
  if (!isTRUE(condicao)) falhas <<- falhas + 1L
}

decisoes <- tibble::tribble(
  ~trait, ~taxonID, ~valor_antigo, ~valor_novo, ~motivo,
  "Habitat_type", NA, "marsh/floodplain/swamp", "marsh|floodplain|swamp", "todos",
  "Habitat_type", "Anura2", "benthic", "lotic", "so a especie",
  "HabitatHydroperiod", NA, "temporary", "", "apaga",
  "snout_shape_lv", NA, "inclined", "sloped", "morfologia")

hab <- tibble::tibble(
  taxonID = c("Anura1", "Anura2", "Anura3", "Anura4"),
  Habitat_type = c("marsh/floodplain/swamp", "benthic", "benthic", "lotic"),
  HabitatHydroperiod = c("temporary", "permanent", NA, "temporary"),
  .linha = 2:5)

registro$log <- NULL
h <- aplicar_vocabulario(hab, "Habitat", decisoes)
checar("Habitat: decisao sem taxonID vale para todos os registros do valor",
       h$Habitat_type[1] == "marsh|floodplain|swamp")
checar("Habitat: decisao com taxonID so muda aquela especie",
       h$Habitat_type[2] == "lotic" && h$Habitat_type[3] == "benthic")
checar("Habitat: valor_novo vazio apaga a celula",
       all(h$HabitatHydroperiod[c(1, 4)] %in% c("", NA)) && h$HabitatHydroperiod[2] == "permanent")
checar("Habitat: valor sem decisao fica igual", h$Habitat_type[4] == "lotic")
checar("Habitat: toda celula alterada vai para o log (R18_vocabulario)",
       nrow(registro$log) == 4 && all(registro$log$regra == "R18_vocabulario"))

morf <- tibble::tibble(
  taxonID = c("Anura1", "Anura2"),
  measurementType = c("snout_shape_lv", "snout_shape_lv"),
  measurementValue = c("inclined", "rounded"),
  .linha = 2:3)
registro$log <- NULL
m <- aplicar_vocabulario(morf, "Morphology_DWC", decisoes)
checar("Morfologia: continua trocando pelo measurementType",
       m$measurementValue[1] == "sloped" && m$measurementValue[2] == "rounded")

cat(if (falhas == 0) "\ntodos os testes passaram\n\n" else sprintf("\n%d FALHA(S)\n\n", falhas))
quit(status = if (falhas == 0) 0 else 1)
