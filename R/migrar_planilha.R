# Migracao da planilha legada (Planilha Amanda NOVA girinos livro.xlsx) para
# um Darwin Core Archive.
#
# REGRA DESTA MIGRACAO: reestruturar, nunca corrigir.
# Cada valor vai para o termo Darwin Core certo, byte por byte como esta na
# planilha. Nenhum espaco e aparado, nenhuma grafia e unificada, nenhum valor
# suspeito e removido. Tudo o que esta errado sai listado em auditoria.xlsx,
# para o grupo decidir. Por isso o arquivo gerado NAO esta pronto para publicar.
#
# Uso:
#   source("R/migrar_planilha.R")
#   migrar("Planilha Amanda NOVA girinos livro.xlsx", "dwca")

library(readxl)
library(dplyr)
library(purrr)
library(stringr)
library(tidyr)

# ---- leitura verbatim -------------------------------------------------------

ler_aba <- function(caminho, aba) {
  # trim_ws = FALSE e essencial: com o padrao do readxl os espacos sobrando
  # sumiriam na leitura e a auditoria nunca os veria.
  d <- read_excel(caminho, sheet = aba, col_types = "text", trim_ws = FALSE,
                  .name_repair = "minimal")
  names(d) <- ifelse(is.na(names(d)) | names(d) == "",
                     paste0("col_", seq_along(names(d))), names(d))
  # linha da planilha (cabecalho = 1), para a auditoria apontar a celula certa
  d$.linha <- seq_len(nrow(d)) + 1L
  vazias <- rowSums(!is.na(select(d, -.linha)) &
                      select(d, -.linha) != "") == 0
  attr(d, "n_vazias") <- sum(vazias)
  d[!vazias, , drop = FALSE]
}

norm_esp <- function(x) str_squish(as.character(x))

# ---- auditoria --------------------------------------------------------------

achado <- function(aba, linha, coluna, valor, problema, acao) {
  tibble::tibble(aba = aba, linha = linha, coluna = coluna,
                 valor = as.character(valor), problema = problema,
                 acao_sugerida = acao)
}

#' Autofill do Excel: arrastar uma celula que termina em numero gera uma serie
#' 2014, 2015, 2016... Detectamos prefixo identico + numeros finais
#' consecutivos (3 ou mais). E o erro mais perigoso da planilha, porque o
#' resultado parece um dado plausivel.
detectar_autofill <- function(valores, aba, linhas, coluna) {
  v <- as.character(valores)
  m <- str_match(v, "^(.*?)(\\d+)\\s*$")
  df <- tibble::tibble(linha = linhas, valor = v,
                       prefixo = m[, 2], num = suppressWarnings(as.integer(m[, 3]))) |>
    filter(!is.na(num), !is.na(prefixo), prefixo != "")

  if (nrow(df) == 0) {
    return(achado(character(), integer(), character(),
                  character(), character(), character()))
  }

  df |>
    group_by(prefixo) |>
    # as tres condicoes numa chamada so: separadas, a ultima chega a rodar
    # sobre grupo ja vazio e min() avisa sem necessidade
    filter(n_distinct(num) >= 3,
           all(diff(sort(unique(num))) == 1),
           num != min(num)) |>   # o menor da serie e o valor real (conf. Denise)
    ungroup() |>
    (\(d) if (nrow(d) == 0) achado(character(), integer(), character(),
                                   character(), character(), character())
          else achado(aba, d$linha, coluna, d$valor,
                      "serie consecutiva: provavel autofill do Excel",
                      paste0("conferir no artigo; manter so '", d$prefixo[1],
                             min(d$num), "' se confirmado")))()
}

# Autofill so faz sentido procurar onde uma serie consecutiva nao pode ser
# dado legitimo. Em DevelopmentalStages ("35-36", "35-37", "35-38") ou numa
# formula de dentes labiais a serie e real - procurar ali so gera falso alarme.
# taxonID fica de fora: Anura1, Anura2, Anura3... e uma serie por construcao.
COLUNAS_IDENTIDADE <- c("scientificName", "eventID", "collectionCode",
                        "bibliographicCitation", "Source of information")

