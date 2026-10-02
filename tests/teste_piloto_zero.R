# Teste do piloto zero (docs/piloto-zero.md): referencia da planilha,
# comparacao, rodadas separadas, registro das chamadas e do contexto.
#
# Sem API e sem GROBID: o modelo e substituido, os bancos sao temporarios.
#
#   Rscript tests/teste_piloto_zero.R
#
# Os defeitos que ele trava, todos levantados lendo o codigo em 01/10/2026:
# 1. escalonamento que termina em "nao encontrado" nao deixava rastro;
# 2. contexto_obra nao dizia se o texto veio de Metodos ou da busca por estagio;
# 3. trechos ja gravados nao recebiam o parse novo (estruturar_obras() pula);
# 4. uma segunda rodada no mesmo banco sobrescreveria a primeira, e rodar por
#    obra com estado_par pularia a especie que outra obra ja extraiu.

if (!dir.exists("R") && dir.exists("../R")) setwd("..")
faltam <- c("duckdb", "ellmer", "config")[!vapply(c("duckdb", "ellmer", "config"),
                                                   requireNamespace, logical(1), quietly = TRUE)]
if (length(faltam)) {
  cat("\n(pulado: faltam os pacotes", paste(faltam, collapse = ", "), ")\n\n"); quit(status = 0)
}
suppressMessages(suppressWarnings({
  source("R/carregar.R"); carregar_projeto("R")
}))

falhas <- 0L
checar <- function(descricao, condicao) {
  cat(if (isTRUE(condicao)) "  ok   " else "  FALHA", descricao, "\n")
  if (!isTRUE(condicao)) falhas <<- falhas + 1L
  invisible(condicao)
}
erro <- function(expr) inherits(try(expr, silent = TRUE), "try-error")
tb <- tibble::tibble

# ---------------------------------------------------------------------------
cat("\nmapa das 11 fontes\n")
mapa <- ler_mapa_piloto()
checar("11 fontes", nrow(mapa) == 11)
checar("eventid unico", !anyDuplicated(mapa$eventid))
checar("so o livro de 2024 fica sem PDF",
       identical(mapa$citacao[is.na(mapa$arquivo_pdf)], "Rossa-Feres et al. (2024)"))
checar("todo PDF tem a forma de conferencia registrada",
       all(!is.na(mapa$conferido_por[!is.na(mapa$arquivo_pdf)])))
if (file.exists("dwca/measurementorfact.txt")) {
  ev <- unique(evento_canonico(readr::read_tsv("dwca/measurementorfact.txt", show_col_types = FALSE,
                                               col_types = readr::cols(.default = "c"))$eventID))
  checar("toda fonte da planilha esta no mapa, menos o erro de digitacao BN00706012007",
         identical(setdiff(ev, mapa$eventid), "BN00706012007"))
}

# ---------------------------------------------------------------------------
cat("\nreferencia_planilha()\n")
checar("sufixo :temporary sai", evento_canonico("10.2994/057.004.0311:temporary") == "10.2994/057.004.0311")
checar("URL com ':' fica intacta",
       evento_canonico("https://doi.org/10.2994/SAJH-D-20-00042.1") == "https://doi.org/10.2994/SAJH-D-20-00042.1")
mapa_f <- tb(eventid = c("E1", "E2"), citacao = c("A (2001)", "B (2002)"))
mof <- tb(measurementID = paste0("m", 1:5), taxonID = c("T1", "T1", "T2", "T1", "T9"),
          measurementType = c("eyes_positioning", "snout_shape_lv", "eyes_positioning",
                              "body_shape_dv", "eyes_positioning"),
          measurementValue = c("dorsal", "rounded", "lateral", "ovoid", "dorsal"),
          eventID = c("E1", "E1:temporary", "E2", "E1", "E3"))
taxon <- tb(taxonID = c("T1", "T2", "T9"), scientificName = c("Sp um", "Sp dois", "Sp nove"))
avisou <- FALSE
ref <- withCallingHandlers(referencia_planilha(mof, taxon, mapa_f),
                           warning = function(w) { avisou <<- grepl("E3", conditionMessage(w)); invokeRestart("muffleWarning") })
checar("so os traits do piloto", all(ref$trait_id %in% TRAITS_PILOTO) && !"body_shape_dv" %in% ref$trait_id)
checar("registro com sufixo entra na obra certa", "m2" %in% ref$measurementID[ref$eventid == "E1"])
checar("fonte fora do mapa avisa (nao some calada)", avisou)
checar("obra_id e o mesmo para o mesmo eventid", length(unique(ref$obra_id[ref$eventid == "E1"])) == 1)

