# Teste da leitura e da pontuacao da conferencia humana do piloto zero
# (ler_conferencia(), pontuar(), avaliar_conferencia()).
#
# Sem rede e sem o arquivo real (dado do grupo, fora do git): planilha
# sintetica no formato da conferencia_piloto_zero_Denise.xlsx.
#
#   Rscript tests/teste_conferencia.R
#
# A conferencia pergunta o que o artigo diz para a especie (valor_correto).
# O que este teste trava: valor fora da lista nao vira numero; conferencia
# pela metade e aceita; o modelo e a planilha sao pontuados contra o artigo,
# com "dois valores do modelo" contado como parcial, nao como acerto.

if (!dir.exists("R") && dir.exists("../R")) setwd("..")
faltam <- c("duckdb", "ellmer", "config", "readxl", "writexl")[!vapply(
  c("duckdb", "ellmer", "config", "readxl", "writexl"), requireNamespace, logical(1), quietly = TRUE)]
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
erro <- function(expr) tryCatch({ expr; "" }, error = conditionMessage)
tb <- tibble::tibble

traits <- tb(trait_id = c("eyes_positioning", "snout_shape_lv"),
             valores_aceitos = c("dorsal;lateral;dorsolateral", "rounded;truncated;sloped"))
NI <- "não informado"; NAO <- "não"
planilha <- function(...) {
  base <- tb(id = sprintf("R%03d", 1:7), bloco = c("1", "1", "1", "1", "1", "1", "2"),
             artigo = "A", especie = "Sp", obra_id = "o1",
             taxon_id = paste0("t", 1:7),
             trait_id = c("eyes_positioning", "eyes_positioning", "eyes_positioning", "snout_shape_lv",
                          "snout_shape_lv", "snout_shape_lv", "eyes_positioning"),
             valor_correto = c("dorsal", "dorsal", NI, "rounded", "outro (ver nota)", NA, "lateral"),
             onde_esta = c("texto", "texto", "não está no artigo", "tabela", "figura", NA, "texto"),
             frase_da_especie_certa = c("sim", NAO, "sem frase", "sim", "sim", NA, "sim"),
             nota = "")
  mods <- list(...)
  for (n in names(mods)) base[[n]] <- mods[[n]]
  f <- tempfile(fileext = ".xlsx")
  writexl::write_xlsx(list(`LEIA-ME` = tb(x = "instrucoes"), revisao = base), f)
  f
}

# ---------------------------------------------------------------------------
cat("\nler_conferencia()\n")
conf <- ler_conferencia(planilha(), traits)
checar("le as 7 linhas", nrow(conf) == 7)
checar("linha sem valor_correto conta como nao conferida (volta pela metade)",
       !conf$conferida[conf$id == "R006"] && sum(conf$conferida) == 6)
m <- erro(ler_conferencia(planilha(valor_correto = c("Dorsal", "dorsal", NI, "rounded", "outro (ver nota)", NA, "lateral")), traits))
checar("valor fora da lista (caixa errada) para, dizendo o id", grepl("valor_correto fora da lista: R001", m))
m <- erro(ler_conferencia(planilha(onde_esta = c("txt", "texto", "texto", "tabela", "figura", NA, "texto")), traits))
checar("onde_esta fora da lista para, dizendo o id", grepl("onde_esta fora da lista: R001", m))
m <- erro(ler_conferencia(planilha(id = c("R001", "R001", sprintf("R%03d", 3:7))), traits))
checar("id repetido para", grepl("id repetido", m))
checar("espacos sobrando nao contam como erro",
       nrow(ler_conferencia(planilha(valor_correto = c("dorsal ", "dorsal", NI, "rounded", "outro (ver nota)", NA, "lateral")), traits)) == 7)

