# Planilha de conferencia humana de uma rodada do piloto zero.
#
# Reescrita em R de "Claude outputs/piloto-zero/para_denise/gerar_planilha.py",
# que gerou a conferencia_piloto_zero_Denise.xlsx da rodada 3 (02/10/2026). O
# Python ficava fora do git e usava caminhos de outra maquina (~/mnt, /tmp/txt).
# Diferencas, de proposito:
# - o sorteio do bloco 2 usa o gerador do R: com a mesma semente, sai outra
#   amostra que a do Python. A planilha ja enviada NAO e regenerada;
# - o nome usado no artigo vem dos sinonimos do banco da rodada (aliases_de(),
#   com os curados e os restritos por obra), e nao de uma lista escrita a mao;
# - a cota do bloco 2 por obra e proporcional, com minimo, e nao fixa.
#
# A leitura das respostas e a pontuacao estao em R/piloto_zero.R
# (ler_conferencia(), avaliar_conferencia()).
#
# Uso:
#   gerar_conferencia(cfg, pares_rodada = "Claude outputs/piloto-zero/r3/pares.csv",
#                     pares_ref = "Claude outputs/piloto-zero/pares.csv",
#                     banco = "Claude outputs/piloto-zero/rodada_3.duckdb",
#                     saida = "Claude outputs/piloto-zero/conferencia_r3/conferencia.xlsx")

library(purrr)
library(dplyr)
library(stringr)

ROTULO_TRAIT <- c(eyes_positioning = "Posição dos olhos",
                  snout_shape_lv = "Focinho em vista lateral")
ROTULO_CASO <- c(diverge = "valores diferentes", so_planilha = "só a planilha tem valor",
                 so_modelo = "só o modelo tem valor", igual = "iguais",
                 # conferencia do corpus da BT 5 (gerar_conferencia_corpus())
                 conflito = "dois valores na mesma obra", extraido = "um valor")

# ---- partes puras ---------------------------------------------------------------

#' Texto para busca: caixa baixa, travessoes e ligaduras padronizados, sem
#' espacos nem hifens. O PDF usa travessao (0.18-0.20 com "en dash") e a frase
#' do modelo vem com hifen; e o PDF quebra palavra com hifen no fim da linha.
normalizar_pdf <- function(s) {
  s <- tolower(s)
  s <- gsub("[–—−]", "-", s)
  s <- gsub("ﬁ", "fi", gsub("ﬂ", "fl", s))
  gsub("[[:space:]-]+", "", s)
}

#' Pagina(s) do PDF onde esta cada frase (separadas por " || "). Procura a
#' frase inteira e, se nao achar, o comeco e o fim (45 caracteres), numa
#' pagina e depois em duas paginas seguidas (frase que atravessa a quebra).
#' Frase de linha de tabela leva "(Tabela N)", N da primeira legenda da pagina.
#' `paginas`: texto de cada pagina (pdftools::pdf_text). "?" = nao achou.
achar_pagina <- function(span, paginas) {
  if (is.na(span) || !nzchar(span) || span == "NA") return("")
  pn <- normalizar_pdf(paginas)
  um <- function(s) {
    ns <- normalizar_pdf(s)
    for (sonda in unique(c(ns, substr(ns, 1, 45), substr(ns, nchar(ns) - 44, nchar(ns))))) {
      if (nchar(sonda) < 15) next
      pg <- which(str_detect(pn, fixed(sonda)))
      if (!length(pg) && length(pn) > 1) {
        pg <- which(str_detect(paste0(pn[-length(pn)], pn[-1]), fixed(sonda)))
      }
      if (length(pg)) {
        tab <- if (str_detect(s, "\\S {3,}\\S")) str_match(pn[pg[1]], "table([0-9]+)")[, 2] else NA
        return(paste0(paste(head(pg, 3), collapse = "/"), if (!is.na(tab)) paste0(" (Tabela ", tab, ")") else ""))
      }
    }
    "?"
  }
  paste(map_chr(str_split(span, fixed(" || "))[[1]], um), collapse = " || ")
}

