# Estruturacao: PDF -> TEI (GROBID) -> trechos.
# Texto corrido, tabelas e legendas viram tipos distintos de trecho (item 6).
# O idioma e detectado e guardado; a extracao roda no idioma original (item 9).

library(xml2)
library(purrr)
library(dplyr)

TEI_NS <- c(tei = "http://www.tei-c.org/ns/1.0")

grobid_tei <- function(pdf, servidor, destino) {
  resp <- httr2::request(paste0(servidor, "/api/processFulltextDocument")) |>
    httr2::req_body_multipart(
      input = curl::form_file(pdf),
      consolidateHeader = "1",
      segmentSentences = "1") |>
    httr2::req_timeout(300) |>
    httr2::req_perform()
  writeBin(httr2::resp_body_raw(resp), destino)
  destino
}

detectar_idioma <- function(txt) {
  if (!requireNamespace("cld3", quietly = TRUE)) return(NA_character_)
  cld3::detect_language(substr(txt, 1, 5000))
}

#' Titulo de secao principal de artigo (Introducao, Metodos, Resultados...),
#' com ou sem numeracao na frente ("2. Material and Methods").
PADRAO_SECAO_PRINCIPAL <- paste0(
  "^\\s*([0-9]+\\.?\\s*)?(introduc|introdu[c\u00e7][a\u00e3]o|materia|methods?\\b|m[e\u00e9]todos?\\b|",
  "results?\\b|resultados?\\b|discuss|conclus|acknowledg|agradecimento|",
  "references\\b|literature cited|refer[e\u00ea]ncias)")

#' O GROBID devolve as secoes achatadas: "MATERIALS AND METHODS" vem como uma
#' div sem paragrafo, e as subsecoes ("Study area", "Sampling") como divs
#' irmas, nao filhas. Marcando o paragrafo so com o titulo imediato, nenhum
#' trecho ficava com "Methods" e o agente de contexto nao tinha o que ler:
#' 3 de 8 obras de P. barrioi (B. ahenea, stone frog, a tese de 2009),
#' conferido nos TEI em 01/10/2026.
#'
#' Por isso a subsecao herda o titulo principal: "MATERIALS AND METHODS /
#' Study area". O titulo principal muda quando a div nao tem paragrafo
#' proprio OU quando o titulo e de secao principal conhecida. So "div vazia"
#' nao basta: na tese, RESULTS tem paragrafos e herdaria METHODS, levando os
#' resultados para o contexto.
#'
#' Pura: recebe o titulo de cada div (NA se nao tem) e quantos paragrafos ela
#' tem, na ordem do documento; devolve o nome de secao de cada div.
secoes_com_principal <- function(titulos, n_paragrafos) {
  principal <- NA_character_
  map2_chr(titulos, n_paragrafos, function(t, n) {
    if (is.na(t)) return(NA_character_)
    if (n == 0 || stringr::str_detect(t, stringr::regex(PADRAO_SECAO_PRINCIPAL, ignore_case = TRUE))) {
      principal <<- t
      return(t)
    }
    if (is.na(principal)) t else paste0(principal, " / ", t)
  })
}

