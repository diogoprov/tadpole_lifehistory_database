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
#'
#' O arquivo identifica a especie pelo nome aceito, nao pelo taxon_id: o
#' piloto usa o taxonID da planilha ("Anura152") e o pipeline o id do
#' species.json ("boana_raniceps"), e uma linha escrita num formato nao
#' casaria no outro. O taxon_id sai de `alvo`; linha de especie fora da
#' lista-alvo nao entra.
#'
#' doi_obra preenchido = sinonimo que vale so naquela obra (01/10/2026). Caso:
#' em Rossa-Feres & Nomura (2006), "Pseudis paradoxa" e P. platensis e
#' "Elachistocleis sp." e E. cesarii; como sinonimos globais, levariam para
#' essas especies o dado de P. paradoxa (valida) e de qualquer Elachistocleis
#' sem nome em outras obras.
carregar_sinonimos_curados <- function(caminho, alvo) {
  vazio <- tibble::tibble(taxon_id = character(), nome_alternativo = character(),
                          fonte = character(), doi_obra = character())
  if (!file.exists(caminho)) return(vazio)
  s <- readr::read_csv(caminho, comment = "#", show_col_types = FALSE,
                       col_types = readr::cols(.default = "c"))
  if (!all(c("especie", "nome_alternativo") %in% names(s))) {
    stop(caminho, " precisa das colunas especie e nome_alternativo", call. = FALSE)
  }
  if (!"doi_obra" %in% names(s)) s$doi_obra <- NA_character_
  if (!"fonte" %in% names(s)) s$fonte <- NA_character_
  s |>
    inner_join(distinct(alvo, taxon_id, especie), by = "especie") |>
    transmute(taxon_id, nome_alternativo, fonte = coalesce(fonte, "curado"),
              doi_obra = na_if(tolower(stringr::str_squish(doi_obra)), ""))
}

# ---- sinonimia empacotada no AmphiNom -----------------------------------------

