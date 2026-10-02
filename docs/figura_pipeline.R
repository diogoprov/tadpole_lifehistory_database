# Gera docs/pipeline.svg, a figura do pipeline usada no README.
#
#   Rscript docs/figura_pipeline.R
#
# Fica fora de R/ de proposito: R/ e carregado inteiro por carregar_projeto()
# e pelo {targets}. Para mudar a figura, mude o texto abaixo e rode de novo;
# o SVG nao e editado a mao. Substitui docs/pipeline_girinos_traits.svg
# (19/09/2026), anterior ao piloto zero e em portugues.

caixa <- function(titulo, texto, tipo = "auto") list(titulo = titulo, texto = texto, tipo = tipo)

ENTRADAS <- list(
  caixa("Target list: Brazilian Tadpoles 5.0",
        "species.json: 1,066 species, 676 with a described tadpole; accepted names and the references already catalogued, used as seed corpus."),
  caixa("Legacy spreadsheet: Girinos do Brasil (2024)",
        "Migrated to Darwin Core and corrected by explicit rules, each correction logged: 376 taxa, 18,214 measurements. Reference for the pilot."),
  caixa("Trait vocabulary",
        "48 traits with definition, unit, accepted values and search terms, fixed before extraction. Only traits with a closed vocabulary are extracted.",
        "humano"))

ETAPAS <- list(
  list(nome = "1  Literature search", caixas = list(
    caixa("Programmatic search",
          "OpenAlex (exact phrase in title, abstract and text) and Crossref (kept only with the binomial in the title); record-type filter; queries in Portuguese, Spanish and English."),
    caixa("Triage",
          "Binomial in the title: relevant. Otherwise Claude Haiku reads title and abstract; probabilities between 0.35 and 0.75, and failed calls, go to a human.",
          "humano"),
    caixa("Synonyms",
          "ASW synonymy from the AmphiNom tables plus curated names. A name that could point to another species goes to review; a curated name can be limited to one work."))),
  list(nome = "2  Document acquisition", caixas = list(
    caixa("Open access",
          "Unpaywall; a download is kept only if it is a real PDF. Posters and conference abstracts are flagged from the landing-page URL."),
    caixa("Manual download",
          "Works without an open PDF are listed in a spreadsheet; the PDFs the group obtains are imported as copies, originals untouched. No ResearchGate or Academia.edu scraping.",
          "humano"),
    caixa("OCR",
          "Scanned works with too little text go through OCR before structuring."))),
  list(nome = "3  Structuring", caixas = list(
    caixa("GROBID to chunks",
          "Paragraphs, tables and captions become separate chunks, in document order. Subsections inherit the main heading (e.g. Methods / Study area)."),
    caixa("Tables from the PDF text",
          "Each 'Table N' caption opens a table chunk read from the PDF layout. GROBID loses tables printed on landscape pages."),
    caixa("Fallback",
          "If GROBID fails or returns a TEI without body text, the page text of the PDF is used."))),
  list(nome = "4  Retrieval (no model calls)", caixas = list(
    caixa("Candidate chunks",
          "Chunks naming the species (accepted name, synonym or abbreviation) and a trait term, ranked by BM25; top 4 per species \u00d7 trait \u00d7 work."),
    caixa("Monographs",
          "A species named in one paragraph is carried to the next ones (up to 3) until another species of the work appears."),
    caixa("Tables",
          "A table that cites the species always gets a slot among the candidates."))),
  list(nome = "5  Extraction agents (Claude)", caixas = list(
    caixa("Context agent, once per work",
          "Reads the Methods or, in notes without Methods, the passages citing Gosner or stage; returns stage, setting and sample size."),
    caixa("Value agent",
          "Sonnet, escalating to Opus. Returns a value from the closed vocabulary and the verbatim sentence; never computes, converts or infers."),
    caixa("Verbatim check",
          "The sentence must exist, character by character, in the chunk. The only automatic barrier against invented values.",
          "barreira"))),
  list(nome = "6  Validation", caixas = list(
    caixa("Plausibility and reconciliation",
          "Out-of-range values are flagged. Within a work, equal values collapse into one record and conflicting ones go to a human."),
    caixa("Primary source",
          "The oldest work reporting a value is primary; a citation in the sentence marks it secondary. Posters and abstracts are never primary."),
    caixa("Calibrated thresholds",
          "Per-trait confidence threshold calibrated on a double-blind gold standard (planned)."))),
  list(nome = "7  Review and publication", caixas = list(
    caixa("Human review",
          "Adjudication of disagreements with the reference; review queue for values below threshold.",
          "humano"),
    caixa("Darwin Core output",
          "Taxon core with MeasurementOrFact; publication through IPT/GBIF and Zenodo (planned)."),
    caixa("Error policy",
          "A failed API call stops the run. It never becomes 'not found'.",
          "barreira"))))