#' Pares iguais em que a mesma frase com numero foi usada para mais de uma
#' especie da obra: "concordar" pode estar escondendo frase de outra especie.
frases_repetidas <- function(pares) {
  sp <- pares |>
    filter(!is.na(span), span != "NA") |>
    mutate(frase = str_split(span, fixed(" || "))) |>
    tidyr::unnest(frase) |>
    filter(str_detect(frase, "[0-9]"))
  rep <- sp |> distinct(obra_id, trait_id, frase, taxon_id) |>
    count(obra_id, trait_id, frase) |> filter(n > 1)
  sp |> semi_join(rep, by = c("obra_id", "trait_id", "frase")) |>
    filter(caso == "igual") |> distinct(obra_id, taxon_id, trait_id)
}

#' Amostra do bloco 2: `n` pares iguais, por obra, proporcional ao numero de
#' iguais e com pelo menos `minimo` por obra (ou todos, se houver menos).
sortear_bloco2 <- function(iguais, n = 25, minimo = 4, semente = 20261002) {
  if (!nrow(iguais)) return(iguais)
  tam <- count(iguais, obra_id)
  cota <- pmax(pmin(minimo, tam$n), round(n * tam$n / sum(tam$n)))
  set.seed(semente)
  map2_dfr(tam$obra_id, cota, function(o, q) {
    d <- filter(iguais, obra_id == o) |> arrange(taxon_id, trait_id)
    d[sort(sample.int(nrow(d), min(q, nrow(d)))), ]
  })
}

#' Como o artigo chama a especie: "" se usa o nome aceito; senao o sinonimo
#' mais citado no texto; "(não achei)" se nenhum aparece.
nome_no_artigo <- function(texto, especie, nomes) {
  t <- str_squish(texto)
  if (str_detect(t, fixed(especie))) return("")
  outros <- setdiff(nomes, especie)
  if (!length(outros)) return("(não achei)")
  n <- map_int(outros, ~ str_count(t, fixed(.x)))
  if (max(n) == 0) "(não achei)" else outros[which.max(n)]
}

#' Paginas em que o nome aparece, para quando o modelo nao devolveu frase.
paginas_do_nome <- function(nome, paginas) {
  pg <- which(str_detect(normalizar_pdf(paginas), fixed(normalizar_pdf(nome))))
  if (!length(pg)) return("")
  paste0("nome nas p. ", paste(head(pg, 5), collapse = ", "), if (length(pg) > 5) " …" else "")
}

#' As linhas da planilha. Pura em relacao a arquivo: recebe os pares da
#' rodada conferida e da rodada de referencia, o texto das paginas de cada
#' obra e os sinonimos de cada especie.
montar_conferencia <- function(pares, pares_ref, paginas, nomes, semente = 20261002, n_amostra = 25) {
  chave <- c("obra_id", "taxon_id", "trait_id")
  b1 <- filter(pares, caso != "igual") |> mutate(bloco = "1")
  iguais <- filter(pares, caso == "igual")
  susp <- semi_join(iguais, frases_repetidas(pares), by = chave)
  amostra <- sortear_bloco2(anti_join(iguais, susp, by = chave), n_amostra, semente = semente)
  b2 <- bind_rows(susp, semi_join(iguais, amostra, by = chave)) |> mutate(bloco = "2")
  ref <- select(pares_ref, all_of(chave), caso_ref = caso)
  limpo <- function(x) ifelse(is.na(x) | x == "NA", "", x)

  linhas <- bind_rows(b1, b2) |>
    left_join(ref, by = chave) |>
    mutate(
      span = limpo(span), valor_modelo = limpo(valor_modelo),
      nome_art = pmap_chr(list(obra_id, especie, taxon_id), function(o, e, t)
        nome_no_artigo(paste(paginas[[o]], collapse = " "), e, nomes[[t]] %||% e)),
      pagina = pmap_chr(list(obra_id, span, especie, nome_art), function(o, s, e, na) {
        p <- achar_pagina(s, paginas[[o]])
        if (nzchar(p)) p else paginas_do_nome(if (nzchar(na) && na != "(não achei)") na else e, paginas[[o]])
      })) |>
    arrange(bloco, citacao, especie, trait_id) |>
    mutate(id = sprintf("R%03d", row_number()))

  attr(linhas, "contagens") <- list(n1 = nrow(b1), n2 = nrow(b2), n_susp = nrow(susp), n_amostra = nrow(amostra))
  linhas
}

