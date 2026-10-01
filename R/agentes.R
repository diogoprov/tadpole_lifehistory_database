# Agentes de extracao, com ellmer.
#
# Estrutura adaptada do pipeline de revisao sistematica citado pelo grupo:
# agentes em serie, cada um com o modelo dimensionado a tarefa, e escalonamento
# para um modelo mais capaz quando um campo critico volta vazio.
#
# Tres agentes:
#   1. triagem  - o artigo pode conter dado de girino? (modelo barato)
#   2. valor    - o valor do trait e a frase que o sustenta (por trecho)
#   3. contexto - as condicoes da medida, lidas da secao de Metodos (por artigo)
#
# O agente 3 existe porque o contexto (estagio de Gosner, temperatura, campo ou
# laboratorio, n) quase nunca esta na mesma frase do valor: esta em Metodos.
# Pedir os dois na mesma chamada faz o modelo inventar o que nao esta ali.

library(ellmer)
library(purrr)
library(dplyr)
library(stringr)

#' Um chat novo por chamada: ellmer acumula historico no objeto, e cada
#' extracao tem que ser independente das anteriores.
criar_chat <- function(spec, sistema) {
  switch(spec$provedor,
    anthropic = chat_anthropic(system_prompt = sistema, model = spec$modelo),
    openai    = chat_openai(system_prompt = sistema, model = spec$modelo),
    stop("provedor '", spec$provedor, "' nao configurado em criar_chat(); ",
         "ellmer traz outros (inclusive locais) - veja o indice do pacote"))
}

# ---- tipos ------------------------------------------------------------------

SISTEMA_VALOR <- paste(
  "Voce extrai dados de historia de vida de girinos da literatura primaria.",
  "Copia valores; nunca calcula, converte, infere ou completa.",
  "Se o valor nao estiver escrito no trecho, responde encontrado = FALSE.",
  "Nao traduz: trabalha no idioma original do trecho.")

tipo_valor <- function(trait) {
  campo <- if (trait$tipo == "numerico") {
    list(valor_num = type_number("o valor como aparece no texto", required = FALSE))
  } else {
    # O esqueleto preenche valores_aceitos com o que JA apareceu na planilha,
    # truncado em 25 com um sufixo "[+N outros]". Isso e ponto de partida para
    # o grupo fechar o vocabulario, nao vocabulario. Se chegasse aqui, o sufixo
    # viraria uma categoria valida no enum e o modelo poderia devolve-lo como
    # valor. Melhor parar alto do que extrair em cima de lista aberta.
    va <- trait$valores_aceitos
    vals <- if (is.null(va) || is.na(va)) character() else trimws(strsplit(va, ";")[[1]])
    if (length(vals) == 0 || any(str_detect(vals, fixed("[+"))) ||
        !isTRUE(trait$status == "fechado")) {
      stop("trait '", trait$trait_id, "': vocabulario ainda nao fechado em ",
           "inst/traits.csv (status = '", trait$status, "'). Feche valores_aceitos ",
           "e marque status = 'fechado' antes de extrair.")
    }
    list(valor_cat = type_enum(vals, "a categoria, entre as aceitas", required = FALSE))
  }
  rlang::inject(type_object(
    paste0("Valor de '", trait$nome, "' para uma especie. ", trait$definicao),
    encontrado = type_boolean("o trecho contem esse valor para essa especie?"),
    !!!campo,
    unidade = type_string("unidade como escrita no texto", required = FALSE),
    nome_no_artigo = type_string("o nome da especie exatamente como escrito no artigo",
                                 required = FALSE),
    span_verbatim = type_string(
      "a frase do trecho, copiada LETRA POR LETRA, que contem o valor"),
    confianca = type_number("0 a 1")))
}

SISTEMA_CONTEXTO <- paste(
  "Voce le a secao de Metodos de um artigo sobre girinos e registra as",
  "condicoes em que as medidas foram tomadas. So registra o que esta escrito.")

tipo_contexto <- function() {
  type_object(
    "Condicoes de medida descritas nos Metodos",
    estagio = type_string("estagio(s) de desenvolvimento, ex.: 'Gosner 25-27'",
                          required = FALSE),
    temperatura_c = type_number("temperatura de manutencao ou de ensaio, em C",
                                required = FALSE),
    ambiente = type_enum(c("campo", "laboratorio", "ambos"),
                         "origem das medidas", required = FALSE),
    n = type_integer("numero de individuos medidos", required = FALSE),
    dispersao = type_string("medida de dispersao reportada, ex.: 'SD'",
                            required = FALSE),
    span_verbatim = type_string("a frase dos Metodos que sustenta o acima"))
}

tipo_triagem <- function() {
  type_object(
    "Triagem de relevancia",
    relevante = type_boolean(),
    prob = type_number("0 a 1"),
    justificativa = type_string("uma frase"))
}

# ---- escalonamento ----------------------------------------------------------