# ---- desenho ------------------------------------------------------------------

L <- 1200; M <- 40; G <- 20; W <- (L - 2 * M - 2 * G) / 3
COR <- list(auto = c("#eef3f8", "#5b7a99"), humano = c("#fbf0e4", "#b26b1f"), barreira = c("#f3eef8", "#6b4f99"))
esc <- function(x) gsub(">", "&gt;", gsub("<", "&lt;", gsub("&", "&amp;", x)))
linhas <- function(x, largura) strwrap(x, width = largura)

svg <- character()
add <- function(...) svg <<- c(svg, paste0(...))
texto <- function(x, y, s, tam = 13, peso = "normal", cor = "#1f2933", ancora = "start")
  add(sprintf('<text x="%.0f" y="%.0f" font-size="%g" font-weight="%s" fill="%s" text-anchor="%s">%s</text>',
              x, y, tam, peso, cor, ancora, esc(s)))

desenha_caixa <- function(cx, x, y, h) {
  tl <- linhas(cx$titulo, 46); bl <- linhas(cx$texto, 54)
  cc <- COR[[cx$tipo]]
  add(sprintf('<rect x="%.0f" y="%.0f" width="%.0f" height="%.0f" rx="6" fill="%s" stroke="%s" stroke-width="1.5"/>',
              x, y, W, h, cc[1], cc[2]))
  yy <- y + 22
  for (s in tl) { texto(x + 12, yy, s, 14, "bold", cc[2]); yy <- yy + 17 }
  yy <- yy + 2
  for (s in bl) { texto(x + 12, yy, s, 12.5); yy <- yy + 16 }
  h
}
altura_caixa <- function(cx) 18 + 17 * length(linhas(cx$titulo, 46)) + 16 * length(linhas(cx$texto, 54)) + 10

corpo <- character(); y <- 0
svg_bloco <- function(caixas, y) {
  h <- max(vapply(caixas, altura_caixa, numeric(1)))
  for (i in seq_along(caixas)) desenha_caixa(caixas[[i]], M + (i - 1) * (W + G), y, h)
  h
}
seta <- function(y1, y2) add(sprintf(
  '<line x1="%d" y1="%.0f" x2="%d" y2="%.0f" stroke="#7b8794" stroke-width="2" marker-end="url(#ponta)"/>', L / 2, y1, L / 2, y2))

y <- 50
texto(M, y, "AI-assisted extraction of tadpole life-history traits from the literature", 22, "bold")
y <- y + 26
texto(M, y, "Every value carries its source, the verbatim sentence that supports it, and the model and prompt that produced it.", 13, cor = "#52606d")
y <- y + 18
texto(M, y, "Final decisions are human.", 13, cor = "#52606d")
y <- y + 28
texto(M, y, "INPUTS", 13, "bold", "#52606d"); y <- y + 10
h <- svg_bloco(ENTRADAS, y); y <- y + h + 14
for (e in ETAPAS) {
  seta(y, y + 22); y <- y + 30
  add(sprintf('<rect x="%d" y="%.0f" width="%d" height="26" rx="4" fill="#1f2933"/>', M, y, L - 2 * M))
  texto(M + 12, y + 18, e$nome, 14, "bold", "#ffffff")
  y <- y + 36
  h <- svg_bloco(e$caixas, y); y <- y + h + 14
}
# legenda
y <- y + 14
lx <- M
for (k in list(c("auto", "Automated"), c("humano", "Human step or decision"), c("barreira", "Safeguard"))) {
  cc <- COR[[k[1]]]
  add(sprintf('<rect x="%d" y="%.0f" width="18" height="14" rx="3" fill="%s" stroke="%s" stroke-width="1.5"/>', lx, y - 11, cc[1], cc[2]))
  texto(lx + 26, y, k[2], 12.5); lx <- lx + 230
}
y <- y + 26
texto(M, y, "Status on 2 October 2026; pilot on 4 works, 276 species \u00d7 trait pairs (docs/piloto-zero.md).", 12, cor = "#52606d")
y <- y + 24

cab <- c(
  sprintf('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%.0f" viewBox="0 0 %d %.0f" font-family="Helvetica, Arial, sans-serif">', L, y, L, y),
  '<title>Pipeline for AI-assisted extraction of tadpole traits</title>',
  '<defs><marker id="ponta" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="7" markerHeight="7" orient="auto"><path d="M0,0 L10,5 L0,10 z" fill="#7b8794"/></marker></defs>',
  sprintf('<rect width="%d" height="%.0f" fill="#ffffff"/>', L, y))
writeLines(c(cab, svg, "</svg>"), "docs/pipeline.svg")
message("docs/pipeline.svg: ", L, " x ", round(y), " px")
