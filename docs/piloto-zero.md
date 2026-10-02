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
- **Orçamento:** teto de **US$ 4 no total** em API (Diogo, 02/10/2026; havia
  US$ 4,77 de crédito na conta). O teto inicial era US$ 5, mas a estimativa
  com a contagem real de trechos deu ~US$ 2–2,5 por rodada. Referência
  medida: US$ 0,083 para 8 obras × 2 traits numa rodada (*P. barrioi*,
  preços de 30/09/2026). **Regra de parada:** `limite_usd = 2` na rodada 1;
  na rodada 2, `limite_usd = 4 −` o que a rodada 1 gastou (menos o custo de
  `verificar_infra()`).
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
   sinonímia do AmphiNom** (https://github.com/hcliedtke/AmphiNom).
   **Feito:** `sinonimos_amphinom()` (`R/sinonimia.R`) lê as tabelas que o
   pacote já traz (`asw_synonyms`, `asw_taxonomy`; AmphiNom 1.1.0, data do
   pacote 2025-10-16), sem varrer o site da ASW. Casa grafia por
   concordância de gênero (*flavoguttata* × *flavoguttatus*) e manda para
   revisão — sem incluir — o sinônimo que atribuiria dado a outra espécie:
   trinômio cujo binômio não é da própria espécie (ex.: "Leptodactylus
   ocellatus var. bonairensis", sob *L. luctator*, viraria "L. ocellatus",
   que a ASW lista sob *L. bolivianus*), binômio que é espécie válida
   diferente, e sinônimo de mais de uma espécie da lista. Teste em
   `tests/teste_sinonimos.R`. Preparação refeita: **133 de 138** espécies
   achadas no texto da própria obra (eram 105); 341 sinônimos; 53 nomes em
   `Claude outputs/piloto-zero/sinonimos_revisar.csv`.

   **5 espécies de Rossa-Feres & Nomura (2006)** que o artigo chama por nomes
   que não são sinônimos no AmphiNom. Decididas pelo Diogo (01/10/2026) e
   gravadas em `inst/sinonimos.csv`:

   | espécie | nome no artigo | escopo |
   |---|---|---|
   | *Trachycephalus typhonius* | *Trachycephalus venulosus*, *Phrynohyas venulosa* | global |
   | *Physalaemus marmoratus* | *Physalaemus fuscomaculatus* | global |
   | *Pseudis platensis* | *Pseudis paradoxa* | só nesta obra (*P. paradoxa* é válida) |
   | *Elachistocleis cesarii* | *Elachistocleis* sp. | só nesta obra (*E. bicolor* é válida e também está na obra) |
   | *Leptodactylus luctator* | *Leptodactylus ocellatus* | só nesta obra |

   Para isso, `inst/sinonimos.csv` passou a identificar a espécie pelo nome
   aceito e a aceitar `doi_obra` (sinônimo que vale só naquela obra);
   `aliases_de()` usa os restritos só na recuperação dentro do PDF, não na
   busca nem na triagem. Escopo global só para nome que não é espécie válida
   na ASW. Preparação refeita: **137 de 138** espécies achadas.

   *L. ocellatus* nesta obra: o Diogo identificou como *L. macrosternum*, mas
   decidiu manter os registros sob *L. luctator*, como está na planilha
   (01/10/2026; "a taxonomia é complicada"). O sinônimo restrito aponta para
   *L. luctator*. Com isso, **138 de 138** espécies achadas no texto.

   **AmphiNom defasado (Diogo).** As tabelas empacotadas foram atualizadas
   pela última vez em 17/10/2025 (commit `77b3674` no GitHub; a versão
   instalada, `81980b8`, é a mais recente); a planilha segue Frost (2026).
   As combinações *Trachycephalus venulosus* e *Phrynohyas venulosa* não
   estão nos sinônimos do pacote. Não deu para comparar com o site: a ASW
   responde HTTP 403 a acesso automático.

   As funções antigas `atualizar_cache_asw()` e `sincronizar_sinonimos()`
   chamam `getTaxonomy()`, `getSynonyms()`, `aswSync()` e `synonymReport()`,
   que o AmphiNom 1.1.0 renomeou (`get_taxonomy()`, `asw_sync()`…): quebram
   se chamadas. `_targets.R` só as chama se existir `inst/asw_cache.rds`.
5. **Escopo:** na prática, as 4 fontes com registro (276 pares = 138
   espécies × 2 traits). As outras 6 entram no banco sem par nenhum e não
   custam nada.
   **Trava: recuperação em monografia.** Medido em 01/10/2026 rodando só a
   recuperação (BM25, sem modelo): 68 dos 118 pares de Pezzuti et al. (2021)
   não têm nenhum trecho candidato, e iriam para "só planilha" sem o modelo
   ver nada. Causa: cada ficha de espécie vem do GROBID em parágrafos
   separados — o nome no primeiro ("Vitreorana eurygnatha (Fig. 9) Specimens
   examined…", seção "Tadpole descriptions / Centrolenidae") e os caracteres
   no seguinte (seção "Tadpole descriptions / Morphology.", sem o nome).
   `recuperar_candidatos()` exige espécie e termo do trait no mesmo trecho.
   **Corrigido (aprovado pelo Diogo, 02/10/2026):** os trechos guardam a
   `ordem` no documento, e `herdar_especie()` (`R/recuperacao.R`) deixa o
   nome valer para os parágrafos de texto seguintes até aparecer outra
   espécie da obra ou passarem 3 parágrafos. O trecho herdado vai ao agente
   com o parágrafo que nomeia a espécie como contexto, mas a frase-fonte tem
   de estar no próprio trecho (`validar_span()` não mudou). Medido no
   banco-base: pares sem candidato em Pezzuti 68 → 8 (limite 3; 6 daria 7,
   com +23 chamadas). Teste em `tests/teste_heranca.R`. Também: TEI sem corpo
   (Prado et al. 2009) agora para com o motivo e cai no texto por página,
   inclusive em `reestruturar_de_tei()`.
   **Custo estimado depois da correção** (caracteres reais dos candidatos,
   preços de `PRECO_MILHAO`, suposição de ~400 tokens de prompt e ~200 de
   resposta por chamada): **573 chamadas, ~US$ 2,3 por rodada sem
   escalonamento, ~US$ 3,4 se o Opus for 1/3 do custo** como em
   *P. barrioi*. Com `k = 3` candidatos por par (hoje 4): 536 chamadas,
   ~US$ 2,1 / ~US$ 3,2. **Duas rodadas não cabem no teto de US$ 4** —
   decisão do Diogo pendente.
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

## Resultados das rodadas (02/10/2026)

Duas rodadas completas, 276 pares cada (138 espécies × 2 traits, 4 obras).
Saídas em `Claude outputs/piloto-zero/` (fora do git). Números agregados:

| | rodada 1 | rodada 2 |
|---|---|---|
| custo | US$ 1,93 | US$ 1,90 |
| tempo | 30,1 min | 29,7 min |
| chamadas ao agente de valor | 573 | 573 |

**Concordância crua com a planilha** (rodada 1, antes da adjudicação):

| trait | pares | igual | diverge | só planilha | só modelo | concordância crua | estáveis entre rodadas |
|---|---|---|---|---|---|---|---|
| `eyes_positioning` | 138 | 86 | 9 | 43 | 0 | 62% | 99% |
| `snout_shape_lv` | 138 | 79 | 20 | 39 | 0 | 57% | 99% |

- **Adjudicação:** 111 pares em `adjudicacao.csv`, para o Diogo.
- **Variação entre rodadas é pequena:** 99% dos pares deram o mesmo resultado
  nas duas rodadas, mesmo sem temperatura fixa (Sonnet 5.5).
- **"Só planilha" (82 pares):** 10 sem nenhum trecho candidato (8 em
  Pezzuti, 2 em Santos), 72 com candidato em que o modelo não achou o valor.
  Conte et al. (2007) concentra 26 dos 32 pares — a investigar (o dado pode
  estar em tabela comparativa ou em figura).
- **"Diverge":** em boa parte o modelo devolve mais de um valor para o par
  (ex.: o valor da planilha e outro, de trechos diferentes); a reconciliação
  marca `conflito`. A adjudicação dirá se o segundo valor é de outra espécie,
  de outra vista ou da descrição.
- **Escalonamento (medida 3):** o agente de valor **não escalou nenhuma** das
  573 chamadas, inclusive as 318 sem valor: ao não achar, o modelo devolve o
  span como texto vazio, e `com_escalonamento()` só escala quando o span vem
  ausente (`NULL`/`NA`). Todo o Opus (US$ 0,07 por rodada) veio do agente de
  contexto, que escalou em 3 das 4 obras. Antes de mexer: decidir se "não
  encontrado" deve escalar (custo sobe) — item 3 de "Onde paramos".
- **Contexto (medida 4):** as 4 obras com Métodos identificados; estágio de
  Gosner devolvido em todas (a conferir no PDF pelo Diogo).
- **Custo por tripla (medida 5):** US$ 0,0070 (US$ 0,0055–0,0088 por obra),
  6,5 s por tripla em sequência.

### Projeção para o projeto inteiro

BT 5.1.1 (gerada em 25/09/2026): 676 espécies com girino descrito; faltam
20.168 das 32.448 células espécie × trait (62%). Sem o livro de 2024 (sem PDF;
a planilha já é a extração dele), as referências da BT 5 dão 37.539 triplas.

| cenário | triplas | custo de API | tempo de máquina |
|---|---|---|---|
| só as referências da BT 5 | 37.539 | ~US$ 260 (210–330) | ~68 h |
| com a busca de literatura | ~2–4× | ~US$ 500–1.000 | ~140–270 h |

O cenário com busca se apoia num caso só (*P. barrioi*: 8 obras relevantes
achadas pela busca contra 1 referência da BT 5 além do livro). Ficam de fora:
traits numéricos (só categóricos foram medidos), escalonamento do agente de
valor (não disparou) e desconto da API de lotes (não conferido). O gargalo
não é custo: só 64 das 753 obras da BT 5 têm DOI, e a maior parte dos PDFs
vai entrar à mão.
