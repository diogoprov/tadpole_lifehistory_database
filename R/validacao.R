# Validacao automatica: plausibilidade, limiar calibrado por trait (item 4) e
# rastreio da fonte primaria (item 8).

library(purrr)
library(dplyr)
library(stringr)

# ---- plausibilidade ---------------------------------------------------------

checar_plausibilidade <- function(con, traits) {
  ext <- dbGetQuery(con, "SELECT * FROM extracoes WHERE status = 'bruto'") |>
    left_join(select(traits, trait_id, tipo, unidade_esperada = unidade,
                     min_plausivel, max_plausivel, valores_aceitos),
              by = "trait_id")
  if (nrow(ext) == 0) return(tibble::tibble())

  ext <- ext |> mutate(
    motivo = case_when(
      tipo == "numerico" & is.na(valor_num) ~ "numerico_sem_valor",
      tipo == "numerico" & !is.na(min_plausivel) & valor_num < min_plausivel ~ "abaixo_do_minimo",
      tipo == "numerico" & !is.na(max_plausivel) & valor_num > max_plausivel ~ "acima_do_maximo",
      tipo == "numerico" & !is.na(unidade) & !is.na(unidade_esperada) &
        normalizar(unidade) != normalizar(unidade_esperada) ~ "unidade_divergente",
      tipo == "categorico" & !map2_lgl(valor_cat, valores_aceitos,
        ~ .x %in% str_trim(str_split(.y, ";")[[1]])) ~ "categoria_fora_do_vocabulario",
      TRUE ~ NA_character_),
    # unidade divergente nao e erro: e conversao pendente (mm vs cm, h vs dia).
    # Fica marcada e vai para a fila humana, nao para a lixeira.
    novo_status = case_when(is.na(motivo) ~ "bruto",
                            motivo == "unidade_divergente" ~ "bruto",
                            TRUE ~ "rejeitado"))

  aplicar_status(con, ext)
  count(filter(ext, !is.na(motivo)), motivo)
}

