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

Vinte e cinco conjuntos; cada um termina em "todos os testes passaram". Nenhum chama a
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
  `sinonimia.R` (`carregar_sinonimos()`: AmphiNom + `inst/sinonimos.csv`) e
  `revisao_sinonimos.R` (planilha dos ambíguos e volta das decisões).
  `referencias_doi.R`: DOI e acesso aberto das referências da BT 5
  (Crossref, OpenAlex, BHL, Unpaywall); só gera tabela, não grava no banco.
  Chaves da OpenAlex e do BHL em `~/.Renviron`, como a da Anthropic.
- **Estruturação:** `parse.R` (GROBID → trechos), `fichas.R` (ficha de cada
  espécie lida do PDF, por coluna e fonte) e `texto_perdido.R` (parágrafo do
  PDF que o GROBID não pôs em trecho nenhum) → `recuperacao.R` (espécie com
  ficha recebe só a ficha; sem ficha, BM25 nos trechos do GROBID, com a
  espécie procurada no título da seção e no texto).
- **Extração:** `agentes.R` (contexto, valor, escalonamento) → `extracao.R`
  (`extrair_tudo()` só cruza obra e espécie ligadas em `obra_taxon`); `lote.R`: o mesmo pela API de lotes, `extrair_tudo_lote()`;
  `extrair_par_multi()`: vários traits numa chamada por trecho).
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

## Memória de sessões (importada do Claude Code, 23/10/2026)

Condensado de
`~/.claude/projects/-Users-diogoborgesprovete-GitHub-tadpole-lifehistory-database/memory/`.

**Trabalho de código — sempre.** Explicitar suposições e perguntar quando ambíguo; mínimo
de código que resolve; mudanças cirúrgicas (cada linha alterada ligada ao pedido); critério
de verificação definido antes de implementar. Antes de mexer: dizer o plano curto com a
verificação de cada passo. Melhoria lateral se menciona, não se faz sem perguntar — foi o
que motivou o pedido ("sempre use este skill", 03/10/2026), no meio de uma sessão em que
correções laterais se acumulavam junto da tarefa pedida. Vale junto com os princípios
deste arquivo (medir antes de mudar, teste que reproduz o defeito).

**O banco principal é a réplica 2, desde 07/10/2026.** `girinos.duckdb` foi substituído por
`Claude outputs/variacao_rodadas_20261007/rep2.duckdb`; o anterior está em
`girinos_antes_rep2_20261007.duckdb`. A rep2 é reextração completa dos 136 pares
(obra, espécie), com os dois traits fechados juntos (modo multi), prompt `v4` e as regras
do focinho de 07/10 (variação = categoria combinada, dorsolateral = lateral);
`marcar_fonte_secundaria()` foi rodada depois da cópia.
Das três rodadas, foi a que mais acertou contra o gabarito da Denise no corpus v2 (olhos
52/58, focinho 42/44; o banco anterior tinha 39/44). Réplica × réplica: olhos 136/136,
focinho 114/116.
Em comparações "antes × depois" a referência é a **rep2**, não a reextração do focinho
(`extracoes_v4`/`chamadas_valor_v4` guardam o estado anterior). A conferência v3 enviada ao
grupo em 07/10 foi gerada com o banco antigo: 2 das 40 linhas (*Pseudis platensis*, olhos e
focinho) têm valor lá e nenhum valor na rep2 — ao pontuar a v3, comparar com o banco atual.

**Shiny app: só depois da base pronta** (pedido de 03/10/2026). Vem depois de pipeline
rodado, vocabulários fechados, conferência humana e base publicada — não começar antes, nem
que seja protótipo, sem pedido explícito. Quando for a hora, o app deve ler a saída
publicada (Darwin Core / `dwca/`), **nunca** o `girinos.duckdb` interno, que tem dados
inéditos do grupo; e deve mostrar a frase-fonte e a referência de cada valor, mais as
lacunas (`lacunas.txt`), coerente com a proveniência que o pipeline guarda. O site da BT 5
(`diogoprov/Brazilian-Tadpoles-5.0`) é JS estático, então o Shiny é peça à parte.