# ---------------------------------------------------------------------------
cat("\nclassificar_par() e comparar_pares()\n")
checar("igual, sem caixa e espaco", classificar_par("Rounded ", "rounded") == "igual")
checar("diverge", classificar_par("rounded", "truncated") == "diverge")
checar("so_planilha", classificar_par("rounded", character()) == "so_planilha")
checar("so_modelo", classificar_par(NA, "rounded") == "so_modelo")
checar("nada dos dois lados nao e par", is.na(classificar_par(character(), NA)))
checar("dois valores do modelo contra um da planilha diverge",
       classificar_par("rounded", c("rounded", "truncated")) == "diverge")
ref2 <- tb(obra_id = "o1", taxon_id = c("T1", "T1", "T2"), trait_id = c("eyes_positioning", "snout_shape_lv", "eyes_positioning"),
           valor = c("dorsal", "rounded", "lateral"))
mod <- tb(obra_id = "o1", taxon_id = c("T1", "T2", "T3"), trait_id = c("eyes_positioning", "eyes_positioning", "snout_shape_lv"),
          valor_cat = c("dorsal", "dorsolateral", "rounded"), span_verbatim = "s", secao = NA)
cp <- comparar_pares(ref2, mod)
caso <- function(t, tr) cp$caso[cp$taxon_id == t & cp$trait_id == tr]
checar("um par por caso",
       caso("T1", "eyes_positioning") == "igual" && caso("T1", "snout_shape_lv") == "so_planilha" &&
         caso("T2", "eyes_positioning") == "diverge" && caso("T3", "snout_shape_lv") == "so_modelo")

cat("\nestabilidade_rodadas()\n")
r1 <- tb(obra_id = "o1", taxon_id = c("T1", "T2"), trait_id = "eyes_positioning", valor_cat = c("dorsal", "lateral"))
r2 <- tb(obra_id = "o1", taxon_id = "T1", trait_id = "eyes_positioning", valor_cat = "Dorsal")
es <- estabilidade_rodadas(r1, r2, tb(obra_id = "o1", taxon_id = c("T1", "T2", "T3"), trait_id = "eyes_positioning"))
checar("mesmo valor nas duas e estavel", es$estavel[es$taxon_id == "T1"])
checar("achou numa e nao na outra e instavel", !es$estavel[es$taxon_id == "T2"])
checar("nada nas duas e estavel", es$estavel[es$taxon_id == "T3"])

cat("\nconcordancia_adjudicada()\n")
adj <- tb(obra_id = "o1", taxon_id = c("T1", "T2", "T3"), trait_id = c("snout_shape_lv", "eyes_positioning", "snout_shape_lv"),
          veredito = c("Planilha", "modelo", "ambos"))
ca <- concordancia_adjudicada(cp, adj)
checar("eyes: 2 pares, modelo certo nos 2 (igual + veredito 'modelo')",
       ca$modelo_certo[ca$trait_id == "eyes_positioning"] == 1)
checar("snout: so_planilha com veredito 'planilha' conta erro do modelo",
       ca$erros_do_modelo[ca$trait_id == "snout_shape_lv"] == 1)
checar("veredito vazio impede o numero",
       erro(concordancia_adjudicada(cp, mutate(adj, veredito = c("planilha", NA, "ambos")))))
checar("veredito fora da lista impede o numero",
       erro(concordancia_adjudicada(cp, mutate(adj, veredito = c("planilha", "talvez", "ambos")))))

# ---------------------------------------------------------------------------
cat("\nbanco: chamadas, contexto, reestruturacao\n")
d <- tempfile("piloto_"); dir.create(d)
con <- suppressMessages(abrir_db(file.path(d, "t.duckdb")))
checar("tabela chamadas_valor existe", "chamadas_valor" %in% DBI::dbListTables(con))
checar("coluna fonte_contexto existe", "fonte_contexto" %in% DBI::dbListFields(con, "contexto_obra"))
registrar(con, "alvo", tb(taxon_id = "T1", especie = "Sp um"))
registrar(con, "trechos", tb(trecho_id = "tr1", obra_id = "o1", tipo = "texto", secao = NA_character_,
                             pagina = NA_integer_, idioma = NA_character_,
                             texto = "Two Stage 36 tadpoles of Sp um were examined; eyes dorsal."))