aplicar_status <- function(con, ext) {
  d <- select(ext, extracao_id, novo_status, motivo)
  dbWriteTable(con, "tmp_val", d, temporary = TRUE, overwrite = TRUE)
  dbExecute(con, "
    UPDATE extracoes SET status = v.novo_status, motivo_rejeicao = v.motivo
      FROM tmp_val v WHERE extracoes.extracao_id = v.extracao_id")
  dbExecute(con, "DROP TABLE tmp_val")
}

# ---- reconciliacao dentro da obra ------------------------------------------

#' Divergencia dentro de um grupo (obra, taxon, trait): categoria diferente,
#' ignorando caixa e espaco, ou numero fora da tolerancia relativa. A mesma
#' tolerancia da calibracao e da concordancia entre revisores, para os tres
#' criterios nao discordarem entre si sobre o que e "o mesmo valor".
valores_divergem <- function(valor_num, valor_cat, tipo, tol_rel) {
  if (identical(tipo, "numerico")) {
    v <- valor_num[!is.na(valor_num)]
    if (length(v) < 2) return(FALSE)
    diff(range(v)) > tol_rel * mean(abs(v))
  } else {
    v <- unique(tolower(trimws(valor_cat[!is.na(valor_cat)])))
    length(v) > 1
  }
}

#' Parte pura: recebe as extracoes brutas com a coluna `tipo` do trait e
#' devolve as mesmas linhas com `novo_status` e `motivo`. Separada do banco
#' para poder ser testada sem DuckDB, sem API e sem GROBID.
decidir_reconciliacao <- function(ext, tol_rel = 0.05) {
  ext |>
    arrange(desc(confianca), extracao_id) |>
    group_by(obra_id, taxon_id, trait_id) |>
    mutate(
      n_no_grupo = n(),
      divergem = valores_divergem(valor_num, valor_cat, first(tipo), tol_rel),
      novo_status = case_when(n_no_grupo == 1   ~ "bruto",
                              divergem          ~ "conflito",
                              row_number() == 1 ~ "bruto",
                              TRUE              ~ "rejeitado"),
      motivo = case_when(novo_status == "conflito"  ~ "conflito_interno_na_obra",
                         novo_status == "rejeitado" ~ "duplicado_na_obra",
                         TRUE                       ~ NA_character_)) |>
    ungroup()
}

#' Um artigo pode render mais de um valor para o mesmo par (especie, trait): o
#' paragrafo da descricao e a mencao de passagem da Discussao sao dois trechos,
#' e o extracao_id inclui o trecho_id, entao os dois persistem como registros
#' independentes. Visto no teste de fumaca de 01/10/2026: Conte et al. (2007)
#' rendeu snout_shape_lv = rounded duas vezes, de dois trechos.
#'
#' Sem este passo, tres coisas dao errado em silencio:
#'   - escrever_dwc() emite duas linhas de MeasurementOrFact para a mesma
#'     medida, e quem usar a base conta a especie duas vezes;
#'   - calibrar_limiares() casa as duas com a MESMA linha do conjunto-ouro, e o
#'     par entra duplicado no denominador da precisao - o limiar calibrado sai
#'     enviesado para o lado dos artigos que repetem o caractere;
#'   - se os valores DIVERGIREM, nada avisa: o de maior confianca e aprovado e o
#'     outro fica na base como se fosse outra medida.
#'
#' Entao: valores que concordam viram um registro so (fica o de maior
#' confianca, desempate pelo extracao_id para ser deterministico); valores que
#' divergem param todos em 'conflito' e vao inteiros para a fila humana.
#' Divergencia dentro do mesmo artigo e informacao - ou a recuperacao trouxe o
#' trecho errado, ou o artigo e ambiguo -, nao ruido a descartar.
#'
#' Duas decisoes deliberadas de NAO fazer:
#'   - a confianca do registro que fica nao sobe por causa da corroboracao. Ela
#'     precisa continuar significando o que o modelo relatou, senao o limiar
#'     calibrado passa a medir outra coisa.
#'   - nao ha preferencia por tipo de trecho (texto de descricao acima de
#'     tabela). Seria palpite; o piloto e que vai dizer se compensa.
reconciliar_internas <- function(con, traits, tol_rel = 0.05) {
  ext <- dbGetQuery(con, "
    SELECT extracao_id, obra_id, taxon_id, trait_id, valor_num, valor_cat, confianca
      FROM extracoes WHERE status = 'bruto'") |>
    left_join(select(traits, trait_id, tipo), by = "trait_id")
  if (nrow(ext) == 0) return(tibble::tibble())

  decidido <- decidir_reconciliacao(ext, tol_rel)

  # So as linhas que este passo de fato muda. Escrever as outras apagaria o
  # 'unidade_divergente' que checar_plausibilidade() deixou em motivo_rejeicao
  # de registros que seguem como 'bruto'.
  mudadas <- filter(decidido, !is.na(motivo))
  if (nrow(mudadas) > 0) aplicar_status(con, mudadas)
  count(mudadas, motivo)
}

# ---- limiar por trait (item 4) ---------------------------------------------

#' Compara extracoes com o conjunto-ouro e varre limiares. Devolve, por trait,
#' o menor limiar que atinge a precisao alvo (ou seja: o que preserva mais
#' recall dentro da precisao que o grupo exige).
calibrar_limiares <- function(con, traits, precisao_alvo, tol_rel = 0.05) {
  ouro <- dbGetQuery(con, "
    SELECT obra_id, taxon_id, trait_id, valor AS valor_ouro FROM ouro") |>
    group_by(obra_id, taxon_id, trait_id) |>
    # so entram os itens em que os dois extratores independentes concordaram
    filter(n_distinct(valor_ouro) == 1) |> slice(1) |> ungroup()

  # 'conflito' fica fora: o artigo deu dois valores para o mesmo par e nenhum
  # deles e uma previsao limpa do modelo. Contar os dois contra a mesma linha do
  # ouro faria o trait parecer pior (ou melhor) do que e.
  ext <- dbGetQuery(con, "
    SELECT extracao_id, obra_id, taxon_id, trait_id, valor_num, valor_cat, confianca
      FROM extracoes WHERE status NOT IN ('rejeitado', 'conflito')")

  pareado <- inner_join(ext, ouro, by = c("obra_id", "taxon_id", "trait_id")) |>
    left_join(select(traits, trait_id, tipo), by = "trait_id") |>
    mutate(acerto = if_else(
      tipo == "numerico",
      abs(valor_num - suppressWarnings(as.numeric(valor_ouro))) <=
        tol_rel * abs(suppressWarnings(as.numeric(valor_ouro))),
      tolower(valor_cat) == tolower(valor_ouro)))

  grades <- seq(0.05, 0.95, by = 0.05)
  res <- pareado |>
    group_split(trait_id) |>
    map_dfr(function(d) {
      curva <- map_dfr(grades, function(lim) {
        sel <- filter(d, confianca >= lim)
        tibble::tibble(limiar = lim,
                       precisao = if (nrow(sel)) mean(sel$acerto, na.rm = TRUE) else NA_real_,
                       recall = if (nrow(d)) sum(sel$acerto, na.rm = TRUE) / nrow(d) else NA_real_)
      })
      atinge <- curva |> filter(!is.na(precisao), precisao >= precisao_alvo) |>
        arrange(limiar) |> head(1)
      # Se nenhum limiar atinge a precisao alvo, o trait nao sai da maquina:
      # vai inteiro para revisao humana. E o que os autores do pipeline de
      # revisao sistematica fizeram com 'traits' e 'trait category' - e a
      # decisao certa, porque publicar saida de modelo abaixo do padrao
      # contamina a base toda com erro que ninguem consegue localizar depois.
      escolhido <- if (nrow(atinge)) mutate(atinge, decisao = "automatica")
                   else mutate(arrange(curva, desc(precisao))[1, ],
                               decisao = "revisao_integral")
      mutate(escolhido, trait_id = d$trait_id[1], n_ouro = nrow(d), data = Sys.time())
    })

  if (nrow(res)) {
    registrar(con, "limiares",
              select(res, trait_id, limiar, precisao, recall, n_ouro, decisao, data))
    integral <- filter(res, decisao == "revisao_integral")$trait_id
    if (length(integral)) {
      message("revisao integral (precisao alvo inalcancavel): ",
              paste(integral, collapse = ", "))
    }
  }
  res
}

# ---- fonte primaria (item 8) ------------------------------------------------

PADRAO_CITACAO <- "\\([A-Z][\\p{L}'-]+( et al\\.| & [A-Z][\\p{L}'-]+)?,? *\\d{4}\\)"

#' Duas marcas de valor recitado: a frase-fonte traz uma citacao, ou o mesmo
#' valor aparece em outra obra mais antiga. O mais antigo fica como primario.
marcar_fonte_secundaria <- function(con) {
  ext <- dbGetQuery(con, "
    SELECT e.extracao_id, e.taxon_id, e.trait_id, e.valor_num, e.valor_cat,
           e.span_verbatim, o.ano, o.doi
      FROM extracoes e JOIN obras o USING (obra_id)
     WHERE e.status = 'bruto'")
  if (nrow(ext) == 0) return(tibble::tibble())

  marcado <- ext |>
    mutate(cita_outro = str_detect(span_verbatim, regex(PADRAO_CITACAO))) |>
    group_by(taxon_id, trait_id, valor_num, valor_cat) |>
    mutate(mais_antigo = ano == min(ano, na.rm = TRUE),
           doi_primario = doi[which.min(ano)]) |>
    ungroup() |>
    mutate(origem = if_else(cita_outro | !mais_antigo, "secundaria", "primaria"),
           fonte_primaria_doi = if_else(origem == "secundaria", doi_primario, NA_character_))

  d <- select(marcado, extracao_id, origem, fonte_primaria_doi)
  dbWriteTable(con, "tmp_fp", d, temporary = TRUE, overwrite = TRUE)
  dbExecute(con, "
    UPDATE extracoes SET origem_valor = f.origem, fonte_primaria_doi = f.fonte_primaria_doi
      FROM tmp_fp f WHERE extracoes.extracao_id = f.extracao_id")
  dbExecute(con, "DROP TABLE tmp_fp")
  count(marcado, origem)
}

#' Aplica o limiar calibrado: acima vai para 'aprovado', abaixo espera revisao.
#' Trait marcado como 'revisao_integral' nao e aprovado por nenhum limiar -
#' cada valor dele passa por humano antes de entrar na base.
aplicar_limiares <- function(con) {
  dbExecute(con, "
    UPDATE extracoes SET status = 'aprovado'
      FROM limiares l
     WHERE extracoes.trait_id = l.trait_id
       AND extracoes.status = 'bruto'
       AND l.decisao = 'automatica'
       AND extracoes.confianca >= l.limiar")
}
