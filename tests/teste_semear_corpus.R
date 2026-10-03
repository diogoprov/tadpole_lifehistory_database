# Teste da semeadura do corpus a partir da BT 5 (semear_corpus()) e da
# gravacao de obras sem sobrescrever (registrar_obras()).
#
# Roda sem API: banco DuckDB em memoria.
#
#   Rscript tests/teste_semear_corpus.R
#
# Os defeitos (medidos numa copia do banco antes de semear, 03/10/2026):
# - INSERT OR REPLACE com status = "encontrada": 4 obras com PDF (inclusive
#   a redescricao de P. barrioi) perderiam caminho_pdf e status. A busca,
#   rodada de novo, fazia o mesmo.
# - DOI em caixa diferente ("10.2994/SAJH-D-13-00033.1") virava outra obra.
# - a mesma obra com DOI numa string da BT e sem DOI noutra virava duas.
# - o campo url da BT (PR #31) nao era lido.

suppressMessages({ library(dplyr); library(purrr); library(tibble) })
if (!dir.exists("R") && dir.exists("../R")) setwd("..")

e <- new.env()
for (f in c("R/db.R", "R/referencias_doi.R", "R/lista_alvo.R"))
  suppressMessages(eval(parse(text = paste(readLines(f, warn = FALSE), collapse = "\n")), envir = e))

falhas <- 0L
checar <- function(descricao, condicao) {
  cat(if (isTRUE(condicao)) "  ok   " else "  FALHA", descricao, "\n")
  if (!isTRUE(condicao)) falhas <<- falhas + 1L
  invisible(condicao)
}

con <- DBI::dbConnect(duckdb::duckdb(), ":memory:")
e$criar_esquema(con)

