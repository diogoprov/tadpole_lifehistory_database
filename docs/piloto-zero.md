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

### Depois do piloto: tabelas (02/10/2026)

Conte et al. (2007) concentrou 26 dos 32 pares "só planilha". O dado está na
Tabela 3 (uma linha por espécie, coluna "Snout shape (Lateral)"), e três
coisas o escondiam: (1) o GROBID perdeu a tabela, em página de paisagem — o
TEI ficou só com cabeçalhos transpostos e um valor; (2) tabela só era
candidata quando nenhum trecho de texto citava a espécie; (3) as linhas usam
abreviações ("Sarg") definidas na legenda pelo nome antigo
("S. argyreornatus"), e o prompt só levava o nome aceito.

Corrigido (aprovado pelo Diogo):

- `tabelas_do_texto_pdf()` / `com_tabelas_do_pdf()` (`R/parse.R`): cada
  legenda "Table N"/"Tabela N" no início de linha do texto do PDF vira um
  trecho de tabela, com o layout; as tabelas do GROBID continuam.
- `recuperar_candidatos()`: tabela que cita a espécie tem vaga garantida
  entre os k candidatos.
- `agente_valor()`: o prompt leva os sinônimos da espécie, os outros nomes do
  trait e, para tabela, como ler a abreviação e copiar a linha da espécie.
  `validar_span()` não mudou.
- **"Eye direction" = `eyes_positioning`** (Diogo: na literatura os dois
  quase nunca se distinguem): coluna nova `nomes_alternativos` em
  `inst/traits.csv`, e o termo nos `termos_busca`.

Medido no banco-base, sem modelo: os 26 pares "só planilha" de Conte et al.
(2007) passam a ter a Tabela 3 como candidata; nos outros, mais 9 pares "só
planilha" e 3 "diverge" ganham tabela. Teste em `tests/teste_tabelas.R`. O
efeito na concordância só se mede rodando de novo (custo de uma rodada,
~US$ 2).

### Rodada 3: com as tabelas (02/10/2026)

Rodada completa com as tabelas do PDF, os sinônimos no prompt e "eye
direction" como `eyes_positioning`. **Custo: US$ 2,36, acima do limite de
US$ 2** pedido pelo Diogo: o limite só era conferido no fim de cada obra, e a
última (Pezzuti et al. 2021) custou US$ 0,89 sozinha; o `stop()` também pulou
a reconciliação, rodada depois à mão (sem modelo). Corrigido: o limite agora é
conferido a cada par, e a plausibilidade e a reconciliação rodam mesmo quando
a rodada para (`tests/teste_piloto_zero.R`). Gasto total do piloto:
US$ 6,19 em três rodadas.

| trait | igual (r1 → r3) | diverge | só planilha | concordância crua (r1 → r3) |
|---|---|---|---|---|
| `snout_shape_lv` | 79 → 93 | 20 → 18 | 39 → 27 | 57% → 67% |
| `eyes_positioning` | 86 → 80 | 9 → 31 | 43 → 27 | 62% → 58% |

- **Tabelas funcionaram:** Conte et al. (2007) foi de 6 para 29 pares iguais,
  e de 26 para 0 "só planilha". 30 registros vieram de tabela.
- **"Eye direction" piorou `eyes_positioning` onde o artigo dá os dois.**
  Pezzuti et al. (2021) escreve "located dorsally (...), directed
  dorsolaterally"; a planilha registra a posição (dorsal), e o modelo, com
  "eye direction" como sinônimo, passou a devolver a direção (dorsolateral):
  17 pares "dorsal → dorsolateral". **A decidir pelo Diogo:** usar a direção
  só quando o trecho não der a posição.

### Conferência humana da rodada 3 (02/10/2026)

