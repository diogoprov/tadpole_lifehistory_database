# Correcao da planilha do livro, aplicando as decisoes aprovadas pelo grupo.
#
# Diferente de R/migrar_planilha.R, que so reestrutura, este script ALTERA
# valores. Por isso, cada celula alterada gera uma linha em
# correcoes_aplicadas.csv, com o valor antes, o valor depois e a regra que a
# mudou. Nada muda sem deixar rastro.
#
# Regras aplicadas (aprovadas pelos co-autores em set/2026):
#   R1 autofill      serie consecutiva -> todos recebem o menor valor da serie
#                    (Denise: "o 1o valor da serie e o correto")
#   R2 identificador eventID de citacao livre -> DOI, conforme inst/eventid_doi.csv
#   R3 traco         sinal de menos U+2212 -> hifen
#   R4 espacos       apara pontas, colapsa espacos repetidos e quebras de linha
#   R5 autoria       scientificName -> nome binomial + scientificNameAuthorship
#
# Uso:
#   source("R/corrigir_planilha.R")
#   corrigir("Planilha Amanda NOVA girinos livro.xlsx",
#            "Planilha_girinos_corrigida.xlsx", "dwca")

library(readxl)
library(writexl)
library(dplyr)
library(purrr)
library(stringr)

MENOS <- "−"   # U+2212, o sinal de menos que o Word/Excel insere

registro <- new.env(parent = emptyenv())

#' Registra toda mudanca, inclusive celula vazia que foi preenchida e celula
#' preenchida que foi esvaziada. Sem tratar o NA aqui, uma regra que preenche
#' vazio (R11) mudaria a planilha sem deixar rastro, que e exatamente o que
#' este script promete nao fazer.
anotar <- function(aba, coluna, linha, antes, depois, regra) {
  a <- antes %|% ""; b <- depois %|% ""
  sel <- a != b
  if (!any(sel)) return(invisible(NULL))
  registro$log <- bind_rows(registro$log, tibble::tibble(
    aba = aba, coluna = coluna, linha = linha[sel],
    valor_antes = if_else(is.na(antes[sel]), "(vazio)", antes[sel]),
    valor_depois = if_else(is.na(depois[sel]), "(vazio)", depois[sel]),
    regra = regra))
  invisible(NULL)
}

# ---- R1: autofill -----------------------------------------------------------

#' Devolve o vetor com cada serie consecutiva colapsada no seu menor valor.
colapsar_autofill <- function(v) {
  m <- str_match(as.character(v), "^(.*?)(\\d+)\\s*$")
  prefixo <- m[, 2]; num <- suppressWarnings(as.integer(m[, 3]))
  ok <- !is.na(num) & !is.na(prefixo) & prefixo != ""
  if (!any(ok)) return(v)

  grupos <- split(which(ok), prefixo[ok])
  out <- v
  for (idx in grupos) {
    n <- sort(unique(num[idx]))
    if (length(n) >= 3 && all(diff(n) == 1)) {
      base <- v[idx][which.min(num[idx])]
      out[idx] <- base
    }
  }
  out
}

aplicar_autofill <- function(d, aba, colunas) {
  for (col in intersect(colunas, names(d))) {
    antes <- d[[col]]
    depois <- colapsar_autofill(antes)
    anotar(aba, col, d$.linha, antes, depois, "R1_autofill")
    d[[col]] <- depois
  }
  d
}

# ---- R2: identificador da obra ---------------------------------------------

#' A chave do mapa e comparada ja normalizada: a mesma citacao aparece com
#' sinal de menos, meia-risca ou hifen conforme quem digitou, e sem isso o
#' casamento falha justamente nas citacoes antigas.
chave_id <- function(x) {
  str_squish(x) |>
    str_replace_all(fixed(MENOS), "-") |>
    str_replace_all("(?<=[0-9])–(?=[0-9])", "-")
}

aplicar_doi <- function(d, aba, mapa, colunas = "eventID") {
  for (col in intersect(colunas, names(d))) {
    antes <- d[[col]]
    chave <- chave_id(antes)
    i <- match(chave, chave_id(mapa$eventID_original))
    depois <- if_else(!is.na(i), mapa$identificador_novo[i], antes)
    anotar(aba, col, d$.linha, antes, depois, "R2_identificador")
    d[[col]] <- depois
  }
  d
}

