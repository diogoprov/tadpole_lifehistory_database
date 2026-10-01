# Carrega todas as funcoes do projeto numa sessao comum de R.
#
# Dentro do {targets} isso e feito por tar_source("R"). Fora dele, um
# source("R/fumaca.R") solto so traz aquele arquivo, e a primeira funcao de
# outro arquivo estoura ("could not find function 'abrir_db'"). Este arquivo
# existe para as duas entradas se comportarem igual.
#
#   source("R/carregar.R"); carregar_projeto()

#' Carrega todos os .R do diretorio, menos este.
#'
#' A trava de reentrada nao e zelo: carregar_projeto() carrega tambem
#' fumaca.R e diagnostico.R, que no topo chamam garantir_projeto(). Em ordem
#' alfabetica diagnostico.R vem ANTES de parse.R, entao quando ele e carregado
#' grobid_tei() ainda nao existe, garantir_projeto() dispara de novo e a coisa
#' se chama para sempre. A trava corta isso.
#
#' A trava sobrevive a um novo source() deste arquivo: os pontos de entrada
#' fazem source("R/carregar.R") sempre, inclusive quando sao eles mesmos
#' carregados no meio de carregar_projeto(). Recriar a trava ali a zeraria e
#' reabriria o laco infinito.
if (!exists(".carregando", envir = globalenv(), inherits = FALSE)) {
  .carregando <- new.env(parent = emptyenv())
  .carregando$ativo <- FALSE
}

carregar_projeto <- function(dir = "R", silencioso = TRUE) {
  if (isTRUE(.carregando$ativo)) return(invisible(character()))
  .carregando$ativo <- TRUE
  on.exit(.carregando$ativo <- FALSE, add = TRUE)

  arquivos <- list.files(dir, pattern = "[.][Rr]$", full.names = TRUE)
  arquivos <- arquivos[!grepl("carregar[.][Rr]$", arquivos)]
  # Um arquivo que nao carrega (pacote faltando, por exemplo) nao pode derrubar
  # o resto: so o que depende dele e que fica de fora. O erro e reportado com o
  # nome do arquivo, em vez de um "there is no package called X" sem contexto.
  falhas <- character()
  for (f in arquivos) {
    r <- tryCatch({
      if (silencioso) suppressMessages(suppressWarnings(source(f, local = FALSE)))
      else source(f, local = FALSE)
      NULL
    }, error = function(e) conditionMessage(e))
    if (!is.null(r)) falhas[basename(f)] <- r
  }
  if (length(falhas) > 0) {
    warning("nao carregaram: ",
            paste(sprintf("%s (%s)", names(falhas), falhas), collapse = "; "),
            call. = FALSE)
  }
  invisible(setdiff(basename(arquivos), names(falhas)))
}

#' Chamado no topo dos pontos de entrada (fumaca.R, fumaca_busca.R,
#' diagnostico.R). Recarrega SEMPRE.
#'
#' Antes so carregava se faltasse alguma de seis funcoes-sentinela. Isso nao
#' enxerga versao velha: em 01/10/2026 montar_consultas() mudou de assinatura
#' (perdeu o argumento traits), a sessao ja tinha as sentinelas de uma rodada
#' anterior, nada foi recarregado, e a versao antiga em memoria estourou com
#' "$ operator is invalid for atomic vectors". Recarregar ~20 arquivos leva
#' menos de um segundo; depurar funcao velha em memoria leva uma tarde.
garantir_projeto <- function(dir = "R") {
  # Chamado de dentro de uma carga em andamento (o ponto de entrada sendo ele
  # mesmo carregado): nao verifica nada, porque os arquivos que vem depois em
  # ordem alfabetica ainda nao foram lidos. Quem verifica e a chamada de fora.
  if (isTRUE(.carregando$ativo)) return(invisible(TRUE))

  carregar_projeto(dir)
  precisa <- c("abrir_db", "grobid_tei", "tei_para_trechos",
               "recuperar_candidatos", "extrair_par", "registrar")
  faltam <- precisa[!vapply(precisa, exists, logical(1), mode = "function")]
  if (length(faltam) > 0) {
    stop("estas funcoes do projeto nao carregaram: ", paste(faltam, collapse = ", "),
         ".\nVeja os avisos acima: costuma ser pacote faltando. ",
         "Rode verificar_infra() para a lista.", call. = FALSE)
  }
  invisible(TRUE)
}
