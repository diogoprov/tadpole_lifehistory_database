# Lista-alvo = Brazilian Tadpoles 5.0 (The Rossa-Feres Tadpole Database),
# assets/data/species.json. Esquema real (schema_version 5.1.x):
#
#   { schema_version, database_name, source, generated, excluded_families,
#     excluded_count, count, characters: ["ext_morph","internal_oral",
#     "chondrocranium"], ref_schema: ["author","year","title","journal","doi",
#     "raw"],
#     species: [ { id, species, genus, epithet, tip_label, family,
#                  ext_morph:      {status, refs[]},
#                  internal_oral:  {status, refs[]},
#                  chondrocranium: {status, refs[]} } ] }
#
#   status in {"described", "not_described"}
#
# A lista define QUAIS nomes sao buscados. O `id` do proprio arquivo e usado
# como taxon_id: estavel, legivel e ja unico.

library(purrr)
library(dplyr)

CARACTERES <- c("ext_morph", "internal_oral", "chondrocranium")

ler_species_json <- function(url) {
  js <- jsonlite::fromJSON(url, simplifyVector = FALSE)
  if (is.null(js$species)) stop("species.json sem a chave 'species'")
  message("BT ", js$schema_version %||% "?", " | gerado ", js$generated %||% "?",
          " | ", js$count %||% length(js$species), " especies")
  js
}

carregar_lista_alvo <- function(js, apenas_descritos = FALSE) {
  alvo <- map_dfr(js$species, function(s) {
    st <- map_chr(CARACTERES, ~ s[[.x]]$status %||% NA_character_)
    tibble::tibble(
      taxon_id = s$id, especie = s$species, genero = s$genus,
      epiteto = s$epithet, familia = s$family,
      status_ext_morph = st[1], status_internal_oral = st[2],
      status_chondrocranium = st[3],
      girino_descrito = any(st == "described", na.rm = TRUE))
  }) |>
    mutate(fonte_lista = paste0(js$database_name %||% "Brazilian Tadpoles",
                                " v", js$schema_version %||% ""),
           data_lista = as.Date(js$generated %||% Sys.Date()))

  if (apenas_descritos) alvo <- filter(alvo, girino_descrito)
  alvo
}

#' Corpus-semente: as referencias ja catalogadas na BT 5.0, com DOI.
#' Sao artigos que descrevem o girino daquela especie - o melhor ponto de
#' partida possivel, e dispensam a triagem de relevancia.
carregar_referencias <- function(js) {
  map_dfr(js$species, function(s) {
    map_dfr(CARACTERES, function(ch) {
      refs <- s[[ch]]$refs %||% list()
      if (length(refs) == 0) return(tibble::tibble())
      map_dfr(refs, ~ tibble::tibble(
        taxon_id = s$id, carater = ch,
        autor = .x$author %||% NA_character_,
        ano = suppressWarnings(as.integer(.x$year %||% NA)),
        titulo = .x$title %||% NA_character_,
        periodico = .x$journal %||% NA_character_,
        doi = .x$doi %||% NA_character_,
        # url: texto completo fora do DOI (BHL, repositorio), campo opcional
        # da BT 5 desde o PR #31 (03/10/2026)
        url = .x$url %||% NA_character_,
        raw = .x$raw %||% NA_character_))
    })
  })
}