# ---- R3 e R4: traco e espacos ----------------------------------------------

#' Rodam em todas as colunas de texto. O traco so troca o sinal de menos
#' (U+2212); a meia-risca (en dash) fica, porque e pontuacao legitima em
#' intervalo de paginas.
aplicar_traco_espacos <- function(d, aba) {
  cols <- setdiff(names(d)[map_lgl(d, is.character)], ".linha")
  for (col in cols) {
    antes <- d[[col]]

    t1 <- antes %|% NA_character_ |>
      str_replace_all(fixed(MENOS), "-") |>
      # meia-risca entre digitos e intervalo numerico: 8-9, 745-754, 35-38.
      # Fora disso (citacao de autoria) ela fica como esta.
      str_replace_all("(?<=[0-9])–(?=[0-9])", "-")
    anotar(aba, col, d$.linha, antes, t1, "R3_traco")

    t2 <- str_squish(t1)   # apara pontas, colapsa espacos e quebras de linha
    anotar(aba, col, d$.linha, t1, t2, "R4_espacos")

    d[[col]] <- t2
  }
  d
}

`%|%` <- function(x, y) ifelse(is.na(x), y, x)

# ---- R5: autoria fora do nome ----------------------------------------------

#' Binomial = as duas primeiras palavras. O resto e autoria.
#' Confirmado na planilha: nenhum nome tem subespecie, cf., aff. ou sp., e os
#' 82 nomes de duas palavras simplesmente nao trazem autoria.
separar_autoria <- function(nome) {
  n <- str_squish(nome)
  # autoria identica repetida, como "(Cope, 1862) (Cope, 1862)"
  n <- str_replace(n, "(\\([^)]+\\))\\s*\\1", "\\1")
  binomial <- str_extract(n, "^\\S+\\s+\\S+")
  autoria <- str_trim(str_remove(n, "^\\S+\\s+\\S+"))
  list(nome = if_else(is.na(binomial), n, binomial),
       autoria = if_else(is.na(autoria) | autoria == "", NA_character_, autoria))
}

aplicar_autoria <- function(d, aba) {
  if (!"scientificName" %in% names(d)) return(d)
  antes <- d$scientificName
  sp <- separar_autoria(antes)
  anotar(aba, "scientificName", d$.linha, antes, sp$nome, "R5_autoria")
  d$scientificName <- sp$nome
  # coluna nova, logo depois do nome
  pos <- which(names(d) == "scientificName")
  d <- tibble::add_column(d, scientificNameAuthorship = sp$autoria, .after = pos)
  d
}

# ---- R11: linhas de continuacao na GeneralInformation -----------------------

#' Ha linhas que trazem so o numero de tombo, sem eventID e sem taxonID: sao
#' vouchers adicionais da mesma especie e da mesma fonte da linha de cima.
#' Denise confirmou em 21/09/2026: "e sempre o anterior".
#'
#' Preenche para baixo APENAS eventID, taxonID e bibliographicCitation, e
#' apenas em celula vazia. Municipio, estado e bioma ficam como estao, porque
#' a localidade de cada tombo e justamente o que ainda esta sendo levantado.
aplicar_continuacao <- function(d, aba,
                                colunas = c("eventID", "taxonID", "bibliographicCitation")) {
  if (!identical(aba, "GeneralInformation")) return(d)
  if (!"collectionCode" %in% names(d)) return(d)

  vazio <- function(x) is.na(x) | str_squish(x %|% "") == ""
  tem_tombo <- !vazio(d$collectionCode)

  for (col in intersect(colunas, names(d))) {
    antes <- d[[col]]
    depois <- antes
    ultimo <- NA_character_
    for (k in seq_along(depois)) {
      if (!vazio(depois[k])) {
        ultimo <- depois[k]
      } else if (tem_tombo[k] && !is.na(ultimo)) {
        depois[k] <- ultimo
      }
    }
    anotar(aba, col, d$.linha, antes, depois, "R11_continuacao")
    d[[col]] <- depois
  }
  d
}

# ---- leitura dos arquivos de decisao ---------------------------------------