A planilha `Claude outputs/piloto-zero/para_denise/conferencia_piloto_zero_Denise.xlsx`
(gerada por `gerar_planilha.py`, na mesma pasta) está com a Denise e uma aluna.
Para as próximas rodadas, o gerador foi reescrito em R: `gerar_conferencia()`
(`R/conferencia.R`), com o mesmo formato. Conferido contra a planilha da
rodada 3: bloco 1, nomes, valores e frases idênticos; página da frase igual
em 112 de 114 pares (nos outros 2, o R acha uma página a mais do nome); o
sorteio do bloco 2 muda, porque o gerador aleatório do R não é o do Python.
A planilha enviada não é regenerada.
Ela substitui o `adjudicacao.csv` das rodadas 1 e 2: em vez de escolher entre
planilha e modelo, registra o que o **artigo** diz (`valor_correto`), e com
isso qualquer rodada, inclusive as futuras, é pontuada sem nova conferência.
136 linhas: bloco 1 = os 103 pares não iguais da rodada 3; bloco 2 = 33 pares
iguais (8 com a mesma frase usada para duas espécies, 25 sorteados).
Conferido contra a rodada 3: chaves, valores e o bloco 1 completo batem.

Quando voltar:

```r
conf <- ler_conferencia("<arquivo devolvido>.xlsx", carregar_traits("inst/traits.csv"))
r3 <- readr::read_csv("Claude outputs/piloto-zero/r3/pares.csv")
avaliar_conferencia(conf, r3)$resumo   # e o mesmo com pares.csv para a rodada 1
```

`ler_conferencia()` para com os ids se algum valor estiver fora das listas e
aceita conferência pela metade. `avaliar_conferencia()` pontua modelo e
planilha contra o artigo: certo, parcial (o certo entre outros valores),
não achou, errado; "outro (ver nota)" fica de fora e é contado à parte. Teste
em `tests/teste_conferencia.R`.

### Conferência da rodada 3 devolvida (04/10/2026)

A Eduarda conferiu as 136 linhas (`conferencia_piloto_zero_Denise_conferidoEduarda.xlsx`,
na raiz, fora do git). Pontuação com `avaliar_conferencia()` contra
`Claude outputs/piloto-zero/r3/pares.csv`, sem chamada de modelo:

| | bloco 1 (103 não iguais) | bloco 2 (33 iguais) |
|---|---|---|
| modelo certo | 26 | 29 |
| modelo parcial (certo entre outros valores) | 20 | — |
| modelo errado | 8 | 4 |
| modelo não achou | 49 | — |
| planilha certa | 60 | 29 |

| bloco 1, por trait | conferidos | modelo certo | parcial | não achou | errado | planilha certa |
|---|---|---|---|---|---|---|
| `eyes_positioning` | 58 | 22 | 7 | 25 | 4 | 19 |
| `snout_shape_lv` | 45 | 4 | 13 | 24 | 4 | 41 |

Nenhuma linha "outro (ver nota)"; 5 "não informado"; nada só em figura.
O bloco 1 reúne só os casos difíceis: **não é taxa de acerto geral.** Dos 276
pares da rodada, 173 eram iguais; no bloco 2, 29 de 33 iguais estavam certos
(4 erros em comum de planilha e modelo).

O que a conferência mostrou:

- **Frase de outra espécie:** `frase_da_especie_certa = "não"` em 32 linhas
  (18 parciais, 8 erradas, 2 não achou, 4 certas por coincidência). Vêm da
  descrição de espécie vizinha na mesma obra, da discussão comparativa
  ("differ from S. fuscovarius by the snout rounded…") e da chave de
  identificação (Rossa-Feres & Nomura 2006). O span confere com o texto: a
  Eduarda estranhou medidas "que não estão no artigo", mas conferido no PDF
  (`pdftools`), "ED/BH = 0.29-0.30" e "0.22-0.22" estão em Santos et al.
  (2023), na descrição de outras espécies. Hífen no lugar de travessão e espaço
  faltando após a vírgula vêm do GROBID. **O span literal não protege contra
  frase de outra espécie;** isso pesa mais quando o trait for numérico.
- **"Não achou" é a maior perda:** 49 no bloco 1, 47 deles sem frase nenhuma.
- **O "||" na planilha** junta os spans distintos do mesmo par
  (`R/piloto_zero.R`, `paste(unique(span_verbatim), collapse = " || ")`);
  a aluna não sabia disso, e o LEIA-ME só diz "o modelo devolveu dois trechos".
