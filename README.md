# tadpole_lifehistory_database

Base de dados de *life history traits* de girinos do Brasil, em Darwin Core, e o
pipeline de extração assistida por modelos que a alimenta.

Dois blocos independentes:

1. **Migração da planilha do livro** (`R/migrar_planilha.R`) — reestrutura a
   planilha já preenchida para Darwin Core e audita o que está inconsistente.
   Roda uma vez, sobre `Planilha Amanda NOVA girinos livro.xlsx`.
2. **Pipeline de extração** (`_targets.R` + `R/`) — busca literatura, obtém
   PDFs, extrai traits com modelos e escreve o arquivo Darwin Core. Roda em
   rodadas, ao longo do projeto.

## Onde começar

```r
# 1. migração + auditoria da planilha existente
source("R/migrar_planilha.R")
migrar("Planilha Amanda NOVA girinos livro.xlsx", "dwca")

# 2. pipeline (depois de preencher config.yml e inst/traits.csv)
targets::tar_make()
```

## Estrutura

```
Planilha Amanda NOVA girinos livro.xlsx   fonte original, não editada
config.yml           endpoints, modelos por agente, limiares, caminhos
_targets.R           orquestração do pipeline (roda só o que está desatualizado)
inst/traits.csv      definições de trait (substituir pelas do grupo)
inst/sinonimos.csv   complemento manual à sinonímia da ASW
R/migrar_planilha.R  planilha do livro -> Darwin Core + auditoria
R/lista_alvo.R       species.json da BT 5.0 -> alvo + corpus-semente
R/sinonimia.R        ASW via AmphiNom -> tabela de sinônimos
R/db.R               esquema DuckDB
R/busca.R            OpenAlex, Crossref, BHL; multilíngue; priorização
R/triagem.R          relevância por agente, margem vai para humano
R/aquisicao.R        PDF + suplementar + OCR
R/parse.R            GROBID -> trechos (texto / tabela / legenda)
R/recuperacao.R      BM25 local: quais trechos merecem uma chamada de modelo
R/agentes.R          os três agentes (ellmer) + escalonamento
R/extracao.R         roteamento encoder/agente, validação do span
R/validacao.R        plausibilidade, limiar por trait, fonte primária
R/revisao.R          conjunto-ouro, fila humana, aprendizado ativo
R/dwc.R              Taxon + MeasurementOrFact + lacunas
python/encoder.py    encoder multilíngue local (fine-tune e inferência)
dwca/                saída da migração + auditoria
docs/                figura do pipeline e plano de próximos passos
```

## Estado atual

| item | situação |
|---|---|
| Migração da planilha | feita; 376 táxons, 695 ocorrências, 18.233 medidas |
| Auditoria | 764 achados em `dwca/auditoria_planilha_girinos.xlsx`, aguardando decisão do grupo |
| Correção da planilha | aprovada pelos co-autores; script a escrever depois que as decisões estiverem preenchidas |
| Pipeline | código escrito, nunca executado; falta chave de API, ids de modelo, GROBID e `inst/traits.csv` |
| Conjunto-ouro | não existe ainda |

## Pré-requisitos

- R ≥ 4.2 com `targets, ellmer, rlang, DBI, duckdb, dplyr, purrr, stringr, tidyr, httr2, xml2, readxl, readr, jsonlite, digest, pdftools, config, reticulate` e, opcional, `cld3`.
- `AmphiNom` para a sinonímia: `remotes::install_github('hcliedtke/AmphiNom')`.
- GROBID: `docker run -p 8070:8070 lfoppiano/grobid:<versão>`.
- `ocrmypdf` no PATH para a literatura escaneada.
- Python com `transformers`, `torch`, `pandas` para o encoder local.
- `OPENAI_API_KEY` ou `ANTHROPIC_API_KEY` no ambiente, nunca no `config.yml`.

Ver `docs/proximos-passos.md` para a ordem de execução acordada com o grupo.