#' Os csv de decisao sao editados a mao, normalmente no Excel. O Excel em
#' portugues salva CSV com ponto e virgula, e o leitor padrao do readr entao
#' devolve uma coluna so, com o cabecalho inteiro dentro dela. Aqui o separador
#' e detectado pela primeira linha, e as colunas obrigatorias sao conferidas
#' com uma mensagem que diz o que foi encontrado.
ler_csv_flex <- function(caminho, obrigatorias = character()) {
  linha1 <- readLines(caminho, n = 1, warn = FALSE)
  delim <- if (str_count(linha1, ";") > str_count(linha1, ",")) ";" else ","
  d <- readr::read_delim(caminho, delim = delim, comment = "#",
                         trim_ws = TRUE, show_col_types = FALSE,
                         progress = FALSE)
  falta <- setdiff(obrigatorias, names(d))
  if (length(falta) > 0) {
    stop("faltam colunas em ", basename(caminho), ": ",
         paste(falta, collapse = ", "),
         "\n  colunas encontradas: ", paste(names(d), collapse = ", "),
         "\n  separador detectado: '", delim, "'",
         "\n  se o arquivo veio do Excel, salve como CSV UTF-8 e mantenha o cabecalho.",
         call. = FALSE)
  }
  d
}

# ---- orquestracao -----------------------------------------------------------

# ---- R6: identificador com espaco -------------------------------------------

#' "Anura 3" e "Anura3" sao o mesmo taxon. So unifica quando a versao sem
#' espaco ja existe na planilha: assim a regra nunca inventa um identificador.
aplicar_id_espaco <- function(d, aba, ids_validos) {
  if (!"taxonID" %in% names(d)) return(d)
  antes <- d$taxonID
  sem <- str_remove_all(antes %|% "", " ")
  depois <- if_else(!is.na(antes) & str_detect(antes, " ") & sem %in% ids_validos,
                    sem, antes)
  anotar(aba, "taxonID", d$.linha, antes, depois, "R6_id_espaco")
  d$taxonID <- depois
  d
}

# ---- R7: comentario dentro de celula de dado --------------------------------

PADRAO_COMENTARIO <- "(?i)acho que|n[aã]o se aplica|conferir com|ver com"

aplicar_comentarios <- function(d, aba,
                                colunas = c("measurementAccuracy", "measurementUnit",
                                            "measurementMethod")) {
  for (col in intersect(colunas, names(d))) {
    antes <- d[[col]]
    depois <- if_else(!is.na(antes) & str_detect(antes, PADRAO_COMENTARIO),
                      NA_character_, antes)
    anotar(aba, col, d$.linha, antes, depois, "R7_comentario")
    d[[col]] <- depois
  }
  d
}

# ---- R8: taxonID malformado -------------------------------------------------

#' Identificador que nao existe na aba Taxonomy. Duas vias de conserto, nessa
#' ordem: (i) o scientificName da linha aponta para um unico taxonID valido;
#' (ii) o identificador esta a no maximo duas edicoes de um unico id valido.
#' Se nenhuma das duas resolver de forma unica, a celula fica como esta.
#' So o binomio, sem autoria: a autoria varia de aba para aba e atrapalharia
#' o casamento por nome.
binomio <- function(x) str_extract(str_squish(x), "^\\S+\\s+\\S+")

resolver_id_malformado <- function(id, nome, ids_validos, nome_para_id) {
  if (is.na(id) || id %in% ids_validos) return(NA_character_)
  if (!is.na(nome)) {
    cand <- nome_para_id[[binomio(nome) %|% ""]]
    if (!is.null(cand) && length(cand) == 1) return(cand)
  }
  # troca de duas letras vizinhas: "Anuar64" -> "Anura64". E o erro de digitacao
  # mais comum, e por isso tem prioridade sobre a distancia de edicao geral,
  # que aqui devolveria cinco candidatos igualmente proximos.
  tr <- transposicoes(id)
  perto_tr <- intersect(tr, ids_validos)
  if (length(perto_tr) == 1) return(perto_tr)

  d <- utils::adist(id, ids_validos)[1, ]
  perto <- ids_validos[d <= 2]
  if (length(perto) == 1) return(perto)
  NA_character_
}

