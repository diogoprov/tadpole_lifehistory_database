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
#' Temperatura por agente, pelo campo `temperatura` do config.yml, e so quando
#' definido. Motivo: sem ela o modelo sorteia a resposta - no teste de
#' P. barrioi (01/10/2026) a MESMA obra saiu "relevante" (0,85) numa rodada e
#' "irrelevante" (0,15) na seguinte. Mas nao da para por em todos: o Haiku 4.5
#' aceita temperature = 0, e o Sonnet 5.5 e o Opus 5.5 recusam com HTTP 400
#' ("temperature is deprecated for this model"). Nesses, a variacao entre
#' rodadas nao e controlavel por parametro - tem de ser MEDIDA (rodar duas
#' vezes no piloto e comparar). verificar_infra() confere cada agente.
criar_chat <- function(spec, sistema) {
  p <- if (is.null(spec$temperatura)) NULL else params(temperature = spec$temperatura)
  switch(spec$provedor,
    anthropic = chat_anthropic(system_prompt = sistema, model = spec$modelo, params = p),
    openai    = chat_openai(system_prompt = sistema, model = spec$modelo, params = p),
    stop("provedor '", spec$provedor, "' nao configurado em criar_chat(); ",
         "ellmer traz outros (inclusive locais) - veja o indice do pacote"))
}

# ---- tipos ------------------------------------------------------------------

