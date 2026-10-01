# Conferencia da infraestrutura, antes de qualquer rodada.
#
# A ideia e falhar aqui, em segundos e de graca, em vez de descobrir no meio de
# uma rodada de 20 artigos que a chave expirou ou que o GROBID caiu. Nenhuma
# funcao daqui escreve na base nem gasta token alem de uma chamada minima.
#
# Uso:
#   source("R/diagnostico.R")
#   verificar_infra()                       # sem tocar em PDF
#   verificar_infra(pdf = "pdf/exemplo.pdf")  # inclui o teste do GROBID ponta a ponta

PACOTES <- c("targets", "config", "DBI", "duckdb", "dplyr", "purrr", "stringr",
             "tidyr", "httr2", "xml2", "readr", "jsonlite", "digest", "ellmer",
             "rlang", "readxl", "writexl", "curl")
PACOTES_OPCIONAIS <- c(cld3 = "deteccao de idioma dos trechos",
                       AmphiNom = "sinonimia da ASW")


# fumaca.R e diagnostico.R sao pontos de entrada: podem ser chamados com um
# source() solto, sem o {targets} ter carregado o resto de R/.
# source() sempre, nao so quando garantir_projeto() falta: uma versao velha
# dele em memoria e exatamente o que deixaria funcao velha passar.
source("R/carregar.R")
garantir_projeto()

ok   <- function(...) cat("  [ok]    ", ..., "\n", sep = "")
erro <- function(...) cat("  [FALTA] ", ..., "\n", sep = "")
aviso <- function(...) cat("  [aviso] ", ..., "\n", sep = "")