auditar_texto <- function(d, aba, colunas) {
  map_dfr(intersect(colunas, names(d)), function(col) {
    v <- d[[col]]; ok <- !is.na(v)
    bind_rows(
      achado(aba, d$.linha[ok & str_detect(v %|% "", "  ")], col,
             v[ok & str_detect(v %|% "", "  ")],
             "espaco duplo dentro do valor", "normalizar espacos"),
      achado(aba, d$.linha[ok & v != str_trim(v %|% "")], col,
             v[ok & v != str_trim(v %|% "")],
             "espaco no inicio ou no fim", "aparar"),
      achado(aba, d$.linha[ok & str_detect(v %|% "", "−|–")], col,
             v[ok & str_detect(v %|% "", "−|–")],
             "traco tipografico (U+2212/en dash) no lugar de hifen",
             "padronizar em hifen simples"),
      if (col %in% COLUNAS_IDENTIDADE)
        detectar_autofill(v[ok], aba, d$.linha[ok], col) else tibble::tibble())
  })
}

#' Quebra de linha (Alt+Enter) ou tabulacao dentro de uma celula corrompe
#' qualquer arquivo de texto delimitado. Varre TODAS as colunas.
auditar_controle <- function(d, aba) {
  cols <- setdiff(names(d)[map_lgl(d, is.character)], ".linha")
  map_dfr(cols, function(col) {
    v <- d[[col]]; sel <- !is.na(v) & str_detect(v, "[\r\n\t]")
    achado(aba, d$.linha[sel], col,
           str_replace_all(v[sel], "[\r\n\t]", "<quebra>"),
           "quebra de linha ou tabulacao dentro da celula",
           "juntar numa linha so antes de exportar para texto delimitado")
  })
}

#' Agrupa achados repetidos: uma linha por (aba, coluna, problema, valor), com
#' a contagem de celulas e um exemplo de linha. Sem isso a auditoria vira um
#' arquivo de 20 mil linhas que ninguem le.
resumir_achados <- function(x) {
  if (nrow(x) == 0 || all(is.na(x$linha))) {
    return(tibble::tibble(aba = character(), coluna = character(),
                          problema = character(), valor = character(),
                          acao_sugerida = character(), n_celulas = integer(),
                          linha_exemplo = integer()))
  }
  x |>
    filter(!is.na(linha)) |>
    group_by(aba, coluna, problema, valor, acao_sugerida) |>
    summarise(n_celulas = n(), linha_exemplo = min(linha), .groups = "drop") |>
    arrange(desc(n_celulas))
}

`%|%` <- function(x, y) ifelse(is.na(x), y, x)

