# Sinonimia via Amphibian Species of the World (ASW), com o pacote AmphiNom
# (Liedtke 2019, Systematics and Biodiversity, doi:10.1080/14772000.2018.1518935).
#
# A ASW entra APENAS para descobrir sob que outros nomes cada especie da
# lista-alvo aparece na literatura. Quem define o conjunto de especies e o
# nome aceito continua sendo a Brazilian Tadpoles 5.0.
#
# getTaxonomy() varre o site da ASW e leva 10-15 min; getSynonyms() e ainda
# mais lento. Por isso o resultado e cacheado em disco e so e refeito quando
# o grupo quiser atualizar.

library(purrr)
library(dplyr)

#' Baixa taxonomia + sinonimos da ASW para os generos presentes na lista-alvo.
#' Roda uma vez por atualizacao da ASW; depois todo mundo le o cache.
atualizar_cache_asw <- function(alvo, cache = "inst/asw_cache.rds") {
  if (!requireNamespace("AmphiNom", quietly = TRUE)) {
    stop("instale AmphiNom: remotes::install_github('hcliedtke/AmphiNom')")
  }
  taxonomia <- AmphiNom::getTaxonomy()
  generos <- sort(unique(alvo$genero))
  sinonimos <- map_dfr(generos, function(g) {
    out <- tryCatch(AmphiNom::getSynonyms(Genus = g), error = function(e) NULL)
    if (is.null(out)) {
      warning("ASW sem resposta para o genero ", g); return(tibble::tibble())
    }
    as_tibble(out)
  })
  saveRDS(list(taxonomia = taxonomia, sinonimos = sinonimos, data = Sys.Date()), cache)
  message("cache ASW: ", nrow(sinonimos), " linhas de sinonimia, ",
          length(generos), " generos")
  cache
}

#' Alinha os nomes da lista-alvo com a ASW e devolve a tabela de sinonimos
#' no formato (taxon_id, nome_alternativo, fonte).
#'
#' aswSync() classifica cada consulta (nome atual, sinonimo, ambiguo, ausente);
#' synonymReport() resume o resultado. O que ficar ambiguo ou ausente NAO entra
#' na tabela: vai para revisao humana, porque um casamento errado aqui atribui
#' dado de uma especie a outra.
sincronizar_sinonimos <- function(alvo, cache = "inst/asw_cache.rds",
                                  relatorio = "revisao/asw_ambiguos.csv") {
  if (!file.exists(cache)) stop("rode atualizar_cache_asw() antes")
  asw <- readRDS(cache)

  # aswSync classifica cada nome da lista-alvo contra a ASW; synonymReport
  # resume. Guarde o csv e olhe os ambiguos antes de confiar no casamento.
  res <- as_tibble(AmphiNom::aswSync(query = alvo$especie, asw = asw$sinonimos))
  print(AmphiNom::synonymReport(res))
  dir.create(dirname(relatorio), showWarnings = FALSE, recursive = TRUE)
  readr::write_csv(res, relatorio)

  # Tabela de sinonimos. Os nomes de coluna de getSynonyms() variam entre
  # versoes do AmphiNom: confira uma vez com names(asw$sinonimos) e ajuste
  # col_aceito/col_sinonimo se o stop() abaixo disparar.
  s <- rename_with(as_tibble(asw$sinonimos), tolower)
  col_aceito <- "species"; col_sinonimo <- "synonym"
  if (!all(c(col_aceito, col_sinonimo) %in% names(s))) {
    stop("colunas de getSynonyms() diferentes do esperado: ",
         paste(names(s), collapse = ", "))
  }

  s |>
    inner_join(select(alvo, taxon_id, especie),
               by = setNames("especie", col_aceito)) |>
    transmute(taxon_id, nome_alternativo = .data[[col_sinonimo]], fonte = "ASW") |>
    filter(!is.na(nome_alternativo), nome_alternativo != "") |>
    distinct()
}

#' Sinonimos curados a mao pelo grupo, somados aos da ASW.
carregar_sinonimos_curados <- function(caminho) {
  if (!file.exists(caminho)) {
    return(tibble::tibble(taxon_id = character(), nome_alternativo = character(),
                          fonte = character()))
  }
  readr::read_csv(caminho, comment = "#", show_col_types = FALSE)
}