#' Todas as variantes do texto com um par de caracteres vizinhos trocado.
transposicoes <- function(x) {
  ch <- strsplit(x, "")[[1]]
  if (length(ch) < 2) return(character())
  map_chr(seq_len(length(ch) - 1), function(i) {
    y <- ch; y[c(i, i + 1)] <- y[c(i + 1, i)]; paste(y, collapse = "")
  })
}

aplicar_id_malformado <- function(d, aba, ids_validos, nome_para_id) {
  if (!"taxonID" %in% names(d)) return(d)
  antes <- d$taxonID
  nome <- if ("scientificName" %in% names(d)) d$scientificName else NA_character_
  novo <- map2_chr(antes, nome, ~ resolver_id_malformado(.x, .y, ids_validos, nome_para_id))
  depois <- if_else(is.na(novo), antes, novo)
  anotar(aba, "taxonID", d$.linha, antes, depois, "R8_id_malformado")
  d$taxonID <- depois
  d
}

# ---- R10: bloco de medidas sob o taxonID errado -----------------------------

#' Acontece quando um bloco inteiro de caracteres de uma especie foi digitado
#' sob o identificador da especie vizinha na planilha. Nao e erro de grafia:
#' o nome esta certo, o identificador e que esta errado, e corrigir o nome
#' destruiria o dado.
#'
#' A regra NAO adivinha nada. Ela aplica exatamente as linhas declaradas em
#' inst/repontar_taxonid.csv, que o grupo preenche depois de olhar a evidencia
#' (fonte, estagio e conjunto de caracteres do bloco).
aplicar_repontar <- function(d, aba, repontar) {
  if (is.null(repontar) || nrow(repontar) == 0) return(d)
  if (!all(c("taxonID", "scientificName", "eventID") %in% names(d))) return(d)

  alvo <- filter(repontar, aba == !!aba)
  if (nrow(alvo) == 0) return(d)

  chave_linha <- paste(str_squish(d$taxonID), binomio(d$scientificName),
                       chave_id(d$eventID), sep = "\r")
  chave_alvo <- paste(str_squish(alvo$taxonID_atual), binomio(alvo$scientificName),
                      chave_id(alvo$eventID), sep = "\r")
  i <- match(chave_linha, chave_alvo)

  antes <- d$taxonID
  depois <- if_else(!is.na(i), alvo$taxonID_novo[i], antes)
  anotar(aba, "taxonID", d$.linha, antes, depois, "R10_repontar")
  d$taxonID <- depois
  d
}

# ---- R9: grafia do nome, decidida fora -------------------------------------

#' Aplica as decisoes de nomenclatura de inst/nomenclatura_decisoes.csv.
#' O arquivo e preenchido pela conferencia na ASW (ver R/nomenclatura_asw.R).
#' Sem arquivo, ou com arquivo vazio, esta regra nao faz nada: o script nunca
#' escolhe grafia de nome por conta propria.
aplicar_nomenclatura <- function(d, aba, decisoes) {
  if (is.null(decisoes) || nrow(decisoes) == 0) return(d)
  if (!"scientificName" %in% names(d)) return(d)
  i <- match(str_squish(d$taxonID), str_squish(decisoes$taxonID))
  antes <- d$scientificName
  depois <- if_else(!is.na(i), decisoes$nome_aceito[i], antes)
  anotar(aba, "scientificName", d$.linha, antes, depois, "R9_nomenclatura")
  d$scientificName <- depois
  if ("scientificNameAuthorship" %in% names(d) && "autoria_aceita" %in% names(decisoes)) {
    a0 <- d$scientificNameAuthorship
    a1 <- if_else(!is.na(i) & !is.na(decisoes$autoria_aceita[i]),
                  decisoes$autoria_aceita[i], a0)
    anotar(aba, "scientificNameAuthorship", d$.linha, a0, a1, "R9_nomenclatura")
    d$scientificNameAuthorship <- a1
  }
  d
}

#' R12 - nome da metrica da dieta.
#'
#' A mesma medida aparecia com tres grafias ("number_itens", "number_of_itens",
#' "percentage_of_itens"). Denise propos padronizar em 29/09/2026, e os dados
#' confirmam que a metrica e composicao: somando os itens de cada amostra
#' (especie x artigo x corpo d'agua), 27 das 28 amostras ficam entre 82% e 101%
#' e nenhuma passa de 101%. Frequencia de ocorrencia nao se comportaria assim.
#' Grafia em ingles, como o resto da planilha.
METRICA_DIETA <- "percentage_of_items"