# o modelo: sempre escala e nunca acha (o caso que nao deixava rastro)
recuperar_candidatos <- function(con, obra_id, taxon_id, trait)
  tb(trecho_id = "tr1", tipo = "texto", secao = NA_character_, pagina = NA_integer_,
     idioma = NA_character_, texto = "x", escore = 1)
agente_valor <- function(...) list(encontrado = FALSE, escalonado = TRUE)
com_escalonamento <- function(prompt, ...) list(estagio = "36", escalonado = FALSE)
cfg_t <- list(encoder_local = "", agentes = list(valor = list(modelo = "s"), forte = list(modelo = "o")),
              prompt_versao = "t")
trait <- list(trait_id = "eyes_positioning", tipo = "categorico")
ext <- extrair_par(con, "o1", "T1", trait, cfg_t)
ch <- DBI::dbGetQuery(con, "SELECT * FROM chamadas_valor")
checar("nenhum registro de valor", nrow(ext) == 0)
checar("mas a chamada escalonada sem resultado ficou registrada",
       nrow(ch) == 1 && ch$escalonado && !ch$encontrado)
ctx <- DBI::dbGetQuery(con, "SELECT fonte_contexto, estagio FROM contexto_obra WHERE obra_id = 'o1'")
checar("contexto da obra sem Metodos gravado como 'estagio'", identical(ctx$fonte_contexto, "estagio"))
registrar(con, "trechos", tb(trecho_id = "tr2", obra_id = "o2", tipo = "texto", secao = "Canto",
                             pagina = NA_integer_, idioma = NA_character_, texto = "O canto tem uma nota so."))
invisible(obter_contexto(con, "o2", cfg_t))
checar("obra sem nada para ler fica 'nenhum'",
       identical(DBI::dbGetQuery(con, "SELECT fonte_contexto FROM contexto_obra WHERE obra_id = 'o2'")[[1]], "nenhum"))
rm(recuperar_candidatos, agente_valor, com_escalonamento)

# reestruturacao: trecho gravado com o parse antigo (so o titulo imediato)
tei_dir <- file.path(d, "tei"); dir.create(tei_dir)
txt <- "We carried out field work in the Serra da Bocaina National Park, Sao Paulo state."
writeLines(paste0('<TEI xmlns="http://www.tei-c.org/ns/1.0"><text><body>',
                  '<div><head>MATERIALS AND METHODS</head></div>',
                  '<div><head>Study area</head><p>', txt, '</p></div></body></text></TEI>'),
           file.path(tei_dir, "o3.tei.xml"))
id_antigo <- id_de("o3", txt)
registrar(con, "trechos", tb(trecho_id = id_antigo, obra_id = "o3", tipo = "texto", secao = "Study area",
                             pagina = NA_integer_, idioma = NA_character_, texto = txt))
r <- reestruturar_de_tei(con, list(dir_tei = tei_dir), c("o3", "sem_tei"))
t3 <- DBI::dbGetQuery(con, "SELECT trecho_id, secao FROM trechos WHERE obra_id = 'o3'")
checar("o trecho ganha a secao de Metodos", identical(t3$secao, "MATERIALS AND METHODS / Study area"))
checar("o trecho_id nao muda (extracoes continuam apontando)", identical(t3$trecho_id, id_antigo))
checar("obra sem TEI aparece com NA, intacta", is.na(r$n_trechos[r$obra_id == "sem_tei"]))
DBI::dbDisconnect(con, shutdown = TRUE)

# ---------------------------------------------------------------------------
cat("\nrodar_rodada()\n")
base <- file.path(d, "base.duckdb")
con <- suppressMessages(abrir_db(base))
registrar(con, "obra_taxon", tb(obra_id = c("oA", "oB"), taxon_id = "T1", fonte = "piloto_zero"))
invisible(semear_estado_par(con, tb(taxon_id = "T1"), tb(trait_id = TRAITS_PILOTO)))
DBI::dbDisconnect(con, shutdown = TRUE)
traits_csv <- file.path(d, "traits.csv")
readr::write_csv(tb(trait_id = TRAITS_PILOTO, nome = "x", tipo = "categorico", unidade = NA,
                    valores_aceitos = "dorsal;lateral", min_plausivel = NA, max_plausivel = NA,
                    termos_busca = "x", status = "fechado"), traits_csv)
