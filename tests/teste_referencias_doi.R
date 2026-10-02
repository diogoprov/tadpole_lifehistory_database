# Teste da resolucao de DOI das referencias da BT 5.0 (R/referencias_doi.R).
#
# Roda sem API: as chamadas HTTP sao substituidas por respostas montadas.
#
#   Rscript tests/teste_referencias_doi.R
#
# Defeitos que este teste reproduz (02/10/2026, amostra de 50 + 30):
# - obra da OpenAlex com `authorships` vazio: list() nao e NULL, o %||% nao
#   pegava, e o [[1]] estourava "indice fora dos limites"; a referencia saia
#   como erro.
# - erro de API tem de sair como status "erro", nunca como "sem_casamento"
#   (principio 1).

suppressMessages({ library(dplyr); library(purrr); library(tibble) })
if (!dir.exists("R") && dir.exists("../R")) setwd("..")

e <- new.env()
`%||%` <- function(x, y) if (is.null(x)) y else x
e$`%||%` <- `%||%`
suppressMessages(eval(parse(text = paste(readLines("R/referencias_doi.R", warn = FALSE), collapse = "\n")), envir = e))

falhas <- 0L
checar <- function(descricao, condicao) {
  cat(if (isTRUE(condicao)) "  ok   " else "  FALHA", descricao, "\n")
  if (!isTRUE(condicao)) falhas <<- falhas + 1L
  invisible(condicao)
}

cat("\nnormalizacao e similaridade\n")
checar("tag HTML e acento saem do titulo",
       e$normalizar_titulo("Morfologia de <i>Scinax</i> catharinae: girino") ==
         "morfologia de scinax catharinae girino")
checar("mesmo titulo com caixa e acento diferentes da 1",
       e$similaridade_titulo("Notas taxonômicas sobre Pseudis", "Notas taxonomicas sobre PSEUDIS") == 1)
checar("girinos de especies diferentes nao passam de 0.95 (cobre o caso 'mesma obra')",
       e$similaridade_titulo("The tadpole of Scinax catharinae (Anura: Hylidae)",
                             "The tadpole of Scinax argyreornatus (Anura: Hylidae)") < 0.95)
checar("titulo da BT 5 sem o subtitulo do Crossref vai para revisao, nao some",
       e$decidir_casamento(e$similaridade_titulo("Redescription of the tadpole of Physalaemus barrioi",
                             "Redescription of the tadpole of Physalaemus barrioi, with notes on its natural history"),
                           2012, 2012, TRUE) == "revisar")
checar("entidade HTML do Crossref nao vira palavra 'amp'",
       e$normalizar_titulo("The tadpole of Scinax juncae Nunes &amp;amp; Pombal") ==
         e$normalizar_titulo("The tadpole of Scinax juncae Nunes & Pombal"))
# Rodada completa (02/10/2026): titulo contido no candidato valia 0.95 e
# aceitava a parte III de uma serie de mesmo titulo e o DOI de uma figura.
s_serie <- e$similaridade_titulo(
  "Contribution a l'etude des Amphibiens de Guyane francaise",
  "Contribution a l'etude des Amphibiens de Guyane francaise. III. Une nouvelle espece de Colostethus")
checar("titulo contido em outro leva no maximo a 'revisar' (serie com mesmo titulo)",
       e$decidir_casamento(s_serie, 1975, 1975, TRUE) == "revisar")
checar("titulo curto contido em outro nao conta (seria metade da literatura)",
       e$similaridade_titulo("The tadpole", "The tadpole of Physalaemus barrioi from Minas Gerais") < 0.75)

cat("\nautor\n")
checar("'Cei, J. M' confere com sobrenome Cei", e$autor_confere("Cei, J. M", "Cei"))
checar("nome por extenso confere", e$autor_confere("Tiago Leite Pezzuti, Felipe Leite", "Pezzuti"))
checar("sobrenome composto confere pela parte mais longa",
       e$autor_confere("Carvalho-e-Silva, A. M. P. T. and Carvalho-e-Silva, S. P.", "Carvalho-e-Silva"))