#' Texto de cada pagina para achar_pagina(): as palavras na ordem do PDF
#' (pdf_data(), que segue as colunas) seguidas do texto por layout
#' (pdf_text(), que mantem as linhas de tabela). So o layout nao basta: em
#' pagina de duas colunas ele intercala as linhas das duas e quebra a frase.
#' Medido na rodada 3 (02/10/2026): frases sem pagina caem de 121 para 2.
texto_paginas_pdf <- function(pdf) {
  layout <- suppressMessages(pdftools::pdf_text(pdf))
  fluxo <- map_chr(suppressMessages(pdftools::pdf_data(pdf)), ~ paste(.x$text, collapse = " "))
  paste(fluxo, layout)
}

# ---- escrita -----------------------------------------------------------------------

arquivo_de_citacao <- function(citacao) {
  paste0(gsub("_+", "_", gsub("^_|_$", "", gsub("[^A-Za-z0-9]+", "_", citacao))), ".pdf")
}

#' Escreve a planilha no formato da que foi para a Denise: aba LEIA-ME, aba
#' revisao com as 4 colunas amarelas, listas de valores, colunas de ligacao
#' ocultas, cabecalho congelado.
escrever_conferencia_xlsx <- function(linhas, caminho, traits, leiame = "inst/conferencia_LEIA-ME.txt",
                                      semente = 20261002) {
  if (!requireNamespace("openxlsx2", quietly = TRUE)) {
    stop("instale openxlsx2 para escrever a planilha formatada", call. = FALSE)
  }
  ct <- attr(linhas, "contagens")
  tab <- tibble::tibble(
    id = linhas$id, bloco = linhas$bloco, artigo = linhas$citacao,
    arquivo_pdf = arquivo_de_citacao(linhas$citacao), pagina_no_pdf = linhas$pagina,
    especie = linhas$especie, nome_no_artigo = linhas$nome_art,
    caractere = unname(ROTULO_TRAIT[linhas$trait_id]), situacao = unname(ROTULO_CASO[linhas$caso]),
    valor_planilha = linhas$valor_planilha, valor_modelo = linhas$valor_modelo,
    frase_do_modelo = linhas$span,
    valor_correto = "", onde_esta = "", frase_da_especie_certa = "", nota = "",
    obra_id = linhas$obra_id, taxon_id = linhas$taxon_id, trait_id = linhas$trait_id,
    caso_r3 = linhas$caso, caso_r1 = linhas$caso_ref)

  txt <- readLines(leiame, encoding = "UTF-8", warn = FALSE)
  txt <- txt[!str_detect(txt, "^# ")]
  campos <- list(n = nrow(tab), n_artigos = n_distinct(tab$artigo), n1 = ct$n1, n2 = ct$n2,
                 n_susp = ct$n_susp, n_amostra = ct$n_amostra, semente = semente)
  for (k in names(campos)) txt <- gsub(paste0("{", k, "}"), campos[[k]], txt, fixed = TRUE)
  negrito <- str_detect(txt, "^## "); txt <- sub("^## ", "", txt)

  amarelas <- c("valor_correto", "onde_esta", "frase_da_especie_certa", "nota")
  col <- function(n) match(n, names(tab))
  n <- nrow(tab) + 1
  wb <- openxlsx2::wb_workbook() |>
    openxlsx2::wb_add_worksheet("LEIA-ME") |>
    openxlsx2::wb_add_data(x = data.frame(x = txt), col_names = FALSE) |>
    openxlsx2::wb_set_col_widths(cols = 1, widths = 120) |>
    openxlsx2::wb_add_cell_style(dims = paste0("A1:A", length(txt)), wrap_text = TRUE, vertical = "top")
  for (i in which(negrito)) wb <- openxlsx2::wb_add_font(wb, dims = paste0("A", i), bold = TRUE, size = if (i == 1) 13 else 11)

  larg <- c(7, 7, 22, 24, 15, 26, 22, 20, 19, 16, 18, 60, 22, 18, 16, 40, 8, 8, 8, 8, 8)
  wb <- wb |>
    openxlsx2::wb_add_worksheet("revisao") |>
    openxlsx2::wb_add_data(x = tab, na.strings = "") |>
    openxlsx2::wb_set_col_widths(cols = seq_along(tab), widths = larg) |>
    openxlsx2::wb_set_col_widths(cols = col("obra_id"):ncol(tab), widths = 8, hidden = TRUE) |>
    openxlsx2::wb_add_cell_style(dims = openxlsx2::wb_dims(rows = 1:n, cols = seq_along(tab)), wrap_text = TRUE, vertical = "top") |>
    openxlsx2::wb_add_font(dims = openxlsx2::wb_dims(rows = 1, cols = seq_along(tab)), bold = TRUE) |>
    openxlsx2::wb_add_fill(dims = openxlsx2::wb_dims(rows = 1, cols = seq_along(tab)), color = openxlsx2::wb_color("FFE8ECEF")) |>
    openxlsx2::wb_add_fill(dims = openxlsx2::wb_dims(rows = 1:n, cols = col(amarelas)), color = openxlsx2::wb_color("FFFFF2A8")) |>
    openxlsx2::wb_freeze_pane(first_active_row = 2, first_active_col = col("nome_no_artigo")) |>
    openxlsx2::wb_add_filter(rows = 1, cols = 1:col("nota"))

  lista <- function(v) paste0('"', paste(v, collapse = ","), '"')
  for (t in unique(tab$trait_id)) {
    linhas_t <- which(tab$trait_id == t) + 1
    vals <- c(str_squish(strsplit(traits$valores_aceitos[traits$trait_id == t], ";")[[1]]), NAO_INFORMADO, OUTRO)
    for (r in linhas_t) {
      # aspas duplas na mensagem quebram o XML do openxlsx2 ("xml import
      # unsuccessful"): por isso as aspas tipograficas
      wb <- openxlsx2::wb_add_data_validation(wb, dims = openxlsx2::wb_dims(rows = r, cols = col("valor_correto")),
                                              type = "list", value = lista(vals),
                                              error_title = "Valor fora da lista",
                                              error = "Escolha um valor da lista; se nenhum servir, use \u201coutro (ver nota)\u201d e explique na nota.")
    }
  }
  wb <- wb |>
    openxlsx2::wb_add_data_validation(dims = openxlsx2::wb_dims(rows = 2:n, cols = col("onde_esta")), type = "list", value = lista(ONDE_ESTA)) |>
    openxlsx2::wb_add_data_validation(dims = openxlsx2::wb_dims(rows = 2:n, cols = col("frase_da_especie_certa")), type = "list", value = lista(FRASE_CERTA))
  dir.create(dirname(caminho), showWarnings = FALSE, recursive = TRUE)
  openxlsx2::wb_save(wb, caminho, overwrite = FALSE)
  invisible(tab)
}

