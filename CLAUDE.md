# CLAUDE.md — base de traits de girinos do Brasil

Base de dados de traits de história de vida de girinos do Brasil, em Darwin Core,
com extração assistida por IA a partir da literatura. Responsável: Diogo B.
Provete (UFMS), com Denise Rossa-Feres e o grupo da Brazilian Tadpoles 5.0.
**O repositório é público.**

Antes de propor trabalho novo, leia a seção "Onde paramos" de
`docs/proximos-passos.md`: estado atual e decisões em aberto. Desenho do
pipeline: `docs/desenho-do-pipeline.md`. Modelos, preços e GROBID:
`docs/infraestrutura.md`.

## Testes

```bash
for t in tests/teste_*.R; do Rscript "$t" || echo "FALHOU: $t"; done
```

Dezesseis conjuntos; cada um termina em "todos os testes passaram". Nenhum chama a
API nem o GROBID. Rode antes de todo commit.

Numa sessão de R: `source("R/carregar.R"); carregar_projeto()`. Os pontos de
entrada (`R/fumaca.R`, `R/fumaca_busca.R`, `R/diagnostico.R`) recarregam o
projeto inteiro sozinhos.

## Nunca

- **Commitar** `pdf/`, `tei/`, `*.tei.xml` (texto completo de artigo com direito
  autoral), `*.xlsx`, `dwca/`, `*.duckdb` (dados inéditos do grupo),
  `Claude outputs/`, `email_*.md`, `.Renviron`. O `.gitignore` cobre tudo isso;
  mesmo assim, rode `git status --short` antes de todo commit e pare se
  aparecer algo da lista.
- **Expor a chave de API.** Ela fica só em `~/.Renviron` (`ANTHROPIC_API_KEY`):
  nunca em código, no `config.yml`, em mensagem de commit ou na saída.
- **Gastar crédito sem o Diogo pedir naquela conversa.** Chamam o modelo:
  `verificar_infra()` (uma chamada por modelo), `teste_de_fumaca()`,
  `teste_de_fumaca_busca(triar = TRUE)`, `teste_de_fumaca_extracao()`,
  `triar_obras()`, `extrair_tudo()`, `targets::tar_make()`. São grátis: os
  testes, o GROBID e a busca sem triagem.
- **Baixar de ResearchGate ou Academia.edu, ou contornar bloqueio de editora.**
  Os termos de uso proíbem. PDF fechado entra por `importar_pdfs_manuais()`.
- **Alterar um PDF do usuário.** O pipeline trabalha sempre numa cópia
  (`pdf/<obra_id>.pdf`).
- **Decidir sozinho uma questão científica:** vocabulário ou definição de trait,
  escopo da busca, o que conta como fonte primária. Mostre a evidência e
  pergunte.
- **Inventar** citação, DOI, URL, preço ou id de modelo. Se não conferiu na
  fonte, diga que não sabe.

## Princípios que vieram de defeitos reais — não desfazer

1. **Erro nunca vira "não encontrado".** Falha de API para a rodada
   (`com_escalonamento()`); triagem que falhou vai para a fila humana com
   `relevante = NA` (`interpretar_triagem()`). Já aconteceu duas vezes: obra
   sumindo da triagem, e "0 registros" com todas as chamadas em HTTP 400.
2. **O span literal (`validar_span()`) é a única barreira automática contra
   valor inventado.** Não afrouxe.
3. **Meça antes de mudar.** Ex.: a consulta antiga zerava a OpenAlex, e isso
   apareceu testando a API de graça, antes de gastar chamada de modelo.
4. **Todo defeito corrigido ganha um teste que o reproduz, e o teste tem de
   falhar com o código antigo.** Confira recolocando o defeito numa cópia do
   repositório (`cp -r . "$(mktemp -d)"`) e rodando o teste lá.
5. **Comentário explica o porquê,** com a data e a evidência (qualquer arquivo
   em `R/` mostra o padrão).

