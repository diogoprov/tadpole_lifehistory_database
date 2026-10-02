# Piloto zero — plano

Escrito em 01/10/2026, a partir de entrevista com o Diogo. Decisões marcadas
"(Diogo)" vieram dele; o resto é proposta de execução e pode ser revisto.

## Para que serve

Rodar o extrator nos artigos que o grupo já extraiu à mão para a planilha do
livro e comparar. O objetivo é **achar defeito no pipeline** antes do piloto 1
(20 artigos novos com conjunto-ouro duplo-cego). Não calibra limiar e não mede
acurácia: a referência é **um** extrator humano, e a planilha também erra
(concordância de 48–55% entre as três descrições de *O. cultripes*, ver
`proximos-passos.md`).

## Escopo

- **Artigos:** os 11 da planilha que já foram extraídos à mão. **Os PDFs estão
  em `pdf/`, menos o livro de 2024, que o Diogo não tem (Diogo, 01/10/2026).**
  O piloto roda sem ele; a tabela abaixo registra a ausência. PDF fechado entra
  por `importar_pdfs_manuais()`; nada de ResearchGate ou Academia.edu.
- **Traits:** só os dois com vocabulário fechado, `eyes_positioning` e
  `snout_shape_lv` (Diogo). `cloacal_opening` e `lower_jaw_shape` entram no
  piloto 1, depois das 4 pendências de vocabulário.
- **Rodadas:** 2 rodadas completas da extração, para medir a variação entre
  rodadas (Diogo). O Sonnet 5.5 e o Opus 5.5 recusam `temperature`, então a
  variação não se fixa por parâmetro: tem de ser medida.
- **Orçamento:** teto de **US$ 5** em API (Diogo). Referência medida: US$ 0,083
  para 8 obras × 2 traits numa rodada (*P. barrioi*, preços de 30/09/2026).
  Para 11 artigos × 2 traits × 2 rodadas, a ordem de grandeza esperada é bem
  menor que o teto, mas o número que vale é o medido. **Regra de parada:** se a
  primeira rodada passar de US$ 2, parar e rever antes da segunda.
- **Escalonamento para o Opus:** **medir, sem mudar** (Diogo). A proposta de
  escalar só quando o valor vem sem span (item 3 de "Onde paramos") se decide
  com o número do piloto.

### Os artigos

A lista sai da planilha (fonte de cada registro dos dois traits), que não está
no repositório. **Primeiro passo: levantar a lista e preencher esta tabela.**

| # | referência | DOI | PDF | observação |
|---|---|---|---|---|
| 1 | [a levantar da planilha] | | | |

## O que medir

### 1. Concordância adjudicada, por trait

Unidade: o par (artigo, espécie, trait). Cada par cai num de quatro casos:

| caso | o que acontece |
|---|---|
| modelo = planilha | conta como concordância, sem revisão |
| modelo ≠ planilha | vai para adjudicação |
| só a planilha tem valor | vai para adjudicação: o modelo perdeu, ou o valor não está no texto (veio de figura, de outra obra, de inferência)? |
| só o modelo tem valor | vai para adjudicação: a planilha perdeu, ou o modelo errou? |

**Adjudicação pelo Diogo (Diogo).** Planilha com o par, o valor de cada lado e
o span literal do modelo. Veredito: `modelo` · `planilha` · `ambos` (os dois
aceitáveis) · `nenhum`. Com isso o número separa erro do pipeline de erro da
planilha.

Saídas: concordância crua e concordância adjudicada por trait; lista dos erros
atribuídos ao pipeline, cada um com uma causa (recuperação, valor, span,
contexto, parse).

### 2. Variação entre rodadas

Por par: as duas rodadas concordam (mesmo valor, ou as duas sem valor)? Taxa de
concordância por trait e lista dos pares instáveis. Par instável que também
diverge da planilha merece atenção especial.

### 3. Escalonamento

Quantas chamadas escalam para o Opus, quanto custam, e quantos registros o
Opus acrescenta que o Sonnet não tinha achado. Em *P. barrioi* o Opus foi 1/3
do custo e não rendeu registro (n = 1 espécie).