- **Ordem:** a planilha separa os blocos, e a mesma espécie aparece longe do
  outro trait. Pedido da Eduarda: agrupar por artigo e espécie, traits sempre
  na mesma ordem. Prometido a ela no e-mail de 04/10/2026 para as próximas
  planilhas (`gerar_conferencia()` / `gerar_conferencia_corpus()` ordenam
  por bloco primeiro).
- Nota em R113 (*Boana raniceps*, Santos et al. 2023): página errada; a
  espécie está na p. 16 do PDF. A conferir.

### Diagnóstico das duas falhas, sem modelo (04/10/2026)

Cruzando a conferência com `chamadas_valor` da rodada 3 (quais trechos o
modelo recebeu em cada par):

- **"Não achou" é falha da recuperação, não do modelo.** Nos 49 pares, a
  ficha da própria espécie quase nunca estava entre os trechos enviados: 6
  pares sem candidato, e os demais receberam chave de identificação, Tabela 1
  de medidas, checklist ou a ficha de outra espécie. O "não encontrado" do
  modelo estava certo diante do que ele viu.
- **Causa principal: título de seção velho do GROBID.** Em Santos et al.
  (2023) e Rossa-Feres & Nomura (2006), o nome de uma espécie fica como
  `secao` de várias fichas seguidas (a de *Trachycephalus typhonius* sob
  "Scinax squalirostris"). Como a espécie é procurada também no título da
  seção, a ficha seguinte era atribuída à espécie do título (frase de outra
  espécie), e a seção com o nome da outra espécie cortava a herança da ficha
  certa (não achou).
