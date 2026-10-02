# DOI e acesso aberto das referencias da BT 5.0.
#
# Por que (02/10/2026): o gargalo da producao nao e custo de API, e acesso ao
# PDF. Das 775 referencias distintas do species.json, so 86 trazem DOI; sem
# DOI o Unpaywall nao acha nada e o PDF entra a mao. Aqui cada referencia sem
# DOI e procurada no Crossref (citacao inteira, query.bibliographic) e na
# OpenAlex (titulo), e o melhor candidato so e aceito sozinho se titulo, ano
# e autor baterem. DOI errado e pior que DOI nenhum: traz o PDF de outra obra
# e o valor extraido sai atribuido a fonte errada.
#
# Nada aqui grava no banco. A saida e uma tabela para conferencia; o que
# fazer com ela (banco, species.json da BT) e decisao separada.
#
# Erro de API nunca vira "nao encontrado" (principio 1): a linha sai com
# status "erro" e a mensagem.

library(httr2)
library(purrr)
library(dplyr)
library(stringr)

# ---- logica pura (testada em tests/teste_referencias_doi.R) --------------------

#' Minusculas, sem acento, sem tag HTML, sem pontuacao. O Crossref devolve
#' titulos com <i>...</i> e a BT 5 escreve com e sem acento.
normalizar_titulo <- function(x) {
  # entidade HTML ("Nunes &amp; Pombal", "&lt;br&gt;") vem do Crossref escapada
  x <- str_replace_all(x %||% NA_character_, c("&amp;(amp;)*" = "&", "&lt;" = "<", "&gt;" = ">"))
  x <- str_replace_all(x, "<[^>]+>", " ")
  x <- stringi::stri_trans_general(x, "Latin-ASCII")
  x <- str_replace_all(tolower(x), "[^a-z0-9 ]", " ")
  str_squish(x)
}

#' Similaridade de titulo em [0, 1]. Usa o maior entre a distancia de edicao
#' normalizada e a cobertura do titulo mais curto pelo mais longo: o Crossref
#' as vezes junta subtitulo que a BT 5 omite, ou o contrario.
similaridade_titulo <- function(a, b) {
  a <- normalizar_titulo(a); b <- normalizar_titulo(b)
  map2_dbl(a, b, function(x, y) {
    if (is.na(x) || is.na(y) || !nzchar(x) || !nzchar(y)) return(0)
    lv <- stringdist::stringsim(x, y, method = "lv")
    curto <- if (nchar(x) <= nchar(y)) x else y
    longo <- if (nchar(x) <= nchar(y)) y else x
    # cobertura so conta com titulo curto razoavel: "the tadpole of" casaria
    # com metade da literatura. Vale 0.89: leva a "revisar", nunca a "aceito".
    # Na rodada completa (02/10/2026) a cobertura a 0.95 aceitou "Contribution
    # a l'etude des Amphibiens de Guyane francaise" como a parte III de uma
    # serie de mesmo titulo, e o artigo como DOI de "Figure 4" dele mesmo.
    cob <- if (nchar(curto) >= 40 && str_detect(longo, fixed(curto))) 0.89 else 0
    max(lv, cob)
  })
}

#' O sobrenome do primeiro autor do candidato aparece na string de autores da
#' BT 5? Comparacao por palavra, sem acento. Os autores da BT 5 vem em formatos
#' variados ("Cei, J. M", "Tiago Leite Pezzuti, Felipe ..."), entao procurar o
#' sobrenome do candidato e mais robusto que tentar extrair o da BT 5.
autor_confere <- function(autores_ref, sobrenome_cand) {
  map2_lgl(autores_ref, sobrenome_cand, function(r, s) {
    if (is.na(r) || is.na(s) || !nzchar(s)) return(NA)
    palavras <- str_split(normalizar_titulo(r), " ")[[1]]
    partes <- str_split(normalizar_titulo(s), " ")[[1]]
    # sobrenome composto ("Carvalho-e-Silva", "de Sa"): basta a parte mais longa
    alvo <- partes[which.max(nchar(partes))]
    alvo %in% palavras
  })
}

