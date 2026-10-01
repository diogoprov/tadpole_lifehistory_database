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
        raw = .x$raw %||% NA_character_))
    })
  })
}

#' Semeia obras + triagem a partir das referencias da BT 5.0.
#' Marcadas como relevantes sem passar pelo LLM: sao descricoes de girino da
#' especie, por construcao.
semear_corpus <- function(con, referencias) {
  com_id <- referencias |>
    filter(!is.na(doi) | !is.na(titulo)) |>
    mutate(chave = coalesce(doi, tolower(titulo)),
           obra_id = map_chr(chave, id_de))

  # Idem executar_busca(): o vinculo sai antes do distinct. Aqui ele importa
  # ainda mais, porque uma referencia da BT 5.0 costuma cobrir varias especies.
  registrar(con, "obra_taxon",
            distinct(com_id, obra_id, taxon_id) |> mutate(fonte = "bt5_refs"))

  obras <- com_id |>
    distinct(obra_id, .keep_all = TRUE) |>
    transmute(obra_id, doi, titulo, ano,
              idioma = NA_character_, fonte = "bt5_refs",
              url_pdf = NA_character_, url_suplementar = NA_character_,
              caminho_pdf = NA_character_, ocr = FALSE, status = "encontrada")

  registrar(con, "obras", obras)
  registrar(con, "triagem", transmute(obras, obra_id, relevante = TRUE,
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
