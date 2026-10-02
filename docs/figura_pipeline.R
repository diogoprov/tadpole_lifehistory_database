# Gera docs/pipeline.svg, a figura do pipeline usada no README.
#
#   Rscript docs/figura_pipeline.R
#
# Fica fora de R/ de proposito: R/ e carregado inteiro por carregar_projeto()
# e pelo {targets}. Para mudar a figura, mude o texto abaixo e rode de novo;
# o SVG nao e editado a mao. Substitui docs/pipeline_girinos_traits.svg
# (19/09/2026), anterior ao piloto zero e em portugues.
#
# 02/10/2026: caixas com uma ou duas linhas e icone; o detalhe de cada etapa
# foi para o texto do README (Diogo), porque a figura com paragrafos tinha
# 1.642 px de altura e ninguem le paragrafo dentro de caixa. O que ainda nao
# esta implementado tem borda tracejada, e o ciclo revisao -> limiares e
# encoder local aparece como seta de volta.
#
# Icones: pacote fontawesome (Font Awesome Free, CC BY 4.0) e dois do
# Academicons (SIL OFL 1.1) guardados em docs/icones/. Atribuicao no rodape.

# tipo: auto | humano | barreira; planejado = TRUE desenha borda tracejada
caixa <- function(titulo, texto, icone, tipo = "auto", planejado = FALSE, id = NA_character_)
  list(titulo = titulo, texto = texto, icone = icone, tipo = tipo, planejado = planejado, id = id)

# Modelos lidos de cfg$agentes, para a figura acompanhar o config.yml.
# "claude-sonnet-5-5" -> "Sonnet 5.5"; "claude-haiku-4-5-20251001" -> "Haiku 4.5".
AGENTES <- config::get(file = "config.yml")$agentes
nome_modelo <- function(id) {
  p <- regmatches(id, regexec("^claude-([a-z]+)-([0-9]+)-([0-9]+)", id))[[1]]
  if (length(p) < 4) return(id)
  # espaco nao separavel: a quebra de linha nao separa "Opus" de "5.5"
  paste0(toupper(substr(p[2], 1, 1)), substr(p[2], 2, nchar(p[2])), " ", p[3], ".", p[4])
}
MOD <- vapply(AGENTES, function(a) nome_modelo(a$modelo), character(1))

ENTRADAS <- list(
  caixa("Brazilian Tadpoles 5.0", "Target species and their catalogued references (seed corpus).", "list-check"),
  caixa("Legacy spreadsheet", "Girinos do Brasil (2024), migrated to Darwin Core. Reference for the pilot.", "table"),
  caixa("Trait vocabulary", "48 traits; only those with a closed vocabulary are extracted.", "book", "humano"),
  caixa("Synonyms", "AmphiNom (ASW) plus curated names.", "tags"))

ETAPAS <- list(
  list(nome = "1  Literature search", caixas = list(
    caixa("Programmatic search", "OpenAlex and Crossref; queries in Portuguese, Spanish and English.", "magnifying-glass"),
    caixa("Triage", sprintf("%s reads title and abstract; uncertain cases and failed calls go to a person.",
                            MOD[["triagem"]]), "filter", "humano"))),
  list(nome = "2  Document acquisition", caixas = list(
    caixa("Open access", "Unpaywall; posters and abstracts flagged by URL.", "ai:open-access"),
    caixa("Manual import", "PDFs obtained by the group, imported as copies.", "folder-open", "humano"),
    caixa("OCR", "For scanned works with too little text.", "file-lines"))),
  list(nome = "3  Structuring", caixas = list(
    caixa("GROBID", "Paragraphs, tables and captions as separate chunks.", "file-code"),
    caixa("Tables from the PDF", "Read from the page layout when GROBID loses them.", "table-cells"),
    caixa("Fallback", "Plain page text when GROBID fails.", "rotate-left"))),
  list(nome = "4  Retrieval (no model calls)", caixas = list(
    caixa("Candidate chunks", "Species name and trait term, ranked by BM25.", "list-ol"),
    caixa("Monographs", "Species name carried across consecutive paragraphs.", "book-open"),
    caixa("Tables", "A table citing the species is always a candidate.", "table"))),
  list(nome = "5  Extraction", caixas = list(
    caixa("Context agent", sprintf("%s, once per work: stage, setting, sample size.", MOD[["contexto"]]), "microscope"),
    caixa("Value agent", sprintf("%s: a vocabulary value and the verbatim sentence.", MOD[["valor"]]), "robot"),
    caixa("Verbatim check", "The sentence must exist, character by character, in the chunk.", "quote-left", "barreira"),
    caixa("Local encoder", "Categorical traits; the model only below a confidence threshold.", "microchip",
          planejado = TRUE, id = "encoder"))),
  list(nome = "6  Validation", caixas = list(
    caixa("Plausibility and reconciliation", "Range checks; conflicts within a work go to a person.", "scale-balanced"),
    caixa("Primary source", "Oldest work is primary; posters and abstracts never are.", "clock-rotate-left"),
    caixa("Calibrated thresholds", "Per-trait confidence threshold set on the gold standard.", "sliders",
          planejado = TRUE, id = "limiares"))),
  list(nome = "7  Human review", caixas = list(
    caixa("Review queue", "Disagreements and values below threshold.", "user-check", "humano"),
    caixa("Gold standard", "Double-blind extraction by two reviewers, without AI assistance.", "user-group", "humano",
          planejado = TRUE, id = "ouro"))),
  list(nome = "8  Output", caixas = list(
    caixa("Darwin Core archive", "Taxon core with MeasurementOrFact and full provenance.", "box-archive"),
    # estado_par -> dwca/lacunas.txt (R/dwc.R): o par buscado sem dado e
    # informacao, nao celula vazia (item 10)
    caixa("Recorded gaps", "Species × trait pairs searched without data are published.", "circle-minus"),
    caixa("Publication", "IPT/GBIF, Zenodo and a data paper.", "ai:zenodo", planejado = TRUE))))

