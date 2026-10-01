# Teste da montagem da consulta e da ligacao obra -> taxon.
#
# Roda sem API e sem banco. Trava dois defeitos achados em 01/10/2026, antes
# da busca rodar uma vez:
#
# 1. montar_consultas() punha os `termos_busca` dos 48 traits como terceira
#    clausula AND. Medido contra a OpenAlex: 33 termos -> ZERO resultados para
#    "Physalaemus barrioi"; sem a clausula -> 23, com o artigo certo em 1o.
#    Alem disso as 46 linhas sem termo injetavam o literal "NA" na consulta.
#
# 2. A ligacao obra -> taxon se perdia: 'obras' nao tem taxon_id, e tanto
#    executar_busca() quanto semear_corpus() deduplicavam por obra antes de
#    gravar. Com isso extrair_tudo() so podia fazer CROSS JOIN.
#
#   Rscript tests/teste_busca.R

suppressMessages({ library(dplyr); library(tibble); library(tidyr) })
if (!dir.exists("R") && dir.exists("../R")) setwd("..")

e <- new.env()
eval(parse(text = paste(readLines("R/busca.R", warn = FALSE), collapse = "\n")), envir = e)
montar_consultas <- e$montar_consultas
TERMOS_GIRINO <- e$TERMOS_GIRINO

falhas <- 0L
checar <- function(descricao, condicao) {
  cat(if (isTRUE(condicao)) "  ok   " else "  FALHA", descricao, "\n")
  if (!isTRUE(condicao)) falhas <<- falhas + 1L
  invisible(condicao)
}

taxa <- tibble(taxon_id = "T1", especie = "Physalaemus barrioi")

cat("\nmontar_consultas()\n")
q <- montar_consultas(taxa, c("pt", "en", "es"))
checar("uma consulta por idioma", nrow(q) == 3)
checar("o binomio entra entre aspas",
       all(grepl('"Physalaemus barrioi"', q$consulta, fixed = TRUE)))
checar("cada idioma traz seus proprios termos de girino",
       grepl("girino", q$consulta[q$idioma == "pt"]) &&
       grepl("tadpole", q$consulta[q$idioma == "en"]) &&
       grepl("renacuajo", q$consulta[q$idioma == "es"]))

cat("\nos termos de trait NAO entram na consulta\n")
checar("sem 'eyes'",   !any(grepl("eyes",    q$consulta)))
checar("sem 'snout'",  !any(grepl("snout",   q$consulta)))
checar("sem 'focinho'",!any(grepl("focinho", q$consulta)))
checar("sem o literal NA (as 46 linhas sem termo)",
       !any(grepl("\\bNA\\b", q$consulta)))
checar("nao sobrou coluna termos_trait", !"termos_trait" %in% names(q))
checar("duas clausulas AND, nao tres",
       all(lengths(regmatches(q$consulta, gregexpr(" AND ", q$consulta))) == 1))
checar("a consulta cabe num parametro de URL razoavel",
       all(nchar(q$consulta) < 120))

cat("\nfiltro por tipo de registro\n")
lixo <- c("dataset", "component", "peer-review", "erratum", "editorial",
          "paratext", "supplementary-materials", "software", "database")
checar("OpenAlex: nenhum tipo-lixo na lista", !any(e$TIPOS_OPENALEX %in% lixo))
checar("Crossref: nenhum tipo-lixo na lista", !any(e$TIPOS_CROSSREF %in% lixo))
checar("OpenAlex: artigo e tese entram",
       all(c("article", "dissertation") %in% e$TIPOS_OPENALEX))
checar("Crossref: artigo, capitulo e tese entram",
       all(c("journal-article", "book-chapter", "dissertation") %in% e$TIPOS_CROSSREF))
corpo <- paste(readLines("R/busca.R", warn = FALSE), collapse = "\n")
checar("buscar_openalex() manda o filtro", grepl("filter = paste0\\(\"type:\", paste\\(TIPOS_OPENALEX", corpo))
checar("buscar_crossref() manda o filtro", grepl("filter = paste0\\(\"type:\", TIPOS_CROSSREF", corpo))
# sintaxe: OpenAlex usa | dentro de um filtro; Crossref repete a chave com virgula
checar("sintaxe OpenAlex (type:a|b)",
       grepl("^type:[a-z-]+(\\|[a-z-]+)+$", paste0("type:", paste(e$TIPOS_OPENALEX, collapse = "|"))))
checar("sintaxe Crossref (type:a,type:b)",
       grepl("^type:[a-z-]+(,type:[a-z-]+)+$", paste0("type:", e$TIPOS_CROSSREF, collapse = ",")))

cat("\nCrossref: so entra se o titulo citar a especie\n")
# padrao_especie() mora em recuperacao.R
suppressMessages(library(stringr)); suppressMessages(library(purrr))
r <- new.env()
eval(parse(text = paste(readLines("R/recuperacao.R", warn = FALSE), collapse = "\n")), envir = r)
environment(e$titulo_cita_especie) <- list2env(list(padrao_especie = r$padrao_especie),
                                               parent = globalenv())