aplicar_metrica_dieta <- function(d, aba) {
  if (aba != "Diet_DWC" || !"measurementValue" %in% names(d)) return(d)
  antes <- d$measurementValue
  alvo <- c("number_itens", "number_of_itens", "percentage_of_itens")
  depois <- if_else(str_squish(antes %|% "") %in% alvo, METRICA_DIETA, antes)
  anotar(aba, "measurementValue", d$.linha, antes, depois, "R12_metrica_dieta")
  d$measurementValue <- depois
  d
}

#' R13 - hidroperiodo fora da coluna MeasurementOrFact.
#'
#' MeasurementOrFact e o nome da CLASSE do padrao, nao um campo de dado. Na aba
#' Diet ela guardava "Perm", "Temp" e "temporary pond", que sao o hidroperiodo
#' do corpo d'agua. No SAJH 2011 isso distingue duas amostras da mesma especie
#' no mesmo artigo (cada grupo soma 82-97% sozinho), entao nao e redundancia:
#' sem essa coluna as duas amostras viram uma so, somando ~180%.
#'
#' A regra move a informacao para o eventID, dando a cada amostra identificador
#' proprio, e esvazia a coluna. O vocabulario e o mesmo que a aba Habitat ja usa
#' em HabitatHydroperiod (permanent / temporary).
#'
#' Isto e um remendo incremental, nao o desenho final: o certo seria um core de
#' Event. Ver dwca/LEIA-ME.md.
HIDROPERIODO <- c(Perm = "permanent", Temp = "temporary",
                  `temporary pond` = "temporary")

aplicar_hidroperiodo <- function(d, aba) {
  if (aba != "Diet_DWC") return(d)
  if (!all(c("MeasurementOrFact", "eventID") %in% names(d))) return(d)
  chave <- str_squish(d$MeasurementOrFact %|% "")
  hidro <- unname(HIDROPERIODO[chave])
  if (all(is.na(hidro))) return(d)

  ev0 <- d$eventID
  ev1 <- if_else(!is.na(hidro) & !is.na(ev0), paste0(ev0, ":", hidro), ev0)
  anotar(aba, "eventID", d$.linha, ev0, ev1, "R13_hidroperiodo")
  d$eventID <- ev1

  m0 <- d$MeasurementOrFact
  m1 <- if_else(!is.na(hidro), NA_character_, m0)
  anotar(aba, "MeasurementOrFact", d$.linha, m0, m1, "R13_hidroperiodo")
  d$MeasurementOrFact <- m1
  d
}

#' R14 - a coluna dietItens sai.
#'
#' Ela dizia "% individuals" nas 262 linhas, o que contradiz a metrica: se o
#' numero fosse a fracao de girinos com cada item, nao haveria razao para somar
#' 100 por amostra, e normalmente passaria disso, porque o mesmo girino tem
#' varios itens. A metrica correta ja vai em measurementValue (R12), entao o
#' rotulo aqui so tem como atrapalhar quem for preencher linha nova.
aplicar_diet_itens <- function(d, aba) {
  if (aba != "Diet_DWC" || !"dietItens" %in% names(d)) return(d)
  antes <- d$dietItens
  depois <- NA_character_
  anotar(aba, "dietItens", d$.linha, antes, rep(NA_character_, nrow(d)),
         "R14_diet_itens")
  d$dietItens <- NA_character_
  d
}