POLITICA <- caixa("Error policy", "A failed API call stops the run; it never becomes 'not found'.",
                  "shield-halved", "barreira")

# ---- icones -------------------------------------------------------------------

# devolve list(viewbox, d); "ai:" = Academicons em docs/icones/
icone <- function(nome) {
  if (startsWith(nome, "ai:")) {
    s <- paste(readLines(file.path("docs/icones", paste0(sub("^ai:", "", nome), ".svg")), warn = FALSE), collapse = " ")
  } else {
    s <- as.character(fontawesome::fa(nome))
  }
  vb <- regmatches(s, regexec('viewBox="([^"]+)"', s))[[1]][2]
  d <- regmatches(s, regexec('\\sd="([^"]+)"', s))[[1]][2]
  stopifnot(!is.na(vb), !is.na(d))
  list(viewbox = vb, d = gsub("\\s+", " ", d))
}

# ---- desenho ------------------------------------------------------------------

# Margem direita maior: e por ela que passa a seta de volta da revisao humana.
L <- 1200; ME <- 40; MD <- 90; G <- 18
LU <- L - ME - MD                      # largura util
largura <- function(n) (LU - (n - 1) * G) / n
# px por caractere medidos com systemfonts (02/10/2026): corpo 12.5 px da
# 5.3 (Helvetica) a 5.7 (Arial); titulo bold 14 px da 6.6. Arredondado para
# cima porque quem renderiza e o navegador de quem le, com a fonte que tiver.
# A versao anterior usava 6.6 no corpo e as caixas ficavam com 1/3 vazio.
quebra <- function(W) c(titulo = floor((W - 46) / 7.0), corpo = floor((W - 24) / 6.0))
COR <- list(auto = c("#eef3f8", "#4f6d8a"), humano = c("#fbf0e4", "#a8601a"), barreira = c("#f3eef8", "#6b4f99"))
esc <- function(x) gsub(">", "&gt;", gsub("<", "&lt;", gsub("&", "&amp;", x)))
linhas <- function(x, n) strwrap(x, width = n)

svg <- character()
add <- function(...) svg <<- c(svg, paste0(...))
texto <- function(x, y, s, tam = 13, peso = "normal", cor = "#1f2933", ancora = "start", extra = "")
  add(sprintf('<text x="%.0f" y="%.0f" font-size="%g" font-weight="%s" fill="%s" text-anchor="%s"%s>%s</text>',
              x, y, tam, peso, cor, ancora, extra, esc(s)))
desenha_icone <- function(nome, x, y, tam, cor) {
  ic <- icone(nome)
  add(sprintf('<svg x="%.0f" y="%.0f" width="%g" height="%g" viewBox="%s"><path fill="%s" d="%s"/></svg>',
              x, y, tam, tam, ic$viewbox, cor, ic$d))
}

POS <- list()   # posicao das caixas com id, para a seta de volta
desenha_caixa <- function(cx, x, y, h, W) {
  q <- quebra(W); cc <- COR[[cx$tipo]]
  traco <- if (cx$planejado) ' stroke-dasharray="6 4"' else ""
  fundo <- if (cx$planejado) "#ffffff" else cc[1]
  add(sprintf('<rect x="%.0f" y="%.0f" width="%.0f" height="%.0f" rx="6" fill="%s" stroke="%s" stroke-width="1.5"%s/>',
              x, y, W, h, fundo, cc[2], traco))
  desenha_icone(cx$icone, x + 12, y + 9, 16, cc[2])
  yy <- y + 22
  for (s in linhas(cx$titulo, q[["titulo"]])) { texto(x + 36, yy, s, 14, "bold", cc[2]); yy <- yy + 17 }
  yy <- yy + 2
  for (s in linhas(cx$texto, q[["corpo"]])) { texto(x + 12, yy, s, 12.5); yy <- yy + 16 }
  if (!is.na(cx$id)) POS[[cx$id]] <<- c(x = x, y = y, w = W, h = h)
}
altura_caixa <- function(cx, W) {
  q <- quebra(W)
  18 + 17 * length(linhas(cx$titulo, q[["titulo"]])) + 16 * length(linhas(cx$texto, q[["corpo"]])) + 10
}
svg_bloco <- function(caixas, y) {
  W <- largura(length(caixas))
  h <- max(vapply(caixas, altura_caixa, numeric(1), W = W))
  for (i in seq_along(caixas)) desenha_caixa(caixas[[i]], ME + (i - 1) * (W + G), y, h, W)
  h
}
XC <- ME + LU / 2
seta <- function(y1, y2) add(sprintf(
  '<line x1="%.0f" y1="%.0f" x2="%.0f" y2="%.0f" stroke="#7b8794" stroke-width="2" marker-end="url(#ponta)"/>', XC, y1, XC, y2))