checar("outro autor nao confere", !e$autor_confere("Cei, J. M", "Lutz"))
checar("candidato sem autor da NA", is.na(e$autor_confere("Cei, J. M", NA)))

cat("\nveredito\n")
checar("titulo, ano e autor batem: aceito", e$decidir_casamento(0.97, 2008, 2008, TRUE) == "aceito")
checar("ano a 1 de distancia: revisar", e$decidir_casamento(0.99, 1983, 1984, TRUE) == "revisar")
checar("sem autor no candidato: revisar, nunca aceito", e$decidir_casamento(1, 2008, 2008, NA) == "revisar")
checar("autor que nao confere com titulo alto: revisar (por similaridade)",
       e$decidir_casamento(0.95, 2008, 2008, FALSE) == "revisar")
checar("ano distante e titulo medio: sem casamento", e$decidir_casamento(0.6, 1980, 1956, FALSE) == "sem_casamento")
checar("sem similaridade: sem casamento", e$decidir_casamento(NA, 2008, 2008, TRUE) == "sem_casamento")

cat("\nOpenAlex com authorships vazio\n")
e$req_api <- function(url, query, pausa = 1) list(results = list(list(
  id = "https://openalex.org/W1", doi = NULL, title = "Musculatura asociada al primer arco visceral",
  publication_year = 1999, authorships = list(),
  primary_location = list(source = NULL), best_oa_location = NULL)))
oa <- tryCatch(e$candidatos_openalex("Musculatura asociada al primer arco visceral", "x@y.z"),
               error = function(err) err)
checar("nao estoura com authorships = list()", !inherits(oa, "error"))
checar("devolve o candidato com sobrenome NA",
       !inherits(oa, "error") && nrow(oa) == 1 && is.na(oa$sobrenome_cand) && oa$openalex_id == "W1")

cat("\nCrossref com author vazio\n")
e$req_api <- function(url, query, pausa = 1) list(message = list(items = list(list(
  DOI = "10.1/X", title = list("Um titulo"), issued = list(`date-parts` = list(list(1990))),
  author = list(), `container-title` = list()))))
cr <- tryCatch(e$candidatos_crossref("Um titulo", "x@y.z"), error = function(err) err)
checar("nao estoura com author = list()", !inherits(cr, "error") && is.na(cr$sobrenome_cand))
checar("DOI em minusculas", !inherits(cr, "error") && cr$doi == "10.1/x")

cat("\nCrossref: figura com DOI proprio fica fora\n")
e$req_api <- function(url, query, pausa = 1) list(message = list(items = list(
  list(DOI = "10.3897/zookeys.706.f4", type = "component",
       title = list("Figure 4. A new species of Scinax from the Purus-Madeira interfluve"),
       issued = list(`date-parts` = list(list(2017)))),
  list(DOI = "10.3897/zookeys.706.13385", type = "journal-article",
       title = list("A new species of Scinax from the Purus-Madeira interfluve"),
       issued = list(`date-parts` = list(list(2017)))))))
cr <- e$candidatos_crossref("A new species of Scinax", "x@y.z")
checar("so o artigo sobra", nrow(cr) == 1 && cr$doi == "10.3897/zookeys.706.13385")

cat("\nerro de API nao vira 'sem casamento'\n")
e$req_api <- function(url, query, pausa = 1) stop("HTTP 503 Service Unavailable")
ref <- tibble(chave = "k", autor = "Cei, J. M", ano = 1980L, titulo = "Um titulo qualquer",
              periodico = NA_character_, raw = "Cei 1980", doi_bt5 = NA_character_, n_especies = 1L)
res <- e$resolver_referencias(ref, "x@y.z", progresso = FALSE)
checar("status_busca = erro", res$status_busca == "erro")
checar("veredito fica NA, nao sem_casamento", is.na(res$veredito))
checar("a mensagem do erro e guardada", grepl("503", res$erro))

cat("\nBHL\n")
checar("volume do mesmo periodico e ano: volume_provavel",
       e$decidir_volume_bhl(0.9, 1975, "1975") == "volume_provavel")