auditar <- function(abas) {
  tax <- abas$Taxonomy; hab <- abas$Habitat; ger <- abas$GeneralInformation
  mor <- abas$Morphology_DWC; die <- abas$Diet_DWC

  # 1. higiene de texto nas colunas que carregam identidade
  higiene <- bind_rows(
    auditar_texto(tax, "Taxonomy", c("taxonID", "scientificName", "family", "genus")),
    auditar_texto(hab, "Habitat", c("taxonID", "scientificName", "eventID")),
    auditar_texto(ger, "GeneralInformation", c("taxonID", "eventID", "collectionCode")),
    auditar_texto(mor, "Morphology_DWC", c("taxonID", "scientificName", "eventID",
                                           "measurementValue", "DevelopmentalStages",
                                           "organismQuantityType")),
    auditar_texto(die, "Diet_DWC", c("taxonID", "scientificName", "eventID")))

  # 2. um taxonID apontando para mais de um nome (depois de normalizar espacos)
  pares <- map_dfr(list(Taxonomy = tax, Habitat = hab, Morphology_DWC = mor, Diet_DWC = die),
                   ~ if (all(c("taxonID", "scientificName") %in% names(.x)))
                       transmute(.x, linha = .linha,
                                 taxonID = norm_esp(taxonID),
                                 nome = norm_esp(scientificName))
                     else tibble::tibble(), .id = "aba") |>
    filter(!is.na(taxonID), !is.na(nome))

  # uma linha por par distinto (taxonID, nome), nao por celula
  conflito_nome <- pares |>
    group_by(taxonID) |> filter(n_distinct(nome) > 1) |> ungroup() |>
    distinct(taxonID, nome, .keep_all = TRUE) |>
    transmute(aba, linha, coluna = "scientificName",
              valor = paste0(taxonID, " -> ", nome),
              problema = "taxonID com mais de um scientificName",
              acao_sugerida = "escolher a grafia aceita e propagar")

  conflito_id <- pares |>
    group_by(nome) |> filter(n_distinct(taxonID) > 1) |> ungroup() |>
    distinct(nome, taxonID, .keep_all = TRUE) |>
    transmute(aba, linha, coluna = "taxonID",
              valor = paste0(nome, " -> ", taxonID),
              problema = "mesmo nome com taxonID diferente",
              acao_sugerida = "unificar o identificador")

  # 3. taxonID orfao entre as abas
  ids_tax <- unique(norm_esp(tax$taxonID))
  orfaos <- map_dfr(list(GeneralInformation = ger, Habitat = hab,
                         Morphology_DWC = mor, Diet_DWC = die),
                    function(d) {
                      i <- norm_esp(d$taxonID)
                      fora <- !is.na(i) & !(i %in% ids_tax)
                      tibble::tibble(linha = d$.linha[fora], valor = i[fora])
                    }, .id = "aba") |>
    distinct(aba, valor, .keep_all = TRUE) |>
    mutate(coluna = "taxonID",
           problema = "taxonID ausente da aba Taxonomy",
           acao_sugerida = "incluir na Taxonomy ou corrigir o identificador") |>
    select(aba, linha, coluna, valor, problema, acao_sugerida)

  # 4. comentario escrito em celula de dado
  comentarios <- map_dfr(c("measurementAccuracy", "measurementUnit", "measurementMethod"),
    function(col) {
      if (!col %in% names(mor)) return(tibble::tibble())
      v <- mor[[col]]; sel <- !is.na(v) & str_detect(v, "(?i)acho que|nao se aplica|não se aplica")
      achado("Morphology_DWC", mor$.linha[sel], col, v[sel],
             "comentario do preenchedor dentro de celula de dado",
             "mover para documentacao; deixar a celula vazia")
    })

  # 5. (removido) A mistura de '|' e '/' em measurementValue nao e erro:
  # a barra faz parte da formula de fileiras de dentes labiais (LTRF), que
  # separa fileiras anteriores das posteriores, e o '|' separa as variantes
  # da formula. Denise confirmou. E exatamente a convencao do Darwin Core
  # para lista, entao a checagem saiu.
  mv <- tibble::tibble()

  # 6. eventID que nao e identificador estavel. URL conta: nem toda revista
  # antiga tem DOI, e o link estavel do periodico e o identificador possivel.
  ev <- ger$eventID
  sel <- !is.na(ev) & !str_detect(ev, "^(10\\.|https?://|97[89])")
  id_fragil <- achado("GeneralInformation", ger$.linha[sel], "eventID", ev[sel],
                      "eventID nao e DOI, ISBN nem URL (citacao livre)",
                      "usar DOI, ISBN ou link estavel como identificador da obra")

  controle <- imap_dfr(abas, ~ auditar_controle(.x, .y))

  # 7. medida sem taxonID: a linha tem valor mas nao esta ligada a especie
  # nenhuma, entao o dado existe e nao pode ser usado. Passou batido na
  # primeira versao da auditoria porque so procuravamos taxonID invalido,
  # nunca taxonID ausente.
  orfas <- map_dfr(list(Morphology_DWC = mor, Habitat = hab, Diet_DWC = die),
    function(d) {
      if (!all(c("taxonID", "measurementValue") %in% names(d))) return(tibble::tibble())
      sel <- (is.na(d$taxonID) | str_squish(d$taxonID %|% "") == "") &
             !is.na(d$measurementValue) & str_squish(d$measurementValue %|% "") != ""
      tibble::tibble(linha = d$.linha[sel], valor = d$measurementValue[sel])
    }, .id = "aba") |>
    mutate(coluna = "taxonID",
           problema = "medida com valor mas sem taxonID",
           acao_sugerida = "identificar a especie do bloco ou remover as linhas") |>
    select(aba, linha, coluna, valor, problema, acao_sugerida)

  # 8. coluna numerica com texto. A auditoria so olhava forma (espaco, traco,
  # autofill) e identidade, nunca se o valor cabia no tipo da coluna; um
  # "Brazil" em maximumDephInMeters passou por ela com zero achados.
  num_texto <- if ("maximumDephInMeters" %in% names(hab)) {
    v <- str_squish(hab$maximumDephInMeters %|% "")
    sel <- v != "" & is.na(suppressWarnings(as.numeric(str_replace(v, ",", "."))))
    tibble::tibble(aba = "Habitat", linha = hab$.linha[sel],
                   coluna = "maximumDephInMeters", valor = v[sel],
                   problema = "texto em coluna numerica",
                   acao_sugerida = "conferir a linha inteira: costuma ser colagem deslocada")
  } else tibble::tibble()

  resumir_achados(
    bind_rows(higiene, controle, conflito_nome, conflito_id, orfaos,
              comentarios, mv, id_fragil, orfas, num_texto))
}