#' TEI -> data frame de trechos. Paragrafo e a unidade de texto; cada tabela
#' (conteudo + legenda) e um trecho unico, para a tabela nao ser picada.
tei_para_trechos <- function(tei_path, obra_id) {
  doc <- read_xml(tei_path)

  divs <- xml_find_all(doc, "//tei:body//tei:div", TEI_NS)
  pars <- map(divs, ~ map_chr(xml_find_all(.x, "./tei:p", TEI_NS), xml_text))
  titulos <- map_chr(divs, function(div) {
    h <- xml_find_first(div, "./tei:head", TEI_NS)
    if (inherits(h, "xml_missing")) NA_character_ else xml_text(h)
  })
  secoes <- secoes_com_principal(titulos, lengths(pars))
  paragrafos <- map2_dfr(secoes, pars, ~ tibble::tibble(tipo = "texto", secao = .x, texto = .y))

  tabelas <- xml_find_all(doc, "//tei:figure[@type='table']", TEI_NS) |>
    map_dfr(~ tibble::tibble(
      tipo = "tabela",
      secao = xml_text(xml_find_first(.x, ".//tei:head", TEI_NS)) %||% NA_character_,
      texto = paste(xml_text(xml_find_first(.x, ".//tei:figDesc", TEI_NS)) %||% "",
                    xml_text(.x))))

  legendas <- xml_find_all(doc, "//tei:figure[not(@type='table')]//tei:figDesc", TEI_NS) |>
    map_dfr(~ tibble::tibble(tipo = "legenda", secao = NA_character_,
                             texto = xml_text(.x)))

  # TEI sem corpo: o GROBID devolveu so o cabecalho. Visto em Prado et al.
  # (2009, PDF da BioOne com folha de rosto), 02/10/2026. Antes isto quebrava
  # adiante com "objeto 'texto' nao encontrado"; agora para com o motivo, e
  # quem chama cai no texto por pagina.
  if (nrow(paragrafos) + nrow(tabelas) + nrow(legendas) == 0) {
    stop("TEI sem texto no corpo (o GROBID devolveu so o cabecalho): ", tei_path, call. = FALSE)
  }

  bind_rows(paragrafos, tabelas, legendas) |>
    filter(!is.na(texto), nchar(texto) > 40) |>
    mutate(obra_id = obra_id,
           pagina = NA_integer_,
           idioma = map_chr(texto, detectar_idioma),
           trecho_id = map2_chr(obra_id, texto, id_de)) |>
    # ordem no documento: a recuperacao deixa o nome da especie valer para os
    # paragrafos seguintes (recuperar_candidatos(), 02/10/2026)
    mutate(ordem = seq_len(n())) |>
    select(trecho_id, obra_id, tipo, secao, pagina, idioma, texto, ordem)
}

#' Tabelas lidas do texto do PDF (com o layout), alem das do GROBID.
#'
#' O GROBID perde tabela em pagina de paisagem: na Tabela 3 de Conte et al.
#' (2007) - uma linha por especie, coluna "Snout shape (Lateral)" - o TEI
#' ficou so com os cabecalhos, transpostos, e um unico valor; as 16 linhas de
#' especie sumiram (conferido em 02/10/2026). No texto do PDF a tabela vem
#' inteira. Cada legenda "Table N"/"Tabela N"/"Tabla N" no inicio de linha
#' abre um trecho que vai ate a proxima legenda ou o fim da pagina. O layout
#' (colunas por espacos) fica como esta; validar_span() normaliza os espacos.
#'
#' Pura em relacao ao banco: recebe o texto das paginas (pdftools::pdf_text).
TABELA_LEGENDA <- "^\\s*(Table|TABLE|Tabela|TABELA|Tabla|TABLA)\\s+[0-9IVXL]+\\b"

tabelas_do_texto_pdf <- function(paginas, obra_id) {
  map_dfr(seq_along(paginas), function(pg) {
    linhas <- strsplit(paginas[pg], "\n", fixed = TRUE)[[1]]
    ini <- grep(TABELA_LEGENDA, linhas)
    if (!length(ini)) return(tibble::tibble())
    fim <- c(ini[-1] - 1L, length(linhas))
    map2_dfr(ini, fim, function(i, f) tibble::tibble(
      tipo = "tabela", secao = substr(stringr::str_squish(linhas[i]), 1, 120),
      pagina = pg, texto = paste(linhas[i:f], collapse = "\n")))
  }) |>
    (\(d) if (nrow(d)) filter(d, nchar(texto) > 40) else d)()
}

#' Acrescenta aos trechos do TEI as tabelas lidas do PDF. Sem pdftools ou sem
#' PDF, avisa e devolve os trechos como estao.
com_tabelas_do_pdf <- function(trechos, pdf, obra_id) {
  if (is.na(pdf) || !file.exists(pdf) || !requireNamespace("pdftools", quietly = TRUE)) {
    warning(obra_id, ": tabelas do PDF nao lidas (sem PDF ou sem pdftools)", call. = FALSE)
    return(trechos)
  }
  tb <- tabelas_do_texto_pdf(suppressMessages(pdftools::pdf_text(pdf)), obra_id)
  if (!nrow(tb)) return(trechos)
  tb <- tb |>
    mutate(obra_id = obra_id, idioma = map_chr(texto, detectar_idioma),
           trecho_id = map2_chr(obra_id, paste0("pdf:", pagina, ":", texto), id_de),
           ordem = max(c(0L, trechos$ordem), na.rm = TRUE) + seq_len(n())) |>
    select(trecho_id, obra_id, tipo, secao, pagina, idioma, texto, ordem)
  bind_rows(trechos, tb)
}