cita <- function(t, nomes = "Physalaemus barrioi") e$titulo_cita_especie(t, nomes)
# titulos reais devolvidos pelo Crossref em 01/10/2026
checar("o artigo certo passa",
       cita("Redescription of Physalaemus barrioi (Anura: Leiuperidae)"))
checar("girino de outra especie do genero fica de fora",
       !cita("The tadpole of Physalaemus henselii (Peters) (Anura: Leiuperidae)"))
checar("mesmo epiteto em outro genero fica de fora (Leptodactylus)",
       !cita("The tadpole of Leptodactylus barrioi from the Atlantic Forest of southeastern Brazil"))
checar("mesmo epiteto numa serpente fica de fora",
       !cita("Revalidation of Apostolepis barrioi (Serpentes: Dipsadidae)"))
checar("girino de ascidia fica de fora",
       !cita("The ascidian tadpole larva: comparative molecular development"))
checar("genero abreviado passa", cita("Notes on the tadpole of P. barrioi"))
checar("binomio partido em tags HTML passa",
       cita("Redescription of <i>Physalaemus</i> <i>barrioi</i>"))
# combinacao ficticia de proposito: testa o mecanismo, nao afirma sinonimia
checar("sinonimo passa quando esta na lista de nomes",
       cita("Larva de Generoficticio barrioi", c("Physalaemus barrioi", "Generoficticio barrioi")))
checar("titulo ausente nao quebra", identical(cita(NA_character_), FALSE))
checar("vetorizado", identical(cita(c("Physalaemus barrioi", "nada")), c(TRUE, FALSE)))
checar("executar_busca() aplica o filtro so no Crossref",
       grepl("cr <- cr\\[titulo_cita_especie\\(cr\\$titulo, aliases_de\\(con, taxon_id\\)\\), \\]", corpo) &&
       !grepl("buscar_openalex\\(q, idioma, cfg\\$email\\)[^\n]*titulo_cita", corpo))

cat("\nmontar_consultas() nao depende mais de traits\n")
checar("assinatura com 2 argumentos",
       identical(names(formals(montar_consultas)), c("taxa", "idiomas")))

cat("\nligacao obra -> taxon: o vinculo sai ANTES do distinct\n")
# Reproduz o trecho de executar_busca(): a mesma obra achada para 2 especies.
# Se o distinct vier primeiro, um dos vinculos desaparece.
bruto <- tibble(
  obra_id  = c("o1", "o1", "o2"),
  taxon_id = c("T1", "T2", "T1"),
  titulo   = c("Revisao do genero", "Revisao do genero", "Girino de P. barrioi"))
vinculos <- distinct(bruto, obra_id, taxon_id)
obras    <- distinct(bruto, obra_id, .keep_all = TRUE)
checar("a obra compartilhada guarda os dois vinculos", nrow(vinculos) == 3)
checar("mas entra uma vez so em obras", nrow(obras) == 2)
checar("o vinculo da 2a especie sobrevive",
       any(vinculos$obra_id == "o1" & vinculos$taxon_id == "T2"))
# o erro que havia: distinct primeiro, vinculo depois
perdido <- distinct(distinct(bruto, obra_id, .keep_all = TRUE), obra_id, taxon_id)
checar("deduplicar antes perderia um vinculo (era o defeito)", nrow(perdido) == 2)

cat("\nextrair_tudo(): INNER JOIN em vez de CROSS JOIN\n")
linhas <- readLines("R/extracao.R", warn = FALSE)
# fora os comentarios: a explicacao do defeito cita "CROSS JOIN" de proposito,
# e e o SQL que precisa estar limpo, nao o texto ao redor dele
sql <- paste(linhas[!grepl("^\\s*#", linhas)], collapse = "\n")
checar("nao ha mais CROSS JOIN no SQL", !grepl("CROSS JOIN", sql))
checar("ha JOIN em obra_taxon", grepl("JOIN obra_taxon", sql))
# quantos pares cada forma geraria com 3 obras, 2 especies, 2 traits
cross <- 3 * 2 * 2
inner <- nrow(tidyr::expand_grid(
  distinct(bruto, obra_id, taxon_id), trait_id = c("tr1", "tr2")))
checar("o INNER JOIN gera menos pares que o CROSS", inner < cross)
cat(sprintf("     (%d pares em vez de %d, neste exemplo minimo)\n", inner, cross))

cat("\nesquema: a tabela obra_taxon existe\n")
ddl <- paste(readLines("R/db.R", warn = FALSE), collapse = "\n")
checar("DDL de obra_taxon presente",
       grepl("CREATE TABLE IF NOT EXISTS obra_taxon", ddl))
checar("PK composta (obra_id, taxon_id)",
       grepl("PRIMARY KEY \\(obra_id, taxon_id\\)", ddl))

cat("\n", if (falhas == 0) "todos os testes passaram\n\n" else
    paste0(falhas, " teste(s) falharam\n\n"), sep = "")
if (falhas > 0) quit(status = 1)