# ---------------------------------------------------------------------------
cat("\npontuar()\n")
checar("um valor, o certo", pontuar("dorsal", "dorsal") == "certo")
checar("sem caixa e espaco", pontuar(" Dorsal", "dorsal") == "certo")
checar("dois valores com o certo = parcial, nao certo", pontuar("dorsal | dorsolateral", "dorsal") == "parcial")
checar("valor errado", pontuar("dorsolateral", "dorsal") == "errado")
checar("nada quando o artigo da o valor = nao_achou", pontuar(NA, "dorsal") == "nao_achou")
checar("nada quando o artigo nao informa = certo", pontuar(NA, NI) == "certo")
checar("valor quando o artigo nao informa = errado", pontuar("lateral", NI) == "errado")
checar("'NA' vindo do csv conta como vazio", pontuar("NA", NI) == "certo")

# ---------------------------------------------------------------------------
cat("\navaliar_conferencia()\n")
pares <- tb(obra_id = "o1", taxon_id = paste0("t", 1:7),
            trait_id = c("eyes_positioning", "eyes_positioning", "eyes_positioning", "snout_shape_lv",
                         "snout_shape_lv", "snout_shape_lv", "eyes_positioning"),
            valor_planilha = c("dorsal", "dorsolateral", "dorsal", "rounded", "sloped", "rounded", "lateral"),
            valor_modelo = c("dorsolateral", "dorsal | dorsolateral", NA, NA, "rounded", NA, "lateral"))
a <- avaliar_conferencia(conf, pares)
pp <- a$pares
checar("so as conferidas entram", nrow(pp) == 6 && !"R006" %in% pp$id)
checar("modelo e planilha pontuados contra o artigo",
       pp$modelo[pp$id == "R001"] == "errado" && pp$planilha[pp$id == "R001"] == "certo" &&
         pp$modelo[pp$id == "R002"] == "parcial" && pp$planilha[pp$id == "R002"] == "errado")
checar("artigo nao informa: o modelo sem valor acerta, a planilha com valor erra",
       pp$modelo[pp$id == "R003"] == "certo" && pp$planilha[pp$id == "R003"] == "errado")
checar("'outro (ver nota)' fica de fora da pontuacao", is.na(pp$modelo[pp$id == "R005"]))
r <- a$resumo
re <- r[r$bloco == "1" & r$trait_id == "eyes_positioning", ]
checar("resumo do bloco 1, olhos: 3 conferidos, 1 certo, 1 parcial, 1 errado",
       re$conferidos == 3 && re$modelo_certo == 1 && re$modelo_parcial == 1 && re$modelo_errado == 1)
checar("frase de outra especie contada", re$frase_de_outra_especie == 1)
rs <- r[r$bloco == "1" & r$trait_id == "snout_shape_lv", ]
checar("resumo do bloco 1, focinho: 'outro' contado a parte e o 'figura' registrado",
       rs$outro == 1 && rs$so_em_figura == 1 && rs$modelo_nao_achou == 1)
checar("bloco 2 separado do bloco 1", any(r$bloco == "2") && r$modelo_certo[r$bloco == "2"] == 1)

# ---------------------------------------------------------------------------
# Gerador (R/conferencia.R), reescrita em R do gerar_planilha.py, 02/10/2026.
cat("\ngerador: partes puras\n")
checar("normalizar_pdf tira espaco, hifen e padroniza travessao e ligadura",
       normalizar_pdf("Eyes – dorsal\n ofﬁce, 0.18–0.20") == normalizar_pdf("eyes-dorsal office, 0.18-0.20"))
pag <- c("Introduction text. Table 3. Morphological characters\nSarg       15.4 (31)      Truncate",
         "Eyes medium-sized, located dorsally, directed dorsolaterally; snout rounded in lateral",
         "view. Spiracle sinistral.")
checar("acha a pagina da frase", achar_pagina("Eyes medium-sized, located dorsally, directed dorsolaterally", pag) == "2")
checar("frase que atravessa a quebra de pagina", grepl("^2", achar_pagina("snout rounded in lateral view. Spiracle sinistral.", pag)))
checar("linha de tabela leva o numero da tabela",
       achar_pagina("Sarg       15.4 (31)      Truncate", pag) == "1 (Tabela 3)")