y <- 46
texto(ME, y, "AI-assisted extraction of tadpole life-history traits", 22, "bold")
y <- y + 24
texto(ME, y, "Every value carries its source, the verbatim sentence that supports it, and the model and prompt that produced it.", 13, cor = "#52606d")
y <- y + 30
texto(ME, y, "INPUTS", 13, "bold", "#52606d"); y <- y + 10
h <- svg_bloco(ENTRADAS, y); y <- y + h + 12
for (e in ETAPAS) {
  seta(y, y + 20); y <- y + 26
  add(sprintf('<rect x="%d" y="%.0f" width="%d" height="26" rx="4" fill="#1f2933"/>', ME, y, LU))
  texto(ME + 12, y + 18, e$nome, 14, "bold", "#ffffff")
  y <- y + 34
  h <- svg_bloco(e$caixas, y); y <- y + h + 12
}
y <- y + 10
h <- svg_bloco(list(POLITICA), y); y <- y + h

# Seta de volta: o conjunto-ouro e as correcoes da fila calibram os limiares
# e treinam o encoder local (itens 4, 12 e 14). Tracejada: nada disso existe
# ainda. Sai da borda direita do conjunto-ouro, sobe pela margem e entra nas
# duas caixas pela direita.
xr <- L - MD + 34
cor_volta <- COR$humano[2]
meio <- function(p) p[["y"]] + p[["h"]] / 2
o <- POS$ouro
add(sprintf('<path d="M %.0f %.0f H %.0f V %.0f H %.0f" fill="none" stroke="%s" stroke-width="2" stroke-dasharray="6 4" marker-end="url(#volta)"/>',
            o[["x"]] + o[["w"]], meio(o), xr, meio(POS$encoder), POS$encoder[["x"]] + POS$encoder[["w"]] + 2, cor_volta))
add(sprintf('<path d="M %.0f %.0f H %.0f" fill="none" stroke="%s" stroke-width="2" stroke-dasharray="6 4" marker-end="url(#volta)"/>',
            xr, meio(POS$limiares), POS$limiares[["x"]] + POS$limiares[["w"]] + 2, cor_volta))
ym <- (meio(POS$encoder) + meio(o)) / 2
texto(xr + 16, ym, "training data and thresholds", 12, "bold", cor_volta, "middle",
      sprintf(' transform="rotate(90 %.0f %.0f)"', xr + 16, ym))

# legenda
y <- y + 30
lx <- ME
for (k in list(c("auto", "Automated", "solido"), c("humano", "Human step or decision", "solido"),
               c("barreira", "Safeguard", "solido"), c("auto", "Planned, not yet implemented", "tracejado"))) {
  cc <- COR[[k[1]]]
  if (k[3] == "tracejado")
    add(sprintf('<rect x="%d" y="%.0f" width="18" height="14" rx="3" fill="#ffffff" stroke="%s" stroke-width="1.5" stroke-dasharray="4 3"/>', lx, y - 11, cc[2]))
  else
    add(sprintf('<rect x="%d" y="%.0f" width="18" height="14" rx="3" fill="%s" stroke="%s" stroke-width="1.5"/>', lx, y - 11, cc[1], cc[2]))
  texto(lx + 26, y, k[2], 12.5); lx <- lx + 220
}
y <- y + 26
texto(ME, y, "Status on 2 October 2026. Icons: Font Awesome Free (CC BY 4.0) and Academicons (SIL OFL 1.1).", 11.5, cor = "#52606d")
y <- y + 22

cab <- c(
  sprintf('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%.0f" viewBox="0 0 %d %.0f" font-family="Helvetica, Arial, sans-serif">', L, y, L, y),
  '<title>Pipeline for AI-assisted extraction of tadpole traits</title>',
  '<defs>',
  '<marker id="ponta" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="7" markerHeight="7" orient="auto"><path d="M0,0 L10,5 L0,10 z" fill="#7b8794"/></marker>',
  sprintf('<marker id="volta" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="7" markerHeight="7" orient="auto"><path d="M0,0 L10,5 L0,10 z" fill="%s"/></marker>', cor_volta),
  '</defs>',
  sprintf('<rect width="%d" height="%.0f" fill="#ffffff"/>', L, y))
writeLines(c(cab, svg, "</svg>"), "docs/pipeline.svg")
message("docs/pipeline.svg: ", L, " x ", round(y), " px")