chamados <- character()
extrair_par <- function(con, obra_id, taxon_id, trait, cfg) {
  chamados <<- c(chamados, paste(obra_id, taxon_id, trait$trait_id))
  # simula a extracao marcando o par como extraido, como extrair_tudo() faria
  atualizar_estado_par(con, taxon_id, trait$trait_id, "extraido")
  tibble::tibble()
}
gasto <- 0
uso_tokens <- function() tb(provider = "a", model = "m", input = gasto, output = 0)
custo_tokens <- function(antes, depois) { gasto <<- gasto + 1; tb(model = "m", input = 1, output = 0, usd = 1) }
invisible(suppressMessages(rodar_rodada(list(traits = traits_csv), 1, dir_saida = d, limite_usd = 10)))
checar("a especie compartilhada e extraida nas duas obras (nao e pulada)",
       all(c("oA T1 eyes_positioning", "oB T1 eyes_positioning") %in% chamados))
checar("a rodada fica no proprio banco, o base intacto",
       file.exists(file.path(d, "rodada_1.duckdb")) &&
         { cb <- DBI::dbConnect(duckdb::duckdb(), base, read_only = TRUE)
           n <- !"custo_obra" %in% DBI::dbListTables(cb); DBI::dbDisconnect(cb, shutdown = TRUE); n })
cr <- DBI::dbConnect(duckdb::duckdb(), file.path(d, "rodada_1.duckdb"), read_only = TRUE)
co <- DBI::dbGetQuery(cr, "SELECT obra_id, usd FROM custo_obra"); DBI::dbDisconnect(cr, shutdown = TRUE)
checar("custo registrado por obra", setequal(co$obra_id, c("oA", "oB")))
checar("rodada que ja existe nao e refeita por cima",
       erro(suppressMessages(rodar_rodada(list(traits = traits_csv), 1, dir_saida = d))))
msg <- tryCatch(suppressMessages(rodar_rodada(list(traits = traits_csv), 2, dir_saida = d, limite_usd = 0.5)),
                error = conditionMessage)
checar("passou do limite: para com mensagem", grepl("limite", msg))
rm(extrair_par, uso_tokens, custo_tokens)

# Rodada 3 do piloto (02/10/2026): limite de US$ 2, gasto de US$ 2,36. O
# limite so era conferido no fim de cada obra, e a ultima custou US$ 0,89; e o
# stop() pulava a reconciliacao. Aqui: uma obra com 6 pares a US$ 0,30 cada,
# limite de US$ 0,50. A regra antiga gastaria US$ 1,80 antes de parar.
cat("\nrodar_rodada(): limite conferido a cada par\n")
base2 <- file.path(d, "base2"); dir.create(base2)
con <- suppressMessages(abrir_db(file.path(base2, "base.duckdb")))
registrar(con, "obra_taxon", tb(obra_id = "oA", taxon_id = c("T1", "T2", "T3"), fonte = "piloto_zero"))
DBI::dbDisconnect(con, shutdown = TRUE)
n_chamadas <- 0L
extrair_par <- function(con, obra_id, taxon_id, trait, cfg) { n_chamadas <<- n_chamadas + 1L; tibble::tibble() }
uso_tokens <- function() tb(provider = "a", model = "m", input = n_chamadas, output = 0)
custo_tokens <- function(antes, depois) tb(model = "m", input = depois$input - antes$input, output = 0,
                                           usd = (depois$input - antes$input) * 0.30)
reconciliou <- FALSE
reconciliar_internas <- function(con, traits) { reconciliou <<- TRUE; tibble::tibble() }
msg <- tryCatch(suppressMessages(rodar_rodada(list(traits = traits_csv), 1, dir_saida = base2, limite_usd = 0.5)),
                error = conditionMessage)
checar("para no par que passou do limite (2 chamadas, nao 6)", n_chamadas == 2L)
checar("a mensagem diz onde parou", grepl("parado em oA, especie T1", msg))
checar("a reconciliacao roda mesmo parando", reconciliou)
cr <- DBI::dbConnect(duckdb::duckdb(), file.path(base2, "rodada_1.duckdb"), read_only = TRUE)
co <- DBI::dbGetQuery(cr, "SELECT obra_id, usd FROM custo_obra"); DBI::dbDisconnect(cr, shutdown = TRUE)
checar("o custo parcial da obra fica registrado", nrow(co) == 1 && abs(co$usd - 0.6) < 1e-9)
rm(extrair_par, uso_tokens, custo_tokens, reconciliar_internas)

unlink(d, recursive = TRUE)
cat(if (falhas == 0) "\ntodos os testes passaram\n\n" else sprintf("\n%d FALHA(S)\n\n", falhas))
quit(status = if (falhas == 0) 0 else 1)