#' Fallback quando o GROBID nao esta de pe: pagina inteira como trecho.
#' Perde a separacao de tabela - use so para destravar, nao como padrao.
pdf_para_trechos <- function(pdf, obra_id) {
  paginas <- pdftools::pdf_text(pdf)
  tibble::tibble(obra_id = obra_id, tipo = "texto", secao = NA_character_,
                 pagina = seq_along(paginas), texto = paginas) |>
    filter(nchar(texto) > 40) |>
    mutate(idioma = map_chr(texto, detectar_idioma),
           trecho_id = map2_chr(obra_id, pagina, id_de)) |>
    mutate(ordem = pagina) |>
    select(trecho_id, obra_id, tipo, secao, pagina, idioma, texto, ordem)
}

estruturar_obras <- function(con, cfg) {
  dir.create(cfg$dir_tei, showWarnings = FALSE, recursive = TRUE)
  pend <- dbGetQuery(con, "
    SELECT obra_id, caminho_pdf FROM obras
     WHERE caminho_pdf IS NOT NULL
       AND obra_id NOT IN (SELECT DISTINCT obra_id FROM trechos)")

  pmap_dfr(pend, function(obra_id, caminho_pdf) {
    tei <- file.path(cfg$dir_tei, paste0(obra_id, ".tei.xml"))
    trechos <- tryCatch({
      if (!file.exists(tei)) grobid_tei(caminho_pdf, cfg$grobid, tei)
      # texto perdido por ultimo: as fichas tambem contam como texto coberto
      com_texto_perdido(com_fichas_do_pdf(com_tabelas_do_pdf(tei_para_trechos(tei, obra_id), caminho_pdf, obra_id),
                                          caminho_pdf, obra_id), caminho_pdf, obra_id)
    }, error = function(e) {
      warning("GROBID falhou em ", obra_id, ": ", conditionMessage(e))
      pdf_para_trechos(caminho_pdf, obra_id)
    })
    registrar(con, "trechos", trechos)
    # idioma predominante do documento
    dbExecute(con, sprintf(
      "UPDATE obras SET idioma = '%s' WHERE obra_id = '%s'",
      names(sort(table(trechos$idioma), decreasing = TRUE))[1] %||% "NA", obra_id))
    tibble::tibble(obra_id = obra_id, n_trechos = nrow(trechos))
  })
}

#' Refaz os trechos a partir do TEI ja gravado, sem chamar o GROBID.
#'
#' estruturar_obras() pula obra que ja tem trechos, entao uma mudanca no parse
#' (como secoes_com_principal(), 01/10/2026) nao chega as obras ja
#' estruturadas. Aqui os trechos da obra sao apagados e regravados. O
#' trecho_id vem do texto (id_de(obra_id, texto)), entao as extracoes que
#' apontam para um trecho continuam apontando para ele. Obra sem TEI fica
#' como esta e aparece no resultado com n_trechos = NA.
reestruturar_de_tei <- function(con, cfg, obra_ids = NULL) {
  if (is.null(obra_ids)) obra_ids <- dbGetQuery(con, "SELECT DISTINCT obra_id FROM trechos")$obra_id
  map_dfr(obra_ids, function(obra_id) {
    tei <- file.path(cfg$dir_tei, paste0(obra_id, ".tei.xml"))
    if (!file.exists(tei)) return(tibble::tibble(obra_id = obra_id, n_trechos = NA_integer_))
    # mesmo plano B de estruturar_obras(): TEI sem texto vira texto por pagina
    pdf <- dbGetQuery(con, "SELECT caminho_pdf FROM obras WHERE obra_id = ?", params = list(obra_id))$caminho_pdf
    if (!length(pdf)) pdf <- NA_character_
    trechos <- tryCatch(com_texto_perdido(com_fichas_do_pdf(com_tabelas_do_pdf(tei_para_trechos(tei, obra_id), pdf, obra_id),
                                                            pdf, obra_id), pdf, obra_id),
                        error = function(e) {
      if (!length(pdf) || is.na(pdf) || !file.exists(pdf)) stop(conditionMessage(e), " (e sem PDF para o plano B)", call. = FALSE)
      warning(obra_id, ": ", conditionMessage(e), "; usado o texto por pagina", call. = FALSE)
      pdf_para_trechos(pdf, obra_id)
    })
    dbExecute(con, "DELETE FROM trechos WHERE obra_id = ?", params = list(obra_id))
    registrar(con, "trechos", trechos)
    tibble::tibble(obra_id = obra_id, n_trechos = nrow(trechos))
  })
}