# obra ja no banco, achada pela busca e com PDF
id_barrioi <- e$id_de("10.1643/ch-10-142")
invisible(DBI::dbExecute(con, sprintf(
  "INSERT INTO obras (obra_id, doi, titulo, ano, fonte, caminho_pdf, ocr, status)
   VALUES ('%s', '10.1643/ch-10-142', 'Redescription of Physalaemus barrioi', 2012,
           'crossref', 'pdf/x.pdf', FALSE, 'pdf_manual')", id_barrioi)))
invisible(DBI::dbExecute(con, sprintf(
  "INSERT INTO triagem VALUES ('%s', TRUE, 0.9, 'humano', 'diogo', now())", id_barrioi)))

refs <- tribble(
  ~taxon_id,       ~carater,        ~autor,  ~ano, ~titulo,                                   ~periodico, ~doi,                          ~url,                                   ~raw,
  "phys_barrioi",  "ext_morph",     "Cruz",  2012, "Redescription of Physalaemus barrioi",    "Copeia",   "10.1643/CH-10-142",           NA,                                     "r1",
  "lept_caat",     "ext_morph",     "Mag",   2014, "The tadpole of Leptodactylus caatingae",  "SAJH",     "10.2994/SAJH-D-13-00033.1",   NA,                                     "r2",
  "lept_caat",     "internal_oral", "Mag",   2014, "The tadpole of Leptodactylus caatingae",  "SAJH",     "10.2994/sajh-d-13-00033.1",   NA,                                     "r3",
  "iron_a",        "ext_morph",     "Pez",   2021, "The Tadpoles of the Iron Quadrangle",     "SAJH",     "10.2994/sajh-d-20-00042.1",   NA,                                     "r4",
  "iron_b",        "ext_morph",     "Pez",   2021, "The tadpoles of the Iron Quadrangle.",    NA,         NA,                            NA,                                     "r5",
  "elosia",        "ext_morph",     "Lutz",  1923, "Elosia Tsch. e os generos correlatos",    "Mem IOC",  NA,                            "https://www.biodiversitylibrary.org/part/291339", "r6",
  "ranit_a",       "ext_morph",     "Sch",   2020, "Six poison-dart frogs of the genus Ranitomeya(Anura)",  NA, NA,                  NA,                                     "r7",
  "ranit_b",       "ext_morph",     "Sch",   2020, "Six poison-dart frogs of the genus Ranitomeya (Anura)", NA, NA,                  NA,                                     "r8")

n <- e$semear_corpus(con, refs)
ob <- DBI::dbGetQuery(con, "SELECT * FROM obras")
tr <- DBI::dbGetQuery(con, "SELECT * FROM triagem")
ot <- DBI::dbGetQuery(con, "SELECT * FROM obra_taxon")

cat("\nobra que ja existia\n")
b <- filter(ob, obra_id == id_barrioi)
checar("nao vira duplicata (DOI em maiuscula cai no mesmo obra_id)", nrow(filter(ob, tolower(doi) == "10.1643/ch-10-142")) == 1)
checar("PDF e status preservados", b$caminho_pdf == "pdf/x.pdf" && b$status == "pdf_manual")
checar("fonte original preservada", b$fonte == "crossref")
checar("triagem humana preservada", filter(tr, obra_id == id_barrioi)$decidido_por == "diogo")
checar("ganha o vinculo com a especie da BT", any(ot$obra_id == id_barrioi & ot$taxon_id == "phys_barrioi"))

cat("\nmesma obra em variacoes\n")
checar("DOI so com caixa diferente: uma obra so",
       nrow(filter(ob, doi == "10.2994/sajh-d-13-00033.1")) == 1 && !any(grepl("[A-Z]", ob$doi)))
checar("variacao sem DOI herda o DOI da que tem (mesmo titulo + ano)",
       nrow(filter(ob, grepl("iron quadrangle", tolower(titulo)))) == 1)
id_iron <- filter(ob, grepl("iron quadrangle", tolower(titulo)))$obra_id
checar("as duas especies ficam ligadas a essa obra",
       all(c("iron_a", "iron_b") %in% filter(ot, obra_id == id_iron)$taxon_id))
checar("sem DOI, variacao so de espaco: uma obra so",
       nrow(filter(ob, grepl("Ranitomeya", titulo))) == 1)
checar("total de obras: 5 (barrioi, caatingae, iron, elosia, ranitomeya)", nrow(ob) == 5 && n == 5)

cat("\ncampo url\n")
checar("url da BT vai para url_pagina",
       filter(ob, grepl("Elosia", titulo))$url_pagina == "https://www.biodiversitylibrary.org/part/291339")

cat("\nre-semear nao muda nada\n")
invisible(DBI::dbExecute(con, sprintf("UPDATE obras SET status = 'pdf_ok', caminho_pdf = 'pdf/e.pdf' WHERE obra_id = '%s'",
                            filter(ob, grepl("Elosia", titulo))$obra_id)))
invisible(e$semear_corpus(con, refs))
ob2 <- DBI::dbGetQuery(con, "SELECT * FROM obras")
checar("mesmo numero de obras", nrow(ob2) == nrow(ob))
checar("obra semeada que ganhou PDF nao volta a 'encontrada'",
       filter(ob2, grepl("Elosia", titulo))$status == "pdf_ok")

cat("\nregistrar_obras preenche so o que esta vazio\n")
invisible(DBI::dbExecute(con, sprintf("UPDATE obras SET url_pagina = NULL WHERE obra_id = '%s'", id_barrioi)))
e$registrar_obras(con, tibble(obra_id = id_barrioi, doi = "10.9999/outro", titulo = "outro titulo",
                              url_pagina = "https://exemplo.org", status = "encontrada"))
b2 <- DBI::dbGetQuery(con, sprintf("SELECT * FROM obras WHERE obra_id = '%s'", id_barrioi))
checar("DOI existente nao e trocado", b2$doi == "10.1643/ch-10-142")
checar("titulo existente nao e trocado", b2$titulo == "Redescription of Physalaemus barrioi")
checar("url_pagina vazia e preenchida", b2$url_pagina == "https://exemplo.org")
checar("status nao e trocado", b2$status == "pdf_manual")

DBI::dbDisconnect(con, shutdown = TRUE)
cat(if (falhas == 0) "\ntodos os testes passaram\n\n" else sprintf("\n%d FALHA(S)\n\n", falhas))
quit(status = if (falhas == 0) 0 else 1)