`%||%` <- function(x, y) if (is.null(x)) y else x

# ---- reestruturacao em Darwin Core -----------------------------------------

#' Taxon core: uma linha por taxonID, valores como estao.
montar_taxon <- function(tax) {
  tax |>
    group_by(taxonID) |> slice(1) |> ungroup() |>
    transmute(
      taxonID,
      scientificName,
      scientificNameAuthorship = if ("scientificNameAuthorship" %in% names(tax))
        .data[["scientificNameAuthorship"]] else NA_character_,
      family, genus,
      kingdom = "Animalia", phylum = "Chordata", class = "Amphibia", order = "Anura",
      taxonRank = "species",
      nameAccordingTo = .data[["nameAccordingToID"]],
      nomenclaturalCode = "ICZN",
      taxonRemarks = .data[["FIRST TADPOLE-DESCRIPTION"]])
}

#' Occurrence: o material-testemunho e a procedencia, que estavam em
#' GeneralInformation.
montar_occurrence <- function(ger) {
  ger |>
    transmute(
      occurrenceID = paste0(taxonID, "|", row_number()),
      taxonID,
      catalogNumber = collectionCode,     # estava sob o rotulo errado
      lifeStage = "tadpole",
      country, stateProvince, municipality, locality,
      higherGeography = .data[["higherGeography (biome)"]],
      bibliographicCitation,
      eventID,
      occurrenceRemarks = NA_character_)
}