#' Adaptado do pipeline dos amigos do grupo: se um campo critico voltou vazio,
#' tenta de novo com o modelo mais capaz e um prompt mais explicito. Vale a
#' pena porque o caro e o PDF, nao a segunda chamada.
com_escalonamento <- function(prompt, tipo, sistema, spec_barato, spec_forte,
                              campos_criticos, reforco = "") {
  tenta <- function(spec, p) {
    tryCatch(criar_chat(spec, sistema)$chat_structured(p, type = tipo),
             error = function(e) NULL)
  }
  out <- tenta(spec_barato, prompt)
  vazio <- is.null(out) ||
    any(map_lgl(campos_criticos, ~ is.null(out[[.x]]) || is.na(out[[.x]])))
  if (vazio && !is.null(spec_forte)) {
    out2 <- tenta(spec_forte, paste0(prompt, "\n\n", reforco))
    if (!is.null(out2)) return(c(out2, list(escalonado = TRUE)))
  }
  if (is.null(out)) return(NULL)
  c(out, list(escalonado = FALSE))
}

# ---- agentes ----------------------------------------------------------------

#' Revisado em 01/10/2026 contra a classificacao de um especialista (23 obras
#' de P. barrioi). So com o titulo, o agente perdeu 4 de 9 obras relevantes:
#' adivinhou o conteudo pelo titulo ("redescricao de especie adulta") e, num
#' caso, excluiu por uma distribuicao geografica que ele mesmo afirmou - e
#' errada (Bokermannohyla ahenea e endemica da mesma serra que P. barrioi). Dai
#' as tres mudancas: le o resumo, decide so pelo que esta no texto, e na duvida
#' fica com a obra - perder uma obra e pior que baixar uma a mais.
SISTEMA_TRIAGEM <- paste(
  "Voce tria literatura para uma base de traits de girinos.",
  "Relevante = a obra trata de larva (girino) de anuro E reporta medida, tempo,",
  "taxa ou categoria de pelo menos uma especie, em estudo primario.",
  "Decida SO pelo titulo e pelo resumo fornecidos. Nao use conhecimento proprio",
  "sobre distribuicao geografica, taxonomia ou conteudo provavel da obra: o escopo",
  "geografico e taxonomico ja foi resolvido pela busca.",
  "Descricoes e redescricoes de especie frequentemente descrevem tambem o girino;",
  "se o resumo mencionar larva, girino ou tadpole, a obra e relevante.",
  "Na duvida, marque relevante: perder uma obra relevante e muito pior do que",
  "examinar uma a mais.")

agente_triagem <- function(obras, cfg) {
  chat <- criar_chat(cfg$agentes$triagem, SISTEMA_TRIAGEM)
  # resumo truncado: alguns passam de 3 mil caracteres e o que decide a
  # relevancia quase sempre esta no comeco
  resumo <- if ("resumo" %in% names(obras)) obras$resumo else rep(NA_character_, nrow(obras))
  resumo <- dplyr::coalesce(substr(resumo, 1, 2500), "(sem resumo disponivel)")
  prompts <- sprintf("Titulo: %s\nAno: %s\nDOI: %s\nResumo: %s",
                     obras$titulo, obras$ano, obras$doi, resumo)
  # on_error = "continue": o default ("return") para de mandar pedidos no
  # primeiro erro, e as obras restantes ficariam sem triagem. Com "continue"
  # todas sao tentadas e as que falharem voltam com a coluna .error, que
  # interpretar_triagem() manda para a fila humana. Requer ellmer >= 0.4.0.
  parallel_chat_structured(chat, as.list(prompts), type = tipo_triagem(),
                           on_error = "continue")
}

agente_valor <- function(trecho_texto, trait, especie, cfg) {
  prompt <- paste0(
    "Especie: ", especie, "\n",
    "Trait: ", trait$nome, " (unidade esperada: ", trait$unidade, ")\n\n",
    "Trecho:\n\"\"\"\n", trecho_texto, "\n\"\"\"")
  com_escalonamento(
    prompt, tipo_valor(trait), SISTEMA_VALOR,
    cfg$agentes$valor, cfg$agentes$forte,
    campos_criticos = c("span_verbatim"),
    reforco = paste(
      "Releia com atencao: o valor pode estar numa tabela, numa faixa",
      "(min-max) ou expresso em outra unidade. Se existir, copie a frase",
      "exata. Se realmente nao existir, responda encontrado = FALSE."))
}

#' Roda uma vez por artigo, sobre os trechos de Metodos. O resultado e o
#' contexto padrao daquele artigo, herdado por todos os valores extraidos dele
#' e sobrescrito quando o proprio trecho do valor trouxer contexto proprio.
agente_contexto <- function(con, obra_id, cfg) {
  metodos <- dbGetQuery(con, sprintf("
    SELECT texto FROM trechos
     WHERE obra_id = '%s'
       AND (lower(secao) LIKE '%%method%%' OR lower(secao) LIKE '%%metodo%%'
            OR lower(secao) LIKE '%%material%%')", obra_id))$texto
  if (length(metodos) == 0) return(NULL)
  txt <- substr(paste(metodos, collapse = "\n"), 1, 12000)
  com_escalonamento(
    paste0("Metodos:\n\"\"\"\n", txt, "\n\"\"\""),
    tipo_contexto(), SISTEMA_CONTEXTO,
    cfg$agentes$contexto, cfg$agentes$forte,
    campos_criticos = c("estagio", "ambiente"),
    reforco = "Procure especificamente estagio de Gosner, temperatura de manutencao e se as medidas sao de campo ou de laboratorio.")
}

`%||%` <- function(x, y) if (is.null(x)) y else x
