# Gera o esqueleto de inst/traits.csv.
#
# Duas origens:
#   planilha   - os caracteres que JA estao na base do livro. Tipo, valores
#                observados e definicao saem dos proprios dados, entao a maior
#                parte do trabalho ja vem pronta e o grupo so revisa.
#   a_definir  - os traits de historia de vida que o grupo quer acrescentar e
#                que ainda nao existem na planilha. Vem em branco.
#
# NADA aqui e definicao final: `status` comeca como "revisar" em toda linha, e
# o pipeline so deve rodar depois que o grupo fechar cada uma.
#
# Uso:
#   source("R/esqueleto_traits.R")
#   esqueleto_traits("dwca/measurementorfact.txt", "inst/traits.csv")

library(dplyr)
library(purrr)
library(stringr)
library(tidyr)

# Traits de historia de vida discutidos pelo grupo e ainda ausentes da
# planilha. Acrescente aqui o que faltar antes de gerar o arquivo.
TRAITS_A_DEFINIR <- tibble::tribble(
  ~trait_id,            ~nome,                             ~tipo,         ~unidade,
  "ctmax",              "Temperatura critica maxima",      "numerico",    "C",
  "ctmin",              "Temperatura critica minima",      "numerico",    "C",
  "tempo_desenvolvimento", "Tempo ate a metamorfose",      "numerico",    "dias",
  "tamanho_metamorfose", "Tamanho na metamorfose",         "numerico",    "mm",
  "taxa_crescimento",   "Taxa de crescimento larval",      "numerico",    "mm/dia",
  "sobrevivencia",      "Sobrevivencia ate a metamorfose", "numerico",    "proporcao",
  "guilda_trofica",     "Guilda trofica",                  "categorico",  NA,
  "tipo_ecomorfologico", "Tipo ecomorfologico",            "categorico",  NA
)

#' Valores observados de um caractere, para o grupo usar como ponto de partida
#' do vocabulario controlado. Corta em 25 para o arquivo nao virar ilegivel.
resumir_valores <- function(v, limite = 25) {
  tb <- sort(table(str_squish(v[!is.na(v)])), decreasing = TRUE)
  if (length(tb) == 0) return(NA_character_)
  vals <- names(tb)[seq_len(min(length(tb), limite))]
  paste0(paste(vals, collapse = ";"),
         if (length(tb) > limite) paste0(" [+", length(tb) - limite, " outros]") else "")
}

esqueleto_traits <- function(mof_txt, saida) {
  mof <- readr::read_tsv(mof_txt, col_types = readr::cols(.default = "c"))

  # Cada item alimentar virou um measurementType na migracao ("diet_item:X"),
  # mas item nao e trait: e valor. Os 31 itens viram UM trait de composicao da
  # dieta, com o item guardado como categoria e a porcentagem como valor.
  itens_dieta <- mof |>
    filter(str_starts(measurementType, "diet_item:")) |>
    pull(measurementType) |> str_remove("^diet_item:") |> unique() |> sort()

  mof <- mof |>
    mutate(measurementType = if_else(str_starts(measurementType, "diet_item:"),
                                     "dieta_composicao", measurementType))

  da_planilha <- mof |>
    mutate(
      # a frase de definicao viaja em measurementRemarks, no formato
      # "origem=...; definicao=...; developmentalStage=..."
      definicao = str_match(measurementRemarks, "definicao=([^;]*)")[, 2],
      origem_aba = str_match(measurementRemarks, "origem=([^;]*)")[, 2]) |>
    group_by(trait_id = measurementType) |>
    summarise(
      n_registros = n(),
      origem_aba = first(na.omit(origem_aba)) %||% NA_character_,
      definicao = first(na.omit(definicao)) %||% NA_character_,
      prop_numerica = mean(str_detect(str_squish(measurementValue),
                                      "^-?[0-9]+([.,][0-9]+)?$"), na.rm = TRUE),
      unidade = first(na.omit(measurementUnit)) %||% NA_character_,
      valores_aceitos = resumir_valores(measurementValue),
      .groups = "drop") |>
    mutate(
      tipo = if_else(prop_numerica > 0.8, "numerico", "categorico"),
      nome = str_replace_all(trait_id, "_", " "),
      valores_aceitos = if_else(tipo == "numerico", NA_character_, valores_aceitos),
      # a dieta e o caso hibrido: valor numerico (%) sobre uma categoria (item)
      valores_aceitos = if_else(trait_id == "dieta_composicao",
                                paste(itens_dieta, collapse = ";"), valores_aceitos),
      definicao = if_else(trait_id == "dieta_composicao",
                          "Porcentagem de cada item alimentar no conteudo intestinal",
                          definicao),
      estagio_ref = NA_character_, min_plausivel = NA_real_, max_plausivel = NA_real_,
      termos_busca = NA_character_,
      origem = paste0("planilha:", origem_aba),
      status = "revisar") |>
    select(-prop_numerica, -origem_aba)

  a_definir <- TRAITS_A_DEFINIR |>
    mutate(n_registros = 0L, definicao = NA_character_, valores_aceitos = NA_character_,
           estagio_ref = NA_character_, min_plausivel = NA_real_,
           max_plausivel = NA_real_, termos_busca = NA_character_,
           origem = "a_definir", status = "revisar")

  sem_codigo <- filter(da_planilha, is.na(trait_id))
  if (nrow(sem_codigo) > 0) {
    message("medidas sem codigo de caractere na planilha: ",
            sum(sem_codigo$n_registros), " registros ficaram de fora do esqueleto")
  }
  da_planilha <- filter(da_planilha, !is.na(trait_id))

  todos <- bind_rows(da_planilha, a_definir) |>
    select(trait_id, nome, tipo, unidade, estagio_ref, definicao,
           valores_aceitos, min_plausivel, max_plausivel, termos_busca,
           origem, status, n_registros) |>
    arrange(origem, desc(n_registros))

  # Preserva o que ja foi preenchido a mao: rodar o esqueleto de novo depois
  # de uma rodada de decisoes nao pode apagar o trabalho de quem preencheu.
  if (file.exists(saida)) {
    antigo <- readr::read_csv(saida, show_col_types = FALSE)
    manter <- intersect(c("estagio_ref", "min_plausivel", "max_plausivel",
                          "termos_busca", "definicao", "valores_aceitos", "status"),
                        names(antigo))
    if (length(manter) > 0) {
      todos <- todos |>
        left_join(select(antigo, trait_id, all_of(paste0(manter))) |>
                    rename_with(~ paste0(.x, "_ant"), -trait_id), by = "trait_id")
      for (col in manter) {
        ant <- paste0(col, "_ant")
        todos[[col]] <- coalesce(as.character(todos[[ant]]), as.character(todos[[col]]))
      }
      todos <- select(todos, -ends_with("_ant"))
    }
  }

  readr::write_csv(todos, saida, na = "")
  list(n = nrow(todos), por_origem = count(todos, origem, tipo))
}

`%||%` <- function(x, y) if (is.null(x) || length(x) == 0 || all(is.na(x))) y else x