#' R15 - erros de digitacao no valor do caractere.
#'
#' Cada par vem de inst/ortografia_traits.csv, conferido um a um: so entram
#' grafias que NAO sao palavra ("truncatedd", "anterovventral", "possterodorsal")
#' e artefatos de forma (caixa alta, espaco sobrando, "o" no lugar de grau).
#' Variantes que sao palavra legitima ("aggregate" x "aggregated", "alternate" x
#' "alternated", "nectonic" x "nektonic") ficam de fora de proposito: aquilo e
#' decisao de vocabulario do grupo, nao erro de digitacao.
#'
#' tooth_row_formulae nao entra em nenhuma hipotese. Ali "2(2)/4(1)" e
#' "2(2)/3(1)" diferem por um caractere e sao formulas diferentes; juntar seria
#' inventar dado.
aplicar_ortografia <- function(d, aba, orto) {
  if (is.null(orto) || nrow(orto) == 0) return(d)
  # na aba Habitat o caractere e a propria coluna; nas outras, o codigo esta em
  # measurementType e o valor em measurementValue. O teste do Habitat vem
  # ANTES da exigencia de measurementValue: essa aba nao tem essa coluna, e com
  # o guard na frente as 25 grafias dela passavam batido.
  if (aba == "Habitat") {
    for (cn in intersect(unique(orto$trait), names(d))) {
      sub <- filter(orto, trait == cn)
      i <- match(d[[cn]], sub$errado)
      antes <- d[[cn]]
      depois <- if_else(!is.na(i), sub$correto[i], antes)
      anotar(aba, cn, d$.linha, antes, depois, "R15_ortografia")
      d[[cn]] <- depois
    }
    return(d)
  }
  if (!all(c("measurementType", "measurementValue") %in% names(d))) return(d)
  i <- match(paste(d$measurementType, d$measurementValue),
             paste(orto$trait, orto$errado))
  antes <- d$measurementValue
  depois <- if_else(!is.na(i), orto$correto[i], antes)
  anotar(aba, "measurementValue", d$.linha, antes, depois, "R15_ortografia")
  d$measurementValue <- depois
  d
}

#' R16 - formula dentaria que o Excel converteu em data ou em divisao.
#'
#' Digitar "2/3" numa celula de formato geral faz o Excel gravar 02/03 como
#' data, ou 0,6667 como conta. Os 23 registros atingidos tinham um digito de
#' cada lado da barra, entao a volta e univoca. O mapa esta em
#' inst/ltrf_excel.csv, junto com a conferencia contra o artigo de origem.
#'
#' So age em tooth_row_formulae: um 46083 em outra coluna pode ser data de
#' verdade.
aplicar_ltrf_excel <- function(d, aba, mapa) {
  if (is.null(mapa) || nrow(mapa) == 0) return(d)
  if (!all(c("measurementType", "measurementValue") %in% names(d))) return(d)
  sel <- d$measurementType %in% "tooth_row_formulae"
  if (!any(sel, na.rm = TRUE)) return(d)
  i <- match(str_squish(d$measurementValue %|% ""), str_squish(mapa$valor_planilha))
  antes <- d$measurementValue
  depois <- if_else(sel & !is.na(i), mapa$ltrf[i], antes)
  anotar(aba, "measurementValue", d$.linha, antes, depois, "R16_ltrf_excel")
  d$measurementValue <- depois
  d
}

#' R17 - correcoes de uma celula so, declaradas em inst/correcoes_pontuais.csv
#' com a evidencia. Confere valor_antes antes de escrever: se a planilha mudou
#' e a celula nao tem mais o valor esperado, para em vez de sobrescrever.
aplicar_pontuais <- function(d, aba, pontuais) {
  if (is.null(pontuais) || nrow(pontuais) == 0) return(d)
  p <- filter(pontuais, aba == !!aba, coluna %in% names(d))
  if (nrow(p) == 0) return(d)
  for (k in seq_len(nrow(p))) {
    cn <- p$coluna[k]
    j <- which(d$.linha == p$linha[k])
    if (length(j) != 1) stop("correcao pontual: linha ", p$linha[k], " nao existe em ", aba)
    atual <- str_squish(d[[cn]][j] %|% "")
    esperado <- str_squish(p$valor_antes[k] %|% "")
    if (!identical(atual, esperado)) {
      stop("correcao pontual em ", aba, " linha ", p$linha[k], ", coluna ", cn,
           ": esperava '", esperado, "' e encontrei '", atual,
           "'. A planilha mudou; confira antes de aplicar.")
    }
    antes <- d[[cn]]
    depois <- antes
    depois[j] <- p$valor_depois[k]
    anotar(aba, cn, d$.linha, antes, depois, "R17_pontual")
    d[[cn]] <- depois
  }
  d
}