- **Chave de identificação** (Rossa-Feres & Nomura 2006): era o único
  candidato de 12 pares e fonte de frases de outra espécie ("eyes
  dorsolaterally directed; snout pointed ........ Elachistocleis sp.").
- **Comparação e descrição de outro autor**: "differ from S. fuscovarius by
  the snout rounded", "described by Kolenc et al. (2008) ... dorsolaterally
  directed eyes".
- **O que ficou sem correção:** em Santos et al. (2023) o GROBID mistura as
  duas colunas (trechos como "view (BW/BH = 1.18-1.21).The snout is sloped"
  sem seção); em Pezzuti et al. (2021) põe parte das descrições longe do
  cabeçalho da ficha, junto das legendas de figura. Aumentar `max_herda` de
  3 para 4 ou 6 não recuperou nenhum desses pares (medido).

**Correções** (cada uma com teste que falha com o código antigo):

1. `secao_vale()` (`R/recuperacao.R`): o título da seção deixa de valer a
   partir do primeiro parágrafo daquela seção que começa com nome de espécie
   da obra. Teste em `tests/teste_heranca.R`.
2. `e_chave()`: linha com pontilhado só é candidata se não houver outro
   trecho. Mesmo teste.
3. `SISTEMA_VALOR` (`R/agentes.R`): só vale o que o trecho descreve desta
   espécie nos exemplares do próprio estudo; ignora comparação e o que outro
   trabalho descreveu. É a regra de fonte primária já decidida (01/10/2026).
   `prompt_versao` passou a `v2`. Teste em `tests/teste_agentes.R`.
4. Planilha de conferência: frase genérica (em mais de 3 páginas) mostra as
   páginas do nome da espécie; linhas ordenadas por artigo, espécie e trait.
   Teste em `tests/teste_conferencia.R`. Era o caso de *Boana raniceps*
   (R113): "The snout is rounded in lateral view." está em 16 páginas de
   Santos et al. (2023), e a planilha mostrava as 3 primeiras; a ficha está
   na p. 16 (a nota da Eduarda está certa; o valor, `rounded`, também).

**Efeito na recuperação, medido sem modelo** nos 131 pares com valor no
artigo (frase com o valor correto, fora da chave, entre os candidatos):

| | antes | depois |
|---|---|---|
| pares com a frase certa entre os candidatos | 35 | 48 |
| idem, entre os 49 "não achou" | 7 | 19 |
| pares com chave de identificação entre os candidatos | 35 | 5 |
| chamadas ao modelo | 289 | 265 |

### Rodada 4 (04/10/2026)

Com as quatro correções acima e o prompt `v2`. Pedida pelo Diogo; limite de
US$ 4. **Custo: US$ 2,08** (Santos 0,77; Conte 0,33; Rossa-Feres & Nomura
0,16; Pezzuti 0,82), 52 min, 552 chamadas, nenhuma escalonada para o Opus.
Banco, pares e pontuação em `Claude outputs/piloto-zero/r4/` (fora do git;
`rodar.R` e `pontuar.R` na mesma pasta). Pontuada contra a conferência da
Eduarda, sem nova conferência humana. 218 registros `bruto`, 29 `conflito`, 32
`rejeitado`.

**Focinho** (63 linhas conferidas; não depende de regra em aberto):

| `snout_shape_lv` | r3 | r4 |
|---|---|---|
| certo | 21 | 31 |
| parcial | 13 | 10 |
| não achou | 24 | 16 |
| errado | 5 | 6 |

Transições: 7 "não achou" e 4 parciais viraram certos; 1 certo virou "não
achou" e 2 "não achou" viraram erro.

**Olhos: a pontuação depende da regra posição × direção.** O
`inst/traits.csv` manda registrar a posição quando o artigo dá as duas
(`regra_extracao`), e o LEIA-ME da conferência dizia o mesmo. A Eduarda marcou
a **direção** em pelo menos 28 linhas ("Eye small, dorsal, dorsolaterally
directed" → `dorsolateral`). A rodada 3 devolvia a direção, contra a regra; a
rodada 4 devolve a posição. Contra a conferência como está, os olhos caem de
34 para 19 certos, mas **27 dos 31 erros da rodada 4 são exatamente esses
casos** (o modelo seguiu a regra; 26 `dorsal`, 1 `lateral`). Os outros 4 são
erros de verdade: 3 frases de outra espécie em Pezzuti et al. (2021) e 1
frase ambígua ("Eyes small, dorsal and laterally directed"). Os 20 "não
achou" dos olhos não mudaram. **Até a regra ser confirmada e as 28 linhas
remarcadas (ou a regra mudar), a nota dos olhos não vale.**

**Frase de outra espécie:** nos 32 pares marcados na rodada 3, 26 ainda
trazem pelo menos uma das mesmas frases. O prompt `v2` sozinho não resolve;
o que mudou veio da recuperação. Resultado desses 32 na rodada 4: 9 certos,
11 parciais, 10 errados (parte deles pela regra dos olhos), 2 não achou.

**O que sobra de "não achou" é GROBID:** Santos et al. (2023) com as duas
colunas misturadas e Pezzuti et al. (2021) com descrições longe do
cabeçalho da ficha. 36 pares no total (16 de focinho, 20 de olhos).

### Por que a frase de outra espécie persistia, e as fichas lidas do PDF (04/10/2026)

Rastreando, sem modelo, de onde vinha cada frase de outra espécie que
voltou na rodada 4 (26 dos 32 pares):

- **Legenda como âncora (12 casos):** em Pezzuti et al. (2021) o GROBID põe
  a legenda "Figure 34. Dendropsophus seniculus…" ao lado da descrição de
  outra espécie, e o parágrafo seguinte herdava o nome da legenda.
- **Comentário como âncora (5 casos):** "Comments. These tadpoles are
  similar to…" cita a espécie de passagem, e a ficha seguinte herdava.
- **Cabeçalho perdido:** em Rossa-Feres & Nomura (2006) o GROBID perdeu o
  cabeçalho da ficha de *Scinax fuscomarginatus*; a frase certa da rodada 4
  veio por sorte, herdada de um comentário.
- **Sinônimo com ponto:** "Elachistocleis sp." (restrito a Rossa-Feres &
  Nomura 2006) virava o padrão `E\.?\s+sp.`, e o ponto solto casava "the
  species" e "the spiracle": todo trecho da obra "citava" *E. cesarii*.
  Corrigido em `padrao_especie()` (nome escapado; sem abreviação de "sp.",
  "cf."), teste em `tests/teste_heranca.R`. No banco principal nenhum
  sinônimo tem ponto.

Restringir a âncora (só cabeçalho de ficha passa o nome adiante) foi
medido e **desfeito**: tirava 7 trechos errados, mas a frase certa caía de
94 para 83 pares, porque em Pezzuti a legenda às vezes está ao lado da
descrição certa. A página do trecho resolveria, mas o GROBID não a grava.
A validade da seção passou a ser por espécie (`secao_vale()`), da primeira
seção que a nomeia até o próximo cabeçalho de ficha: mesma recuperação
certa (94), trechos de outra espécie de 19 para 17.

**Conclusão: os itens 2 e 3 eram o mesmo problema, a estrutura que o GROBID
entrega para monografias.** `R/fichas.R` lê as fichas direto do PDF
(`pdftools::pdf_data`, com posição e fonte de cada palavra): divide a página
em duas colunas, pula linha com fonte menor que a do corpo (legenda, tabela,
rodapé; 7–8 pt contra 9–10 pt nos três PDFs), abre ficha na linha que começa
com binômio em itálico seguido de autor e ano, "(Fig", "cf." ou híbrido, e
fecha no próximo cabeçalho, em título de seção em caixa alta ou nas
Referências. As fichas entram como trechos `tipo = "ficha"`
(`estruturar_obras()`, `reestruturar_de_tei()`; `acrescentar_fichas()` para
obra já estruturada). Na recuperação, **espécie com ficha recebe só a
ficha**; sem ficha, segue o GROBID (Conte et al. 2007, por exemplo, que é
tabela). Teste em `tests/teste_fichas.R`.

Medido sem modelo nos 131 pares com valor no artigo:

| | rodada 4 | com fichas |
|---|---|---|
| frase com o valor certo entre os candidatos | 94 | 122 |
| trechos de frase de outra espécie entre os candidatos | 19 | 0 |
| pares sem candidato | 7 | 1 |
| chamadas ao modelo | 270 | 149 |

### Rodada 5 (04/10/2026)

Com as fichas. Pedida pelo Diogo; limite de US$ 4. **Custo: US$ 1,63**
(Santos 0,40; Conte 0,34; Rossa-Feres & Nomura 0,16; Pezzuti 0,73), 22 min,
331 chamadas, nenhuma escalonada. 267 `bruto`, 2 `conflito`, 4
`rejeitado`. Arquivos em `Claude outputs/piloto-zero/r5/` (`rodar.R`,
`pontuar.R`).

| contra a conferência da Eduarda | r3 | r4 | r5 |
|---|---|---|---|
| focinho certo (de 63) | 21 | 31 | **60** |
| focinho errado | 5 | 6 | 2 |
| focinho não achou | 24 | 16 | 1 |
| olhos certo (de 73) | 34 | 19 | 35 |
| olhos errado | 7 | 31 | 36 |
| olhos não achou | 25 | 20 | 2 |

**Os 36 erros de olhos da rodada 5 são todos a regra posição × direção:** o
artigo dá as duas ("located dorsally, directed dorsolaterally"; "Eyes small,
dorsal and laterally directed"), o modelo registrou a posição, como manda o
`inst/traits.csv`, e a conferência registrou a direção. Se a regra for
mantida, os olhos ficam em 71 de 73 certos; se mudar para a direção, é
mudar a `regra_extracao` e rodar de novo.

Das 32 linhas com frase de outra espécie na rodada 3, 26 estão certas na
rodada 5; 7 pares ainda repetem alguma frase da rodada 3, em geral a certa.

**Limitações conhecidas das fichas:** cabeçalho com letras espaçadas no
PDF ("E u p e m p h i x n a t t e r e r i", Rossa-Feres & Nomura 2006) não é
reconhecido; a última ficha antes de uma seção sem título em caixa alta
pode engolir texto (a de *Proceratophrys boiei* em Pezzuti tem 20 mil
caracteres); layout de uma coluna ou de três não foi testado. Só os 4 PDFs
do piloto foram medidos.

### Regra da posição dos olhos e variação entre rodadas (04/10/2026)

**Regra (Diogo, 04/10/2026): vale a posição** quando o artigo dá posição e
direção, como já dizia o `inst/traits.csv`. O gabarito da conferência foi
corrigido sem mexer na planilha devolvida: `corrigir_regra_posicao()`
(`R/piloto_zero.R`, teste em `tests/teste_conferencia.R`) lê a posição na
frase do artigo (nota da conferência, ou a frase literal da rodada 5) e
troca o valor registrado quando a frase dá as duas. **35 trocas**, cada uma
em `Claude outputs/piloto-zero/regra_posicao/trocas.csv` com a frase e a
fonte; script em `regra_posicao/pontuar.R`.

**Variação entre rodadas:** rodadas 6 e 7 com a mesma base (fichas com as
correções do corpus) e o mesmo código (prompt `v3`), em paralelo. Custo:
US$ 1,40 e US$ 1,33. **Os 276 pares deram o mesmo conjunto de valores nas
duas rodadas (100%)**; com a recuperação estável e o vocabulário fechado, o
Sonnet 5.5 sem temperatura não variou nos dois traits. Script em
`Claude outputs/piloto-zero/variacao_r6_r7.R`.

Contra o gabarito corrigido (regra da posição):

| | r3 | r4 | r5 | r6 = r7 |
|---|---|---|---|---|
| olhos certo (de 73) | 20 | 46 | 70 | **71** |
| olhos errado | 21 | 3 | 1 | 1 |
| olhos não achou | 25 | 20 | 2 | 1 |
| focinho certo (de 63) | 21 | 31 | 60 | **60** |
| focinho errado | 5 | 6 | 2 | 2 |
| focinho não achou | 24 | 16 | 1 | 1 |

Gasto total do piloto: US$ 12,63 em sete rodadas.

### Haiku 4.5 e API de lotes (04/10/2026)

Pedidos pelo Diogo depois da estimativa de custo do pipeline inteiro.

**Rodada 8: Haiku 4.5** nos agentes de valor e de contexto (escalonamento
segue para o Opus), mesma base e código das rodadas 6 e 7. Contra o gabarito
corrigido:

| | Sonnet 5.5 (r6 = r7) | Haiku 4.5 (r8) |
|---|---|---|
| olhos certo (de 73) | 71 | 70 |
| focinho certo (de 63) | 60 | 58 |
| custo registrado | US$ 1,37 | US$ 0,82 |

O Haiku erra 3 pares a mais em 136 e custa ~60% do Sonnet (os dois custos
sem a leitura de cache; ver abaixo).

**API de lotes:** `extrair_tudo_lote()` (`R/lote.R`, teste em
`tests/teste_lote.R`). Mesmo prompt (`prompt_valor()`) e mesmo registro
(`registro_extracao()`) do modo normal; um lote por trait; o escalonamento é
um segundo lote só com os pedidos sem span; pedido com erro ou resposta
ilegível para a rodada sem gravar nada (no `ellmer` 0.5.0, resposta ilegível
vira só aviso e linha NA); o limite de gasto é conferido por estimativa antes
de mandar. Validado em Conte et al. (2007) com o Sonnet: **os 32 pares iguais
aos da rodada 6**. Custo: **US$ 0,22, contra ~US$ 0,26 no modo normal** (só
~15% menos). O modo normal já usa cache de prompt (o prefixo repetido,
sistema e esquema, ~1.250 tokens por chamada, é lido a 0,1× o preço), e o
lote do `ellmer` não usa cache: cada pedido paga o prefixo inteiro, com 50%
de desconto. Para esta carga, o lote quase empata com o modo normal; o ganho
grande teria de vir de menos chamadas (vários traits por chamada) ou de
modelo mais barato.

**Defeito achado: a leitura de cache ficava fora do custo.** `uso_tokens()`
lia só `input` e `output` do `ellmer::token_usage()`, sem `cached_input`.
Os custos do modo normal registrados até 04/10/2026 estão por baixo (em
Conte, ~8%). Corrigido em `R/fumaca_busca.R` (`PRECO_MILHAO` ganhou o preço
da leitura de cache), teste em `tests/teste_limite_gasto.R`.