#' Le os arquivos e gera a planilha. Nao sobrescreve: a planilha ja enviada
#' fica intacta. Copia os PDFs para a pasta da planilha com o nome da citacao.
gerar_conferencia <- function(cfg, pares_rodada, pares_ref, banco, saida, semente = 20261002) {
  if (file.exists(saida)) stop(saida, " ja existe; a conferencia enviada nao e sobrescrita", call. = FALSE)
  le <- function(f) readr::read_csv(f, show_col_types = FALSE, col_types = readr::cols(.default = "c"))
  pares <- le(pares_rodada); ref <- le(pares_ref)
  con <- dbConnect(duckdb::duckdb(), banco, read_only = TRUE)
  on.exit(dbDisconnect(con, shutdown = TRUE), add = TRUE)
  obras <- dbGetQuery(con, "SELECT obra_id, titulo, caminho_pdf FROM obras") |> filter(obra_id %in% pares$obra_id)
  paginas <- set_names(map(obras$caminho_pdf, texto_paginas_pdf), obras$obra_id)
  taxa <- unique(pares$taxon_id)
  nomes <- set_names(map(taxa, function(t) {
    ob <- unique(pares$obra_id[pares$taxon_id == t])
    unique(unlist(map(ob, ~ aliases_de(con, t, .x))))
  }), taxa)
  linhas <- montar_conferencia(pares, ref, paginas, nomes, semente)
  traits <- carregar_traits(cfg$traits)
  tab <- escrever_conferencia_xlsx(linhas, saida, traits, semente = semente)
  destino <- file.path(dirname(saida), arquivo_de_citacao(obras$titulo))
  walk2(obras$caminho_pdf, destino, ~ if (!file.exists(.y)) file.copy(.x, .y))
  invisible(tab)
}

# ---- conferencia do corpus da BT 5 --------------------------------------------
#
# 03/10/2026: primeira extracao fora do piloto. Nao ha planilha de referencia
# para comparar: cada valor extraido e conferido contra o artigo. Mesmo
# formato da conferencia do piloto (mesmo escritor, mesmas colunas amarelas),
# para ler_conferencia() ler as respostas sem mudanca.
#
#   gerar_conferencia_corpus(cfg, banco = cfg$db,
#                            saida = "Claude outputs/conferencia_corpus/conferencia_corpus.xlsx")