### 4. Contexto e estágio

Por artigo: de onde veio o contexto (`metodos`, `estagio` ou `nenhum`) e se o
estágio de Gosner devolvido bate com o artigo (o Diogo confere no PDF) e com a
planilha. Testa as duas correções de 01/10/2026:

- subseção de Métodos achatada pelo GROBID herda o título principal
  (`secoes_com_principal()` em `R/parse.R`);
- obra sem Métodos (nota curta, pôster) busca o estágio no texto: Gosner,
  Stage ou estágio (`trechos_de_contexto()` em `R/agentes.R`).

Notas vão ser comuns (Diogo), então vale contar quantos dos artigos caem em
`estagio` e quantos em `nenhum`.

### 5. Custo e tempo por artigo

Tokens de entrada e saída por modelo, US$ e segundos, por artigo e por trait.
É o número para projetar a rodada grande (376 espécies × traits × obras).

### Fora do escopo

Posição do trecho certo no BM25 (se `k = 3` basta) e diagnóstico detalhado da
estrutura do GROBID. Ficam para o piloto 1, salvo se aparecerem como causa de
erro na adjudicação.

## Critério para passar ao piloto 1

**Nenhum defeito aberto (Diogo).** Todo erro que a adjudicação atribuir ao
pipeline tem de estar explicado e, ou corrigido (com teste que o reproduz), ou
registrado como limitação conhecida em `proximos-passos.md`. Não há
concordância mínima: com 11 artigos e 2 traits o intervalo seria largo demais
para decidir alguma coisa.

## O que falta no código antes de rodar

Levantado lendo o código em 01/10/2026. Nada disso está feito.

1. **Rodadas separadas.** `extracao_id` não inclui a rodada, então a segunda
   sobrescreveria a primeira; e `estado_par` marca o par como `extraido`, então
   a segunda nem rodaria. Proposta mais simples: cada rodada num banco próprio
   (cópia do banco preparado, `db` diferente no config), comparadas depois.
2. **Registro de toda chamada escalonada.** Hoje o escalonamento só aparece no
   `extrator` do registro que ele gerou (`llm_escalonado`); escalonamento que
   termina em "não encontrado" não deixa rastro. Para a medida 3, gravar cada
   chamada (par, modelo, escalonou, achou, tokens).
3. **Origem do contexto.** `contexto_obra` não guarda se o texto veio de
   Métodos ou da busca por estágio. Acrescentar a coluna (por `ALTER TABLE ...
   ADD COLUMN IF NOT EXISTS`).
4. **Comparação com a planilha.** Script que cruza as extrações com os
   registros da planilha por (artigo, espécie, trait), classifica nos quatro
   casos e exporta a planilha de adjudicação (lida de volta com
   `ler_planilha_humana()`).
5. **Trechos já gravados.** As obras que já estão no banco foram estruturadas
   com o parse antigo; `estruturar_obras()` pula obra que já tem trechos. Os
   artigos do piloto devem ser estruturados com o parse novo (do TEI já
   existente, sem chamar o GROBID de novo).

## Sequência

1. Levantar a lista dos 11 artigos, preencher a tabela e ligar cada PDF de
   `pdf/` ao artigo (só falta o livro de 2024).
2. Fazer os itens 1–5 de "O que falta no código", com teste.
3. `verificar_infra()` (custa uma chamada por modelo — só com o Diogo pedindo).
4. Rodada 1. Conferir custo contra a regra de parada.
5. Rodada 2.
6. Gerar a planilha de adjudicação; o Diogo adjudica.
7. Relatório: as 5 medidas, a lista de defeitos com causa e destino de cada um.

## Onde ficam as saídas

Planilha de adjudicação, relatório e qualquer tabela com dado da planilha do
grupo vão para `Claude outputs/piloto-zero/`, que o `.gitignore` já exclui: são
dados inéditos e o repositório é público. No repositório entram só o código, os
testes e o resumo dos números neste arquivo ou em `proximos-passos.md`.