## Convenções

- R. `purrr` (`map`, `map_dfr`, `map_chr`…) em vez de `apply`/`sapply`/`lapply`.
  Pacotes do projeto: `dplyr`, `stringr`, `DBI` + `duckdb`, `httr2`, `ellmer`,
  `targets`.
- Comentários de código em português **sem acento** (o código inteiro segue
  assim); documentação em `docs/` com acento.
- Lógica testável separada do banco e da API: `decidir_reconciliacao()`,
  `interpretar_triagem()`, `marcar_binomio()`.
- Planilha que passa por mão humana: `ler_planilha_humana()` (aceita o `;` do
  Excel em português e lê tudo como texto).
- Coluna nova em tabela existente: `ALTER TABLE ... ADD COLUMN IF NOT EXISTS`
  em `criar_esquema()`, para o banco antigo continuar valendo.

## Mapa de `R/`

- **Busca:** `busca.R` (OpenAlex + Crossref; o Crossref só entra com o binômio
  no título; filtro por tipo de registro) → `triagem.R` (binômio no título
  entra direto; o resto, Haiku lendo título e resumo) → `aquisicao.R`
  (Unpaywall; `exportar_sem_pdf()` / `importar_pdfs_manuais()`).
- **Estruturação:** `parse.R` (GROBID → trechos) → `recuperacao.R` (BM25; a
  espécie é procurada no título da seção e no texto).
- **Extração:** `agentes.R` (contexto, valor, escalonamento) → `extracao.R`
  (`extrair_tudo()` só cruza obra e espécie ligadas em `obra_taxon`).
- **Validação e saída:** `validacao.R` (plausibilidade, reconciliação dentro da
  obra, limiares, fonte primária) → `revisao.R` (conjunto-ouro, fila humana) →
  `dwc.R`.
- **Planilha legada do livro:** `migrar_planilha.R`, `corrigir_planilha.R`
  (regras R1–R18, cada mudança registrada), `decisoes_traits.R`.
- **Orquestração:** `_targets.R`. **Diagnóstico:** `verificar_infra()` em
  `diagnostico.R`. **Testes de fumaça:** `fumaca.R` (um PDF escolhido a dedo),
  `fumaca_busca.R` (busca, triagem, aquisição e extração de uma espécie).

## Armadilhas conhecidas

- **DuckDB aceita um processo escrevendo por vez.** Se o RStudio estiver com o
  `girinos.duckdb` aberto, o `Rscript` rodado daqui falha ao abrir o banco.
  Peça para fechar com `DBI::dbDisconnect(con, shutdown = TRUE)`.
- **Temperatura.** O Haiku 4.5 aceita `temperatura: 0` (no `config.yml`, só na
  triagem); o Sonnet 5.5 e o Opus 5.5 recusam o parâmetro com HTTP 400. Nesses
  dois, a variação entre rodadas tem de ser medida, não fixada.
- **GROBID** roda no Docker, em `http://localhost:8070`:
  `docker run --rm --init --ulimit core=0 -p 8070:8070 grobid/grobid:0.9.1-crf`
- **OpenAlex** responde 429 se receber chamadas em sequência rápida: espaçar.
- `limpar_fumaca_busca()` apaga extrações, trechos e obras órfãs do táxon de
  teste (os PDFs ficam). Não rode antes de o Diogo ver os resultados.
- **Táxons de teste no banco:** `TESTEBUSCA001` = *Physalaemus barrioi* (busca
  e extração completas); `TESTE001` = Conte et al. (2007), *Scinax catharinae*.

## Commits

- Mensagem em português: o que mudou e por quê.
- Manter a linha `Co-Authored-By` da IA: o projeto declara o uso de IA,
  conforme COPE e as diretrizes do CNPq/CAPES.
- Rodar todos os testes antes do commit. `git push` só quando o Diogo pedir.