#' R18 - decisoes de vocabulario do grupo (inst/vocabulario_decisoes.csv).
#'
#' Diferente da R15: ali o valor estava escrito errado; aqui esta escrito certo
#' e o grupo decidiu que a categoria e outra ("inclined" vira "sloped"), ou que
#' aquilo nao e dado ("absent" que na verdade era informacao faltante).
#'
#' taxonID vazio vale para todos os registros daquele valor; preenchido, so
#' para aquela especie. valor_novo vazio apaga a celula.
aplicar_vocabulario <- function(d, aba, decisoes) {
  if (is.null(decisoes) || nrow(decisoes) == 0) return(d)
  if (!all(c("measurementType", "measurementValue", "taxonID") %in% names(d))) return(d)
  antes <- d$measurementValue
  depois <- antes
  for (k in seq_len(nrow(decisoes))) {
    r <- decisoes[k, ]
    sel <- d$measurementType %in% r$trait & depois %in% r$valor_antigo
    if (!is.na(r$taxonID) && str_squish(r$taxonID) != "") {
      sel <- sel & str_squish(d$taxonID %|% "") == str_squish(r$taxonID)
    }
    if (!any(sel, na.rm = TRUE)) next
    depois[which(sel)] <- r$valor_novo
  }
  anotar(aba, "measurementValue", d$.linha, antes, depois, "R18_vocabulario")
  d$measurementValue <- depois
  d
}

ABAS_DADOS <- c("GeneralInformation", "Habitat", "Taxonomy",
                "Morphology_DWC", "Diet_DWC")
ABAS_EXTRA <- c("Metadata", "Nest")

