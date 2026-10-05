# Fichas de especie lidas direto do PDF (pdftools::pdf_data), sem o GROBID.
#
# Por que (04/10/2026): nas monografias com muitas especies o GROBID estraga a
# estrutura que importa - a ficha de cada especie. Na conferencia da rodada 3
# do piloto zero:
#   - Santos et al. (2023): duas colunas misturadas no mesmo trecho e o nome
#     de uma especie como secao de varias fichas seguidas;
#   - Pezzuti et al. (2021): pedacos da descricao postos longe do cabecalho,
#     junto de legendas de figura de outra especie;
#   - Rossa-Feres & Nomura (2006): cabecalho de ficha perdido (Scinax
#     fuscomarginatus so aparece nas legendas e nos comentarios).
# Medido sem modelo nos 131 pares conferidos com valor no artigo: a frase com
# o valor certo estava entre os candidatos do GROBID em 94; estava na ficha
# lida do PDF em 115 - em todos os pares cuja ficha foi achada.
#
# Como: as palavras vem com posicao e fonte. Cada pagina e dividida em duas
# colunas pelo meio, as linhas sao lidas coluna por coluna, e uma ficha comeca
# na linha que abre com binomio em italico seguido de autor e ano, "(Fig",
# "cf." ou hibrido ("Boana raniceps Cope 1862", "Physalaemus signifer (Fig.
# 68)"). Termina no proximo cabecalho, num titulo de secao em caixa alta ou
# nas Referencias. Linha com fonte menor que a do corpo (legenda, tabela,
# rodape) e pulada: nao entra na ficha e nao a corta.

library(purrr)
library(dplyr)
library(stringr)

#' Linhas na ordem de leitura. `paginas`: lista de data frames de
#' pdftools::pdf_data(font_info = TRUE). Pura.
linhas_de_palavras <- function(paginas) {
  d <- bind_rows(imap(paginas, function(p, i) if (nrow(p)) mutate(p, pagina = i)))
  if (!nrow(d)) return(tibble::tibble())
  corpo <- as.numeric(names(which.max(table(round(d$font_size * 2) / 2))))
  d |>
    group_by(pagina) |>
    mutate(coluna = if_else(x < corte_coluna(x, width), 1L, 2L)) |>
    ungroup() |>
    mutate(italico = str_detect(font_name, "Italic|Oblique")) |>
    arrange(pagina, coluna, y, x) |>
    # linha nova quando o y salta mais de 2 pontos. Faixa fixa (round(y / 3))
    # partia linha com sobrescrito e juntava linhas vizinhas ("dorwith sal
    # view", corpus da BT 5, 04/10/2026)
    group_by(pagina, coluna) |>
    mutate(y_l = cumsum(c(TRUE, diff(y) > 2))) |>
    group_by(pagina, coluna, y_l) |>
    arrange(x, .by_group = TRUE) |>
    summarise(x0 = min(x), texto = paste(text, collapse = " "),
              ital2 = length(italico) >= 2 && all(italico[1:2]),
              fonte = median(font_size), .groups = "drop") |>
    mutate(menor = fonte < corpo - 0.75) |>
    arrange(pagina, coluna, y_l)
}

#' Onde comeca a coluna da direita: o x de inicio de palavra mais comum no
#' meio da pagina (35-65% da largura). Pagina em que mais de 2% das palavras
#' atravessam esse ponto e de uma coluna so (Inf). O meio exato da pagina nao
#' serve: num PDF do corpus a coluna da esquerda vai ate x = 289 e a da
#' direita comeca em 306, com a pagina de 538; cortando em 269, "di-" ia para
#' a outra coluna e a frase saia "laterally rected" (04/10/2026). Pura.
corte_coluna <- function(x, width) {
  larg <- max(x + width)
  meio <- x[x > 0.35 * larg & x < 0.65 * larg]
  if (length(meio) < 5) return(Inf)
  c0 <- as.numeric(names(which.max(table(meio)))) - 3
  if (mean(x < c0 & x + width > c0) > 0.02) Inf else c0
}

#' Linha que abre ficha de especie. Pura.
e_cabecalho <- function(texto, ital2) {
  ital2 &
    # depois do binomio: fim da linha, "(Fig.", "(Figura", "(Autor, ano)",
    # "Autor ano" ou hibrido. Parentese qualquer nao: "Physalaemus cicada (n=8,
    # estagio 37)." era titulo de tabela e virou ficha (04/10/2026)
    str_detect(texto, paste0("^[A-Z][a-z]+ (cf\\. |aff\\. )?([a-z-]{3,}|sp\\.)",
                             "(\\s*$|\\s*\\(\\s*(Figs?\\b|Figur[ae]s?\\b|L\u00e1m|Plate|[A-Z][[:alpha:]'.-]*[ ,&)])",
                             "|\\s+[A-Z][[:alpha:]'-]+[ ,&]|\\s+[A-Z][[:alpha:]'-]+ ?[0-9]{4}|\\s+(x|\u00d7)\\s)")) &
    !str_detect(texto, "^(Figure|Fig|Table|Tabela)\\b")
}

#' Titulo de secao em caixa alta ("MATERIAL AND METHODS", "DISCUSSION").
#' Fecha a ficha aberta. Pura.
e_titulo_secao <- function(texto) {
  str_detect(texto, "^[A-Z][A-Z ,&-]{7,}$") |
    str_detect(texto, "^(Discussion|Taxonomic key|Key to|Acknowledg)")
}