#' MeasurementOrFact: habitat, morfologia e dieta viram o mesmo formato.
#' measurementType recebe o codigo de maquina; o texto da definicao vai para
#' measurementRemarks, junto com estagio, fonte e aba de origem.
montar_mof <- function(hab, mor, die) {
  mof_hab <- hab |>
    pivot_longer(any_of(c("HabitatPosition", "Habitat_type", "HabitatHydroperiod",
                          "maximumDephInMeters", "HabitatMarginalVegetation",
                          "HabitatAquaticVegetation", "behavior", "Vegetation_cover")),
                 names_to = "measurementType", values_to = "measurementValue") |>
    filter(!is.na(measurementValue)) |>
    transmute(taxonID, measurementType, measurementValue,
              measurementUnit = if_else(measurementType == "maximumDephInMeters",
                                        "m", NA_character_),
              organismQuantity = NA_character_, organismQuantityType = NA_character_,
              measurementMethod = NA_character_,
              measurementRemarks = paste0(
                "origem=Habitat; biome=", .data[["HigherGeography (biome)"]] %|% "NA",
                "; locationID=", .data[["LocationID"]] %|% "NA"),
              bibliographicCitation = .data[["Source of information"]],
              eventID)

  # Na aba de morfologia o codigo de maquina (body_shape_dv etc.) esta na
  # coluna logo depois de "MeasurementOrFact" e nasceu sem cabecalho.
  # Localizar por posicao relativa, nunca por indice fixo: a separacao da
  # autoria insere uma coluna antes e desloca tudo.
  i_def <- which(names(mor) == "MeasurementOrFact")
  if (length(i_def) != 1 || i_def + 1 > ncol(mor)) {
    stop("nao encontrei a coluna de codigo do caractere em Morphology_DWC")
  }
  col_codigo <- names(mor)[i_def + 1]
  mof_mor <- mor |>
    filter(!is.na(.data[["measurementValue"]])) |>
    transmute(taxonID,
              measurementType = .data[[col_codigo]],
              measurementValue,
              measurementUnit = NA_character_,
              organismQuantity,
              organismQuantityType,
              measurementMethod = .data[["measurementMethod"]],
              measurementRemarks = paste0(
                "origem=Morphology; definicao=", .data[["MeasurementOrFact"]] %|% "NA",
                "; developmentalStage=", .data[["DevelopmentalStages"]] %|% "NA"),
              bibliographicCitation = .data[["Source of information"]],
              eventID)

  # dieta: as colunas estavam rotacionadas (o item estava em measurementType,
  # o tipo de contagem em measurementValue e o numero em measurementAccuracy)
  # Os nomes de origem e de destino colidem (measurementValue na planilha
  # guarda a metrica; no arquivo guarda o numero), e dentro de um transmute o
  # .data ja enxerga a coluna reescrita. Entao copio os originais para nomes
  # proprios ANTES, senao measurementMethod recebe o numero em vez da metrica.
  die_src <- die |>
    filter(!is.na(.data[["measurementAccuracy"]])) |>
    mutate(
      .item     = .data[["measurementType"]] %|% "NA",
      .numero   = .data[["measurementAccuracy"]],
      .unidade  = .data[["organismQuantity"]],
      .metrica  = .data[["measurementValue"]],
      .n_girinos = .data[["organismQuantityType"]],
      .estagio  = if ("DevelopmentalStage" %in% names(die))
        .data[["DevelopmentalStage"]] %|% "NA" else "NA")

  mof_die <- die_src |>
    transmute(taxonID,
              measurementType = paste0("diet_item:", .item),
              measurementValue = .numero,
              measurementUnit = .unidade,
              # .n_girinos guarda o numero de girinos examinados ("5", "5 - 7").
              # Em DwC organismQuantity e o numero e organismQuantityType o
              # sistema de contagem, entao o par certo e <numero, "individuals">.
              # Nao uso sampleSizeValue/Unit porque esses termos sao da classe
              # Event, nao da extensao MeasurementOrFact.
              organismQuantity = .n_girinos,
              organismQuantityType = if_else(is.na(.n_girinos), NA_character_,
                                             "individuals"),
              # a metrica ("percentage_of_items") descreve COMO o numero foi
              # obtido, entao e measurementMethod, nao measurementValue
              measurementMethod = .metrica,
              # DevelopmentalStage entrou na aba em 29/09/2026 (Denise foi aos
              # artigos conferir). Sem esta linha o estagio da dieta se perdia
              # na migracao, porque a morfologia usa DevelopmentalStages, no
              # plural, e a dieta usa o singular. O hidroperiodo saiu de
              # MeasurementOrFact e virou sufixo do eventID (regra R13).
              measurementRemarks = paste0(
                "origem=Diet; girinosExaminados=", .n_girinos %|% "NA",
                "; developmentalStage=", .estagio),
              bibliographicCitation = NA_character_,
              eventID)

  bind_rows(mof_hab, mof_mor, mof_die) |>
    mutate(measurementID = paste0("mof", row_number()), .before = 1)
}

#' Anexa as observacoes de inst/notas_registro.csv ao measurementRemarks das
#' linhas correspondentes. Sao lacunas da fonte, nao da transcricao, e precisam
#' viajar com o dado: um README nao acompanha quem baixa o arquivo.
anexar_notas <- function(mof, caminho = "inst/notas_registro.csv") {
  if (!file.exists(caminho)) return(mof)
  notas <- readr::read_csv(caminho, comment = "#", show_col_types = FALSE)
  if (nrow(notas) == 0) return(mof)
  i <- match(paste(mof$taxonID, mof$eventID),
             paste(notas$taxonID, notas$eventID))
  mof$measurementRemarks <- if_else(
    is.na(i), mof$measurementRemarks,
    paste0(mof$measurementRemarks, "; nota=", notas$nota[i]))
  message("notas anexadas a ", sum(!is.na(i)), " registros")
  mof
}