#' aceito: titulo >= 0.90, mesmo ano e autor conferido.
#' revisar: titulo >= 0.75, ou titulo alto com ano a 1 de distancia (volume
#'   datado de um ano e publicado no seguinte e comum) ou sem autor no
#'   candidato.
#' sem_casamento: o resto.
#' Limiares iniciais, a medir contra as referencias que ja tem DOI.
decidir_casamento <- function(sim, ano_ref, ano_cand, autor_ok) {
  dano <- abs(as.integer(ano_ref) - as.integer(ano_cand))
  case_when(
    is.na(sim) ~ "sem_casamento",
    sim >= 0.90 & !is.na(dano) & dano == 0 & autor_ok %in% TRUE ~ "aceito",
    sim >= 0.90 & (is.na(dano) | dano <= 1) & !(autor_ok %in% FALSE) ~ "revisar",
    sim >= 0.75 ~ "revisar",
    TRUE ~ "sem_casamento")
}

#' Entre os candidatos de uma referencia, o de maior similaridade de titulo;
#' empate desfeito pelo ano mais proximo.
melhor_candidato <- function(cands, titulo_ref, ano_ref, autores_ref) {
  if (nrow(cands) == 0) return(cands)
  cands |>
    mutate(sim = similaridade_titulo(titulo_ref, titulo_cand),
           dano = abs(as.integer(ano_ref) - as.integer(ano_cand)),
           autor_ok = autor_confere(autores_ref, sobrenome_cand)) |>
    arrange(desc(sim), dano) |>
    slice(1)
}

# ---- APIs -------------------------------------------------------------------

#' Primeiro elemento ou NULL (NULL$campo e NULL, e o %||% pega). Crossref e OpenAlex mandam lista vazia (nao NULL)
#' em author, container-title e authorships, e list() passa pelo %||%: o [[1]]
#' estourava (02/10/2026, amostra de 80 referencias).
primeiro <- function(x) if (length(x)) x[[1]] else NULL

#' max_seconds: em 02/10/2026 a OpenAlex esgotou a cota diaria sem chave
#' (US$ 0,10/dia, 10 creditos por busca: ~100 buscas) e mandou Retry-After de
#' 12.111 s; o req_retry obedecia e a rodada ficava parada por horas. Agora
#' desiste em 1 min e a referencia sai como "erro", para rodar de novo.
req_api <- function(url, query, pausa = 1) {
  Sys.sleep(pausa)   # OpenAlex responde 429 a chamadas em sequencia rapida
  request(url) |>
    req_url_query(!!!query) |>
    req_user_agent("girinos-traits (resolucao de DOI das referencias da BT 5.0)") |>
    req_retry(max_tries = 3, max_seconds = 60) |>
    req_perform() |>
    resp_body_json()
}

#' Crossref com a citacao inteira: o proprio Crossref recomenda
#' query.bibliographic para casar referencia. Sem filtro de tipo: capitulo e
#' livro tambem valem aqui.
candidatos_crossref <- function(citacao, email, n = 5) {
  js <- req_api("https://api.crossref.org/works",
                list(query.bibliographic = citacao, rows = n, mailto = email))
  # "component" e figura ou tabela com DOI proprio (Zootaxa, ZooKeys, PLOS):
  # o titulo e "Figure 4. <titulo do artigo>" e casava com o artigo
  itens <- keep(js$message$items %||% list(), ~ !identical(.x$type, "component"))
  map_dfr(itens, ~ tibble::tibble(
    fonte = "crossref",
    doi = tolower(.x$DOI %||% NA_character_),
    openalex_id = NA_character_,
    titulo_cand = as.character(primeiro(.x$title) %||% NA),
    ano_cand = as.integer(primeiro(primeiro(.x$issued$`date-parts`)) %||% NA),
    sobrenome_cand = as.character(primeiro(.x$author)$family %||% NA),
    periodico_cand = as.character(primeiro(.x$`container-title`) %||% NA),
    oa_url = NA_character_))
}