corrigir <- function(entrada, saida, dir_log = "dwca",
                     mapa_doi = "inst/eventid_doi.csv",
                     decisoes_nome = "inst/nomenclatura_decisoes.csv",
                     repontes = "inst/repontar_taxonid.csv",
                     ortografia = "inst/ortografia_traits.csv",
                     ltrf = "inst/ltrf_excel.csv",
                     pontuais_csv = "inst/correcoes_pontuais.csv",
                     vocabulario = "inst/vocabulario_decisoes.csv") {
  registro$log <- NULL
  dir.create(dir_log, showWarnings = FALSE, recursive = TRUE)
  mapa <- ler_csv_flex(mapa_doi, c("eventID_original", "identificador_novo"))
  decisoes <- if (file.exists(decisoes_nome)) {
    ler_csv_flex(decisoes_nome, c("taxonID", "nome_aceito")) |>
      # o valor digitado a mao costuma vir com espaco sobrando, e a R9 roda
      # depois da limpeza de espacos: sem aparar aqui, o espaco volta pra base
      mutate(across(where(is.character), str_squish)) |>
      filter(!is.na(taxonID), !is.na(nome_aceito), nome_aceito != "")
  } else NULL
  repontar <- if (file.exists(repontes)) {
    ler_csv_flex(repontes, c("aba", "taxonID_atual", "taxonID_novo")) |>
      filter(!is.na(taxonID_atual), !is.na(taxonID_novo))
  } else NULL

  orto <- if (file.exists(ortografia)) {
    readr::read_csv(ortografia, comment = "#", show_col_types = FALSE) |>
      filter(!is.na(errado), !is.na(correto))
  } else NULL
  mapa_ltrf <- if (file.exists(ltrf)) {
    readr::read_csv(ltrf, comment = "#", col_types = readr::cols(.default = "c")) |>
      filter(!is.na(valor_planilha), !is.na(ltrf))
  } else NULL
  pontuais <- if (file.exists(pontuais_csv)) {
    readr::read_csv(pontuais_csv, comment = "#",
                    col_types = readr::cols(linha = "i", .default = "c")) |>
      filter(!is.na(aba), !is.na(linha), !is.na(coluna))
  } else NULL

  decisoes_voc <- if (file.exists(vocabulario)) {
    readr::read_csv(vocabulario, comment = "#",
                    col_types = readr::cols(.default = "c")) |>
      filter(!is.na(trait), !is.na(valor_antigo))
  } else NULL

  abas <- set_names(ABAS_DADOS) |> map(~ ler_aba(entrada, .x))
  antes_dim <- map(abas, dim)

  ids_validos <- map(abas, ~ str_squish(.x$taxonID)) |> unlist() |> unique()
  ids_validos <- ids_validos[!is.na(ids_validos)]

  # A coluna do codigo do caractere nasceu sem cabecalho na planilha e ganhou
  # um nome provisorio na leitura. Batiza-la de measurementType aqui evita
  # que o nome provisorio vaze para o arquivo corrigido.
  if ("MeasurementOrFact" %in% names(abas$Morphology_DWC)) {
    i <- which(names(abas$Morphology_DWC) == "MeasurementOrFact") + 1
    if (str_starts(names(abas$Morphology_DWC)[i], "col_")) {
      names(abas$Morphology_DWC)[i] <- "measurementType"
      message("Morphology_DWC: coluna sem cabecalho renomeada para measurementType")
    }
  }

  # a aba Taxonomy define quais identificadores existem; e o mapa nome -> id
  ids_taxonomy <- unique(str_squish(abas$Taxonomy$taxonID))
  ids_taxonomy <- ids_taxonomy[!is.na(ids_taxonomy)]
  nome_para_id <- abas$Taxonomy |>
    transmute(nome = binomio(scientificName), id = str_squish(taxonID)) |>
    filter(!is.na(nome), !is.na(id)) |>
    distinct() |>
    group_by(nome) |> summarise(ids = list(unique(id)), .groups = "drop")
  nome_para_id <- set_names(nome_para_id$ids, nome_para_id$nome)

  corrigidas <- imap(abas, function(d, aba) {
    d |>
      aplicar_autofill(aba, COLUNAS_IDENTIDADE) |>
      aplicar_doi(aba, mapa) |>
      aplicar_traco_espacos(aba) |>
      aplicar_id_espaco(aba, ids_validos) |>
      aplicar_id_malformado(aba, ids_taxonomy, nome_para_id) |>
      aplicar_repontar(aba, repontar) |>
      aplicar_continuacao(aba) |>
      aplicar_comentarios(aba) |>
      aplicar_autoria(aba) |>
      aplicar_nomenclatura(aba, decisoes) |>
      # as tres da dieta rodam por ultimo: a R13 escreve no eventID e precisa
      # que a R2 ja tenha trocado o rotulo antigo pelo DOI
      aplicar_metrica_dieta(aba) |>
      aplicar_hidroperiodo(aba) |>
      aplicar_diet_itens(aba) |>
      # ortografia depois da limpeza de espacos (R4), senao as grafias do CSV
      # nao casam; pontuais por ultimo, para conferir o valor ja corrigido
      aplicar_ortografia(aba, orto) |>
      aplicar_ltrf_excel(aba, mapa_ltrf) |>
      # vocabulario depois da ortografia: as decisoes sao sobre o valor ja
      # escrito corretamente
      aplicar_vocabulario(aba, decisoes_voc) |>
      aplicar_pontuais(aba, pontuais)
  })

  # verificacao 1: nenhuma linha perdida ou criada
  walk2(corrigidas, antes_dim, function(d, dim0) {
    stopifnot(nrow(d) == dim0[1])
  })

  log <- registro$log %||% tibble::tibble()
  readr::write_csv(log, file.path(dir_log, "correcoes_aplicadas.csv"), na = "")

  # verificacao 2: toda celula que mudou tem linha no log
  mudou <- map2_int(corrigidas, abas, function(novo, velho) {
    cols <- intersect(names(velho), names(novo))
    sum(map_int(cols, ~ sum(velho[[.x]] != novo[[.x]], na.rm = TRUE)))
  }) |> sum()
  if (nrow(log) < mudou) {
    stop("celulas alteradas sem registro no log: ", mudou - nrow(log))
  }

  # as abas que nao sao de dados passam intactas
  extras <- set_names(ABAS_EXTRA) |>
    map(~ suppressMessages(read_excel(entrada, sheet = .x, col_types = "text",
                                      .name_repair = "minimal")))

  limpar <- function(d) select(d, -any_of(".linha"))
  write_xlsx(c(map(corrigidas, limpar), extras), saida)

  resumo <- count(log, aba, regra, sort = TRUE)
  readr::write_csv(resumo, file.path(dir_log, "correcoes_resumo.csv"))
  list(celulas_alteradas = nrow(log), resumo = resumo, saida = saida)
}

`%||%` <- function(x, y) if (is.null(x)) y else x