#' Sinonimos da lista-alvo a partir das tabelas que o AmphiNom ja traz
#' (asw_synonyms, asw_taxonomy), sem varrer o site da ASW. Decisao do Diogo
#' (01/10/2026). Medido no piloto zero: com o nome atual, 105 de 138 especies
#' apareciam no texto da propria obra; com estes sinonimos, 133.
#'
#' Dois cuidados, ambos vistos no piloto:
#' - grafia: a planilha usa "Ololygon flavoguttata" e a ASW "Ololygon
#'   flavoguttatus" (concordancia de genero). O nome e casado pelo radical do
#'   epiteto dentro do mesmo genero, e o nome da ASW tambem vira sinonimo.
#' - trinomio: "Leptodactylus ocellatus var. bonairensis" e sinonimo de
#'   L. luctator, mas padrao_especie() abrevia pelas duas primeiras palavras e
#'   casaria qualquer "L. ocellatus" - binomio que a ASW lista sob outra
#'   especie (L. bolivianus). Trinomio cujo binomio nao e nome nem sinonimo da
#'   propria especie vai para `revisar`, nao entra. Idem para sinonimo cujo
#'   binomio e especie valida diferente, e para sinonimo listado sob mais de
#'   uma especie da lista-alvo: os tres atribuiriam dado de uma especie a outra.
#'
#' Devolve list(sinonimos = (taxon_id, nome_alternativo, fonte),
#'              revisar = (taxon_id, especie, nome_alternativo, motivo)).
#' `syn` e `tax` existem para o teste; o padrao sao as tabelas do pacote.
sinonimos_amphinom <- function(alvo, syn = NULL, tax = NULL) {
  if (is.null(syn) || is.null(tax)) {
    if (!requireNamespace("AmphiNom", quietly = TRUE)) {
      stop("instale AmphiNom: remotes::install_github('hcliedtke/AmphiNom')", call. = FALSE)
    }
    e <- new.env()
    utils::data("asw_synonyms", "asw_taxonomy", package = "AmphiNom", envir = e)
    syn <- e$asw_synonyms; tax <- e$asw_taxonomy
  }
  fonte <- paste0("ASW via AmphiNom ", tryCatch(as.character(utils::packageVersion("AmphiNom")),
                                               error = function(e) "?"))
  radical <- function(x) {
    p <- stringr::str_split_fixed(x, " ", 3)
    paste(p[, 1], stringr::str_remove(p[, 2], "(us|a|um|is|e)$"))
  }
  validas <- unique(tax$species)

  # nome da planilha -> nome da ASW (exato, ou pela grafia)
  casa <- alvo |>
    distinct(taxon_id, especie) |>
    mutate(nome_asw = map_chr(especie, function(e) {
      if (e %in% validas) return(e)
      cand <- validas[radical(validas) == radical(e)]
      if (length(cand) == 1) cand else NA_character_
    }))

  todos <- casa |>
    filter(!is.na(nome_asw)) |>
    inner_join(rename(as_tibble(syn), nome_asw = species, nome_alternativo = synonyms),
               by = "nome_asw", relationship = "many-to-many") |>
    bind_rows(transmute(filter(casa, !is.na(nome_asw), nome_asw != especie),
                        taxon_id, especie, nome_asw, nome_alternativo = nome_asw)) |>
    filter(!is.na(nome_alternativo), nome_alternativo != especie) |>
    distinct(taxon_id, especie, nome_alternativo) |>
    mutate(binomio = stringr::word(nome_alternativo, 1, 2))

  repetidos <- todos |> count(nome_alternativo) |> filter(n > 1)
  # binomios que sao de fato desta especie: o nome, o nome na ASW e os
  # sinonimos de duas palavras
  proprios <- bind_rows(transmute(casa, taxon_id, b = especie), transmute(casa, taxon_id, b = nome_asw),
                        transmute(filter(todos, stringr::str_count(nome_alternativo, " ") == 1), taxon_id, b = nome_alternativo))
  todos <- todos |>
    mutate(
      nome_asw = casa$nome_asw[match(taxon_id, casa$taxon_id)],
      proprio = map2_lgl(taxon_id, binomio, ~ .y %in% proprios$b[proprios$taxon_id == .x]),
      motivo = case_when(
        binomio %in% validas & binomio != especie & binomio != coalesce(nome_asw, "") ~
          paste0("binomio '", binomio, "' e especie valida na ASW"),
        stringr::str_count(nome_alternativo, " ") >= 2 & !proprio ~
          paste0("trinomio: a abreviacao casaria '", binomio, "', que nao e sinonimo desta especie"),
        nome_alternativo %in% repetidos$nome_alternativo ~ "sinonimo de mais de uma especie da lista",
        TRUE ~ NA_character_))

  revisar <- bind_rows(
    filter(todos, !is.na(motivo)) |> select(taxon_id, especie, nome_alternativo, motivo),
    filter(casa, is.na(nome_asw)) |>
      transmute(taxon_id, especie, nome_alternativo = NA_character_, motivo = "nome nao achado na ASW"))
  list(sinonimos = filter(todos, is.na(motivo)) |>
         transmute(taxon_id, nome_alternativo, fonte = fonte, doi_obra = NA_character_),
       revisar = revisar)
}

#' Sinonimos do pipeline: os do AmphiNom (sinonimos_amphinom()) mais os
#' curados, gravados no banco SO os que ainda nao estao la (a tabela nao tem
#' chave primaria, e registrar() so acrescenta). Os ambiguos vao para
#' `revisar_csv`, para revisao humana. Devolve os sinonimos novos.
#'
#' Por que (04/10/2026): o _targets.R so lia um cache da ASW
#' (inst/asw_cache.rds) que nunca foi gerado, e o banco principal ficou com 2
#' sinonimos (os do teste de fumaca) contra 347 no piloto. As duas extracoes do
#' corpus da BT 5 rodaram sem sinonimos; carregados, os pares sem candidato
#' cairam de 111 para 75.
carregar_sinonimos <- function(con, alvo, curados = "inst/sinonimos.csv",
                               revisar_csv = "revisao/sinonimos_revisar.csv") {
  asw <- sinonimos_amphinom(alvo)
  if (!is.null(revisar_csv) && nrow(asw$revisar)) {
    dir.create(dirname(revisar_csv), showWarnings = FALSE, recursive = TRUE)
    readr::write_excel_csv2(asw$revisar, revisar_csv)
  }
  sin <- bind_rows(carregar_sinonimos_curados(curados, alvo), asw$sinonimos) |>
    distinct(taxon_id, nome_alternativo, .keep_all = TRUE)
  novos <- sinonimos_novos(sin, dbGetQuery(con, "SELECT taxon_id, nome_alternativo FROM sinonimos"))
  registrar(con, "sinonimos", novos)
  novos
}

#' Os sinonimos que ainda nao estao no banco (mesmo taxon e mesmo nome). Pura.
sinonimos_novos <- function(sin, existentes) {
  anti_join(sin, existentes, by = c("taxon_id", "nome_alternativo"))
}
