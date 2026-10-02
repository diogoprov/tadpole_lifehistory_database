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

Levantada em 01/10/2026 a partir de `dwca/` (a planilha do livro já em Darwin
Core): são as 11 fontes distintas da base, juntando as variantes de `eventID`
(`:temporary`/`:permanent`). Cada PDF foi conferido pelo conteúdo (DOI, ou
periódico e páginas, na primeira página), não só pelo nome do arquivo. O mapa
fica em `inst/piloto_zero_obras.csv`.

A coluna "registros" conta os registros de `eyes_positioning` +
`snout_shape_lv` na planilha.

| # | referência (como na planilha) | PDF | registros |
|---|---|---|---|
| 1 | Rossa-Feres et al. (2024) — livro, ISBN 978-6599245831 | **não há** | 735 |
| 2 | Pezzuti et al. (2021) — 10.2994/SAJH-D-20-00042.1 | `pezzuti2021.pdf` | 118 |
| 3 | Santos et al. (2023) — 10.1590/1676-0611-BN-2023-1486 | `santos2023.pdf` | 82 |
| 4 | Rossa-Feres & Nomura (2006) — 10.1590/S1676-06032006000100014 | `rossa-feres2006.pdf` | 46 |
| 5 | Conte et al. (2007) — 10.1163/156853807780202387 | `conte2007.pdf` | 32 |
| 6 | Vasconcelos et al. (2011) — 10.1007/s10750-011-0762-9 | `vasconcelos2011.pdf` | 0 |
| 7 | Gomes, Rossa-Feres & Casatti (2007) — 10.1590/S0073-47212007000100007 | `gomes2007.pdf` | 0 |
| 8 | Conte & Rossa-Feres (2007) — 10.1590/S0101-81752007000400020 | `conteRossa2007.pdf` | 0 |
| 9 | Rossa-Feres, Jim & Fonseca (2004) — 10.1590/s0101-81752004000400003 | `Rossa-Feres2004.pdf` | 0 |
| 10 | Prado et al. (2009) — 10.2994/057.004.0311 | `doPrado2009.pdf` | 0 |
| 11 | Vasconcelos & Rossa-Feres (2005) — Biota Neotrop. 5(2), sem DOI | `vasconcelos 2005.pdf` | 0 |

**Consequência para o escopo (a decidir pelo Diogo):**

- Nos 2 traits do piloto só **4 fontes com PDF** têm registro na planilha
  (278 registros). As fontes 6–11 são de ecologia, distribuição e dieta e não
  trazem esses caracteres: o modelo rodaria nelas só para medir falso
  positivo, sem nada a comparar. `preparar_piloto_zero()` só liga a uma obra as
  espécies que a planilha tem nela, então as fontes 6–11 entram sem par
  nenhum.
- O livro de 2024 tem **73% dos registros** desses traits (735 de 1.013), e
  sem PDF fica fora.
- Pezzuti et al. (2021, 110 páginas) e Santos et al. (2023, 43 páginas) são
  chaves com muitas espécies: devem dominar o custo.
- **Citação a conferir:** o PDF de `gomes2007.pdf` tem como primeiro autor
  Tiago Gomes dos Santos (Iheringia 97(1):37-49); a planilha cita a mesma obra
  como "Gomes, Rossa-Feres & Casatti (2007)" e como "Santos et al. (2007)".
- O `eventID` `BN00706012007` (1 registro, fora dos traits do piloto) não
  casa com nenhuma fonte; parece erro de digitação de `BN00706012006`
  (Rossa-Feres & Nomura 2006). Não corrigido.

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

## O código do piloto

Os 5 itens levantados lendo o código em 01/10/2026 estão feitos, cada um com
teste em `tests/teste_piloto_zero.R` que falha com o defeito recolocado:

1. **Rodadas separadas.** `extracao_id` não inclui a rodada, e `estado_par`
   marcaria o par como `extraido`. `rodar_rodada()` (`R/piloto_zero.R`) copia o
   banco-base para `rodada_<n>.duckdb` e percorre os pares (obra, espécie,
   trait) direto, sem `estado_par` — senão a primeira obra que extraísse um
   par faria as outras obras com a mesma espécie serem puladas. Não refaz
   rodada que já existe.
2. **Toda chamada ao agente de valor** vai para a tabela `chamadas_valor`
   (escalonou? achou?), inclusive as que terminam em "não encontrado".
