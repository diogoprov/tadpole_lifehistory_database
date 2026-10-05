# Revisao humana dos sinonimos ambiguos (04/10/2026).
#
# sinonimos_amphinom() deixa de fora o que atribuiria dado de uma especie a
# outra: trinomio cuja abreviacao casaria outro binomio, binomio que e especie
# valida, sinonimo de mais de uma especie da lista e nome que a ASW nao acha.
# No corpus da BT 5 foram 304 casos em 173 especies. Decidir se um nome vale
# e questao cientifica (Diogo): aqui so se junta a evidencia - em que obras do
# corpus o nome aparece, e se aparece em obra ligada a propria especie - e se
# le a decisao de volta para inst/sinonimos.csv.
#
#   planilha_revisao_sinonimos(con, "revisao/sinonimos_revisar_corpus.csv",
#                              "Claude outputs/sinonimos/sinonimos_para_revisar.xlsx")
#   aplicar_revisao_sinonimos("<planilha devolvida>.xlsx", "Diogo B. Provete")

library(purrr)
library(dplyr)
library(stringr)

DECISOES_SINONIMO <- c("global", "so_nesta_obra", "nao_entra")

#' Evidencia para cada sinonimo a revisar. `textos`: obra_id, titulo, texto
#' (um ou mais trechos por obra); `obra_taxon`: obra_id, taxon_id. Pura.
evidencia_sinonimos <- function(revisar, textos, obra_taxon) {
  por_obra <- textos |> group_by(obra_id, titulo) |> summarise(texto = paste(texto, collapse = " "), .groups = "drop")
  outras <- revisar |> filter(!is.na(nome_alternativo)) |> group_by(nome_alternativo) |>
    summarise(todas = list(unique(especie)), .groups = "drop")
  pmap_dfr(revisar, function(taxon_id, especie, nome_alternativo, motivo, ...) {
    vazio <- tibble::tibble(taxon_id, especie, nome_alternativo, motivo, n_obras = 0L, n_obras_da_especie = 0L,
                            obras = NA_character_, exemplo = NA_character_, outras_especies = NA_character_)
    if (is.na(nome_alternativo)) return(vazio)
    rx <- regex(paste0("\\b", str_escape(nome_alternativo), "\\b"), ignore_case = TRUE)
    acha <- por_obra[str_detect(por_obra$texto, rx), ]
    ligadas <- obra_taxon$obra_id[obra_taxon$taxon_id == taxon_id]
    da_especie <- acha$obra_id %in% ligadas
    outras_sp <- setdiff(unlist(outras$todas[outras$nome_alternativo == nome_alternativo]), especie)
    if (!nrow(acha)) return(mutate(vazio, outras_especies = if (length(outras_sp)) paste(outras_sp, collapse = "; ") else NA_character_))
    # o exemplo vem de preferencia de uma obra ligada a especie
    k <- if (any(da_especie)) which(da_especie)[1] else 1
    pos <- str_locate(acha$texto[k], rx)[1, ]
    tibble::tibble(
      taxon_id, especie, nome_alternativo, motivo,
      n_obras = nrow(acha), n_obras_da_especie = sum(da_especie),
      obras = paste(str_trunc(acha$titulo[order(!da_especie)], 60), collapse = " | "),
      exemplo = paste0(str_trunc(acha$titulo[k], 60), ": \u2026",
                       str_squish(str_sub(acha$texto[k], max(1, pos[1] - 150), pos[2] + 150)), "\u2026"),
      outras_especies = if (length(outras_sp)) paste(outras_sp, collapse = "; ") else NA_character_)
  }) |>
    arrange(desc(n_obras_da_especie), desc(n_obras), especie)
}

