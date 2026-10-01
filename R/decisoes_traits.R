# Aplica ao inst/traits.csv as decisoes que vieram do grupo, uma funcao por
# rodada de respostas. Fica separado do esqueleto de proposito: o esqueleto e
# gerado a partir dos dados e pode ser refeito a qualquer momento; as decisoes
# sao humanas e precisam de registro de quem decidiu e quando.
#
# Uso:
#   source("R/decisoes_traits.R")
#   decisoes_denise_2026_09_22("inst/traits.csv")

library(dplyr)
library(stringr)

decisoes_denise_2026_09_22 <- function(caminho = "inst/traits.csv") {
  t <- readr::read_csv(caminho, show_col_types = FALSE)
  antes <- t

  t <- t |> mutate(
    # "Para os caracteres morfologicos, o estagio de desenvolvimento esta
    # indicado na coluna K (DevelopmentalStage) da aba Morphology."
    # Sistema de estagiamento confirmado por Denise em 22/09/2026: Gosner.
    estagio_ref = if_else(origem == "planilha:Morphology",
      "por registro: coluna DevelopmentalStages (Gosner)", estagio_ref),

    # "E para os caracteres de ecologia, os artigos nao informam o estagio de
    # desenvolvimento, porque nao faz sentido."
    estagio_ref = if_else(origem == "planilha:Habitat",
      "nao se aplica (caractere de ecologia)", estagio_ref),

    # "O valor minimo e maximo para dieta e 0 e 100% (o quantitativo dos itens
    # sao proporcoes)."
    min_plausivel = if_else(trait_id == "dieta_composicao", 0, min_plausivel),
    max_plausivel = if_else(trait_id == "dieta_composicao", 100, max_plausivel),
    unidade = if_else(trait_id == "dieta_composicao", "%", unidade),
    # "Vou buscar nos artigos se informam o estagio de desenvolvimento" - aberto
    estagio_ref = if_else(trait_id == "dieta_composicao",
      "a confirmar: Denise verificando nos artigos", estagio_ref),

    # Profundidade: o limite nao e biologico, e uma trava contra erro de
    # digitacao. Observado na base: 0,1 a 2,0 m em 210 registros. Teto de 5 m
    # proposto, pendente de confirmacao.
    min_plausivel = if_else(trait_id == "maximumDephInMeters", 0, min_plausivel),
    max_plausivel = if_else(trait_id == "maximumDephInMeters", 5, max_plausivel))

  mudou <- sum(map_lgl_linhas(antes, t))
  readr::write_csv(t, caminho, na = "")
  list(caminho = caminho, linhas_alteradas = mudou)
}

map_lgl_linhas <- function(a, b) {
  purrr::map_lgl(seq_len(nrow(a)), function(i) {
    !identical(as.character(unlist(a[i, ])), as.character(unlist(b[i, ])))
  })
}

#' Segunda rodada de respostas, na planilha que a Denise devolveu em 29/09/2026.
#' Ela foi aos artigos e preencheu DevelopmentalStage na aba Diet_DWC.
decisoes_denise_2026_09_29 <- function(caminho = "inst/traits.csv") {
  t <- readr::read_csv(caminho, show_col_types = FALSE)
  t <- t |> mutate(estagio_ref = if_else(trait_id == "dieta_composicao",
    "35-38 (Gosner), unico valor para toda a aba", estagio_ref))
  readr::write_csv(t, caminho, na = "")
  invisible(caminho)
}

#' Terceira rodada: respostas da Denise de 30/09/2026 sobre o vocabulario do
#' piloto. Fecha os caracteres cujo vocabulario nao tem mais pendencia e grava
#' os termos de busca. status = "fechado" e o que libera o trait para extracao
#' (ver a trava em tipo_valor(), R/agentes.R).
decisoes_denise_2026_09_30 <- function(caminho = "inst/traits.csv") {
  t <- readr::read_csv(caminho, show_col_types = FALSE)

  fechados <- list(
    eyes_positioning = "dorsal;lateral;dorsolateral",
    snout_shape_lv = paste("rounded", "truncated", "sloped", "pointed",
                           "bipartite with tapered projections",
                           "rounded or sloped", "rounded or truncated",
                           "sloped to truncated", sep = ";"))
  for (id in names(fechados)) {
    t$valores_aceitos[t$trait_id == id] <- fechados[[id]]
    t$status[t$trait_id == id] <- "fechado"
  }

  termos <- c(
    eyes_positioning = "olhos;olho;eyes;eye;ojos;ojo",
    cloacal_opening = paste("tubo cloacal;abertura cloacal;tubo anal",
      "vent tube;cloacal tube;cloacal opening;vent", "tubo cloacal;abertura cloacal", sep = ";"),
    lower_jaw_shape = paste("bico corneo inferior;bainha mandibular inferior;mandibula inferior",
      "lower jaw sheath;lower jaw", "pico corneo inferior;vaina mandibular inferior", sep = ";"),
    snout_shape_lv = paste("focinho em vista lateral;focinho, vista lateral;focinho",
      "snout in lateral view;snout", "hocico en vista lateral;hocico", sep = ";"),
    maximumDephInMeters = "profundidade;profundidade maxima;depth;maximum depth;profundidad")
  for (id in names(termos)) t$termos_busca[t$trait_id == id] <- termos[[id]]

  # "5 m me parece muito, talvez 3 m?" - observado na base: 0,1 a 2,0 m
  t$max_plausivel[t$trait_id == "maximumDephInMeters"] <- 3

  readr::write_csv(t, caminho, na = "")
  invisible(caminho)
}