3. **Origem do contexto:** coluna `contexto_obra.fonte_contexto` (`metodos`,
   `estagio` ou `nenhum`).
4. **Comparação com a planilha:** `comparar_piloto()` classifica cada par nos
   quatro casos, mede a estabilidade entre rodadas e escreve
   `adjudicacao.csv` (separado por `;`, para o Excel em português), com as
   colunas `veredito`, `causa` e `nota` vazias. `concordancia_adjudicada()` lê
   de volta e **recusa calcular** se faltar veredito ou houver veredito fora de
   `modelo | planilha | ambos | nenhum`.
5. **Trechos já gravados:** `reestruturar_de_tei()` refaz os trechos a partir
   do TEI, sem GROBID; o `trecho_id` não muda. Aplicado ao `girinos.duckdb` em
   01/10/2026: a tese de 2009 passou de 0 para 21 trechos de Métodos, *B.
   ahenea* de 0 para 8, *stone frog* de 0 para 6.

Também: custo e tempo por obra na tabela `custo_obra` de cada rodada, e regra
de parada por `limite_usd` (a rodada para com erro ao passar do limite).

## Sequência

1. ~~Levantar a lista dos 11 artigos e ligar cada PDF ao artigo.~~ Feito
   (tabela acima, `inst/piloto_zero_obras.csv`).
2. ~~Os 5 itens de código, com teste.~~ Feito.
3. ~~`preparar_piloto_zero(cfg)`: banco-base, cópia dos PDFs, GROBID.~~ Feito
   em 01/10/2026 (30 s, sem modelo). Resultado em
   `Claude outputs/piloto-zero/preparacao.csv`: 10 obras estruturadas; as 4
   com registro ligam 16 (Conte et al. 2007), 22 (Rossa-Feres & Nomura 2006),
   41 (Santos et al. 2023) e 59 (Pezzuti et al. 2021) espécies. Contexto: 8
   obras com Métodos, Conte & Rossa-Feres (2007) pela busca por estágio,
   Prado et al. (2009) sem nada — o GROBID devolveu o TEI sem corpo (só o
   cabeçalho) e a obra caiu no texto por página. Prado não tem registro nos 2
   traits.
4. **Trava: nomes antigos nos artigos.** Das 138 espécies ligadas às 4 obras
   com registro, **33 não aparecem no texto da própria obra** com o nome atual
   da planilha (Frost 2026): 16 de 16 em Conte et al. (2007) (*Scinax* →
   *Ololygon*), 10 de 22 em Rossa-Feres & Nomura (2006) (*Hypsiboas* →
   *Boana* e outros), 5 de 59 em Pezzuti et al. (2021), 2 de 41 em Santos et
   al. (2023). Sem sinônimo, `recuperar_candidatos()` não acha a espécie e o
   par vira "só planilha" por defeito de nome, não de extração — custo gasto
   para medir a coisa errada. **Decisão do Diogo (01/10/2026): tirar a
   sinonímia do AmphiNom** (https://github.com/hcliedtke/AmphiNom), o pacote
   que `R/sinonimia.R` já usa. A fazer: obter os sinônimos por ele, revisar os
   ambíguos, e refazer a preparação (apagar `base.duckdb` e rodar
   `preparar_piloto_zero()` de novo).
5. **Decidir o escopo** à luz da tabela acima (só 4 fontes com registro nos 2
   traits; o livro fora).
6. `verificar_infra()` (custa uma chamada por modelo — só com o Diogo pedindo).
7. `rodar_rodada(cfg, 1, limite_usd = 2)`. **Gasta crédito.**
8. `rodar_rodada(cfg, 2)`. **Gasta crédito.**
9. `comparar_piloto()` e `resumo_medidas()`; o Diogo adjudica
   `adjudicacao.csv`; `concordancia_adjudicada()`.
10. Relatório: as 5 medidas, a lista de defeitos com causa e destino de cada um.

## Onde ficam as saídas

Planilha de adjudicação, relatório e qualquer tabela com dado da planilha do
grupo vão para `Claude outputs/piloto-zero/`, que o `.gitignore` já exclui: são
dados inéditos e o repositório é público. No repositório entram só o código, os
testes e o resumo dos números neste arquivo ou em `proximos-passos.md`.
