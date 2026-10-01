# Triagem de relevancia: agente barato decide, humano arbitra a margem.
# Entra em titulo + periodico + ano, nao no PDF: e onde a decisao de
# relevancia realmente se resolve, e custa quase nada.
# As obras-semente da BT 5.0 nao passam por aqui - ja sao relevantes.

library(purrr)
library(dplyr)

triar_obras <- function(con, obras, cfg, margem = c(0.35, 0.75)) {
  if (nrow(obras) == 0) return(tibble::tibble())

  res <- tryCatch(agente_triagem(obras, cfg), error = function(e) NULL)
  if (is.null(res)) {
    warning("agente de triagem falhou; nenhuma obra triada nesta rodada")
    return(tibble::tibble())
  }

  d <- tibble::tibble(
    obra_id = obras$obra_id,
    relevante = map_lgl(res, ~ isTRUE(.x$relevante)),
    prob = map_dbl(res, ~ as.numeric(.x$prob %||% NA)),
    justificativa = map_chr(res, ~ .x$justificativa %||% NA_character_)) |>
    mutate(decidido_por = if_else(prob >= margem[1] & prob <= margem[2],
                                  "fila_humana",
                                  paste0("agente:", cfg$agentes$triagem$modelo)),
           data = Sys.time())

  registrar(con, "triagem", d)
  d
}

#' Obras na margem: planilha para o grupo decidir a mao.
exportar_fila_triagem <- function(con, caminho) {
  fila <- dbGetQuery(con, "
    SELECT o.obra_id, o.titulo, o.ano, o.doi, t.prob, t.justificativa
      FROM triagem t JOIN obras o USING (obra_id)
     WHERE t.decidido_por = 'fila_humana'
     ORDER BY t.prob DESC")
  fila$decisao_humana <- ""   # o revisor preenche: sim / nao
  dir.create(dirname(caminho), showWarnings = FALSE, recursive = TRUE)
  readr::write_csv(fila, caminho)
  nrow(fila)
}

importar_fila_triagem <- function(con, caminho, revisor) {
  d <- readr::read_csv(caminho, show_col_types = FALSE) |>
    filter(decisao_humana %in% c("sim", "nao")) |>
    transmute(obra_id, relevante = decisao_humana == "sim", prob,
              justificativa, decidido_por = revisor, data = Sys.time())
  registrar(con, "triagem", d)
  nrow(d)
}