checar("duas frases separadas por ||", achar_pagina("located dorsally, directed dorsolaterally || Morphological characters Sarg", pag) == "2 || 1")
checar("frase que nao esta no PDF vira ?", achar_pagina("This sentence is not in the document at all.", pag) == "?")
checar("sem frase, vazio", achar_pagina(NA, pag) == "")
generica <- c(rep("The snout is rounded in lateral view. Other text.", 4), "Genus x: snout sloped.")
checar("frase generica (em mais de 3 paginas) vira ?, para cair nas paginas do nome",
       achar_pagina("The snout is rounded in lateral view.", generica) == "?")

prs <- tb(obra_id = "o1", taxon_id = c("a", "b", "c", "d"), trait_id = "snout_shape_lv",
          caso = c("igual", "igual", "igual", "diverge"),
          span = c("Snout rounded, 0.52 of body.", "Snout rounded, 0.52 of body.", "Snout rounded.", "Snout sloped."))
fr <- frases_repetidas(prs)
checar("mesma frase com numero para duas especies = suspeita", setequal(fr$taxon_id, c("a", "b")))
checar("frase repetida sem numero nao conta", !"c" %in% fr$taxon_id)

ig <- tb(obra_id = rep(c("grande", "pequena"), c(40, 3)), taxon_id = paste0("t", 1:43), trait_id = "x")
s1 <- sortear_bloco2(ig, n = 25, minimo = 4, semente = 1); s2 <- sortear_bloco2(ig, n = 25, minimo = 4, semente = 1)
checar("sorteio reprodutivel com a mesma semente", identical(s1, s2))
checar("obra pequena entra inteira quando tem menos que o minimo", sum(s1$obra_id == "pequena") == 3)
checar("obra grande recebe a cota proporcional", sum(s1$obra_id == "grande") == round(25 * 40 / 43))

txt <- "The tadpole of Scinax argyreornatus ... S. argyreornatus ... Scinax argyreornatus."
checar("nome aceito no texto = vazio", nome_no_artigo("Ololygon argyreornata here", "Ololygon argyreornata", "Ololygon argyreornata") == "")
checar("senao, o sinonimo mais citado",
       nome_no_artigo(txt, "Ololygon argyreornata", c("Ololygon argyreornata", "Hyla argyreornata", "Scinax argyreornatus")) == "Scinax argyreornatus")
checar("nenhum nome no texto", nome_no_artigo("nada", "Sp um", c("Sp um", "Sp dois")) == "(não achei)")

cat("\ngerador: planilha montada, escrita e lida de volta\n")
pares_r <- tb(obra_id = "o1", taxon_id = c("a", "b", "c", "d", "e"), trait_id = "snout_shape_lv",
              caso = c("diverge", "so_planilha", "igual", "igual", "igual"),
              citacao = "Autor (2000)", especie = paste("Genus", c("a", "b", "c", "d", "e")),
              valor_planilha = "rounded", valor_modelo = c("sloped", NA, "rounded", "rounded", "rounded"),
              span = c("Genus a: snout sloped in lateral view.", NA, "Genus c: snout rounded.",
                       "Genus d: snout rounded.", "Genus e: snout rounded."))
ref_r <- mutate(pares_r, caso = "igual")
pgs <- list(o1 = c("Genus a: snout sloped in lateral view. Genus b appears here.",
                   "Genus c: snout rounded. Genus d: snout rounded. Genus e: snout rounded."))
lin <- montar_conferencia(pares_r, ref_r, pgs, list(), semente = 1, n_amostra = 2)
checar("bloco 1 = todos os nao-iguais", setequal(lin$taxon_id[lin$bloco == "1"], c("a", "b")))
checar("bloco 2 = iguais; com menos iguais que o minimo por obra (4), entram todos os 3",
       sum(lin$bloco == "2") == 3 && all(lin$caso[lin$bloco == "2"] == "igual"))
checar("ids R001.. na ordem artigo, especie, trait (blocos misturados)",
       identical(lin$id, sprintf("R%03d", seq_len(nrow(lin)))) && identical(lin$especie, sort(lin$especie)))