SISTEMA_VALOR <- paste(
  "Voce extrai dados de historia de vida de girinos da literatura primaria.",
  "Copia valores; nunca calcula, converte, infere ou completa.",
  "Se o valor nao estiver escrito no trecho, responde encontrado = FALSE.",
  # 04/10/2026: na rodada 3 do piloto, 32 de 136 frases conferidas eram de
  # outra especie: comparacao ("differ from S. fuscovarius by the snout
  # rounded") ou descricao de outro autor ("described by Kolenc et al.
  # (2008) ... dorsolaterally directed eyes"). Valor de outro trabalho nao e
  # fonte primaria (decisao de 01/10/2026).
  "So vale o que o trecho descreve DESTA especie, nos exemplares do proprio estudo.",
  "Ignore frase que descreve outra especie, que compara especies sem dar o",
  "estado desta, ou que relata o que outro trabalho descreveu.",
  # Diogo, 04/10/2026: caractere descrito para um grupo de especies nao vale
  # para cada especie do grupo (ex.: "Characteristics: Leptodactylus fuscus
  # species group - ... Eyes dorsal.", na monografia de 63 especies)
  "Caractere descrito para um grupo de especies (species group, genero) nao vale",
  "para a especie: responda encontrado = FALSE.",
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
#'
#' Erro de API NUNCA vira "nao encontrado". Antes, tenta() devolvia NULL em
#' qualquer erro, e NULL seguia como resposta vazia: no teste de P. barrioi
#' (01/10/2026) TODAS as chamadas ao Sonnet e ao Opus deram HTTP 400 e o
#' pipeline relatou "0 registros", como se as 8 obras nao tivessem nada.
#' Agora erro para a rodada com a mensagem da API. Parar e seguro: extrair_tudo()
#' grava cada par ao terminar, e o par que falhou continua pendente em
#' estado_par - rodar de novo retoma de onde parou. Falha transitoria (429, 529)
#' o ellmer ja tenta de novo antes de chegar aqui.
#'
#' Unica excecao: se o modelo barato falhou e o forte respondeu, segue com a
#' resposta do forte - mas avisa, porque escalar por erro custa mais caro.
com_escalonamento <- function(prompt, tipo, sistema, spec_barato, spec_forte,
                              campos_criticos, reforco = "") {
  tenta <- function(spec, p) {
    tryCatch(list(out = criar_chat(spec, sistema)$chat_structured(p, type = tipo), erro = NULL),
             error = function(e) list(out = NULL, erro = conditionMessage(e)))
  }
  falha <- function(spec, erro) paste0(spec$modelo, ": ", erro)

  r1 <- tenta(spec_barato, prompt)
  out <- r1$out
  vazio <- is.null(out) ||
    any(map_lgl(campos_criticos, ~ is.null(out[[.x]]) || is.na(out[[.x]])))
  if (vazio && !is.null(spec_forte)) {
    r2 <- tenta(spec_forte, paste0(prompt, "\n\n", reforco))
    if (!is.null(r2$erro)) {
      stop("chamada ao modelo falhou - ",
           paste(c(if (!is.null(r1$erro)) falha(spec_barato, r1$erro), falha(spec_forte, r2$erro)),
                 collapse = " | "), call. = FALSE)
    }
    if (!is.null(r1$erro)) {
      warning("modelo barato falhou, usada a resposta do forte - ",
              falha(spec_barato, r1$erro), call. = FALSE)
    }
    return(c(r2$out, list(escalonado = TRUE)))
  }
  if (!is.null(r1$erro)) stop("chamada ao modelo falhou - ", falha(spec_barato, r1$erro), call. = FALSE)
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

#' `ancora`: o paragrafo que nomeia a especie, quando o trecho a herdou
#' (herdar_especie(), 02/10/2026). Vai no prompt so como contexto, cortado;
#' o valor e a frase-fonte tem de vir do trecho.
#'
#' `nomes`: sinonimos da especie (aliases_de()). Artigo antigo usa o nome
#' antigo, e a legenda de tabela o abrevia ("Sarg - S. argyreornatus" para
#' Ololygon argyreornata); so com o nome aceito o modelo nao liga a linha a
#' especie. `tipo`: "tabela" acrescenta como ler a tabela (02/10/2026).
#' `trait$nomes_alternativos`: outros nomes do caractere na literatura
#' (eyes_positioning = "eye direction", decisao do Diogo, 02/10/2026).
#' `trait$regra_extracao`: instrucao propria do trait (inst/traits.csv). Caso:
#' com "eye direction" como sinonimo, o modelo passou a devolver a direcao
#' onde o artigo da as duas ("located dorsally, directed dorsolaterally") e
#' a planilha registra a posicao - 17 pares em Pezzuti et al. (2021), rodada 3
#' do piloto. Regra (Diogo, 02/10/2026): posicao primeiro; direcao so sem posicao.
#' O prompt do agente de valor para um trecho. Pura: o modo normal
#' (agente_valor()) e o de lotes (extrair_tudo_lote()) usam o mesmo texto.
prompt_valor <- function(trecho_texto, trait, especie, ancora = NA_character_,
                         nomes = character(), tipo = "texto") {
  contexto <- if (is.na(ancora) || !nzchar(ancora)) "" else paste0(
    "O trecho nao repete o nome da especie; ele vem depois deste paragrafo, ",
    "que a nomeia (so contexto, nao copie valor dele):\n\"\"\"\n",
    substr(ancora, 1, 400), "\n\"\"\"\n\n")
  outros <- head(setdiff(nomes, especie), 12)
  alt <- trait$nomes_alternativos %||% NA_character_
  regra <- trait$regra_extracao %||% NA_character_
  tabela <- if (identical(tipo, "tabela")) paste0(
    "O trecho e uma tabela. A especie pode aparecer abreviada nas linhas; a ",
    "legenda diz a que especie corresponde cada abreviacao. Ache a linha da ",
    "especie e a coluna do trait; copie como span_verbatim a linha da especie ",
    "exatamente como esta no trecho.\n\n") else ""
  paste0(
    "Especie: ", especie, "\n",
    if (length(outros)) paste0("Tambem chamada na literatura: ", paste(outros, collapse = "; "), "\n") else "",
    "Trait: ", trait$nome, " (unidade esperada: ", trait$unidade, ")\n",
    if (!is.na(alt) && nzchar(alt)) paste0("O trait tambem aparece como: ", gsub(";", "; ", alt), "\n") else "",
    if (!is.na(regra) && nzchar(regra)) paste0("Regra para este trait: ", regra, "\n") else "",
    "\n", contexto, tabela,
    "Trecho:\n\"\"\"\n", trecho_texto, "\n\"\"\"")
}

REFORCO_VALOR <- paste(
  "Releia com atencao: o valor pode estar numa tabela, numa faixa",
  "(min-max) ou expresso em outra unidade. Se existir, copie a frase",
  "exata. Se realmente nao existir, responda encontrado = FALSE.")

agente_valor <- function(trecho_texto, trait, especie, cfg, ancora = NA_character_,
                         nomes = character(), tipo = "texto") {
  com_escalonamento(
    prompt_valor(trecho_texto, trait, especie, ancora, nomes, tipo), tipo_valor(trait), SISTEMA_VALOR,
    cfg$agentes$valor, cfg$agentes$forte,
    campos_criticos = c("span_verbatim"), reforco = REFORCO_VALOR)
}

#' Quais trechos o agente de contexto le. Primeiro os de Metodos (pelo nome
#' da secao). Se a obra nao tem Metodos, os trechos de texto que citam Gosner
#' ou Stage (ou estagio, em portugues: o poster de P. barrioi diz "estagios 35
#' a 37"). Motivo: nota curta nao tem cabecalho de Metodos, e notas vao ser
#' comuns (Diogo, 01/10/2026). Em Pseudopaludicola (Amphibia-Reptilia, 2013)
#' o estagio esta num bloco sem titulo junto com a introducao: "Two Stage 36
#' and two Stage 39 tadpoles of P. falcipes...". Sem isto, o agente devolvia
#' NULL e os valores saiam sem estagio.
#'
#' Pura: recebe os trechos da obra (tipo, secao, texto). Devolve os textos e
#' de onde vieram: "metodos", "estagio" ou "nenhum".
PADRAO_SECAO_METODOS <- "method|metodo|material"
PADRAO_ESTAGIO <- "\\bgosner\\b|\\bstages?\\b|\\best[a\u00e1]gios?\\b"

trechos_de_contexto <- function(trechos) {
  secao <- coalesce(tolower(trechos$secao), "")
  metodos <- trechos$texto[str_detect(secao, PADRAO_SECAO_METODOS)]
  if (length(metodos)) return(list(textos = metodos, fonte = "metodos"))
  estagio <- trechos$texto[trechos$tipo == "texto" &
                             str_detect(trechos$texto, regex(PADRAO_ESTAGIO, ignore_case = TRUE))]
  if (length(estagio)) return(list(textos = estagio, fonte = "estagio"))
  list(textos = character(), fonte = "nenhum")
}

#' Roda uma vez por artigo, sobre os trechos de Metodos. O resultado e o
#' contexto padrao daquele artigo, herdado por todos os valores extraidos dele
#' e sobrescrito quando o proprio trecho do valor trouxer contexto proprio.
agente_contexto <- function(con, obra_id, cfg) {
  trechos <- dbGetQuery(con, sprintf(
    "SELECT tipo, secao, texto FROM trechos WHERE obra_id = '%s'", obra_id))
  sel <- trechos_de_contexto(trechos)
  if (length(sel$textos) == 0) return(NULL)
  txt <- substr(paste(sel$textos, collapse = "\n"), 1, 12000)
  rotulo <- if (sel$fonte == "metodos") "Metodos" else
    "Trechos que citam o estagio (a obra nao tem secao de Metodos)"
  out <- com_escalonamento(
    paste0(rotulo, ":\n\"\"\"\n", txt, "\n\"\"\""),
    tipo_contexto(), SISTEMA_CONTEXTO,
    cfg$agentes$contexto, cfg$agentes$forte,
    campos_criticos = c("estagio", "ambiente"),
    reforco = "Procure especificamente estagio de Gosner, temperatura de manutencao e se as medidas sao de campo ou de laboratorio.")
  # de onde o texto veio, para obter_contexto() gravar em contexto_obra
  c(out, list(fonte_contexto = sel$fonte))
}

`%||%` <- function(x, y) if (is.null(x)) y else x

# ---- varios traits numa chamada (04/10/2026) ------------------------------------
#
# Com as fichas, a mesma ficha e candidata para todos os traits da especie, e
# o modo um-trait-por-chamada mandava o mesmo texto uma vez por trait. Antes
# dos 48 traits, o numero de chamadas e o que pesa no custo (estimativa de
# 04/10/2026: ~US$ 600-700 no modo atual). Aqui o trecho vai uma vez, com
# todos os traits para os quais ele e candidato; a resposta tem um bloco por
# trait, com os mesmos campos de tipo_valor(). O escalonamento continua por
# trait (agente_valor_forte()).

#' Tipo da resposta multi-trait: um bloco tipo_valor() por trait.
tipo_valor_multi <- function(traits) {
  blocos <- set_names(map(traits, tipo_valor), map_chr(traits, "trait_id"))
  rlang::inject(type_object("Um bloco por trait pedido, com o valor para a especie.", !!!blocos))
}

#' Prompt multi-trait: a especie e o trecho uma vez, e a lista de traits. Pura.
prompt_valor_multi <- function(trecho_texto, traits, especie, ancora = NA_character_,
                               nomes = character(), tipo = "texto") {
  contexto <- if (is.na(ancora) || !nzchar(ancora)) "" else paste0(
    "O trecho nao repete o nome da especie; ele vem depois deste paragrafo, ",
    "que a nomeia (so contexto, nao copie valor dele):\n\"\"\"\n",
    substr(ancora, 1, 400), "\n\"\"\"\n\n")
  outros <- head(setdiff(nomes, especie), 12)
  tabela <- if (identical(tipo, "tabela")) paste0(
    "O trecho e uma tabela. A especie pode aparecer abreviada nas linhas; a ",
    "legenda diz a que especie corresponde cada abreviacao. Ache a linha da ",
    "especie e a coluna de cada trait; copie como span_verbatim a linha da especie ",
    "exatamente como esta no trecho.\n\n") else ""
  linha_trait <- function(t) {
    alt <- t$nomes_alternativos %||% NA_character_
    regra <- t$regra_extracao %||% NA_character_
    paste0("- ", t$trait_id, ": ", t$nome, " (unidade esperada: ", t$unidade, ")",
           if (!is.na(alt) && nzchar(alt)) paste0("; tambem aparece como: ", gsub(";", "; ", alt)) else "",
           if (!is.na(regra) && nzchar(regra)) paste0("\n  Regra para este trait: ", regra) else "")
  }
  paste0(
    "Especie: ", especie, "\n",
    if (length(outros)) paste0("Tambem chamada na literatura: ", paste(outros, collapse = "; "), "\n") else "",
    "Traits pedidos (responda um bloco para cada; cada bloco e independente, ",
    "com a propria frase copiada do trecho):\n",
    paste(map_chr(traits, linha_trait), collapse = "\n"), "\n\n",
    contexto, tabela,
    "Trecho:\n\"\"\"\n", trecho_texto, "\n\"\"\"")
}

#' Um trecho, varios traits. Devolve uma lista nomeada por trait_id, cada
#' item com os campos de tipo_valor() e `escalonado`. Trait que volta sem
#' span e refeito so, no modelo forte, com o reforco (como em
#' com_escalonamento()). Erro de API para a rodada (principio 1).
agente_valor_multi <- function(trecho_texto, traits, especie, cfg, ancora = NA_character_,
                               nomes = character(), tipo = "texto") {
  prompt <- prompt_valor_multi(trecho_texto, traits, especie, ancora, nomes, tipo)
  out <- tryCatch(criar_chat(cfg$agentes$valor, SISTEMA_VALOR)$chat_structured(prompt, type = tipo_valor_multi(traits)),
                  error = function(e) stop("chamada ao modelo falhou - ", cfg$agentes$valor$modelo, ": ",
                                           conditionMessage(e), call. = FALSE))
  set_names(map(traits, function(t) {
    r <- out[[t$trait_id]]
    vazio <- is.null(r) || is.null(r$span_verbatim) || is.na(r$span_verbatim)
    if (vazio && !is.null(cfg$agentes$forte)) {
      p1 <- paste0(prompt_valor(trecho_texto, t, especie, ancora, nomes, tipo), "\n\n", REFORCO_VALOR)
      r <- tryCatch(criar_chat(cfg$agentes$forte, SISTEMA_VALOR)$chat_structured(p1, type = tipo_valor(t)),
                    error = function(e) stop("chamada ao modelo falhou - ", cfg$agentes$forte$modelo, ": ",
                                             conditionMessage(e), call. = FALSE))
      return(c(r, list(escalonado = TRUE)))
    }
    c(r, list(escalonado = FALSE))
  }), map_chr(traits, "trait_id"))
}
