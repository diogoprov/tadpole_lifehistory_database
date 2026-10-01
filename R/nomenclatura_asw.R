# Conferencia da nomenclatura contra a Amphibian Species of the World (ASW).
#
# POR QUE ISTO E UM SCRIPT SEPARADO: o site da ASW responde 403 a requisicao
# automatizada de fora e o robots.txt bloqueia leitura por ferramenta. Quem
# roda esta etapa e voce, na sua maquina, onde o AmphiNom instala e o site
# responde. O resultado vira um csv de decisoes que o corrigir_planilha.R
# aplica. Enquanto esse csv nao existir, nenhuma grafia de nome e alterada.
#
# Fluxo:
#   1. casos_nomenclatura()  -> lista os conflitos e as evidencias (roda em
#                               qualquer lugar, nao precisa de rede)
#   2. resolver_com_asw()    -> consulta a ASW e preenche a grafia aceita
#   3. o grupo revisa o csv e marca o que o modelo nao resolveu
#   4. corrigir_planilha.R aplica

library(dplyr)
library(purrr)
library(stringr)

#' Conflitos de nome: um taxonID com mais de uma grafia, ou uma grafia com
#' mais de um taxonID. Devolve as evidencias que o revisor precisa: quantas
#' linhas sustentam cada grafia e em que abas ela aparece.
casos_nomenclatura <- function(abas) {
  pares <- imap_dfr(abas, function(d, aba) {
    if (!all(c("taxonID", "scientificName") %in% names(d))) return(tibble::tibble())
    transmute(d, aba = aba,
              taxonID = str_squish(taxonID),
              nome = str_extract(str_squish(scientificName), "^\\S+\\s+\\S+"))
  }) |>
    filter(!is.na(taxonID), !is.na(nome))

  contagem <- count(pares, taxonID, nome, aba, name = "n_linhas")

  id_conflitante <- pares |> distinct(taxonID, nome) |>
    count(taxonID) |> filter(n > 1) |> pull(taxonID)
  nome_conflitante <- pares |> distinct(taxonID, nome) |>
    count(nome) |> filter(n > 1) |> pull(nome)

  contagem |>
    filter(taxonID %in% id_conflitante | nome %in% nome_conflitante) |>
    group_by(taxonID, nome) |>
    summarise(n_linhas = sum(n_linhas),
              abas = paste(sort(unique(aba)), collapse = "|"), .groups = "drop") |>
    mutate(tipo_conflito = case_when(
      taxonID %in% id_conflitante & nome %in% nome_conflitante ~ "id e nome",
      taxonID %in% id_conflitante ~ "mesmo id, grafias diferentes",
      TRUE ~ "mesmo nome, ids diferentes")) |>
    arrange(taxonID, desc(n_linhas))
}

#' Consulta a ASW para cada grafia candidata e diz se ela e o nome aceito,
#' um sinonimo, ou nao foi encontrada. Precisa do cache da ASW montado por
#' atualizar_cache_asw() (ver R/sinonimia.R).
resolver_com_asw <- function(casos, cache = "inst/asw_cache.rds") {
  if (!requireNamespace("AmphiNom", quietly = TRUE)) {
    stop("instale AmphiNom: remotes::install_github('hcliedtke/AmphiNom')")
  }
  if (!file.exists(cache)) stop("rode atualizar_cache_asw() antes")
  asw <- readRDS(cache)

  res <- as_tibble(AmphiNom::aswSync(query = unique(casos$nome), asw = asw$sinonimos))
  readr::write_csv(res, "revisao/asw_conflitos_bruto.csv")
  message("saida bruta do aswSync em revisao/asw_conflitos_bruto.csv; ",
          "confira os nomes de coluna antes de confiar no join abaixo")

  # AmphiNom muda nomes de coluna entre versoes. O join abaixo assume
  # 'query' e 'ASW_names'; ajuste se a saida bruta mostrar outra coisa.
  if (!all(c("query", "ASW_names") %in% names(res))) {
    stop("colunas inesperadas em aswSync(): ", paste(names(res), collapse = ", "),
         ". Ajuste resolver_com_asw() e rode de novo.")
  }

  casos |>
    left_join(select(res, nome = query, nome_asw = ASW_names), by = "nome") |>
    mutate(aceito_na_asw = !is.na(nome_asw) & nome_asw == nome)
}

#' Template do csv de decisoes. Uma linha por taxonID em conflito.
#' Preencha nome_aceito (e autoria_aceita, se souber) e a fonte.
template_decisoes <- function(casos, caminho = "inst/nomenclatura_decisoes.csv") {
  d <- casos |>
    group_by(taxonID) |>
    summarise(
      grafias = paste0(nome, " (", n_linhas, " linhas, ", abas, ")", collapse = " | "),
      tipo_conflito = first(tipo_conflito),
      nome_aceito = NA_character_,
      autoria_aceita = NA_character_,
      fonte = NA_character_,   # ASW | humano
      nota = NA_character_,
      .groups = "drop")
  dir.create(dirname(caminho), showWarnings = FALSE, recursive = TRUE)
  readr::write_csv(d, caminho, na = "")
  nrow(d)
}