#' Planilha de revisao (xlsx) com a evidencia e as colunas amarelas
#' decisao / doi_obra / nota.
planilha_revisao_sinonimos <- function(con, revisar_csv, saida) {
  if (file.exists(saida)) stop(saida, " ja existe; a planilha enviada nao e sobrescrita", call. = FALSE)
  revisar <- ler_planilha_humana(revisar_csv)
  textos <- dbGetQuery(con, "SELECT t.obra_id, o.titulo, t.texto FROM trechos t JOIN obras o USING (obra_id)")
  ev <- evidencia_sinonimos(revisar, textos, dbGetQuery(con, "SELECT obra_id, taxon_id FROM obra_taxon"))
  tab <- mutate(ev, decisao = "", doi_obra = "", nota = "")
  leia <- c(
    "Sinonimos ambiguos: revisao",
    paste0(nrow(tab), " nomes que a sinonimia automatica (AmphiNom) deixou de fora, porque podem levar dado de uma especie para outra."),
    "Preencha so as colunas AMARELAS da aba 'revisao'.",
    "decisao: global (o nome vale para esta especie em qualquer obra) | so_nesta_obra (vale so na obra do doi_obra) | nao_entra.",
    "doi_obra: obrigatorio quando a decisao e so_nesta_obra.",
    "n_obras: em quantas obras do corpus (58 com texto) o nome aparece; n_obras_da_especie: quantas delas sao obras ligadas a esta especie. Linha sem evidencia pode ficar em branco: o nome nao aparece no corpus atual.",
    "Motivos: trinomio (a abreviacao do binomio casaria outro nome); binomio e especie valida; sinonimo de mais de uma especie da lista (ver outras_especies); nome nao achado na ASW (confira a grafia do nome aceito).",
    "Linha em branco = nao decidido (nada entra).")
  col <- function(n) match(n, names(tab))
  n <- nrow(tab) + 1
  dir.create(dirname(saida), showWarnings = FALSE, recursive = TRUE)
  wb <- openxlsx2::wb_workbook() |>
    openxlsx2::wb_add_worksheet("LEIA-ME") |>
    openxlsx2::wb_add_data(x = data.frame(x = leia), col_names = FALSE) |>
    openxlsx2::wb_set_col_widths(cols = 1, widths = 120) |>
    openxlsx2::wb_add_cell_style(dims = paste0("A1:A", length(leia)), wrap_text = TRUE, vertical = "top") |>
    openxlsx2::wb_add_font(dims = "A1", bold = TRUE, size = 13) |>
    openxlsx2::wb_add_worksheet("revisao") |>
    openxlsx2::wb_add_data(x = tab, na.strings = "") |>
    openxlsx2::wb_set_col_widths(cols = seq_along(tab), widths = c(8, 24, 30, 40, 8, 10, 40, 60, 24, 14, 22, 30)) |>
    openxlsx2::wb_set_col_widths(cols = col("taxon_id"), widths = 8, hidden = TRUE) |>
    openxlsx2::wb_add_cell_style(dims = openxlsx2::wb_dims(rows = 1:n, cols = seq_along(tab)), wrap_text = TRUE, vertical = "top") |>
    openxlsx2::wb_add_font(dims = openxlsx2::wb_dims(rows = 1, cols = seq_along(tab)), bold = TRUE) |>
    openxlsx2::wb_add_fill(dims = openxlsx2::wb_dims(rows = 1:n, cols = col(c("decisao", "doi_obra", "nota"))), color = openxlsx2::wb_color("FFFFF2A8")) |>
    openxlsx2::wb_freeze_pane(first_active_row = 2, first_active_col = col("nome_alternativo")) |>
    openxlsx2::wb_add_filter(rows = 1, cols = seq_along(tab)) |>
    openxlsx2::wb_add_data_validation(dims = openxlsx2::wb_dims(rows = 2:n, cols = col("decisao")), type = "list",
                                      value = paste0('"', paste(DECISOES_SINONIMO, collapse = ","), '"'))
  openxlsx2::wb_save(wb, saida)
  invisible(tab)
}

#' Decisoes da planilha devolvida -> linhas de inst/sinonimos.csv (especie,
#' nome_alternativo, doi_obra, fonte). So global e so_nesta_obra entram.
#' Para com os nomes se houver decisao fora da lista ou so_nesta_obra sem
#' doi_obra. Pura.
decisoes_sinonimos <- function(rev, revisor, data = format(Sys.Date(), "%d/%m/%Y")) {
  d <- mutate(rev, decisao = na_if(str_squish(coalesce(decisao, "")), ""),
              doi_obra = na_if(str_squish(coalesce(doi_obra, "")), ""))
  ruins <- c(
    d$nome_alternativo[!is.na(d$decisao) & !d$decisao %in% DECISOES_SINONIMO],
    d$nome_alternativo[d$decisao %in% "so_nesta_obra" & is.na(d$doi_obra)])
  if (length(ruins)) {
    stop("decisao invalida (fora da lista, ou so_nesta_obra sem doi_obra): ", paste(ruins, collapse = "; "), call. = FALSE)
  }
  d |>
    filter(decisao %in% c("global", "so_nesta_obra"), !is.na(nome_alternativo)) |>
    transmute(especie, nome_alternativo,
              doi_obra = if_else(decisao == "so_nesta_obra", tolower(doi_obra), NA_character_),
              fonte = paste0(revisor, ", ", data, ": revisao dos sinonimos ambiguos",
                             if_else(is.na(nota) | nota == "", "", paste0("; ", nota))))
}

#' Le a planilha devolvida e acrescenta as decisoes a inst/sinonimos.csv,
#' sem repetir linha que ja esta la. Devolve as linhas acrescentadas.
aplicar_revisao_sinonimos <- function(planilha, revisor, curados = "inst/sinonimos.csv") {
  rev <- readxl::read_excel(planilha, sheet = "revisao", col_types = "text")
  novas <- decisoes_sinonimos(rev, revisor)
  atuais <- readr::read_csv(curados, comment = "#", show_col_types = FALSE, col_types = readr::cols(.default = "c"))
  novas <- anti_join(novas, atuais, by = c("especie", "nome_alternativo"))
  if (nrow(novas)) readr::write_csv(novas, curados, append = TRUE, na = "")
  novas
}