checar("volume de outro ano: sem casamento", e$decidir_volume_bhl(0.9, 1975, "1980") == "sem_casamento")
checar("volume de outro periodico: sem casamento", e$decidir_volume_bhl(0.3, 1975, "1975") == "sem_casamento")
checar("sem chave, para em vez de devolver 'nada'",
       inherits(tryCatch(e$resolver_bhl(ref, chave = "", progresso = FALSE), error = function(err) err), "error"))
# 02/10/2026: busca sem resultado devolvia tibble sem colunas, o filter()
# estourava e a obra saia como "erro" em vez de "sem_casamento"
e$req_api <- function(url, query, pausa = 1) list(Status = "ok", Result = list())
b <- e$resolver_bhl(ref, chave = "k", progresso = FALSE)
checar("busca vazia no BHL: sem_casamento, nao erro", b$bhl_veredito == "sem_casamento")
e$req_api <- function(url, query, pausa = 1) stop("HTTP 500 Internal Server Error")
b <- e$resolver_bhl(ref, chave = "k", progresso = FALSE)
checar("erro no BHL: veredito NA e mensagem guardada", is.na(b$bhl_veredito) && grepl("500", b$bhl_erro))
e$req_api <- function(url, query, pausa = 1) list(Status = "unauthorized", ErrorMessage = "invalid API key")
b <- e$resolver_bhl(ref, chave = "k", progresso = FALSE)
checar("chave recusada pelo BHL: erro, nao 'nada'", is.na(b$bhl_veredito) && grepl("invalid", b$bhl_erro))

cat("\nconsolidacao das tres fontes\n")
cv <- e$consolidar_veredito
checar("Crossref aceito ganha", cv("aceito", "10.1/a", "aceito", "10.1/b", NA) == "aceito:crossref")
checar("OpenAlex aceito quando o Crossref nao achou", cv("sem_casamento", NA, "aceito", "10.1/b", NA) == "aceito:openalex")
checar("OpenAlex aceito com outro DOI no 'revisar' do Crossref: conflito vai para revisao",
       cv("revisar", "10.1/a", "aceito", "10.1/b", NA) == "revisar")
checar("OpenAlex aceito com o mesmo DOI do 'revisar' do Crossref: aceito",
       cv("revisar", "10.1/a", "aceito", "10.1/a", NA) == "aceito:openalex")
checar("BHL aceito so depois das outras", cv("sem_casamento", NA, "sem_casamento", NA, "aceito") == "aceito:bhl")
checar("volume provavel do BHL nao vira aceito", cv("sem_casamento", NA, "sem_casamento", NA, "volume_provavel") == "volume_provavel")
checar("fonte com erro e nada achado: erro, nao sem casamento",
       cv("sem_casamento", NA, NA, NA, NA, erro = TRUE) == "erro")
checar("erro numa fonte nao apaga aceito de outra", cv("aceito", "10.1/a", NA, NA, NA, erro = TRUE) == "aceito:crossref")

cat("\nreferencias distintas\n")
refs <- tibble(taxon_id = c("a", "b", "c"), carater = "ext_morph",
               autor = c("Cei, J. M", "Cei, J.M.", "Lutz, B."), ano = c(1980L, 1980L, 1950L),
               titulo = c("Sobre o girino de <i>Hyla</i>", "Sobre o girino de Hyla", "Outro"),
               periodico = NA_character_, doi = c(NA, "10.1/ABC", NA), raw = c("r1", "r2", "r3"))
d <- e$referencias_distintas(refs)
checar("mesma obra com strings diferentes vira uma linha", nrow(d) == 2)
checar("o DOI de uma das strings fica com a obra", d$doi_bt5[d$ano == 1980] == "10.1/abc")
checar("a obra conta as duas especies", d$n_especies[d$ano == 1980] == 2)

cat(if (falhas == 0) "\ntodos os testes passaram\n\n" else sprintf("\n%d FALHA(S)\n\n", falhas))
quit(status = if (falhas == 0) 0 else 1)