#' Uma linha por (obra, especie, trait) com valor: registros 'bruto' e
#' 'conflito' (estes agrupados, valores separados por " | "). Rejeitados
#' (span que nao confere) e taxons de teste ficam de fora.
gerar_conferencia_corpus <- function(cfg, banco, saida, leiame = "inst/conferencia_corpus_LEIA-ME.txt") {
  if (file.exists(saida)) stop(saida, " ja existe; a conferencia enviada nao e sobrescrita", call. = FALSE)
  con <- dbConnect(duckdb::duckdb(), banco, read_only = TRUE)
  on.exit(dbDisconnect(con, shutdown = TRUE), add = TRUE)
  ext <- dbGetQuery(con, "
    SELECT e.obra_id, e.taxon_id, e.trait_id, e.valor_cat, e.span_verbatim, e.status,
           a.especie, o.titulo, o.ano, o.caminho_pdf
      FROM extracoes e JOIN alvo a USING (taxon_id) JOIN obras o USING (obra_id)
     WHERE e.status IN ('bruto', 'conflito') AND e.taxon_id NOT LIKE 'TESTE%'")
  pares <- ext |>
    group_by(obra_id, taxon_id, trait_id, especie, titulo, ano, caminho_pdf) |>
    summarise(valor_modelo = paste(unique(valor_cat), collapse = " | "),
              span = paste(unique(span_verbatim), collapse = " || "),
              caso = if (any(status == "conflito")) "conflito" else "extraido", .groups = "drop") |>
    mutate(citacao = paste0(str_trunc(str_squish(titulo), 70), " (", ano, ")"),
           bloco = if_else(caso == "conflito", "1", "2"),
           valor_planilha = "", caso_ref = NA_character_)
  obras <- distinct(pares, obra_id, caminho_pdf, citacao)
  paginas <- set_names(map(obras$caminho_pdf, texto_paginas_pdf), obras$obra_id)
  nomes <- map(set_names(seq_len(nrow(pares))), ~ unique(aliases_de(con, pares$taxon_id[.x], pares$obra_id[.x])))
  linhas <- pares |>
    mutate(nome_art = pmap_chr(list(obra_id, especie, nomes), function(o, e, n)
             nome_no_artigo(paste(paginas[[o]], collapse = " "), e, n %||% e)),
           pagina = pmap_chr(list(obra_id, span, especie, nome_art), function(o, s, e, na) {
             p <- achar_pagina(s, paginas[[o]])
             # "?": frase nao achada ou curta demais para procurar ("Eyes
             # dorsal." na monografia de 63 especies); as paginas do nome da
             # especie ajudam mais que um "?"
             if (nzchar(p) && p != "?") p else paginas_do_nome(if (nzchar(na) && na != "(não achei)") na else e, paginas[[o]])
           })) |>
    arrange(bloco, citacao, especie, trait_id) |>
    mutate(id = sprintf("C%03d", row_number()))
  attr(linhas, "contagens") <- list(n1 = sum(linhas$bloco == "1"), n2 = sum(linhas$bloco == "2"),
                                    n_susp = 0, n_amostra = 0)
  tab <- escrever_conferencia_xlsx(linhas, saida, carregar_traits(cfg$traits), leiame = leiame)
  # o mesmo texto da aba LEIA-ME, como arquivo solto na pasta
  txt <- readLines(leiame, encoding = "UTF-8", warn = FALSE)
  txt <- sub("^## ", "", txt[!str_detect(txt, "^# ")])
  campos <- list(n = nrow(tab), n_artigos = n_distinct(tab$artigo), n1 = sum(linhas$bloco == "1"),
                 n2 = sum(linhas$bloco == "2"))
  for (k in names(campos)) txt <- gsub(paste0("{", k, "}"), campos[[k]], txt, fixed = TRUE)
  writeLines(txt, file.path(dirname(saida), "LEIA-ME.txt"), useBytes = TRUE)
  destino <- file.path(dirname(saida), arquivo_de_citacao(obras$citacao))
  walk2(obras$caminho_pdf, destino, ~ if (!file.exists(.y)) file.copy(.x, .y))
  invisible(tab)
}
