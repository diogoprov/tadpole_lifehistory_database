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

# O defeito (06/11/2026): a R18 guardava o valor anterior so na morfologia. No
# Habitat, juntar "temporary ponds" em lentic apagava o "temporary" do registro.
checar("Habitat: guarda o valor anterior so nas celulas que a regra mudou",
       identical(h$Habitat_type_original,
                 c("marsh/floodplain/swamp", "benthic", NA, NA)))
checar("Habitat: cada caractere tem a sua coluna de original",
       identical(h$HabitatHydroperiod_original, c("temporary", NA, NA, "temporary")))

hab_dwc <- h |> dplyr::mutate(
  `HigherGeography (biome)` = "Cerrado", LocationID = "L1",
  `Source of information` = "fonte", eventID = paste0("e", 1:4))
mor_vazia <- tibble::tibble(
  taxonID = character(), MeasurementOrFact = character(), codigo = character(),
  measurementValue = character(), organismQuantity = character(),
  organismQuantityType = character(), measurementMethod = character(),
  DevelopmentalStages = character(), `Source of information` = character(),
  eventID = character())
die_vazia <- tibble::tibble(
  taxonID = character(), measurementType = character(), measurementValue = character(),
  measurementAccuracy = character(),
  organismQuantity = character(), organismQuantityType = character(),
  measurementMethod = character(), `Source of information` = character(),
  eventID = character())
mof <- montar_mof(hab_dwc, mor_vazia, die_vazia)
rem <- function(tax, tipo) mof$measurementRemarks[mof$taxonID == tax & mof$measurementType == tipo]
checar("DwC: frase original do Habitat vai para o measurementRemarks",
       grepl('verbatim="benthic"', rem("Anura2", "Habitat_type"), fixed = TRUE))
checar("DwC: o verbatim de um caractere nao vaza para outro da mesma linha",
       !grepl("verbatim", rem("Anura2", "HabitatHydroperiod"), fixed = TRUE))
checar("DwC: sem regra, sem verbatim",
       !grepl("verbatim", rem("Anura4", "Habitat_type"), fixed = TRUE))

morf <- tibble::tibble(
  taxonID = c("Anura1", "Anura2"),
  measurementType = c("snout_shape_lv", "snout_shape_lv"),
  measurementValue = c("inclined", "rounded"),
  .linha = 2:3)
registro$log <- NULL
m <- aplicar_vocabulario(morf, "Morphology_DWC", decisoes)
checar("Morfologia: continua trocando pelo measurementType",
       m$measurementValue[1] == "sloped" && m$measurementValue[2] == "rounded")

# O defeito (26/10/2026, apontado pela Denise): a R18 trocava a descricao longa
# do livro pelo estado curto, e a frase sumia da planilha e do DwC-A.
checar("Morfologia: guarda o valor anterior quando a regra muda o valor",
       identical(m$measurementValue_original, c("inclined", NA)))
checar("DwC: frase original vai para o measurementRemarks, no formato do dwc.R",
       identical(remark_verbatim(c('a "b"', NA)), c("; verbatim=\"a 'b'\"", "")))

cat(if (falhas == 0) "\ntodos os testes passaram\n\n" else sprintf("\n%d FALHA(S)\n\n", falhas))
quit(status = if (falhas == 0) 0 else 1)
