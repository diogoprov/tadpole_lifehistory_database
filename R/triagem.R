# Triagem de relevancia: regra fixa primeiro (binomio no titulo), depois o
# agente barato, e humano arbitra a margem. Entra em titulo + resumo + ano,
# nao no PDF: custa quase nada. So pelo titulo nao bastava (01/10/2026).
# As obras-semente da BT 5.0 nao passam por aqui - ja sao relevantes.

library(purrr)
library(dplyr)

triar_obras <- function(con, obras, cfg, margem = c(0.35, 0.75)) {
  if (nrow(obras) == 0) return(tibble::tibble())

  # Regra fixa antes do modelo: obra com o binomio de uma especie-alvo a que
  # ela esta ligada no titulo entra direto. E o caso mais caro de perder - no
  # teste de P. barrioi (01/10/2026) o agente descartou a propria redescricao
  # da especie por achar, pelo titulo, que tratava so do adulto. O falso
  # positivo possivel custa um PDF a mais. Decisao do grupo em 01/10/2026.
  direto <- binomio_alvo_no_titulo(con, obras)
  d_regra <- tibble::tibble(
    obra_id = obras$obra_id[direto], relevante = TRUE, prob = NA_real_,
    justificativa = "binomio da especie-alvo no titulo",
    decidido_por = "regra:binomio_no_titulo", data = Sys.time())

  resto <- obras[!direto, ]
  d_agente <- tibble::tibble()
  if (nrow(resto) > 0) {
    res <- tryCatch(agente_triagem(resto, cfg), error = function(e) e)
    if (inherits(res, "error")) {
      warning("agente de triagem falhou (", conditionMessage(res), "); ",
              nrow(resto), " obra(s) sem triagem nesta rodada", call. = FALSE)
    } else {
      d_agente <- interpretar_triagem(res, resto$obra_id, cfg$agentes$triagem$modelo, margem)
      if (any(is.na(d_agente$relevante))) {
        warning(sum(is.na(d_agente$relevante)), " obra(s) sem resposta do agente de ",
                "triagem; foram para a fila humana", call. = FALSE)
      }
    }
  }

  d <- bind_rows(d_regra, d_agente)
  registrar(con, "triagem", d)
  d
}

#' Para cada obra: o titulo cita o binomio (ou sinonimo) de alguma especie-alvo
#' a que ela esta ligada em obra_taxon?
binomio_alvo_no_titulo <- function(con, obras) {
  ids <- paste0("'", obras$obra_id, "'", collapse = ",")
  pares <- dbGetQuery(con, sprintf(
    "SELECT obra_id, taxon_id FROM obra_taxon WHERE obra_id IN (%s)", ids))
  taxa <- unique(pares$taxon_id)
  nomes <- set_names(map(taxa, ~ aliases_de(con, .x)), taxa)
  marcar_binomio(obras, pares, nomes)
}

#' Parte pura de binomio_alvo_no_titulo(), testavel sem banco.
#' @param pares data frame (obra_id, taxon_id)
#' @param nomes lista nomeada taxon_id -> nomes aceitos e sinonimos
marcar_binomio <- function(obras, pares, nomes) {
  if (nrow(pares) == 0) return(rep(FALSE, nrow(obras)))
  pares$titulo <- obras$titulo[match(pares$obra_id, obras$obra_id)]
  cita <- map2_lgl(pares$titulo, pares$taxon_id,
                   ~ titulo_cita_especie(.x, nomes[[.y]]))
  obras$obra_id %in% pares$obra_id[cita]
}

#' Parte pura: resposta do agente -> linhas da tabela triagem. Separada para
#' ser testada sem API.
#'
#' parallel_chat_structured() devolve um TIBBLE - uma linha por obra, uma
#' coluna por campo (relevante, prob, justificativa) e, se alguma chamada
#' falhou, uma coluna .error. Nao e uma lista de respostas. O codigo anterior
#' iterava com map_lgl(res, ~ .x$relevante), que percorre as COLUNAS: o
#' primeiro elemento era o vetor `relevante` inteiro, e dava "$ operator is
#' invalid for atomic vectors" (teste de fumaca da busca, 01/10/2026).
#'
#' Chamada que falhou NAO vira "irrelevante". O isTRUE() antigo transformava
#' resposta ausente em FALSE, e a obra sumia em silencio - o pior erro possivel
#' numa busca de literatura, porque ninguem fica sabendo que perdeu. Agora ela
#' vai para a fila humana com relevante = NA e o motivo na justificativa.
interpretar_triagem <- function(res, obra_id, modelo, margem = c(0.35, 0.75)) {
  stopifnot(is.data.frame(res), nrow(res) == length(obra_id))
  erro <- if (".error" %in% names(res)) {
    map_chr(res$.error, ~ if (is.null(.x)) NA_character_ else conditionMessage(.x))
  } else rep(NA_character_, nrow(res))
  sem_resposta <- !is.na(erro) | is.na(res$relevante)

  tibble::tibble(
    obra_id = obra_id,
    relevante = if_else(sem_resposta, NA, as.logical(res$relevante)),
    prob = if_else(sem_resposta, NA_real_, as.numeric(res$prob)),
    justificativa = if_else(sem_resposta,
                            paste("sem resposta do agente:", coalesce(erro, "resposta vazia")),
                            as.character(res$justificativa)),
    # prob ausente com resposta presente tambem vai para humano: sem a
    # probabilidade nao ha como saber se esta na margem
    decidido_por = if_else(sem_resposta | coalesce(prob >= margem[1] & prob <= margem[2], TRUE),
                           "fila_humana", paste0("agente:", modelo)),
    data = Sys.time())
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