verificar_infra <- function(config_path = "config.yml", pdf = NULL) {
  cfg <- config::get(file = config_path)
  falhas <- 0L

  cat("\n1. Pacotes\n")
  faltando <- PACOTES[!map_lgl_simples(PACOTES, ~ requireNamespace(.x, quietly = TRUE))]
  if (length(faltando) == 0) ok(length(PACOTES), " pacotes presentes")
  else {
    erro("faltam: ", paste(faltando, collapse = ", "))
    cat('          install.packages(c("', paste(faltando, collapse = '", "'), '"))\n', sep = "")
    falhas <- falhas + 1L
  }
  for (p in names(PACOTES_OPCIONAIS)) {
    if (!requireNamespace(p, quietly = TRUE))
      aviso(p, " ausente (opcional: ", PACOTES_OPCIONAIS[[p]], ")")
  }

  cat("\n2. Chave de API\n")
  chave <- Sys.getenv("ANTHROPIC_API_KEY", "")
  if (nchar(chave) == 0) {
    erro("ANTHROPIC_API_KEY vazia. Ponha em ~/.Renviron (nao no config.yml,")
    cat("          nao no script, nao no git) e reinicie o R:\n")
    cat('          usethis::edit_r_environ()  ->  ANTHROPIC_API_KEY=sk-ant-...\n')
    falhas <- falhas + 1L
  } else {
    ok("variavel definida (", nchar(chave), " caracteres, nao mostro o valor)")
  }

  cat("\n3. Modelos\n")
  disponiveis <- NULL
  if (nchar(chave) > 0 && requireNamespace("ellmer", quietly = TRUE)) {
    disponiveis <- tryCatch(ellmer::models_anthropic(), error = function(e) {
      erro("a chave nao foi aceita: ", conditionMessage(e)); NULL })
    if (!is.null(disponiveis)) {
      ids <- disponiveis[[grep("^id$|model", names(disponiveis))[1]]]
      ok(length(ids), " modelos disponiveis para esta chave")
      cat("          ", paste(utils::head(ids, 12), collapse = ", "), "\n", sep = "")
    } else falhas <- falhas + 1L
  } else aviso("pulado (sem chave ou sem ellmer)")

  for (nome in names(cfg$agentes)) {
    m <- cfg$agentes[[nome]]$modelo
    if (grepl("PREENCHER", m)) {
      erro("agente '", nome, "' ainda com placeholder: ", m)
      falhas <- falhas + 1L
    } else if (!is.null(disponiveis)) {
      ids <- disponiveis[[grep("^id$|model", names(disponiveis))[1]]]
      if (m %in% ids) ok("agente '", nome, "': ", m)
      else {
        erro("agente '", nome, "': '", m, "' nao esta na lista da sua chave")
        falhas <- falhas + 1L
      }
    } else ok("agente '", nome, "': ", m, " (nao conferido contra a API)")
  }

  cat("\n4. Chamada real, com saida estruturada\n")
  if (nchar(chave) > 0 && requireNamespace("ellmer", quietly = TRUE) &&
      !grepl("PREENCHER", cfg$agentes$triagem$modelo)) {
    tipo <- ellmer::type_object(
      "teste de conexao",
      encontrado = ellmer::type_boolean("o trecho menciona o estagio de Gosner?"),
      span = ellmer::type_string("o trecho exato, copiado", required = FALSE))
    r <- tryCatch(
      ellmer::chat_anthropic(model = cfg$agentes$triagem$modelo,
                             system_prompt = "Responda so com o que esta no texto.")$
        chat_structured("Tadpoles at Gosner stage 36 were measured.", type = tipo),
      error = function(e) { erro("falhou: ", conditionMessage(e)); NULL })
    if (!is.null(r)) {
      ok("resposta estruturada recebida: encontrado = ", r$encontrado)
      # a validacao de span e a unica barreira automatica contra alucinacao;
      # se ela nao funcionar aqui, nao vai funcionar na extracao
      if (!is.null(r$span) && grepl(r$span, "Tadpoles at Gosner stage 36 were measured.", fixed = TRUE))
        ok("o span devolvido existe literalmente no texto")
      else aviso("o span devolvido nao bate com o texto - conferir antes de rodar")
    } else falhas <- falhas + 1L
  } else aviso("pulado")

  cat("\n5. GROBID\n")
  vivo <- tryCatch({
    httr2::request(paste0(cfg$grobid, "/api/isalive")) |>
      httr2::req_timeout(5) |> httr2::req_perform() |> httr2::resp_body_string()
  }, error = function(e) NULL)
  if (is.null(vivo)) {
    erro("nao respondeu em ", cfg$grobid)
    cat("          docker run --rm --init --ulimit core=0 -p 8070:8070 grobid/grobid:0.9.1-crf\n")
    falhas <- falhas + 1L
  } else {
    ok("vivo em ", cfg$grobid, " (resposta: ", trimws(vivo), ")")
    if (!is.null(pdf) && file.exists(pdf)) {
      tei <- tempfile(fileext = ".tei.xml")
      r <- tryCatch(grobid_tei(pdf, cfg$grobid, tei), error = function(e) {
        erro("falhou no PDF de teste: ", conditionMessage(e)); NULL })
      if (!is.null(r)) {
        tr <- tei_para_trechos(tei, "teste")
        ok(nrow(tr), " trechos extraidos de ", basename(pdf),
           " (", sum(tr$tipo == "tabela"), " tabelas)")
        if (nrow(tr) < 5) aviso("poucos trechos: o PDF pode ser digitalizado e precisar de OCR")
      } else falhas <- falhas + 1L
    } else if (!is.null(pdf)) aviso("PDF de teste nao encontrado: ", pdf)
  }

  cat("\n6. Banco\n")
  d <- tryCatch({
    con <- DBI::dbConnect(duckdb::duckdb(), cfg$db)
    on.exit(DBI::dbDisconnect(con, shutdown = TRUE))
    DBI::dbGetQuery(con, "SELECT 1 AS ok")
    DBI::dbListTables(con)
  }, error = function(e) { erro("nao abriu ", cfg$db, ": ", conditionMessage(e)); NULL })
  if (!is.null(d)) ok(cfg$db, " abre e escreve (", length(d), " tabelas)")
  else falhas <- falhas + 1L

  cat("\n7. Traits liberados para extracao\n")
  t <- readr::read_csv(cfg$traits, show_col_types = FALSE)
  fechados <- t[!is.na(t$status) & t$status == "fechado", ]
  sem_termo <- fechados[is.na(fechados$termos_busca) | fechados$termos_busca == "", ]
  if (nrow(fechados) == 0) {
    erro("nenhum trait com status = 'fechado'; a extracao nao tem o que rodar")
    falhas <- falhas + 1L
  } else {
    ok(nrow(fechados), " de ", nrow(t), " traits fechados: ",
       paste(fechados$trait_id, collapse = ", "))
    if (nrow(sem_termo) > 0) {
      erro("fechados mas sem termos_busca: ", paste(sem_termo$trait_id, collapse = ", "))
      falhas <- falhas + 1L
    }
  }

  cat("\n")
  if (falhas == 0) cat("Tudo pronto. Pode rodar o teste de fumaca.\n\n")
  else cat(falhas, " item(ns) pendente(s) acima.\n\n", sep = "")
  invisible(falhas)
}

# evita depender de purrr so para isto
map_lgl_simples <- function(x, f) {
  f <- rlang::as_function(f)
  vapply(x, function(i) isTRUE(f(i)), logical(1))
}
