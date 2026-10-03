# Planilha para o grupo definir o vocabulario dos traits ainda abertos.
#
# 03/10/2026: so 2 dos 48 traits tem vocabulario fechado (eyes_positioning,
# snout_shape_lv). Os 36 categoricos da planilha do livro acumulam 801
# valores distintos (erros de digitacao, sinonimos, "X or Y"), e a extracao so
# roda em trait fechado (trava em tipo_valor(), R/agentes.R). A planilha mostra
# o que existe hoje e deixa em amarelo o que o grupo decide; nenhum
# agrupamento de valores e sugerido aqui, porque juntar sinonimos e decisao
# cientifica.
#
# Uso:
#   source("R/carregar.R"); carregar_projeto()
#   planilha_vocabulario("inst/traits.csv", "dwca/measurementorfact.txt", "dwca/taxon.txt",
#                        "Claude outputs/vocabulario/vocabulario_traits_para_grupo.xlsx")

library(dplyr)
library(purrr)
library(stringr)

DECISAO_TRAIT <- c("fechar", "discutir na reuniao", "fora do escopo")

#' Valores observados por trait na base do livro: um por linha, com o numero
#' de registros e ate 3 especies de exemplo. Registro com dois estados vem
#' separado por "|" na migracao e conta para cada um. Os itens alimentares
#' ("diet_item:X") sao os valores de dieta_composicao.
valores_observados <- function(mof, taxon) {
  mof |>
    mutate(item = str_match(measurementType, "^diet_item:(.*)$")[, 2],
           trait_id = if_else(is.na(item), measurementType, "dieta_composicao"),
           measurementValue = if_else(is.na(item), measurementValue, item)) |>
    tidyr::separate_rows(measurementValue, sep = "[|]") |>
    mutate(valor = str_squish(measurementValue)) |>
    filter(!is.na(valor), valor != "") |>
    left_join(select(taxon, taxonID, scientificName), by = "taxonID") |>
    group_by(trait_id, valor) |>
    summarise(n_registros = n(),
              exemplos = paste(head(unique(scientificName), 3), collapse = "; "),
              .groups = "drop") |>
    arrange(trait_id, desc(n_registros), valor)
}