# especies do bloco 1 com nome que ordena depois das do bloco 2 (antes, a
# planilha saia pelo bloco primeiro e separava os traits da mesma especie)
lin_inv <- montar_conferencia(mutate(pares_r, especie = rev(especie)), mutate(ref_r, especie = rev(especie)),
                              pgs, list(), semente = 1, n_amostra = 2)
checar("bloco 2 nao vai todo para o fim: ordem por especie", identical(lin_inv$especie, sort(lin_inv$especie)))
checar("sem frase: paginas do nome", lin$pagina[lin$taxon_id == "b"] == "nome nas p. 1")
checar("caso da rodada de referencia anotado", all(lin$caso_ref == "igual"))
if (requireNamespace("openxlsx2", quietly = TRUE)) {
  f <- tempfile(fileext = ".xlsx")
  escrever_conferencia_xlsx(lin, f, traits)
  volta <- ler_conferencia(f, traits)
  checar("a planilha gerada volta por ler_conferencia(), sem nada conferido",
         nrow(volta) == nrow(lin) && !any(volta$conferida))
  checar("abas LEIA-ME e revisao", identical(readxl::excel_sheets(f), c("LEIA-ME", "revisao")))
  le <- readxl::read_excel(f, sheet = "LEIA-ME", col_names = FALSE, col_types = "text", .name_repair = "minimal")[[1]]
  checar("o LEIA-ME vem com as contagens preenchidas", any(grepl("Bloco 1 \\(2 linhas\\)", le)) && !any(grepl("\\{n1\\}", le)))
  m <- erro(escrever_conferencia_xlsx(lin, f, traits))
  checar("nao sobrescreve planilha que ja existe", nzchar(m))
}

# o arquivo real, se estiver aqui: as colunas que a leitura exige existem
real <- "Claude outputs/piloto-zero/para_denise/conferencia_piloto_zero_Denise.xlsx"
if (file.exists(real)) {
  cat("\narquivo real (local)\n")
  checar("a planilha enviada tem as colunas que ler_conferencia() exige",
         nrow(ler_conferencia(real, carregar_traits("inst/traits.csv"))) == 136)
}

# ---------------------------------------------------------------------------
# Regra posicao x direcao (Diogo, 04/10/2026): a conferencia registrou a
# direcao onde o artigo da as duas; o gabarito passa a ter a posicao.
cat("\nregra da posicao dos olhos\n")
checar("posicao, nao direcao", identical(posicao_dos_olhos(c(
  "Eye small, dorsal, dorsolaterally directed.",
  "Eyes medium-sized (ED/BWE = 0.21-0.26), located dorsally (IOD/BWE = 0.76-0.83), laterally directed.",
  "Eyes small, lateral, dorsolaterally directed.",
  "Eyes small, dorsal and laterally directed.",
  "Eyes dorsal, oriented dorsolaterally.")), c("dorsal", "dorsal", "lateral", "dorsal", "dorsal")))
checar("frase so com direcao nao da posicao", is.na(posicao_dos_olhos("Eyes dorsolaterally directed.")))
cf <- tb(id = c("R1", "R2", "R3", "R4"), trait_id = c("eyes_positioning", "eyes_positioning", "eyes_positioning", "snout_shape_lv"),
         valor_correto = c("dorsolateral", "lateral", "dorsolateral", "rounded"))
fr <- c(R1 = "Eye small, dorsal, dorsolaterally directed.", R2 = "Eyes small, lateral, laterally directed.",
        R3 = "Eyes dorsolaterally directed.", R4 = "Snout rounded, directed forward.")
cr <- corrigir_regra_posicao(cf, fr)
checar("troca a direcao registrada pela posicao", cr$conf$valor_correto[1] == "dorsal" && identical(cr$trocas$id, "R1"))
checar("nao mexe quando posicao e direcao concordam, sem posicao, ou em outro trait",
       identical(cr$conf$valor_correto[2:4], c("lateral", "dorsolateral", "rounded")))

cat(if (falhas == 0) "\ntodos os testes passaram\n\n" else sprintf("\n%d FALHA(S)\n\n", falhas))
quit(status = if (falhas == 0) 0 else 1)