#' Titulo das Referencias, em ingles, portugues e espanhol. "REFERENCIAS
#' BIBLIOGRAFICAS" nao era reconhecido, e as referencias viravam fichas
#' (Physalaemus cicada, corpus da BT 5, 04/10/2026). Pura.
e_referencias <- function(texto) {
  str_detect(texto, paste0("^(REFERENCES|References|LITERATURE CITED|Literature [Cc]ited|",
                           "Refer\u00eancias|REFER\u00caNCIAS|Referencias|REFERENCIAS|Literatura [Cc]itada|LITERATURA CITADA|",
                           "Bibliograf\u00eda|BIBLIOGRAF\u00cdA|Bibliografia|BIBLIOGRAFIA)",
                           "( [Bb]ibliogr\u00e1ficas| BIBLIOGR\u00c1FICAS| [Cc]itadas?| CITADAS?)?\\s*$"))
}

#' Fichas a partir das linhas. Pura. Devolve cabecalho, pagina e texto.
segmentar_fichas <- function(linhas) {
  vazio <- tibble::tibble(cabecalho = character(), pagina = integer(), texto = character())
  if (!nrow(linhas)) return(vazio)
  l <- filter(linhas, !menor)
  ficha <- rep(NA_integer_, nrow(l)); atual <- NA_integer_; k <- 0L
  for (i in seq_len(nrow(l))) {
    if (e_referencias(l$texto[i])) break
    if (e_cabecalho(l$texto[i], l$ital2[i])) { k <- k + 1L; atual <- k }
    else if (e_titulo_secao(l$texto[i])) atual <- NA_integer_
    ficha[i] <- atual
  }
  l$ficha <- ficha
  if (all(is.na(ficha))) return(vazio)
  l |>
    filter(!is.na(ficha)) |>
    group_by(ficha) |>
    summarise(cabecalho = first(texto), pagina = first(pagina),
              texto = paste(texto, collapse = " "), .groups = "drop") |>
    # palavra partida no fim da linha ("lat- eral"): o span do modelo vem
    # daqui, e a pagina da planilha normaliza hifen e espaco (normalizar_pdf)
    mutate(texto = str_replace_all(texto, "([[:lower:]])- ([[:lower:]])", "\\1\\2")) |>
    select(cabecalho, pagina, texto)
}

#' Fichas lidas do PDF como trechos (tipo "ficha", secao = o cabecalho), com
#' `ordem` a partir de `ordem0` + 1. Sem pdftools ou sem PDF, nenhuma.
fichas_do_pdf <- function(pdf, obra_id, ordem0 = 0L) {
  if (is.na(pdf) || !file.exists(pdf) || !requireNamespace("pdftools", quietly = TRUE)) return(tibble::tibble())
  fi <- segmentar_fichas(linhas_de_palavras(suppressMessages(pdftools::pdf_data(pdf, font_info = TRUE))))
  if (!nrow(fi)) return(tibble::tibble())
  fi |>
    transmute(obra_id = obra_id, tipo = "ficha", secao = str_trunc(str_squish(cabecalho), 120),
              pagina, texto, idioma = map_chr(texto, detectar_idioma),
              trecho_id = map2_chr(obra_id, paste0("ficha:", texto), id_de),
              ordem = ordem0 + seq_len(n())) |>
    distinct(trecho_id, .keep_all = TRUE) |>
    select(trecho_id, obra_id, tipo, secao, pagina, idioma, texto, ordem)
}

com_fichas_do_pdf <- function(trechos, pdf, obra_id) {
  bind_rows(trechos, fichas_do_pdf(pdf, obra_id, max(c(0L, trechos$ordem), na.rm = TRUE)))
}

#' A ficha pode substituir o GROBID? Entre 400 e 10 mil caracteres e sem
#' pontilhado de chave. No corpus da BT 5 (04/10/2026), entrada de chave
#' ("Rhinella crucifer (Fig. 3c) ......", 110 caracteres) virava ficha, e em
#' artigo de uma especie so a "ficha" ia do titulo ao fim (14 a 30 mil
#' caracteres). Nesses casos fica o caminho do GROBID. Pura.
ficha_util <- function(texto) nchar(texto) >= 400 & nchar(texto) <= 10000 & !e_chave(texto)

#' Fichas para obras ja estruturadas, sem refazer o GROBID: so acrescenta os
#' trechos "ficha" de quem tem PDF e ainda nao tem ficha. Devolve quantas
#' fichas cada obra ganhou.
acrescentar_fichas <- function(con, obra_ids = NULL) {
  obras <- dbGetQuery(con, "
    SELECT o.obra_id, o.caminho_pdf FROM obras o
     WHERE o.caminho_pdf IS NOT NULL
       AND o.obra_id IN (SELECT DISTINCT obra_id FROM trechos)
       AND o.obra_id NOT IN (SELECT obra_id FROM trechos WHERE tipo = 'ficha')")
  if (!is.null(obra_ids)) obras <- filter(obras, obra_id %in% obra_ids)
  map2_dfr(obras$obra_id, obras$caminho_pdf, function(o, pdf) {
    ordem0 <- dbGetQuery(con, "SELECT max(ordem) m FROM trechos WHERE obra_id = ?", params = list(o))$m
    fi <- fichas_do_pdf(pdf, o, if (is.na(ordem0)) 0L else as.integer(ordem0))
    if (nrow(fi)) registrar(con, "trechos", fi)
    tibble::tibble(obra_id = o, n_fichas = nrow(fi))
  })
}
