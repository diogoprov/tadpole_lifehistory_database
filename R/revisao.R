# Conjunto-ouro com dupla extracao cega (item 5), fila de revisao humana e
# realimentacao do treino (item 14).

library(purrr)
library(dplyr)

# ---- conjunto-ouro ----------------------------------------------------------

#' Sorteia obras e gera UMA planilha por revisor, sem valor nenhum preenchido.
#' Cega de verdade: o revisor nao ve a extracao do modelo nem a do colega.
preparar_ouro <- function(con, revisores, fracao, dir_saida, semente = 1) {
  set.seed(semente)
  obras <- dbGetQuery(con, "
    SELECT DISTINCT obra_id FROM trechos
     WHERE obra_id NOT IN (SELECT DISTINCT obra_id FROM ouro)")$obra_id
  if (length(obras) == 0) return(0L)
  sel <- sample(obras, max(1, floor(length(obras) * fracao)))

  base <- dbGetQuery(con, sprintf("
    SELECT DISTINCT e.obra_id, o.doi, o.titulo, a.taxon_id, a.especie
      FROM extracoes e JOIN obras o USING (obra_id) JOIN alvo a USING (taxon_id)
     WHERE e.obra_id IN ('%s')", paste(sel, collapse = "','")))

  traits <- dbGetQuery(con, "SELECT trait_id, nome, unidade FROM traits")
  planilha <- tidyr::expand_grid(base, traits) |>
    mutate(valor = "", unidade_medida = "", span_verbatim = "", observacao = "")

  dir.create(dir_saida, showWarnings = FALSE, recursive = TRUE)
  walk(revisores, ~ readr::write_csv(
    planilha, file.path(dir_saida, paste0("ouro_", .x, ".csv"))))
  length(sel)
}

importar_ouro <- function(con, caminho, revisor) {
  d <- readr::read_csv(caminho, show_col_types = FALSE) |>
    filter(!is.na(valor), valor != "") |>
    transmute(obra_id, taxon_id, trait_id, revisor = revisor,
              valor = as.character(valor), unidade = unidade_medida,
              span_verbatim, data = Sys.time())
  registrar(con, "ouro", d)
  nrow(d)
}

#' Concordancia entre os dois extratores humanos. Divergencia alta num trait
#' significa definicao ambigua - o problema esta na definicao, nao no modelo.
concordancia_ouro <- function(con, traits) {
  o <- dbGetQuery(con, "SELECT obra_id, taxon_id, trait_id, revisor, valor FROM ouro")
  o |>
    left_join(select(traits, trait_id, tipo), by = "trait_id") |>
    group_by(obra_id, taxon_id, trait_id, tipo) |>
    filter(n() == 2) |>
    summarise(concorda = if (first(tipo) == "categorico") {
        tolower(valor[1]) == tolower(valor[2])
      } else {
        v <- suppressWarnings(as.numeric(valor))
        abs(diff(v)) <= 0.05 * mean(abs(v))
      }, .groups = "drop") |>
    group_by(trait_id) |>
    summarise(n = n(), concordancia = mean(concorda, na.rm = TRUE))
}

# ---- fila de revisao --------------------------------------------------------

#' 100% do que ficou abaixo do limiar + amostra do que passou (auditoria).
amostrar_para_revisao <- function(con, fracao_auditoria, semente = 1) {
  set.seed(semente)
  # abaixo do limiar, sem limiar ainda, ou trait em revisao integral
  abaixo <- dbGetQuery(con, "
    SELECT e.* FROM extracoes e LEFT JOIN limiares l USING (trait_id)
     WHERE e.status = 'bruto'
       AND (l.limiar IS NULL OR e.confianca < l.limiar
            OR l.decisao = 'revisao_integral')")
  acima <- dbGetQuery(con, "SELECT * FROM extracoes WHERE status = 'aprovado'")
  auditoria <- if (nrow(acima)) slice_sample(acima, prop = fracao_auditoria) else acima
  bind_rows(mutate(abaixo, fila = "abaixo_do_limiar"),
            mutate(auditoria, fila = "auditoria"))
}

exportar_revisao <- function(con, caminho, fracao_auditoria) {
  d <- amostrar_para_revisao(con, fracao_auditoria) |>
    select(extracao_id, fila, taxon_id, trait_id, valor_num, valor_cat, unidade,
           estagio, temperatura_c, ambiente, n, dispersao, confianca,
           extrator, span_verbatim)
  d$veredito <- ""          # ok / errado / ambiguo
  d$valor_corrigido <- ""
  readr::write_csv(d, caminho)
  nrow(d)
}

importar_revisao <- function(con, caminho, revisor) {
  d <- readr::read_csv(caminho, show_col_types = FALSE) |>
    filter(veredito %in% c("ok", "errado", "ambiguo")) |>
    transmute(extracao_id, revisor = revisor, veredito,
              valor_corrigido = as.character(valor_corrigido),
              comentario = NA_character_, data = Sys.time())
  registrar(con, "revisao", d)
  dbExecute(con, "
    UPDATE extracoes SET status = CASE r.veredito
        WHEN 'ok' THEN 'aprovado' WHEN 'errado' THEN 'rejeitado' ELSE 'bruto' END,
        motivo_rejeicao = CASE WHEN r.veredito = 'errado' THEN 'revisao_humana' ELSE motivo_rejeicao END
      FROM revisao r WHERE extracoes.extracao_id = r.extracao_id")
  nrow(d)
}

# ---- aprendizado ativo (item 14) -------------------------------------------

#' Tudo que passou por revisor vira dado rotulado para o proximo treino do
#' encoder local: o que o modelo erra hoje e o que ele aprende na proxima volta.
exportar_treino <- function(con, caminho) {
  d <- dbGetQuery(con, "
    SELECT t.texto, e.trait_id,
           COALESCE(NULLIF(r.valor_corrigido,''), e.valor_cat, CAST(e.valor_num AS VARCHAR)) AS rotulo,
           r.veredito
      FROM revisao r JOIN extracoes e USING (extracao_id) JOIN trechos t USING (trecho_id)
     WHERE r.veredito IN ('ok','errado')")
  readr::write_csv(d, caminho)
  nrow(d)
}

#' Cobertura por especie: entra no data paper e define a proxima rodada.
cobertura <- function(con) {
  dbGetQuery(con, "
    SELECT a.especie,
           sum(CASE WHEN p.estado IN ('extraido','revisado') THEN 1 ELSE 0 END) AS traits_com_dado,
           count(*) AS traits_alvo
      FROM alvo a JOIN estado_par p USING (taxon_id)
     GROUP BY 1 ORDER BY traits_com_dado ASC") |> as_tibble()
}
