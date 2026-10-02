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

# o arquivo real, se estiver aqui: as colunas que a leitura exige existem
real <- "Claude outputs/piloto-zero/para_denise/conferencia_piloto_zero_Denise.xlsx"
if (file.exists(real)) {
  cat("\narquivo real (local)\n")
  checar("a planilha enviada tem as colunas que ler_conferencia() exige",
         nrow(ler_conferencia(real, carregar_traits("inst/traits.csv"))) == 136)
}

cat(if (falhas == 0) "\ntodos os testes passaram\n\n" else sprintf("\n%d FALHA(S)\n\n", falhas))
quit(status = if (falhas == 0) 0 else 1)