#' OpenAlex pelo titulo. Pega obra sem DOI que a OpenAlex conhece por outra
#' via (SciELO, repositorios), e ja traz a melhor localizacao aberta.
candidatos_openalex <- function(titulo, email, n = 5) {
  # virgula e dois-pontos quebram a sintaxe de filter da OpenAlex
  q <- str_squish(str_replace_all(titulo, "[,:;|]", " "))
  # chave gratuita da OpenAlex (~/.Renviron): sem ela a cota diaria e de
  # ~100 buscas e acabou no meio da rodada de 02/10/2026; com ela, 10x mais
  chave <- Sys.getenv("OPENALEX_API_KEY", "")
  js <- req_api("https://api.openalex.org/works",
                c(list(filter = paste0("title.search:", q), `per-page` = n, mailto = email),
                  if (nzchar(chave)) list(api_key = chave)))
  map_dfr(js$results %||% list(), ~ tibble::tibble(
    fonte = "openalex",
    doi = tolower(sub("^https://doi.org/", "", .x$doi %||% NA_character_)),
    openalex_id = sub("^https://openalex.org/", "", .x$id %||% NA_character_),
    titulo_cand = .x$title %||% NA_character_,
    ano_cand = as.integer(.x$publication_year %||% NA),
    sobrenome_cand = {
      nome <- as.character(primeiro(.x$authorships)$author$display_name %||% NA)
      if (is.na(nome)) NA_character_ else tail(str_split(nome, " ")[[1]], 1)
    },
    periodico_cand = .x$primary_location$source$display_name %||% NA_character_,
    oa_url = .x$best_oa_location$pdf_url %||% .x$best_oa_location$landing_page_url %||% NA_character_))
}

#' Unpaywall: ha copia aberta do DOI? Erro sai como "erro", nao como fechado.
consultar_unpaywall <- function(doi, email) {
  r <- tryCatch(req_api(paste0("https://api.unpaywall.org/v2/", doi), list(email = email), pausa = 0.2),
                error = function(e) e)
  if (inherits(r, "error"))
    return(tibble::tibble(oa_status = "erro", oa_pdf = NA_character_, oa_host = NA_character_,
                          erro_oa = conditionMessage(r)))
  tibble::tibble(oa_status = r$oa_status %||% NA_character_,
                 oa_pdf = r$best_oa_location$url_for_pdf %||% r$best_oa_location$url %||% NA_character_,
                 oa_host = r$best_oa_location$host_type %||% NA_character_,
                 erro_oa = NA_character_)
}

# ---- orquestracao -----------------------------------------------------------

#' Referencias distintas da BT 5. A mesma obra aparece com strings diferentes
#' (775 strings para 683 titulos), entao a chave e titulo normalizado + ano.
referencias_distintas <- function(refs) {
  refs |>
    filter(!is.na(titulo)) |>
    mutate(chave = paste(normalizar_titulo(titulo), ano)) |>
    group_by(chave) |>
    summarise(autor = first(autor), ano = first(ano), titulo = first(titulo),
              periodico = first(periodico), raw = first(raw),
              doi_bt5 = first(na.omit(na_if(tolower(doi), ""))) %||% NA_character_,
              n_especies = n_distinct(taxon_id), .groups = "drop")
}

#' Procura cada referencia nas duas fontes. Uma linha por referencia, com o
#' melhor candidato e o veredito. `status_busca` = "ok" ou "erro".
#' `fontes`: a OpenAlex tem cota diaria; da para rodar so o Crossref e deixar
#' a OpenAlex para as referencias que sobrarem.
resolver_referencias <- function(refs, email, progresso = TRUE,
                                 fontes = c("crossref", "openalex")) {
  map_dfr(seq_len(nrow(refs)), function(i) {
    r <- refs[i, ]
    if (progresso) message(i, "/", nrow(refs), "  ", substr(r$titulo, 1, 60))
    cands <- tryCatch(
      bind_rows(if ("crossref" %in% fontes) candidatos_crossref(r$raw %||% r$titulo, email),
                if ("openalex" %in% fontes) candidatos_openalex(r$titulo, email)),
      error = function(e) e)
    if (inherits(cands, "error"))
      return(mutate(r, status_busca = "erro", erro = conditionMessage(cands), veredito = NA_character_))
    m <- melhor_candidato(cands, r$titulo, r$ano, r$autor)
    if (nrow(m) == 0)
      return(mutate(r, status_busca = "ok", erro = NA_character_, veredito = "sem_casamento",
                    fontes = paste(fontes, collapse = "+")))
    # outra fonte achou a mesma obra? guarda o id da OpenAlex e o link aberto.
    # Exige titulo quase identico e mesmo ano: "The tadpole of Scinax X" e
    # "The tadpole of Scinax Y" sao parecidos o bastante para enganar.
    mesma <- cands |>
      mutate(sim = similaridade_titulo(r$titulo, titulo_cand)) |>
      filter(sim >= 0.95, ano_cand %in% r$ano)
    bind_cols(r, select(m, -dano)) |>
      mutate(doi = doi %||% NA_character_,
             doi = coalesce(doi, first(na.omit(mesma$doi)) %||% NA_character_),
             openalex_id = coalesce(openalex_id, first(na.omit(mesma$openalex_id)) %||% NA_character_),
             oa_url = coalesce(oa_url, first(na.omit(mesma$oa_url)) %||% NA_character_),
             veredito = decidir_casamento(sim, ano, ano_cand, autor_ok),
             status_busca = "ok", erro = NA_character_, fontes = paste(fontes, collapse = "+"))
  })
}