# ---- meta.xml ---------------------------------------------------------------

TERMO <- function(x) paste0("http://rs.tdwg.org/dwc/terms/", x)

campos_xml <- function(cols, id_col) {
  idx <- seq_along(cols) - 1L
  linhas <- map2_chr(cols, idx, function(nome, i) {
    if (nome == id_col) return("")
    sprintf('      <field index="%d" term="%s"/>', i, TERMO(nome))
  })
  paste(c(sprintf('      <id index="%d"/>', which(cols == id_col) - 1L),
          linhas[linhas != ""]), collapse = "\n")
}

escrever_meta <- function(dir_saida, cols_taxon, cols_occ, cols_mof) {
  xml <- sprintf('<?xml version="1.0" encoding="UTF-8"?>
<archive xmlns="http://rs.tdwg.org/dwc/text/">
  <core encoding="UTF-8" fieldsTerminatedBy="\\t" linesTerminatedBy="\\n"
        fieldsEnclosedBy="&quot;" ignoreHeaderLines="1" rowType="%s">
    <files><location>taxon.txt</location></files>
%s
  </core>
  <extension encoding="UTF-8" fieldsTerminatedBy="\\t" linesTerminatedBy="\\n"
             fieldsEnclosedBy="&quot;" ignoreHeaderLines="1" rowType="%s">
    <files><location>occurrence.txt</location></files>
%s
  </extension>
  <extension encoding="UTF-8" fieldsTerminatedBy="\\t" linesTerminatedBy="\\n"
             fieldsEnclosedBy="&quot;" ignoreHeaderLines="1" rowType="%s">
    <files><location>measurementorfact.txt</location></files>
%s
  </extension>
</archive>
', TERMO("Taxon"), campos_xml(cols_taxon, "taxonID"),
   TERMO("Occurrence"), campos_xml(cols_occ, "taxonID"),
   TERMO("MeasurementOrFact"), campos_xml(cols_mof, "taxonID"))
  writeLines(xml, file.path(dir_saida, "meta.xml"))
}

# ---- orquestracao -----------------------------------------------------------

migrar <- function(caminho_xlsx, dir_saida = "dwca") {
  dir.create(dir_saida, showWarnings = FALSE, recursive = TRUE)
  abas <- set_names(c("GeneralInformation", "Habitat", "Taxonomy",
                      "Morphology_DWC", "Diet_DWC")) |>
    map(~ ler_aba(caminho_xlsx, .x))

  problemas <- auditar(abas)

  taxon <- montar_taxon(abas$Taxonomy)
  occ   <- montar_occurrence(abas$GeneralInformation)
  mof   <- montar_mof(abas$Habitat, abas$Morphology_DWC, abas$Diet_DWC) |>
    anexar_notas()

  # quote = "all": ha celulas com quebra de linha dentro (Alt+Enter no Excel).
  # Sem aspas em tudo, essas celulas partem a linha e o arquivo fica corrompido.
  write_tsv2 <- function(d, f) readr::write_tsv(d, file.path(dir_saida, f),
                                                na = "", quote = "all")
  write_tsv2(taxon, "taxon.txt")
  write_tsv2(occ, "occurrence.txt")
  write_tsv2(mof, "measurementorfact.txt")
  escrever_meta(dir_saida, names(taxon), names(occ), names(mof))
  readr::write_csv(problemas, file.path(dir_saida, "auditoria.csv"), na = "")

  resumo <- count(problemas, problema, sort = TRUE)
  readr::write_csv(resumo, file.path(dir_saida, "auditoria_resumo.csv"))

  list(taxon = nrow(taxon), occurrence = nrow(occ), mof = nrow(mof),
       problemas = nrow(problemas), resumo = resumo)
}
