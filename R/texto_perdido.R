# Texto do PDF que o GROBID perdeu.
#
# Por que (06/10/2026): em Santos et al. (2018), *Adelphobates galactonotus*
# (Zootaxa, Correspondence, 4 paginas), o TEI comeca em "anterolaterally.
# Nares small": a introducao, os metodos e o comeco da descricao ("Snout
# rounded in dorsal and lateral views. Eyes small (ED/BH = 0.09-0.11mm),
# dorsally positioned") nao estavam em nenhum trecho (5,8 mil de 15,7 mil
# caracteres). Sem aviso: a extracao daria "nao encontrado". Medido no corpus
# da BT 5 no mesmo dia: 3 obras com menos de 50% do texto do PDF nos trechos.
#
# Como: as linhas do PDF, na ordem de leitura e por coluna
# (linhas_de_palavras(), R/fichas.R), sao comparadas com o texto dos trechos ja
# gravados, so letras e numeros. Linha que nao esta la e texto perdido; as
# perdidas viram paragrafos (o recuo da primeira linha abre paragrafo) e
# entram como trechos de texto, depois dos outros na ordem do documento, com
# a pagina. Linha de fonte menor (legenda, tabela, afiliacao) fica de fora,
# como nas fichas, e as Referencias tambem.

library(purrr)
library(dplyr)
library(stringr)

#' So letras e numeros, em caixa baixa, com as ligaduras desfeitas: o GROBID
#' escreve "fixed" onde o PDF tem "ﬁxed". Pura.
normalizar_cobertura <- function(s) {
  s <- gsub("ﬁ", "fi", gsub("ﬂ", "fl", tolower(s)))
  gsub("[^a-z0-9]", "", s)
}

#' Paragrafos do PDF que nao estao em `texto_trechos`. Pura.
#' `linhas`: saida de linhas_de_palavras(). Linha curta demais para comparar
#' (numero de pagina, "287") segue a anterior. Paragrafo com menos de
#' `min_chars` (cabeco de pagina solto) fica de fora.
paragrafos_perdidos <- function(linhas, texto_trechos, min_chars = 150) {
  vazio <- tibble::tibble(pagina = integer(), texto = character())
  if (!nrow(linhas)) return(vazio)
  ref <- which(e_referencias(linhas$texto))[1]
  if (!is.na(ref)) linhas <- linhas[seq_len(ref - 1), ]
  l <- filter(linhas, !menor)
  if (!nrow(l)) return(vazio)
  tr <- normalizar_cobertura(paste(texto_trechos, collapse = " "))
  n <- normalizar_cobertura(l$texto)
  coberta <- ifelse(nchar(n) < 15, NA, map_lgl(n, ~ str_detect(tr, fixed(.x))))
  for (i in seq_along(coberta)) if (is.na(coberta[i])) coberta[i] <- if (i == 1) TRUE else coberta[i - 1]
  # recuo de primeira linha: x0 alem da margem mais comum da coluna
  margem <- l |> group_by(pagina, coluna) |>
    mutate(m = as.numeric(names(which.max(table(x0))))) |> pull(m)
  novo <- l$x0 > margem + 4 | coberta != c(TRUE, head(coberta, -1)) | seq_along(coberta) == 1
  l |>
    mutate(par = cumsum(novo), coberta = coberta) |>
    filter(!coberta) |>
    group_by(par) |>
    summarise(pagina = first(pagina), texto = paste(texto, collapse = " "), .groups = "drop") |>
    mutate(texto = str_replace_all(texto, "([[:lower:]])- ([[:lower:]])", "\\1\\2")) |>
    # chave de identificacao fica de fora: perdida, ela virava o unico
    # candidato de 28 pares da monografia de 2020 (medido em 06/10/2026), e
    # chave e fonte de frase de outra especie (piloto zero, rodada 3)
    filter(nchar(texto) >= min_chars, !e_chave(texto)) |>
    select(pagina, texto)
}

#' Acrescenta aos trechos os paragrafos perdidos, como trechos de texto com a
#' pagina, depois dos outros na ordem. `linhas` (opcional) evita ler o PDF.
#' Sem PDF ou sem pdftools, devolve os trechos como estao.
com_texto_perdido <- function(trechos, pdf, obra_id, linhas = NULL) {
  if (is.null(linhas)) {
    if (is.na(pdf) || !file.exists(pdf) || !requireNamespace("pdftools", quietly = TRUE)) return(trechos)
    linhas <- linhas_de_palavras(suppressMessages(pdftools::pdf_data(pdf, font_info = TRUE)))
  }
  pp <- paragrafos_perdidos(linhas, trechos$texto)
  if (!nrow(pp)) return(trechos)
  pp <- pp |>
    transmute(trecho_id = map_chr(texto, ~ id_de(obra_id, paste0("perdido:", .x))),
              obra_id = obra_id, tipo = "texto", secao = NA_character_, pagina = as.integer(pagina),
              idioma = map_chr(texto, detectar_idioma), texto,
              ordem = max(c(0L, trechos$ordem), na.rm = TRUE) + seq_len(n()))
  bind_rows(trechos, pp)
}

#' Para obras ja estruturadas: acrescenta so os trechos perdidos novos.
#' Devolve quantos trechos e caracteres cada obra ganhou.
acrescentar_texto_perdido <- function(con, obra_ids = NULL) {
  obras <- dbGetQuery(con, "SELECT obra_id, caminho_pdf FROM obras
                             WHERE caminho_pdf IS NOT NULL AND obra_id IN (SELECT obra_id FROM trechos)")
  if (!is.null(obra_ids)) obras <- filter(obras, obra_id %in% obra_ids)
  map2_dfr(obras$obra_id, obras$caminho_pdf, function(o, pdf) {
    tr <- dbGetQuery(con, "SELECT * FROM trechos WHERE obra_id = ?", params = list(o))
    novos <- filter(com_texto_perdido(tr, pdf, o), !trecho_id %in% tr$trecho_id)
    registrar_novos(con, "trechos", novos)
    tibble::tibble(obra_id = o, n_trechos = nrow(novos), n_chars = sum(nchar(novos$texto)))
  })
}