# ---- BHL ----------------------------------------------------------------------
#
# Para a literatura antiga sem DOI no Crossref (02/10/2026: 181 das 251 obras
# sem casamento sao de antes de 2000). A busca do BHL devolve dois tipos:
# "Part" (artigo segmentado, com titulo, autores, data e as vezes DOI
# 10.5962/p.*) e "Item" (o volume inteiro onde o texto aparece). Part casa
# pelo titulo como no Crossref. Item nunca e aceito sozinho: no maximo vira
# "volume_provavel", quando o periodico e o ano batem, para alguem achar a
# pagina. Chave em ~/.Renviron (BHL_API_KEY); a API recusa chamada sem chave.

#' Item do BHL e o volume certo? Periodico parecido e ano a 1 de distancia.
decidir_volume_bhl <- function(sim_periodico, ano_ref, ano_item) {
  dano <- abs(as.integer(ano_ref) - suppressWarnings(as.integer(substr(ano_item, 1, 4))))
  if_else(!is.na(sim_periodico) & sim_periodico >= 0.6 & !is.na(dano) & dano <= 1,
          "volume_provavel", "sem_casamento")
}

candidatos_bhl <- function(titulo, chave) {
  js <- req_api("https://www.biodiversitylibrary.org/api3",
                list(op = "PublicationSearch", searchterm = titulo, searchtype = "F",
                     format = "json", apikey = chave))
  if (!identical(js$Status, "ok")) stop("BHL: ", js$ErrorMessage %||% "status nao ok")
  map_dfr(js$Result %||% list(), ~ tibble::tibble(
    bhl_tipo = .x$BHLType %||% NA_character_,
    bhl_id = .x$PartID %||% .x$ItemID %||% NA_character_,
    bhl_url = .x$PartUrl %||% .x$ItemUrl %||% NA_character_,
    titulo_cand = .x$Title %||% NA_character_,
    ano_cand_txt = .x$PublicationDate %||% NA_character_,
    sobrenome_cand = sub(",.*$", "", as.character(primeiro(.x$Authors)$Name %||% NA))))
}

metadados_parte_bhl <- function(id, chave) {
  js <- req_api("https://www.biodiversitylibrary.org/api3",
                list(op = "GetPartMetadata", id = id, pages = "f", names = "f",
                     format = "json", apikey = chave))
  x <- primeiro(js$Result)
  if (is.null(x)) stop("BHL: parte ", id, " sem metadados")
  tibble::tibble(ano_cand = suppressWarnings(as.integer(substr(x$Date %||% NA, 1, 4))),
                 doi_bhl = tolower(x$Doi %||% NA_character_),
                 sobrenome_cand = sub(",.*$", "", as.character(primeiro(x$Authors)$Name %||% NA)))
}