#' Uma linha por referencia, com o obra_id da obra a que ela pertence.
#'
#' Por que (03/10/2026): na BT 5 a mesma obra aparece em varias strings, com
#' DOI em umas e sem em outras, ou com o DOI em caixa diferente
#' ("10.2994/SAJH-D-13-00033.1" e "10.2994/sajh-d-13-00033.1"). Com a chave
#' antiga (doi ou titulo, como veio) cada variacao virava uma obra: 4 obras
#' duplicadas por titulo e 2 por caixa, medidas antes de semear. Agora: mesma
#' obra = mesmo titulo normalizado + ano; se alguma variacao tem DOI, todas
#' herdam; o DOI vai em minusculas (DOI nao diferencia caixa, e a busca ja
#' grava assim: nenhum DOI do banco tinha maiuscula).
agrupar_obras_bt5 <- function(referencias) {
  # tabela lida antes do campo url existir: sem a coluna, `url` seria base::url
  if (!"url" %in% names(referencias)) referencias$url <- NA_character_
  referencias |>
    filter(!is.na(doi) | !is.na(titulo)) |>
    mutate(doi = tolower(na_if(doi, "")),
           k = if_else(is.na(titulo), paste0("doi:", doi), paste(normalizar_titulo(titulo), ano))) |>
    group_by(k) |>
    # sem DOI, a chave e o titulo; um titulo so por grupo, senao
    # "Ranitomeya(Anura" e "Ranitomeya (Anura" viram duas obras
    mutate(doi = first(na.omit(doi)) %||% NA_character_,
           url = first(na.omit(url)) %||% NA_character_,
           titulo_chave = first(tolower(titulo))) |>
    ungroup() |>
    mutate(chave = coalesce(doi, titulo_chave),
           obra_id = map_chr(chave, id_de)) |>
    # DOI repetido com titulos diferentes cai na mesma obra pelo obra_id;
    # o url tambem tem de ser um so por obra
    group_by(obra_id) |>
    mutate(url = first(na.omit(url)) %||% NA_character_) |>
    ungroup() |>
    select(-k, -titulo_chave)
}

#' Semeia obras + triagem a partir das referencias da BT 5.0.
#' Marcadas como relevantes sem passar pelo LLM: sao descricoes de girino da
#' especie, por construcao. Obra que ja existe no banco (achada pela busca,
#' com PDF) nao e sobrescrita: ganha o vinculo com a especie e o que estava
#' vazio (registrar_obras(), em R/db.R), e a triagem dela fica como estava.
semear_corpus <- function(con, referencias) {
  com_id <- agrupar_obras_bt5(referencias)

  # Idem executar_busca(): o vinculo sai antes do distinct. Aqui ele importa
  # ainda mais, porque uma referencia da BT 5.0 costuma cobrir varias especies.
  registrar_novos(con, "obra_taxon",
                  distinct(com_id, obra_id, taxon_id) |> mutate(fonte = "bt5_refs"))

  obras <- com_id |>
    distinct(obra_id, .keep_all = TRUE) |>
    transmute(obra_id, doi, titulo, ano,
              idioma = NA_character_, fonte = "bt5_refs",
              url_pdf = NA_character_, url_suplementar = NA_character_,
              caminho_pdf = NA_character_, ocr = FALSE, status = "encontrada",
              url_pagina = url)

  registrar_obras(con, obras)
  registrar_novos(con, "triagem", transmute(obras, obra_id, relevante = TRUE,
                                            prob = 1, justificativa = "referencia da BT 5.0",
                                            decidido_por = "semente_bt5", data = Sys.time()))
  nrow(obras)
}


carregar_traits <- function(caminho) {
  tr <- readr::read_csv(caminho, show_col_types = FALSE)
  obrig <- c("trait_id", "nome", "tipo", "unidade", "termos_busca")
  if (!all(obrig %in% names(tr))) {
    stop("traits.csv precisa das colunas: ", paste(obrig, collapse = ", "))
  }
  if (!all(tr$tipo %in% c("categorico", "numerico"))) {
    stop("coluna 'tipo' so aceita 'categorico' ou 'numerico'")
  }
  tr
}

#' Semeia estado_par com todos os pares especie x trait como 'nao_buscado'.
#' E o que sustenta o item 10: a ausencia passa a ser um estado registrado.
semear_estado_par <- function(con, alvo, traits) {
  pares <- tidyr::expand_grid(taxon_id = alvo$taxon_id, trait_id = traits$trait_id) |>
    mutate(estado = "nao_buscado", data_atualizacao = Sys.time())
  ja <- dbGetQuery(con, "SELECT taxon_id, trait_id FROM estado_par")
  novos <- anti_join(pares, ja, by = c("taxon_id", "trait_id"))
  registrar(con, "estado_par", novos)
  nrow(novos)
}

atualizar_estado_par <- function(con, taxon_id, trait_id, estado) {
  registrar(con, "estado_par", tibble::tibble(
    taxon_id = taxon_id, trait_id = trait_id,
    estado = estado, data_atualizacao = Sys.time()))
}

`%||%` <- function(x, y) if (is.null(x)) y else x
