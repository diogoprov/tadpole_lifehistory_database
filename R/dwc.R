# Saida em Darwin Core: Taxon core + extensao MeasurementOrFact.
#
# RESSALVA: a extensao MeasurementOrFact foi desenhada para occurrence/event.
# Usa-la sobre um Taxon core e uma escolha pragmatica, comum em bases de traits
# em nivel de especie, mas nao e um padrao consolidado - confirmem com o
# administrador do IPT antes de publicar.

library(dplyr)

escrever_dwc <- function(con, dir_saida, traits) {
  dir.create(dir_saida, showWarnings = FALSE, recursive = TRUE)

  taxon <- dbGetQuery(con, "
    SELECT taxon_id AS taxonID, especie AS scientificName, familia AS family
      FROM alvo") |>
    mutate(kingdom = "Animalia", phylum = "Chordata", class = "Amphibia",
           order = "Anura", taxonRank = "species",
           nameAccordingTo = "Brazilian Tadpoles 5.0 (Rossa-Feres Tadpole Database)")

  mof <- dbGetQuery(con, "
    SELECT e.extracao_id, e.taxon_id, e.trait_id, e.valor_num, e.valor_cat,
           e.unidade, e.estagio, e.temperatura_c, e.ambiente, e.n, e.dispersao,
           e.span_verbatim, e.confianca, e.extrator, e.modelo_versao,
           e.prompt_versao, e.origem_valor, e.fonte_primaria_doi, e.pagina,
           e.nome_no_artigo, e.data, o.doi, o.ano
      FROM extracoes e JOIN obras o USING (obra_id)
     WHERE e.status = 'aprovado'") |>
    left_join(select(traits, trait_id, nome, tipo), by = "trait_id") |>
    transmute(
      measurementID = extracao_id,
      taxonID = taxon_id,
      measurementType = nome,
      measurementTypeID = trait_id,
      measurementValue = coalesce(valor_cat, as.character(valor_num)),
      measurementUnit = unidade,
      measurementAccuracy = dispersao,
      measurementDeterminedDate = format(data, "%Y-%m-%d"),
      measurementDeterminedBy = paste0(extrator, ifelse(is.na(modelo_versao), "",
                                       paste0(" (", modelo_versao, "; prompt ", prompt_versao, ")"))),
      measurementMethod = paste0("extracao assistida de literatura; origem do valor: ",
                                 origem_valor),
      # o contexto da medida (item 7) e a proveniencia (item 3) viajam aqui:
      measurementRemarks = paste0(
        "estagio=", coalesce(estagio, "NA"),
        "; temperatura_C=", coalesce(as.character(temperatura_c), "NA"),
        "; ambiente=", coalesce(ambiente, "NA"),
        "; n=", coalesce(as.character(n), "NA"),
        "; nome_no_artigo=", coalesce(nome_no_artigo, "NA"),
        "; confianca=", round(confianca, 3),
        "; fonte=", coalesce(doi, "NA"), " p.", coalesce(as.character(pagina), "NA"),
        "; fonte_primaria=", coalesce(fonte_primaria_doi, doi, "NA"),
        "; verbatim=\"", gsub('"', "'", span_verbatim), "\""))

  readr::write_tsv(taxon, file.path(dir_saida, "taxon.txt"), na = "")
  readr::write_tsv(mof, file.path(dir_saida, "measurementorfact.txt"), na = "")

  # Item 10: o que foi procurado e nao existe sai junto com os dados. Sem este
  # arquivo o usuario da base nao sabe distinguir ausencia de dado de ausencia
  # de busca, e toda analise de cobertura fica errada.
  lacunas <- dbGetQuery(con, "
    SELECT a.especie, p.trait_id, p.estado, p.data_atualizacao
      FROM estado_par p JOIN alvo a USING (taxon_id)
     WHERE p.estado IN ('nao_buscado','buscado_sem_dado')")
  readr::write_tsv(lacunas, file.path(dir_saida, "lacunas.txt"), na = "")

  list(taxon = nrow(taxon), medidas = nrow(mof), lacunas = nrow(lacunas))
}

#' Metricas do data paper: desempenho por trait e cobertura.
relatorio_metricas <- function(con, traits, caminho) {
  lim <- dbGetQuery(con, "SELECT * FROM limiares")
  conc <- concordancia_ouro(con, traits)
  cob <- cobertura(con)
  rel <- list(limiares = lim, concordancia_ouro = conc,
              cobertura = summary(cob$traits_com_dado),
              gerado_em = Sys.time())
  saveRDS(rel, caminho)
  rel
}