#' Uma linha por referencia: melhor Part (com veredito como no Crossref) ou,
#' sem Part boa, o Item de volume provavel. Erro sai como "erro".
resolver_bhl <- function(refs, chave = Sys.getenv("BHL_API_KEY", ""), progresso = TRUE) {
  if (!nzchar(chave)) stop("BHL_API_KEY vazia em ~/.Renviron")
  map_dfr(seq_len(nrow(refs)), function(i) {
    r <- refs[i, c("chave", "autor", "ano", "titulo", "periodico")]
    if (progresso) message(i, "/", nrow(refs), "  ", substr(r$titulo, 1, 60))
    out <- tryCatch({
      cands <- candidatos_bhl(r$titulo, chave)
      # busca sem resultado devolve tibble sem colunas; e "nada", nao erro
      if (nrow(cands) == 0) return(bind_cols(r, tibble::tibble(bhl_veredito = "sem_casamento")))
      partes <- filter(cands, bhl_tipo == "Part") |>
        mutate(sim = similaridade_titulo(r$titulo, titulo_cand)) |> arrange(desc(sim))
      if (nrow(partes) && partes$sim[1] >= 0.75) {
        p <- slice(partes, 1)
        m <- metadados_parte_bhl(p$bhl_id, chave)
        tibble::tibble(bhl_tipo = "Part", bhl_url = p$bhl_url, bhl_titulo = p$titulo_cand,
                       bhl_ano = m$ano_cand, bhl_doi = m$doi_bhl, bhl_sim = p$sim,
                       bhl_autor_ok = autor_confere(r$autor, coalesce(m$sobrenome_cand, p$sobrenome_cand)),
                       bhl_veredito = decidir_casamento(p$sim, r$ano, m$ano_cand, bhl_autor_ok))
      } else {
        itens <- filter(cands, bhl_tipo == "Item") |>
          mutate(sim_per = similaridade_titulo(r$periodico, titulo_cand),
                 v = decidir_volume_bhl(sim_per, r$ano, ano_cand_txt)) |>
          filter(v == "volume_provavel") |> arrange(desc(sim_per))
        if (nrow(itens)) tibble::tibble(bhl_tipo = "Item", bhl_url = itens$bhl_url[1],
                                        bhl_titulo = itens$titulo_cand[1],
                                        bhl_ano = suppressWarnings(as.integer(substr(itens$ano_cand_txt[1], 1, 4))),
                                        bhl_doi = NA_character_, bhl_sim = itens$sim_per[1],
                                        bhl_autor_ok = NA, bhl_veredito = "volume_provavel")
        else tibble::tibble(bhl_veredito = "sem_casamento")
      }
    }, error = function(e) tibble::tibble(bhl_veredito = NA_character_, bhl_erro = conditionMessage(e)))
    bind_cols(r, out)
  })
}

# ---- consolidacao -------------------------------------------------------------

#' Veredito final de uma referencia a partir das tres fontes. Ordem: Crossref
#' aceito; OpenAlex aceito (mas se o Crossref tinha outro DOI em "revisar", e
#' conflito e vai para revisao); BHL aceito; qualquer "revisar"; volume
#' provavel do BHL; erro; sem casamento. `erro`: alguma fonte falhou. Erro so
#' ganha de "sem casamento": fonte que falhou nao prova que a obra nao existe
#' (principio 1).
consolidar_veredito <- function(v_cr, doi_cr, v_oa, doi_oa, v_bhl, erro = FALSE) {
  conflito <- v_oa %in% "aceito" & v_cr %in% "revisar" & !is.na(doi_cr) & !is.na(doi_oa) & doi_cr != doi_oa
  case_when(
    v_cr %in% "aceito" ~ "aceito:crossref",
    v_oa %in% "aceito" & !conflito ~ "aceito:openalex",
    v_bhl %in% "aceito" ~ "aceito:bhl",
    conflito | v_cr %in% "revisar" | v_oa %in% "revisar" | v_bhl %in% "revisar" ~ "revisar",
    v_bhl %in% "volume_provavel" ~ "volume_provavel",
    erro %in% TRUE ~ "erro",
    TRUE ~ "sem_casamento")
}

#' O DOI esta registrado? API de handles do doi.org: responseCode 1 = existe,
#' 100 = nao encontrado. Por que (02/10/2026): a OpenAlex deu para "Frogs of
#' Boraceia" o DOI 10.11606/issn.2176-7793.v31i4p231-410, que a revista
#' exibe mas nunca registrou (404 no doi.org). Todo DOI passa por aqui antes
#' de sair do pipeline. Erro de rede devolve NA, nunca FALSE (principio 1).
#' O doi.org responde 404 com corpo {"responseCode":100} para handle que nao
#' existe: o 404 e a resposta, nao erro, e nao pode passar pelo req_api().
doi_existe <- function(dois, pausa = 0.15) {
  map_lgl(dois, function(d) {
    Sys.sleep(pausa)
    r <- tryCatch(
      request(paste0("https://doi.org/api/handles/", d)) |>
        req_user_agent("girinos-traits (conferencia de DOI)") |>
        req_error(is_error = function(resp) !resp_status(resp) %in% c(200, 404)) |>
        req_retry(max_tries = 3, max_seconds = 60) |>
        req_perform() |>
        resp_body_json(),
      error = function(e) NULL)
    if (is.null(r) || is.null(r$responseCode)) return(NA)
    identical(as.integer(r$responseCode), 1L)
  })
}