planilha_vocabulario <- function(traits_csv, mof_txt, taxon_txt, saida) {
  if (file.exists(saida)) stop(saida, " ja existe; a planilha enviada nao e sobrescrita", call. = FALSE)
  le <- function(f) readr::read_tsv(f, col_types = readr::cols(.default = "c"))
  todos <- readr::read_csv(traits_csv, show_col_types = FALSE)
  traits <- filter(todos, status != "fechado")
  vals <- valores_observados(le(mof_txt), le(taxon_txt)) |>
    semi_join(filter(traits, tipo == "categorico" | trait_id == "dieta_composicao"), by = "trait_id")
  # pre-preenchimento (Diogo, 03/10/2026): o grupo edita a partir do que ja
  # existe em vez de digitar do zero. Nada fecha sem decisao = "fechar".
  lista_obs <- vals |> group_by(trait_id) |>
    summarise(lista = paste(valor, collapse = ";"), .groups = "drop")

  # categoricos da planilha primeiro, do menor vocabulario para o maior (os
  # faceis fecham primeiro); depois os numericos; por ultimo os que nao tem dado
  aba_traits <- traits |>
    left_join(count(vals, trait_id, name = "n_valores_distintos"), by = "trait_id") |>
    mutate(grupo = case_when(origem == "a_definir" ~ 3, tipo == "numerico" ~ 2, TRUE ~ 1),
           observacao = case_when(
             trait_id == "tooth_row_formulae" ~ "Formula com gramatica (2(2)/3): sugiro validar por padrao, nao por lista.",
             trait_id %in% c("cloacal_opening", "lower_jaw_shape") ~ "Ha 4 pendencias do piloto em pendencias_vocabulario_v2.xlsx.",
             trait_id == "dieta_composicao" ~ "Valor numerico (%) sobre uma categoria (o item alimentar): o vocabulario e a lista de itens.",
             origem == "a_definir" ~ "Trait novo, sem dado na planilha do livro: definicao e unidade do zero.",
             TRUE ~ "")) |>
    arrange(grupo, n_valores_distintos, trait_id) |>
    left_join(lista_obs, by = "trait_id") |>
    transmute(trait_id, tipo, origem, n_registros, n_valores_distintos,
              definicao_atual = definicao, unidade_atual = unidade, estagio_ref,
              min_atual = min_plausivel, max_atual = max_plausivel, observacao,
              definicao = coalesce(definicao, ""), unidade = coalesce(unidade, ""),
              min_plausivel = as.character(coalesce(min_plausivel, NA)),
              max_plausivel = as.character(coalesce(max_plausivel, NA)),
              valores_aceitos = coalesce(lista, ""), termos_busca = coalesce(termos_busca, ""),
              regra_extracao = coalesce(regra_extracao, ""), decisao = "", nota = "")
  # os 2 traits ja fechados no topo, como exemplo de linha pronta
  exemplos <- filter(todos, status == "fechado") |>
    transmute(trait_id, tipo, origem, n_registros, n_valores_distintos = NA_integer_,
              definicao_atual = definicao, unidade_atual = unidade, estagio_ref,
              min_atual = min_plausivel, max_atual = max_plausivel,
              observacao = "EXEMPLO: trait ja fechado, para mostrar como fica uma linha pronta. Nao precisa mexer.",
              definicao = coalesce(definicao, ""), unidade = coalesce(unidade, ""),
              min_plausivel = NA_character_, max_plausivel = NA_character_,
              valores_aceitos, termos_busca = coalesce(termos_busca, ""),
              regra_extracao = coalesce(regra_extracao, ""), decisao = "fechar", nota = "")
  aba_traits <- bind_rows(exemplos, aba_traits)
  aba_valores <- vals |>
    mutate(ordem = match(trait_id, aba_traits$trait_id)) |>
    arrange(ordem, desc(n_registros), valor) |>
    transmute(trait_id, valor_observado = valor, n_registros, exemplos,
              valor_padronizado = valor, nota = "")

  leia <- c(
    "Vocabulário dos traits ainda abertos",
    "",
    sprintf("São %d traits (%d categóricos, %d numéricos). Só 2 dos 48 traits têm vocabulário fechado hoje (posição dos olhos e focinho em vista lateral), e a extração automática só roda em trait fechado.",
            nrow(traits), sum(traits$tipo == "categorico"), sum(traits$tipo == "numerico")),
    "Preencha só as colunas AMARELAS. Não precisa fazer tudo de uma vez: um trait de cada vez, começando pelo topo da aba 'traits' (os de vocabulário menor).",
    "As colunas amarelas já vêm PRÉ-PREENCHIDAS com o que existe hoje (definição, unidade, limites, e a lista de valores que aparecem na planilha do livro, do mais frequente para o menos frequente). É um ponto de partida para editar, não uma decisão: apague, junte e corrija. Um trait só fecha quando a coluna decisao disser 'fechar'.",
    "As 2 primeiras linhas da aba 'traits' (posição dos olhos e focinho em vista lateral) são EXEMPLOS de traits já fechados: mostram como fica uma linha pronta.",
    "",
    "Aba 'traits': uma linha por trait",
    "As colunas cinzas mostram o que existe hoje. Nas amarelas:",
    "definicao: a definição do caractere como vai para a base (em inglês). Pode copiar a atual, se estiver boa.",
    "unidade, min_plausivel, max_plausivel: só para numéricos. Os limites são uma trava contra erro (valor fora vai para revisão), não um intervalo biológico exato.",
    "valores_aceitos: a lista FINAL de estados, separados por ponto e vírgula (ex.: dextral;medial). Para combinações que existem de fato, escreva a combinação como um estado (ex.: rounded or truncated).",
    "termos_busca: como o caractere aparece nos artigos, em português, inglês e espanhol, separados por ponto e vírgula (ex.: abertura cloacal;tubo cloacal;vent tube;cloacal tube;tubo cloacal).",
    "regra_extracao: alguma regra que o leitor do artigo precisa seguir (ex.: 'se o artigo der posição e direção, vale a posição'). Opcional.",
    "decisao: fechar (está pronto para extrair), discutir na reuniao, ou fora do escopo.",
    "",
    "Aba 'valores': os valores que aparecem hoje na planilha do livro",
    "Uma linha por valor observado, com o número de registros e até 3 espécies de exemplo.",
    "valor_padronizado: em qual estado da lista final (valores_aceitos) este valor entra. Vem preenchido com o próprio valor: mude só os que devem ser juntados (ex.: 'elliptical elongated' -> 'elongated elliptical'). Escreva 'erro' se for erro de registro e 'ausente' se for estrutura ausente.",
    "Isso serve duas vezes: fecha a lista do trait e, depois, corrige a própria planilha do livro com o mesmo mapeamento.",
    "",
    "Casos especiais",
    "tooth_row_formulae: é uma fórmula (2(2)/3), não uma lista; a sugestão é validar por padrão. Diga na nota se concorda.",
    "dieta_composicao: o valor é uma porcentagem; o vocabulário é a lista de itens alimentares (aba 'valores').",
    "Os 8 traits novos (CTmax, CTmin, tempo de desenvolvimento etc.) não têm dado na planilha: definição e unidade do zero.",
    "",
    "Não mude a ordem das colunas nem apague linhas: a planilha volta para o programa pelas colunas trait_id e valor_observado.")

  if (!requireNamespace("openxlsx2", quietly = TRUE)) stop("instale openxlsx2", call. = FALSE)
  amarelo <- openxlsx2::wb_color("FFFFF2A8"); cinza <- openxlsx2::wb_color("FFE8ECEF")
  formatar <- function(wb, aba, tab, amarelas, larg, congelar) {
    n <- nrow(tab) + 1; col <- match(amarelas, names(tab))
    wb |>
      openxlsx2::wb_add_worksheet(aba) |>
      openxlsx2::wb_add_data(x = tab, na.strings = "") |>
      openxlsx2::wb_set_col_widths(cols = seq_along(tab), widths = larg) |>
      openxlsx2::wb_add_cell_style(dims = openxlsx2::wb_dims(rows = 1:n, cols = seq_along(tab)), wrap_text = TRUE, vertical = "top") |>
      openxlsx2::wb_add_font(dims = openxlsx2::wb_dims(rows = 1, cols = seq_along(tab)), bold = TRUE) |>
      openxlsx2::wb_add_fill(dims = openxlsx2::wb_dims(rows = 1, cols = seq_along(tab)), color = cinza) |>
      openxlsx2::wb_add_fill(dims = openxlsx2::wb_dims(rows = 1:n, cols = col), color = amarelo) |>
      openxlsx2::wb_freeze_pane(first_active_row = 2, first_active_col = congelar) |>
      openxlsx2::wb_add_filter(rows = 1, cols = seq_along(tab))
  }
  wb <- openxlsx2::wb_workbook() |>
    openxlsx2::wb_add_worksheet("LEIA-ME") |>
    openxlsx2::wb_add_data(x = data.frame(x = leia), col_names = FALSE) |>
    openxlsx2::wb_set_col_widths(cols = 1, widths = 120) |>
    openxlsx2::wb_add_cell_style(dims = paste0("A1:A", length(leia)), wrap_text = TRUE, vertical = "top")
  for (i in which(leia %in% c(leia[1], "Aba 'traits': uma linha por trait",
                              "Aba 'valores': os valores que aparecem hoje na planilha do livro", "Casos especiais")))
    wb <- openxlsx2::wb_add_font(wb, dims = paste0("A", i), bold = TRUE, size = if (i == 1) 13 else 11)
  wb <- formatar(wb, "traits", aba_traits,
                 c("definicao", "unidade", "min_plausivel", "max_plausivel", "valores_aceitos",
                   "termos_busca", "regra_extracao", "decisao", "nota"),
                 c(26, 11, 18, 10, 10, 40, 10, 22, 8, 8, 34, 40, 10, 10, 10, 40, 40, 30, 16, 30), 2)
  wb <- openxlsx2::wb_add_data_validation(wb, sheet = "traits",
          dims = openxlsx2::wb_dims(rows = 2:(nrow(aba_traits) + 1), cols = match("decisao", names(aba_traits))),
          type = "list", value = paste0('"', paste(DECISAO_TRAIT, collapse = ","), '"'))
  wb <- formatar(wb, "valores", aba_valores, c("valor_padronizado", "nota"), c(28, 40, 10, 50, 30, 30), 3)
  dir.create(dirname(saida), showWarnings = FALSE, recursive = TRUE)
  openxlsx2::wb_save(wb, saida, overwrite = FALSE)
  invisible(list(traits = aba_traits, valores = aba_valores))
}
