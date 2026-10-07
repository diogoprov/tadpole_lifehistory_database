# Próximos passos

Estado em 07/10/2026.

## Onde paramos (leia primeiro)

### Estado em 07/10/2026 (tarde): respostas da Denise, compilação, reextração do focinho

Dois e-mails da Denise (07/10/2026), processados no mesmo dia.

- **R075** (*E. cesarii*): `sloped`, confirmado. O gabarito já usava.
- **R042** (*O. longilinea*): **o gabarito estava errado.** Santos et al.
  (2023) descreve a espécie como *Scinax longilineus* (11 girinos, Figura
  23), p. 21: "The snout is rounded in lateral view." A nota de 06/10 ("só
  aparece nas referências") veio de buscar a grafia *longilinea*. Corrigido
  nos dois gabaritos do piloto (`conferencia_denise/processar.R` e
  `regra_posicao/pontuar.R`). **Lição: ao conferir no PDF, buscar também o
  nome do artigo (sinônimo, gênero antigo, concordância do epíteto).**
- **R106** (*O. ariadne*, Conte et al. 2007): a Denise confirmou que o dado é
  compilado ("based on original descriptions … and not on direct
  examination") e propôs manter. **Decisão do Diogo: opção (b), o valor
  compilado vale, sempre como fonte secundária.** `inst/compilacoes.csv`
  (DOI da obra e espécies descritas nela, que seguem a regra comum),
  `carregar_compilacoes()` e `marcar_compilada()` em `R/validacao.R`;
  `decidir_fonte_primaria()` marca o valor como secundário e não deixa a
  obra compilada ser primária de ninguém. Teste em
  `tests/teste_fonte_primaria.R` (falha com o código antigo). O prompt não
  mudou: a Tabela 3 não cita a fonte por linha, e o modelo já extraía.
  Valor: Tabela 3, "Snout shape (Lateral)" = Rounded (a "Dorsal" é
  Truncate; o Apêndice 1 confirma). `rounded` nos dois gabaritos (a Eduarda
  tinha juntado as duas vistas). **Dubeux et al. (2020) não é compilação**
  (os autores examinaram exemplares) e não entrou. Só *Phyllodytes* tem
  parte "obtained from the literature because specimens were not
  available"; não tratado.
- **Piloto contra a Denise (r10):** olhos 72/73, **focinho 61/63** (eram
  59/63). Sobram R021 (não achou) e R047.
- **Grupo ou gênero:** a Denise aceita a regra e pergunta se deve anotar as
  espécies que são as únicas do gênero ou do grupo. Pedido no rascunho de
  resposta, com as 12 espécies das linhas de grupo (C045–C074).

**Reextração do focinho com as regras novas** (variação = categoria
combinada; dorsolateral = lateral). `Claude outputs/reextracao_focinho_20261007/`
(`rodar.R`, `pontuar.R`, `antes_depois.csv`; backup
`girinos_antes_reextracao_focinho_20261007.duckdb`; histórico em
`chamadas_valor_v4`/`extracoes_v4`). 116 pares, só `snout_shape_lv`, prompt
`v4`. **Custo: US$ 0,84** (Sonnet). Antes × depois: 57 iguais, 51 sem valor
nas duas, 6 ganharam valor, 2 perderam.

- Ganhou: *P. iheringii* ("rounded in a dorsolateral view", C002), e 4 da
  monografia de 2020 com "oval in lateral view" = `rounded`.
- **Corpus v2 contra a Denise (regra do grupo): olhos 52/58, focinho 39/44
  (eram 41/44).** As perdas são variação entre rodadas, não regra nova:
  *Pipa arrabali* (C011): mesmo `truncated`, mas o span veio com pedaço de
  tabela e `validar_span()` recusou; *B. ahenea* (C092): o trecho do GROBID
  acaba em "Snout rounded in", e desta vez o modelo recusou; *P.
  gyrinaethes* (C065): "Characteristics" do gênero *Phyllodytes*, que desta
  vez o modelo aceitou. Mais um sinal de que **a variação entre rodadas
  precisa ser medida** (item 6 da lista de 04/10).

**Variação entre rodadas, medida (07/10/2026, pedida pelo Diogo).**
`Claude outputs/variacao_rodadas_20261007/` (`rodar.R`, `comparar.R`,
`tres_rodadas.csv`, `instaveis.csv`; réplicas em `rep1.duckdb` e
`rep2.duckdb`, o banco principal não foi tocado). Duas réplicas idênticas dos
136 pares (obra, espécie) do corpus, os dois traits, prompt `v4`, modo multi.
**Custo: US$ 2,44** (1,27 + 1,18).

- **Réplica × réplica:** olhos 136/136 iguais; focinho 114/116 (98,3%). Nos
  pares com valor em alguma das 3 rodadas (r0 = banco atual): olhos 69/71
  estáveis, focinho 60/65.
- Instáveis: *Pipa arrabali* (`truncated` numa réplica só; na outra e no r0
  o span saiu com pedaço de tabela e foi recusado), *Pseudis laevis*
  (`pointed` × `sloped`), *P. gyrinaethes* e *Pseudis platensis* (valor só
  no r0), *B. ahenea* e *Physalaemus nattereri* (valor só nas réplicas).
- **Contra a Denise (corpus v2):** olhos 52/58 nas três; focinho **r0 39,
  rep1 41, rep2 42 de 44**. O r0 do focinho veio da reextração só com o
  trait do focinho; as réplicas, dos dois traits juntos. Com uma rodada de
  cada, não dá para dizer se o modo pesa ou se foi sorteio.
- Leitura: a variação é pequena (~2% dos pares de focinho entre réplicas,
  zero nos olhos) e se concentra em spans de tabela, trechos cortados pelo
  GROBID e caractere de gênero. Para o conjunto-ouro, uma rodada basta; os
  pares que mudam entre rodadas são candidatos naturais à fila humana.

**Para o grupo (passo 6):**

- **Conferência v3 refeita:** `Claude outputs/conferencia_corpus_v3/`
  (`gerar_20261007.R`): 40 linhas em 12 artigos, valores de hoje, só pares
  que a Denise não conferiu na v2 nem no piloto (Santos 2017/2018). A v3 de
  04/10 (nunca enviada) foi para `conferencia_corpus_v3_backup/v3_de_20261004/`.
  LEIA-ME com todas as regras (`inst/conferencia_corpus_LEIA-ME.txt`,
  incluída a do valor compilado).
- **Vocabulário v2:** `Claude outputs/vocabulario/vocabulario_traits_para_grupo_v2_20261007.xlsx`,
  os mesmos 46 traits, com as regras gerais no LEIA-ME
  (`planilha_vocabulario()`). Se o grupo já começou a de 03/10, segue nela.
- Rascunho de resposta à Denise: `Claude outputs/email_Denise_2026-10-07.md`.

**Próximos passos:**

1. Mandar o e-mail, a v3 e o vocabulário v2.
2. **Girino sem nome no trecho** e **adulto sem contexto** (C008, C101, C084).
3. **Variação entre rodadas:** medir antes de mais reextrações (rodar duas
   vezes os mesmos pares e contar as diferenças).
4. **PDFs com descrição original** (gargalo); reavaliar ali a regra do grupo.

### Estado em 07/10/2026: conferência do corpus v2 pela Denise

A planilha que voltou (`Claude outputs/conferencia_corpus_Denise.xlsx`) é a
**v2 inteira** (102 linhas, C001–C102), feita a partir da original, e não a
v3. A v3 (38 linhas) continua sem conferência. Processada sem chamada de
modelo: `Claude outputs/conferencia_corpus_v2/processar_Denise.R`
(`traducao_Denise.csv`, `erros_conferencia_Denise.csv`,
`gabarito_Denise.rds`). Ela não conseguiu escrever nas colunas certas: as
frases foram para a célula à direita e as observações foram acrescentadas à
`frase_do_modelo`. C084 e C102 vieram com `valor_correto` vazio e a nota
"é do adulto": contadas como `não informado`; C058 e C075 ("oval") como
`rounded`.

- **Concorda com a Eduarda em 50 das 52 linhas** que as duas conferiram. As
  2 diferenças: C059 (*L. caatingae*, caractere de grupo; a Denise aceita) e
  C101 (*Crossodactylus trachystomus*): a Denise achou o focinho na descrição
  do girino ("Corpo, visto de lado (fig. 6), aproximadamente triangular, com
  focinho de contorno arredondado"), com o nome *C. bokermanni*. Fica
  `rounded`; a frase do modelo (de grupo, de adulto) estava errada.
- **Banco de hoje (`v4`), com a regra do grupo aplicada ao gabarito:**
  olhos 52 de 58, focinho 41 de 44. Com o grupo aceito, como a Denise
  propõe: olhos 51 de 58, focinho 38 de 44 (os 7 + 5 "não achou" são, na
  maior parte, o `v4` recusando o grupo).
- **Erros que sobram:**
  - Caractere de gênero na monografia de 2020 que o `v4` ainda extrai
    (C066, C071–C074: *Physalaemus albifrons*, *Pseudopaludicola
    mystacalis*, três *Rhinella*). Só são erro se a regra do grupo ficar.
  - **Girino sem nome no trecho (tipo novo, 2 pares):** *Hylodes
    dactylocinus* (C008; "Description of tadpole: … Snout truncate; eyes
    dorsolateral", trecho na seção "Introduction" do GROBID) e *C.
    trachystomus* (C101; "Girino. Um girino característico…", sem seção). O
    trecho está no banco e o sinônimo *C. bokermanni* também; a
    recuperação não liga o trecho à espécie. O `v4` recusou corretamente a
    frase do adulto, mas não achou a do girino. O par de focinho de *H.
    dactylocinus* ("Snout truncate") nem está na planilha. É o espelho do
    item 4 abaixo.
  - *Phyllomedusa iheringii* (C002): "The snout is rounded in a
    dorsolateral view"; a Denise marca `rounded`, o `v4` não dá valor.
    Decidido abaixo: vista dorsolateral conta como lateral.
  - *Aplastodiscus cochranae* (C084): adulto sem contexto, já conhecido.

**Respostas da Denise (e-mail de 07/10/2026) e decisões do Diogo (mesmo dia):**

1. **Grupo ou gênero (Dubeux et al. 2020):** a Denise acha que pode incluir.
   **Decisão do Diogo: fica a regra de 04/10/2026** (não vale para a
   espécie), por enquanto. A monografia de 2020 é um compilado de descrições
   originais, e o caso deve ser raro nas obras com descrição original.
   **Reavaliar depois de rodar o pipeline nos PDFs com descrição original.**
2. **Variação dentro da espécie = categoria combinada** (`rounded or
   sloped`, `rounded or truncated`, `sloped to truncated`), não o estado
   modal. Resposta da Denise à dúvida 2, confirmada pelo Diogo.
3. **Vista dorsolateral do focinho conta como lateral** (Diogo).

As regras 2 e 3 estão na `regra_extracao` de `snout_shape_lv`
(`inst/traits.csv`; teste em `tests/teste_tabelas.R`). Só valem para
extração nova: o banco não foi reextraído. No gabarito do piloto
(`conferencia_denise/processar.R`), R047 (*P. oreades*, "rounded to sloped")
passou a `rounded or sloped`, e R041 (*L. luctator*) e R097 (*R.
rubescens*), em que a Denise tinha dado o estado modal, passaram à
combinada. **r10 contra esse gabarito: olhos 72/73, focinho 59/63** (eram
57/62). Os erros de focinho que sobram: R047 (o modelo deu `sloped to
truncated`), R042 e R106 (já conhecidos) e R021 (não achou).

A Denise ainda vai conferir as três linhas pendentes para ela.

**Próximos passos (07/10/2026):**

1. **Girino sem nome no trecho** e **adulto sem contexto** (item 4 da lista
   de 06/10): os dois pedem levar ao modelo o título da seção ou o parágrafo
   anterior. Medir antes no corpus, de graça.
2. **Reextração do focinho com as regras novas** (variação e vista
   dorsolateral): só com pedido do Diogo; poucos pares, centavos.
3. **Conferência v3 do corpus** (38 linhas) e **vocabulário dos 46 traits
   abertos:** com o grupo. Mandar as regras novas para a próxima conferência.
4. **PDFs com descrição original:** continuam sendo o gargalo.

### Estado em 06/10/2026 (fim do dia): regra dos olhos, prompt v4, texto perdido, reextração

Pedido pelo Diogo depois da resposta da Denise (e-mail de 05/10/2026: "não
vamos considerar a direção dos olhos, só a posição"; célula vazia = não
informado).

- **Olhos: só posição.** `regra_extracao` de `eyes_positioning`: trecho só
  com a direção = não encontrado; "eye direction" saiu dos nomes
  alternativos. Teste em `tests/teste_tabelas.R`.
- **Prompt `v4`: só vale a descrição do girino**, não a do adulto
  (`SISTEMA_VALOR`; teste em `tests/teste_agentes.R`).
- **Texto que o GROBID perdeu** (`R/texto_perdido.R`, teste em
  `tests/teste_texto_perdido.R`): linhas do PDF (lidas por coluna, como nas
  fichas) que não estão em nenhum trecho viram parágrafos de texto, com a
  página; ficam de fora fonte menor, Referências e chave de identificação.
  Entra no `estruturar_obras()` e no `reestruturar_de_tei()`; nas obras já
  estruturadas, `acrescentar_texto_perdido()`. Aplicado ao corpus: 442
  trechos em 57 obras (backup `girinos_antes_texto_perdido_20261006.duckdb`).
  Medido antes, numa cópia: 20 pares ganham candidato. A chave entrava como
  candidato único de 28 pares da monografia de 2020 e foi excluída.
- **Reextração `v4`** (`Claude outputs/reextracao_v4_20261006/`: `rodar.R`,
  `pares.R`, `pontuar.R`, `antes_depois.csv`; backup
  `girinos_antes_reextracao_v4_20261006.duckdb`; histórico em
  `chamadas_valor_v3`/`extracoes_v3`). 148 pares refeitos (os com extração
  em prompt anterior ao `v4` ou com candidato novo) e 6 novos. **Custo: US$
  0,91** (Sonnet 0,89; Opus 0,02), modo multi. Resultado: 129 `bruto`, 18
  `rejeitado`, nenhum `conflito`.
  - **Santos et al. 2017 e 2018: 4 de 4** contra o gabarito da Denise
    (dorsal e rounded nas duas espécies; a de 2018 veio do texto perdido).
  - **Corpus v2 contra a Eduarda (52 linhas):** olhos 26/29, focinho 19/23
    com o gabarito como veio. Os 6 "não achou" são caractere de grupo ou de
    gênero que ela aceitou ("Dendropsophus minutus species group – … truncate
    in lateral view"; os "Characteristics" do gênero *Phyllodytes*,
    conferidos no PDF), e que a regra de 04/10/2026 recusa. Com a regra
    aplicada a essas 6 linhas: **olhos 29/29, focinho 22/23.**
  - O erro que sobra é adulto: *Aplastodiscus cochranae* (2001). O trecho do
    GROBID ("Cabeça mais larga do que longa… Focinho arredondado… arredondado
    a truncado em vista lateral") não diz que é o adulto, e a seção veio
    ilegível (", 16"); o `v4` não tem como ver. O outro caso de adulto
    (*Cycloramphus boraceiensis*, 1983) e o de grupo (*Leptodactylus
    caatingae*) saíram.
  - Antes × depois nos 154 pares: 121 iguais, 3 diferentes (*Rhinella
    diptycha* e *Bokermannohyla astartea* passaram à posição, `dorsal`;
    *Odontophrynus toledoi* de `rounded | sloped` para `rounded`), 12
    perderam o valor (grupo, gênero ou adulto), 5 ganharam.

**Próximos passos, em ordem (06/10/2026, fim do dia):**

1. **Caractere de grupo ou gênero (Diogo, talvez com a Denise):** a Eduarda
   aceitou em 6 de 52 linhas. A decisão de 04/10/2026 o recusa, e com isso a
   monografia de 2020 (63 espécies, caracteres por gênero e grupo) quase não
   dá valor. Manter, ou aceitar quando o grupo tem espécies examinadas no
   próprio estudo?
2. **"rounded to sloped"** (*P. oreades*): é `rounded or sloped`?
3. ~~**Rodada nova do piloto.**~~ **Feita (r10, US$ 1,14):** olhos 72/73
   (eram 66), focinho 57/62 (eram 59). Os 2 erros novos de focinho são
   variação dentro da espécie ("two presented a snout sloped"), que a r10
   registrou como categoria combinada (`rounded or sloped`) e a Denise como
   estado modal. **Decisão de vocabulário, junto com o item 2.** Ver
   `piloto-zero.md`.
4. **Adulto sem contexto:** levar ao modelo o título da seção ou o parágrafo
   anterior quando o trecho não cita a espécie, ou marcar seção de holótipo.
   Medir antes quantos pares do corpus vêm de descrição de adulto.
5. **Esperando o grupo:** a primeira metade da conferência v2 (C001–C050),
   a v3 e o vocabulário dos 46 traits abertos. Mandar à Eduarda e à Denise
   a regra do grupo e a da direção, para a próxima conferência já seguir.
6. **PDFs** continuam sendo o gargalo (item 1 da lista de 04/10).

### Estado em 06/10/2026: conferências da Denise e da Eduarda

Voltaram duas conferências e dois PDFs. Tudo processado sem chamada de
modelo.

**Piloto zero, conferência da Denise** (a mesma planilha da rodada 3).
Detalhes em [`piloto-zero.md`](piloto-zero.md). Concorda com a da Eduarda em
125 de 129 linhas, e as 3 diferenças de olhos são do gabarito da Eduarda (a
correção automática da regra da posição não tinha a frase). Contra o
gabarito dela, a rodada 9 acerta olhos 66 de 68 e focinho 59 de 61. Ficaram
7 linhas pendentes, que pedem decisão (abaixo).

**Corpus v2, conferência da Eduarda:** 52 das 102 linhas (C051–C102; a
primeira metade não veio). Script e saídas em
`Claude outputs/conferencia_corpus_v2/` (`processar_Eduarda.R`,
`traducao.csv`, `erros_conferencia_Eduarda.csv`). As 6 linhas "outro (ver
nota)" foram traduzidas pelas regras já decididas: 2 "oval" e 1 "round" viram
`rounded`; 3 viram `não informado`. Contra o banco de hoje: **olhos 28 de 29,
focinho 20 de 23.** Os 4 erros:

- **Descrição do adulto (2 pares, tipo de erro novo):** *Aplastodiscus
  cochranae* (2001; "Focinho arredondado em vista dorsal… arredondado a
  truncado em vista lateral" é do adulto) e *Cycloramphus boraceiensis*
  (1983; "Description of Holotype… rounded with a flared lip in profile").
  O `SISTEMA_VALOR` não diz que a frase tem de ser do girino.
- **Caractere de grupo (1):** *Leptodactylus caatingae*, "Eyes dorsal."; o
  par não foi reextraído com o prompt `v3`, que já recusa isso. **97 pares
  do corpus ainda estão com extração `v2`.**
- **Frase de outra espécie (1):** *Phyllodytes edelmoi* (monografia de 2020).

C101 (*Crossodactylus trachystomus*, 1985): ela marcou `rounded`, com a nota
de que o artigo não diz que é a vista lateral; a frase é de um grupo de três
espécies e trata de focinho curto e canto rostral, caracteres de adulto.
Contada como `não informado`; confirmar. A reextração `v3` já tinha tirado
esse valor.

**PDFs novos (Santos et al. 2017 e 2018), mandados pela Denise:**
registrados com `importar_pdfs_manuais()` nas obras que já estavam no banco
(`f63b18365bcb6f4f`, *Proceratophrys dibernardoi*; `3ba1d0271a6009f2`,
*Adelphobates galactonotus*) e estruturados (GROBID 0.9.1). Backup antes:
`girinos_antes_santos_20261006.duckdb`. Planilha da importação:
`revisao/pdfs_manuais_20261006.csv`. Os 4 pares ainda não foram extraídos.
- 2017: a recuperação acha "snout is rounded in dorsal and lateral views;
  eyes are small, dorsally positioned and dorsolaterally directed", o que bate
  com o gabarito da Denise.
- **2018: o GROBID perdeu a primeira metade do artigo** (5,8 mil de 15,7 mil
  caracteres; os trechos começam em "anterolaterally. Nares small"). A frase
  "Snout rounded in dorsal and lateral views. Eyes small…, dorsally
  positioned" não está em nenhum trecho, e extrair agora daria "não
  encontrado". Medido no corpus (`Claude outputs/grobid_cobertura_20261006/`):
  3 obras com menos de 50% do texto do PDF nos trechos, 12 com menos de 70%;
  em 5 artigos de uma espécie, alguma frase de olhos ou focinho do PDF não
  está nos trechos. A medida é grosseira (o texto do `pdftools` inclui
  referências e mistura colunas), então esses 5 ainda precisam ser
  conferidos um a um.

**Próximos passos, em ordem (06/10/2026, manhã; só o 1b segue aberto, ver acima):**

1. **Decisões (Diogo; grátis):**
   (a) **Olhos: direção não é posição?** A Denise diz que não se pode usar
   a direção como posição. Hoje a `regra_extracao` usa a direção quando o
   artigo não dá a posição (Conte et al. 2007, por exemplo, só dá a
   direção). As alternativas são manter, deixar `não informado` ou criar um
   trait `eyes_direction`.
   (b) **"rounded to sloped"** (*P. oreades*): é `rounded or sloped`?
   (c) **Perguntar à Denise** por que deixou vazias R104–R107 (Conte et al.
   2007). Hipótese: dado compilado de outros trabalhos, que não é fonte
   primária. Se for isso, a tabela de Conte et al. (2007) só vale para *S.
   catharinae*. Confirmar também R075, R042 e C101.
2. **Adulto não vale:** acrescentar ao `SISTEMA_VALOR` que a frase tem de
   descrever o girino (prompt `v4`), com teste em `tests/teste_agentes.R`.
3. **Cobertura do GROBID:** conferir as obras que perderam texto e, onde
   faltar, completar os trechos com o texto das páginas do PDF. Sem isso, o
   artigo de 2018 não tem o que extrair.
4. **Extrair (pede crédito):** os 4 pares de Santos et al. 2017/2018,
   depois do passo 3, pontuados contra `gabarito_santos_2017_2018.csv`; e os
   97 pares do corpus ainda em `v2` (com o `v4`, se o passo 2 entrar). Custo
   de centavos a ~US$ 1. Usar `multi = TRUE`.
5. **Esperando o grupo:** a primeira metade da conferência v2 do corpus
   (C001–C050), a v3 e a planilha de vocabulário dos 46 traits abertos.
6. **PDFs** continuam sendo o gargalo (abaixo, item 1 da lista de 04/10).

### Estado em 04/10/2026: piloto zero, rodada 5

A conferência humana da rodada 3 voltou (Eduarda, 136 linhas) e pontuou as
rodadas 4 e 5 sem nova conferência. Detalhes em
[`piloto-zero.md`](piloto-zero.md). Resumo:

- **"Não achou" e "frase de outra espécie" eram o GROBID** desmontando as
  monografias (colunas misturadas, cabeçalho perdido, legenda ao lado da
  ficha errada). Agora as fichas de espécie são lidas direto do PDF
  (`R/fichas.R`) e, quando a espécie tem ficha, só ela vai ao modelo.
- **Rodada 5 (US$ 1,63):** focinho com 60 certos em 63 (eram 21 na rodada
  3); olhos com 35 certos, e os 36 erros são todos a regra posição × direção
  (abaixo). Gasto do piloto até aqui: US$ 9,90 em cinco rodadas.

**Feito em 04/10/2026 (tarde):**

- **Regra dos olhos decidida (Diogo): vale a posição.** Gabarito do piloto
  corrigido com registro (35 trocas); olhos em 71 de 73 e focinho em 60 de
  63 nas rodadas 6 e 7. Ver `piloto-zero.md`.
- **Variação entre rodadas medida:** rodadas 6 e 7 idênticas nos 276 pares.
- **Custo gravado:** `extrair_tudo()` grava cada execução em
  `custo_extracao` (por modelo, pares, se parou), inclusive quando para no
  limite ou por erro. Teste em `tests/teste_limite_gasto.R`.
- **Fichas no corpus, conferência grátis:** título de tabela virava
  cabeçalho ("Physalaemus cicada (n=8, estágio 37)") e referências em
  português não fechavam a segmentação; corrigidos com teste. Cabeçalho com
  letras espaçadas só em 1 obra; 10 obras só têm páginas de uma coluna
  (seguem pelo GROBID).
- **Achado: o banco principal estava sem sinônimos** (2, do teste de
  fumaça; o piloto tinha 347). O `_targets.R` só os carrega de um cache da
  ASW que não existe. Carregados os do AmphiNom e os curados
  (`sinonimos_amphinom()` + `inst/sinonimos.csv`, como no piloto): 1.581.
  Backup antes: `girinos_antes_sinonimos_20261004.duckdb`. 304 ambíguos para
  revisão em `revisao/sinonimos_revisar_corpus.csv` (homônimos, binômios que
  são espécie válida, sinônimos de mais de uma espécie). No corpus, pares
  sem candidato de 111 para 75 e pares com ficha de 37 para 57.

**Custo e modelo (decidido pelo Diogo, 04/10/2026, noite):** modelos
chineses (DeepSeek, Qwen) **não** entram: a economia é pequena em valor
absoluto (os 2 traits na BT 5 inteira custam ~US$ 25–30 com o Sonnet) e há
risco com o texto dos artigos (a DeepSeek guarda os dados na China e treina
com eles, salvo pedido de exclusão). Medido no piloto: Haiku 4.5 erra 3 pares
a mais em 136 e custa ~60% do Sonnet; a API de lotes (`extrair_tudo_lote()`)
dá os mesmos valores e economiza só ~15%, porque o modo normal já usa cache de
prompt. Ver `piloto-zero.md`.

**Próximos passos, em ordem (04/10/2026, fim do dia):**

1. **PDFs: o gargalo de verdade.** Das 690 obras da BT 5, só 58 têm PDF
   (133 das 676 espécies; 1.666 dos 1.827 vínculos obra-espécie sem PDF).
   `revisao/sem_pdf.csv` traz o link de acesso aberto ou de repositório
   quando há (159 com acesso aberto, 29 com URL da BT). Aquisição manual
   (`importar_pdfs_manuais()`) com o grupo; depois `estruturar_obras()` (com
   fichas) e `extrair_tudo()`. Custo da extração dos 2 traits nas 690 obras:
   ~US$ 25–30.
2. ~~**Conferência v3 do corpus.**~~ **Gerada (04/10/2026):**
   `Claude outputs/conferencia_corpus_v3/` (38 linhas em 14 artigos), só
   com os 56 pares chamados na segunda reextração
   (`gerar_conferencia_corpus(..., pares = )`). Mandar ao grupo quando a v2
   voltar.
3. **Revisar os sinônimos ambíguos (Diogo).** Planilha pronta:
   `Claude outputs/sinonimos/sinonimos_para_revisar.xlsx`
   (`planilha_revisao_sinonimos()`, `R/revisao_sinonimos.R`). Para cada um
   dos 304 nomes: em quantas obras do corpus aparece, quantas são obras
   ligadas à própria espécie, um trecho de exemplo e as outras espécies com
   o mesmo nome. **Só 11 aparecem no corpus atual, 4 em obra da própria
   espécie**; o resto pode esperar até aparecer em PDF novo. Colunas
   amarelas: `decisao` (global / so_nesta_obra / nao_entra), `doi_obra`,
   `nota`. Na volta, `aplicar_revisao_sinonimos("<planilha>.xlsx", "Diogo B.
   Provete")` acrescenta as decisões a `inst/sinonimos.csv` sem duplicar
   (teste em `tests/teste_revisao_sinonimos.R`); depois,
   `carregar_sinonimos()` leva ao banco.
4. ~~**Sinônimos no `_targets.R`.**~~ **Feito (04/10/2026):** o target usa
   `carregar_sinonimos()` (AmphiNom + curados, como no piloto), que grava só
   os sinônimos que ainda não estão no banco e escreve os ambíguos em
   `revisao/sinonimos_revisar.csv`. Teste em `tests/teste_sinonimos.R`. O
   `cache_asw` do `config.yml` e `sincronizar_sinonimos()` ficaram sem uso.
5. ~~**Confirmar "gênero".**~~ **Decidido (Diogo, 04/10/2026):** caractere
   descrito para um gênero também não vale para as espécies, como o de
   grupo de espécies. É o que o prompt `v3` já diz.
6. ~~**Vários traits por chamada.**~~ **Feito e medido (04/10/2026):**
   `extrair_tudo(..., multi = TRUE)`. Rodada 9 do piloto: os mesmos 270
   valores da rodada 6, mesma nota (71/73, 60/63), 186 pedidos em vez de 322,
   28% menos tokens de entrada. **Usar `multi = TRUE` daqui em diante**; o
   ganho cresce com o número de traits fechados. Ver `piloto-zero.md`.
7. **Esperando o grupo:** conferência do corpus v2 (enviada em 04/10/2026)
   e planilha de vocabulário dos 46 traits abertos (03/10/2026).

<details><summary>Lista anterior (04/10/2026, tarde)</summary>

**Próximos passos, em ordem:**

1. ~~**Rodar a segunda reextração do corpus.**~~ **Feito (04/10/2026,
   pedido pelo Diogo)**: `Claude outputs/reextracao_oval_20261004/`. Backup:
   `girinos_antes_reextracao2_20261004.duckdb`. 21 pares refeitos (histórico
   em `chamadas_valor_v2`/`extracoes_v2`), 116 chamadas novas. **Primeiro
   custo gravado em `custo_extracao`: US$ 0,51** (Sonnet 0,43; Opus 0,08).
   Resultado: 135 `bruto`, 2 `conflito`, 14 `rejeitado` (antes 100, 4, 10);
   espécies com valor de 59 para 73. Os 3 pares "oval" saíram `rounded`.
   Falta: gerar a conferência v3 do corpus só com o que mudou.
2. **Revisar os 304 sinônimos ambíguos** (Diogo):
   `revisao/sinonimos_revisar_corpus.csv`. Os que valerem entram em
   `inst/sinonimos.csv` (com `doi_obra` quando valem só numa obra).
3. **Sinônimos no `_targets.R`:** trocar o cache da ASW por
   `sinonimos_amphinom()` + curados, como no piloto, para o banco não ficar
   de novo sem sinônimos.
4. **Caractere de gênero:** a regra do prompt `v3` diz "grupo de espécies
   (species group, gênero)"; o "gênero" foi extensão minha da decisão do
   Diogo. Confirmar.
5. **Esperando o grupo:** conferência do corpus v2 (enviada em 04/10/2026)
   e planilha de vocabulário dos 46 traits abertos (03/10/2026).

</details>

<details><summary>Lista anterior (04/10/2026, depois da reextração)</summary>

1. **Regra dos olhos (Diogo e Denise; e-mail enviado em 04/10/2026).** O
   `inst/traits.csv` manda registrar a posição quando o artigo dá posição e
   direção; a conferência da Eduarda registrou a direção. Todos os 36 erros
   de olhos da rodada 5 do piloto são isso. Mantida a regra, os olhos ficam
   em 71 de 73; mudando, troca-se a `regra_extracao` e reextrai-se. Repontuar
   é grátis: `Claude outputs/piloto-zero/r5/pontuar.R`.
2. **Reextrair os pares de focinho "oval"** (~7 pares, decisão de
   04/10/2026). Pede apagar as chamadas desses pares em `chamadas_valor`
   (senão `extrair_tudo()` os pula), então o Diogo roda; custo de centavos.
   Se a regra dos olhos mudar, vale juntar as duas reextrações.
3. **Mandar a conferência do corpus v2 ao grupo**
   (`Claude outputs/conferencia_corpus_v2/`, 102 linhas). A de 03/10/2026
   avaliou o código antigo e pode ser descartada.
4. **Conferir de graça:** a ficha em português de *Physalaemus cicada* não
   trouxe "focinho arredondado dorsalmente e lateralmente"; e as limitações
   das fichas (cabeçalho com letras espaçadas, layout de uma ou três
   colunas) no resto do corpus.
5. **Registrar o custo em `extrair_tudo()`** (hoje só o `rodar_rodada()` do
   piloto grava em `custo_obra`); o gasto da reextração de 04/10/2026 ficou
   sem registro.
6. **Variação entre rodadas:** rodar a rodada 5 do piloto de novo e medir a
   concordância (Sonnet e Opus não aceitam temperatura).
7. **Esperando o grupo:** planilha de vocabulário dos 46 traits abertos
   (enviada em 03/10/2026, sem resposta).

</details>

<details><summary>Lista anterior (04/10/2026, antes da reextração)</summary>

1. **Regra dos olhos (Diogo e Denise).** O `inst/traits.csv` manda
   registrar a posição quando o artigo dá posição e direção; a conferência
   registrou a direção. Todos os 36 erros de olhos da rodada 5 são isso.
   Mantida a regra, a Eduarda remarca essas linhas (ou o Diogo autoriza
   trocar `valor_correto` delas pela posição) e os olhos ficam em 71 de 73;
   mudando, troca-se a `regra_extracao` e roda-se de novo (~US$ 1,60). A
   correção do e-mail para a Eduarda e a Denise está como rascunho no
   Gmail. Repontuar é grátis: `Claude outputs/piloto-zero/r5/pontuar.R`.
2. ~~**Fichas no corpus da BT 5, de graça primeiro.**~~ **Feito
   (04/10/2026)** numa cópia do banco. O corpus expôs três defeitos que o
   piloto não mostrou, corrigidos com teste (`tests/teste_fichas.R`): corte
   de coluna no meio da página (num PDF a coluna da esquerda passa do meio, e
   a frase saía "laterally rected"; agora o corte é onde a coluna da direita
   começa, `corte_coluna()`); entrada de chave de identificação virando
   ficha; e, em artigo de uma espécie só, "ficha" do título ao fim (14 a 30
   mil caracteres). Ficha só substitui o GROBID com 400 a 10 mil caracteres
   e sem pontilhado de chave (`ficha_util()`). Resultado: 24 das 58 obras têm
   fichas, **37 dos 322 pares** passam a usá-las (todas fichas reais, texto
   conferido), chamadas previstas de 478 para 433. No piloto, sem mudança:
   122 de 131 com a frase certa, nenhum trecho de outra espécie.
3. ~~**Reextrair o corpus da BT 5.**~~ **Feito (04/10/2026)**, rodado pelo
   Diogo (`Claude outputs/reextracao_20261004/rodar.R`). Backup:
   `girinos_antes_fichas_20261004.duckdb`. 176 fichas em 24 obras; as
   extrações e chamadas antigas estão em `extracoes_v1` (158) e
   `chamadas_valor_v1` (496). 433 chamadas em 211 pares; o custo não foi
   registrado (o `extrair_tudo()` não grava gasto). Resultado: 100 `bruto`,
   4 `conflito`, 10 `rejeitado` (antes 112, 14, 32); 30 dos 104 registros
   vieram de ficha. Por par, contra a versão antiga: 85 iguais, 7 diferentes,
   10 só na nova, 26 só na antiga. Nova conferência (102 linhas, por artigo e
   espécie): `Claude outputs/conferencia_corpus_v2/`.

   **As 26 perdas pediram duas decisões científicas. Decididas pelo Diogo
   (04/10/2026):**
   (a) **Caractere de grupo de espécies não vale para a espécie.** Em
   *Morphological characterization and taxonomic key of tadpoles…* os
   caracteres vêm por grupo ("Characteristics: *Leptodactylus fuscus*
   species group — … Eyes dorsal."); a versão antiga atribuía o caractere a
   cada espécie do grupo. As ~11 perdas de olhos estão certas. A regra ficou
   explícita no `SISTEMA_VALOR` (`prompt_versao` `v3`), teste em
   `tests/teste_agentes.R`.
   (b) **"Snout oval in lateral view" conta como `rounded`.** Na
   `regra_extracao` de `snout_shape_lv` (`inst/traits.csv`), teste em
   `tests/teste_tabelas.R`. Os ~7 pares perdidos precisam ser extraídos de
   novo (próximo passo 2).
   As outras perdas: 2 de *Physalaemus cicada* (a ficha em português não
   trouxe a frase "focinho arredondado dorsalmente e lateralmente", a
   conferir) e frases de comparação ou de outro trabalho, que o `v2` recusa
   de propósito.
4. **Variação entre rodadas:** com a recuperação estável, rodar a rodada 5
   de novo e medir a concordância (Sonnet e Opus não aceitam temperatura).
5. **Esperando o grupo:** planilha de vocabulário dos 46 traits abertos
   (enviada em 03/10/2026, sem resposta) e a conferência do corpus.

</details>

### Estado em 01/10/2026

**O pipeline rodou de ponta a ponta para uma espécie.** *Physalaemus barrioi*
(táxon de teste `TESTEBUSCA001`): busca → triagem → aquisição (2 PDFs
automáticos, 6 manuais) → GROBID → extração → validação. Três registros, todos
com span literal, todos do Sonnet 5.5:

| obra | trait | valor | span |
|---|---|---|---|
| *Redescription of P. barrioi* (2012) | `eyes_positioning` | dorsal | "Eyes small, dorsal, dorsolaterally directed." |
| *Redescription of P. barrioi* (2012) | `snout_shape_lv` | rounded | "Snout rounded in dorsal and lateral views." |
| pôster no F1000Research (2011) | `snout_shape_lv` | rounded | "Focinho arredondado, aparato oral anteroventral." |

Contexto da redescrição: Gosner 29-40, n = 23, campo. **Custo medido: US$ 0,083
para 8 obras × 2 traits, 70 s** (preços de 30/09/2026). As obras sobre outras
espécies que comparam com *P. barrioi* (*P. erikae*, *P. evangelistai*) não
renderam nada; se isso é falso negativo, só o Diogo pode dizer.

**Decisões em aberto, por ordem de urgência:**

1. ~~**Pôster × artigo como fonte primária.**~~ **Decidido (Diogo,
   01/10/2026): pôster e resumo de congresso nunca são fonte primária.**
   Implementado em `decidir_fonte_primaria()` / `marcar_fonte_secundaria()`,
   teste em `tests/teste_fonte_primaria.R`. O tipo fica em
   `obras.tipo_documento` (`poster` | `resumo_congresso`), marcado à mão com
   `marcar_tipo_documento()`: a OpenAlex classifica o pôster do F1000Research
   como `type: "article"` de periódico, então a busca não separa.
   Desdobramentos, decididos pelo Diogo em 01/10/2026:
   (a) valor que só aparece em pôster fica `secundaria` sem
   `fonte_primaria_doi`, e o `dwc.R` usa o DOI do próprio pôster
   (`coalesce(fonte_primaria_doi, doi)`). **Fica assim:** se a informação veio
   do pôster, o DOI dele é a fonte. Caso raro, ainda mais com publicação
   duplicada; não vale tratamento especial.
   (b) **Detecção automática pela URL**, com a marca manual como complemento.
   Feito: a busca guarda `obras.url_pagina` (OpenAlex
   `primary_location.landing_page_url`, Crossref `resource.primary.URL`) e
   `marcar_tipo_por_url()` aplica `PADROES_URL_TIPO` (`R/busca.R`). Por ora só
   `f1000research.com/posters/`; padrão novo entra quando houver caso
   conferido na página da editora. A marca manual nunca é sobrescrita. Teste
   em `tests/teste_tipo_documento.R`. No banco, `preencher_url_pagina()`
   preencheu as 18 obras com DOI (01/10/2026) e marcou o pôster de
   *P. barrioi*; as 5 sem DOI ficam sem URL (o id da OpenAlex não é
   guardado). `/slides/` e `/documents/` do F1000 entram como
   `resumo_congresso` (Diogo, 01/10/2026).
2. ~~**Caractere sem vista indicada.**~~ **Decidido (Diogo, 02/10/2026):
   formato do focinho sem vista indicada conta como vista lateral**, porque
   na literatura de girinos ele costuma ser descrito só em vista lateral. O
   caso era o pôster ("focinho arredondado" → `snout_shape_lv`). Implementado
   como `regra_extracao` de `snout_shape_lv` em `inst/traits.csv`: com as duas
   vistas, usa a lateral; só a dorsal, não encontrado. Teste em
   `tests/teste_tabelas.R`. Vale só para o focinho; outro caractere com vista
   (ex.: `snout_shape_dv`) pede decisão própria.
3. **Escalonamento em todo "não encontrado".** `com_escalonamento()` escala
   para o Opus sempre que o span volta vazio, e isso inclui toda resposta
   negativa. Nesta rodada o Opus foi 1/3 do custo e não rendeu nenhum
   registro. Proposta: escalar só quando o valor veio sem span. n = 1
   espécie — medir no piloto zero antes de mudar.
4. **Métodos não identificados em 5 de 8 obras** (*B. ahenea*, *stone frog*,
   *Pseudopaludicola*, a tese de 2009, o pôster). Valores dessas obras saem
   sem estágio: o agente de contexto (`R/agentes.R`) só lê trechos cuja seção
   case `method|metodo|material`, e ali não acha nenhum. Investigado em
   01/10/2026, lendo os TEI; **não é falha do GROBID**:
   - *B. ahenea*, *stone frog* e a tese: o GROBID achou `MATERIALS AND
     METHODS`, mas devolve a hierarquia achatada: a seção vem com 0
     parágrafos e as subseções (`Study area`, `Sampling`…) como irmãs.
     `tei_para_trechos()` marca o parágrafo só com o título imediato, então
     nenhum trecho fica com "Methods". **Corrigido:** a subseção herda o
     título principal (`secoes_com_principal()` em `R/parse.R`); o título
     principal muda quando a div vem sem parágrafo ou quando é seção principal
     conhecida (senão RESULTS, que tem parágrafos na tese, herdaria METHODS).
     Relido dos TEI: a tese passa de 0 para 22 trechos de Métodos, *B. ahenea*
     para 8, *stone frog* para 6.
   - *Pseudopaludicola*: **nota curta, sem cabeçalho de Métodos no PDF**
     (conferido no texto). Os métodos ("Two Stage 36 and two Stage 39
     tadpoles…") estão num bloco sem título junto com a Introdução.
   - Pôster: não tem Métodos (`Anatomia oral interna`, `Canto de anúncio`,
     `Morfologia externa`).

   **Notas vão ser comuns** (Diogo). **Corrigido:** obra sem trecho de
   Métodos passa ao agente de contexto os trechos de texto que citam Gosner
   ou Stage (Diogo), e também "estágio", porque o pôster está em português
   ("estágios 35 a 37") (`trechos_de_contexto()` em `R/agentes.R`). Nos TEI:
   *Pseudopaludicola* rende 6 trechos, o pôster 2. Teste em
   `tests/teste_contexto.R`. Os trechos já gravados no banco seguem com o
   parse antigo até serem reestruturados (ver `piloto-zero.md`).
5. **Variação entre rodadas da extração.** Sonnet e Opus 5.5 não aceitam
   temperatura; no piloto zero, rodar a extração duas vezes e medir a
   concordância.
6. Vocabulário: 4 pendências em `cloacal_opening`/`lower_jaw_shape` (o Diogo
   resolve); 33 vocabulários categóricos ainda abertos (o grupo).

**Próximo passo técnico:** piloto zero — plano em
[`piloto-zero.md`](piloto-zero.md): os artigos da planilha × os 2 traits
fechados, 2 rodadas, adjudicação pelo Diogo, teto de US$ 5. Código e
preparação prontos (01/10/2026). Sinonímia do AmphiNom + curados: 138 de 138 espécies
achadas no texto. Recuperação corrigida para monografia (Pezzuti: 68 → 8
pares sem candidato). Pendente: o custo estimado de duas rodadas
(~US$ 4,6–6,8) passa do teto de US$ 4.

### DOI e acesso aberto das referências da BT 5 (02/10/2026)

Feito enquanto a conferência do piloto zero está com a Denise. Código em
`R/referencias_doi.R`, teste em `tests/teste_referencias_doi.R`; saída em
`Claude outputs/refs_doi/` (fora do git). Nada foi gravado no banco nem no
`species.json`.

**Método.** As 775 strings de referência do `species.json` são 680 obras
distintas (título normalizado + ano). Cada obra sem DOI foi procurada no
Crossref (citação inteira, `query.bibliographic`) e, na amostra, também na
OpenAlex (título). O melhor candidato é **aceito** só com título ≥ 0,90,
mesmo ano e sobrenome do primeiro autor conferido; título ≥ 0,75, ano ±1 ou
autor que não confere vão para **revisar**. Unpaywall para todos os DOIs.

**Precisão medida nas 68 obras que já tinham DOI** (controle, procuradas como
se não tivessem): 60 aceitas, **60 de 60 com o DOI certo** (uma delas é o
DOI da BT 5 que é alias: `10.1655/herpetologica-d-17-00055.1` redireciona
para `10.1655/0018-0831.323`); as 8 em "revisar" também estavam certas
(ano ±1 de publicação online antecipada, grafia do autor). O critério é
conservador.

**Resultado** (Crossref em todas; depois OpenAlex, com chave, nas que não
casaram ou ficaram para revisar; depois BHL nas que ainda sobraram):

| | obras |
|---|---|
| com DOI na BT 5 | 68 de 680 (10%) |
| aceitas pelo Crossref | 311 |
| aceitas pela OpenAlex | 51 (17 com DOI, 12 deles do Zenodo/BLR; as demais só com id da OpenAlex) |
| aceitas pelo BHL | 5 (artigos segmentados no BHL: só URL, sem DOI) |
| **identificadas** | **435 (64%)**; 390 com DOI (57%), todos conferidos no doi.org |
| **com link aberto** | **226 (33%)** (Unpaywall, OpenAlex ou BHL) |
| para revisar | 56 + 8 volumes prováveis do BHL (`revisar_doi.csv`) |
| erro de API | 2 (HTTP 400 da OpenAlex) |
| sem casamento | 179 |

O BHL rendeu pouco (5 aceitas, 3 a revisar, 8 volumes prováveis em 197).
Parte dos resultados do BHL é o volume inteiro ("Item"), não o artigo: esses
nunca são aceitos sozinhos, só marcados como `volume_provavel` quando
periódico e ano batem, para alguém achar a página.

**O "revisar" precisa mesmo de gente.** Tem casamento errado ali: espécie
trocada (*P. lisei* × *P. nanus*, *Pseudis* × *Lysapsus*), gênero trocado,
e a rodada completa mostrou dois defeitos que a amostra não mostrou,
corrigidos e testados: DOI de *figura* (Zootaxa/ZooKeys, "Figure 4. …")
casando com o artigo, e título de série ("Contribution à l'étude des
Amphibiens de Guyane française", partes III e IX) aceito como se fosse a
obra. Título contido em outro agora só leva a "revisar".

**Sem casamento só com o Crossref (251):** 181 são de antes de 2000. Os periódicos que mais
aparecem são *Revista Brasileira de Biologia* (37), *Herpetologica* antiga
(13, JSTOR sem DOI no Crossref), *Arquivos do Museu Nacional* (8),
*Arquivos da UFRRJ* (7), *Alytes*, *Cuadernos de Herpetología*,
*Salamandra*, além de resumos de congresso, teses e capítulos. Duas
referências estão mal estruturadas na própria BT 5 (título "albofrenata",
título "151 f").

**Próximos passos:**

1. ~~**Diogo:** conferir `revisar_doi.csv`.~~ **Feito (02/10/2026)** sobre a
   versão de 50 linhas (só candidatos do Crossref; o Excel sobrescreveu a de
   64). Conferindo as decisões contra o Crossref, 5 não batiam e ficaram
   fora do PR: *P. lisei* → DOI de *P. nanus*; grupo *fuscus* → *marmoratus*;
   *Pseudis* → *Lysapsus*; *Cusco Amazónico* → resenha na Choice; *Frogs of
   Boracéia* → resenha na Copeia. O DOI que a *Arquivos de Zoologia* exibe
   para *Frogs of Boracéia* (`10.11606/issn.2176-7793.v31i4p231-410`) não
   está registrado: 404 no doi.org e "handle not found" na API de handles,
   com qualquer grafia. A linha de *Hamptophryne* (1991) foi apagada na
   planilha; ficou fora. **Lição:** a OpenAlex pode trazer DOI que não
   existe; todo DOI agora passa pela API de handles do doi.org antes de
   sair daqui (os 419 do PR e da BT passaram).
2. **Chaves (02/10/2026).** OpenAlex e BHL em `~/.Renviron`
   (`OPENALEX_API_KEY`, `BHL_API_KEY`), lidas por `Sys.getenv()`. A OpenAlex
   passou a ter orçamento diário: sem chave, US$ 0,10/dia e 10 créditos por
   busca (~100 buscas); com a chave gratuita, US$ 1/dia (conferido no
   cabeçalho da resposta). A primeira rodada esgotou a cota sem chave e
   levou `Retry-After` de 12.111 s; o `req_api()` agora desiste em 1 min e
   marca "erro". O `bhl_key` do `config.yml` continua vazio de propósito:
   ligar o BHL na busca principal traria volumes inteiros como "obras" para
   a triagem, e isso pede desenho próprio.
3. ~~**`per-page` 200 em `buscar_openalex()`.**~~ A documentação diz que o
   máximo é 100, mas a API aceitou 200 com a chave (conferido em
   02/10/2026, `meta.per_page = 200`). Fica como está; se começar a dar 400,
   é aqui.
4. **As 179 sem casamento** são, na maior parte, *Revista Brasileira de
   Biologia*, *Arquivos do Museu Nacional*, *Arquivos da UFRRJ*, teses,
   capítulos e resumos de congresso: vão entrar à mão ou ficar sem PDF.
5. **BT 5: PR aberto** ([diogoprov/Brazilian-Tadpoles-5.0#29](https://github.com/diogoprov/Brazilian-Tadpoles-5.0/pull/29),
   02/10/2026): DOI para 345 obras (379 strings `raw`, 744 entradas do
   `species.json`), só onde o campo era `null`. Ficaram fora: 12 DOIs do
   Zenodo/BLR (**decisão do Diogo:** o campo `doi` aceita DOI de
   repositório?), as 5 decisões que não batem, 14 candidatos da
   OpenAlex/BHL e 8 volumes prováveis ainda não revisados. O PR também
   aponta, sem corrigir, duas referências mal estruturadas pelo
   `parse_refs.py` (títulos "albofrenata" e "151 f"), a mesma obra em duas
   grafias ("coombianos"/"colombianos") e um DOI alias. Semear o corpus aqui
   depois do merge: `obra_id` é o hash do DOI ou, sem DOI, do título
   (`semear_corpus()`), e obra semeada sem DOI e achada depois pela busca
   com DOI viraria duas obras.
   **#29 com merge feito (02/10/2026).**
6. **Correções de estrutura na BT 5**:
   [#30](https://github.com/diogoprov/Brazilian-Tadpoles-5.0/pull/30), com
   merge feito (03/10/2026): 29 entradas com título mal extraído, barra
   solta, duas referências coladas, "coombianos" e DOI alias.
7. **Segunda rodada**:
   [#31](https://github.com/diogoprov/Brazilian-Tadpoles-5.0/pull/31),
   aberto em 03/10/2026, a partir de `revisar_doi_2.xlsx`. **Decisões do
   Diogo (03/10/2026):**
   - DOI do Zenodo/BLR **vale** para o campo `doi`, porque todos trazem o
     PDF do artigo (12 obras);
   - o DOI da *Biota Neotropica* era o resumo da dissertação do Prado
     (2006) e sai das 17 entradas; a dissertação completa está no
     repositório da UNESP;
   - URLs de texto completo (BHL, handles, repositórios) entram num campo
     `url` opcional, criado no #31: `ref_schema`, link "texto completo" no
     site e campo no BibTeX, em commit separado.

   Os IDs do BHL foram conferidos pela API, porque o site do BHL recusa
   checagem por HTTP mesmo com agente de navegador. Ficam pendentes:
   *Frogs of Boracéia* (DOI não registrado; o PDF aberto pode entrar como
   `url`) e o formulário de `issue_to_pr.py`, que ainda não pede URL.

### Corpus semeado da BT 5 (03/10/2026)

Depois dos merges dos PRs #29, #30 e #31 na BT 5. Backup do banco antes:
`girinos_antes_semente_20261003.duckdb` (fora do git).

**Defeitos medidos antes de semear** (simulação numa cópia do banco),
corrigidos e testados em `tests/teste_semear_corpus.R`, que falha com o
código antigo:

- `semear_corpus()` e `executar_busca()` gravavam obras com `INSERT OR
  REPLACE` e `status = "encontrada"`: **4 obras com PDF** (inclusive a
  redescrição de *P. barrioi*) voltariam a "encontrada" sem `caminho_pdf`,
  e a triagem delas seria trocada. Agora `registrar_obras()` (`R/db.R`) só
  insere obra nova e, na que já existe, só preenche o que está vazio;
  triagem e `obra_taxon` usam `registrar_novos()` (`INSERT OR IGNORE`).
- DOI com maiúscula na BT ("10.2994/SAJH-D-13-00033.1") virava outra obra:
  o DOI agora entra em minúsculas, na semente e na busca. Nenhum DOI do
  banco tinha maiúscula, então nenhum `obra_id` existente mudou.
- A mesma obra com DOI numa string e sem DOI noutra, ou com títulos que só
  diferem num espaço, virava duas obras. `agrupar_obras_bt5()` junta as
  variações por título normalizado + ano, e todas herdam o DOI.
- O campo `url` da BT vai para `obras.url_pagina`.

**Resultado:** 671 obras distintas da BT; 666 novas (de 24 para 690 no
banco), 412 delas com DOI e 29 com URL de texto completo; 1.827 vínculos
obra-espécie; 677 espécies da lista-alvo com pelo menos uma obra. Nenhuma
obra antiga com status ou PDF alterado, nenhuma triagem trocada, nenhum
título + ano repetido.

**Aquisição de PDFs (03/10/2026).** `adquirir_pdfs()` nas 666 obras
semeadas, em 4 min: 49 PDFs novos (47 `pdf_ok`, 2 `precisa_ocr`), todos
conferidos como PDF de verdade; 617 `sem_pdf` (363 com DOI). Backup antes:
`girinos_antes_aquisicao_20261003.duckdb`. Dois defeitos corrigidos antes de
rodar, com teste em `tests/teste_aquisicao.R`:

- erro na chamada ao Unpaywall virava NA, e a obra ia para `sem_pdf` como se
  não houvesse cópia aberta (princípio 1). Agora fica `erro` e é retentada
  na próxima rodada. O 404 do Unpaywall (DOI que ele não conhece, como os do
  Zenodo) continua `sem_pdf`;
- sem `ocrmypdf` instalado, o PDF escaneado saía `pdf_ok`. Agora fica
  `precisa_ocr`.

Na amostra de 20, as obras com DOI sem PDF eram de três tipos: fechadas;
abertas sem link direto para o PDF (o Unpaywall só tem a página: PeerJ,
Caldasia); ou abertas com download bloqueado pela editora (Wiley 403,
Biotaxa devolvendo HTML). O link vai para a lista de `exportar_sem_pdf()`.
**Não feito (lateral):** achar o PDF a partir da página do artigo; baixar
pelas 29 URLs do BHL.

**Lista-alvo e `estado_par` carregados (03/10/2026).** Achado: a
lista-alvo nunca tinha sido carregada no banco (`alvo` e `estado_par` só
tinham os táxons de teste). Decisões do Diogo: só os 2 traits de
vocabulário fechado (`eyes_positioning`, `snout_shape_lv`); só as 676
espécies com girino descrito (`apenas_descritos: true` no `config.yml`);
táxons de teste fora dos pares. Resultado: 676 espécies na `alvo`, 1.352
pares `nao_buscado`. Quando o grupo fechar outro vocabulário, basta rodar
`semear_estado_par()` de novo com os traits fechados, porque ela só
acrescenta pares novos. Backup antes: `girinos_antes_estado_par_20261003.duckdb`.

**OCR (03/10/2026):** os 2 PDFs `precisa_ocr` (*Odontophrynus salvatori*;
*Cycloramphus*, Heyer 1983) passaram no `ocrmypdf` depois de instalar
`ocrmypdf` e `tesseract-lang` (o Tesseract só tinha `eng`, e
`rodar_ocr()` pede `por+spa+eng`): de 0 para 14.518 e 218.675 caracteres;
status `pdf_ocr`. Como já tinham `caminho_pdf`, a aquisição não os
reprocessaria: o OCR foi rodado direto neles.

### Estruturação e primeira extração no corpus da BT 5 (03/10/2026)

**GROBID:** 49 obras novas estruturadas em 1,6 min (3.224 trechos, 231
deles de tabela; nenhuma obra sem trecho). As 5 obras com parse antigo
foram refeitas do TEI (`reestruturar_de_tei()`).

**Obras sem PDF:** `revisao/sem_pdf.csv`, com 617 obras (363 com DOI, 159
com link de acesso aberto). Desde 03/10/2026 leva também
`link_texto_completo`, o campo `url` da BT (BHL, repositórios): 29 obras,
21 delas no BHL. Só das obras da BT, porque nas da busca a `url_pagina` é
a página da editora.

**Extração dos 2 traits fechados:** 322 pares (obra × espécie × trait), em 54
obras e 133 espécies. Antes de rodar, `extrair_tudo()` ganhou `limite_usd`,
conferido a cada par (antes só o `rodar_rodada()` do piloto tinha limite),
com teste em `tests/teste_limite_gasto.R`. Rodada com limite de US$ 5.

- **Parou por HTTP 400 depois de US$ 2,01**, na monografia *Morphological
  characterization and taxonomic key of tadpoles* (63 espécies). Causa,
  achada ao reproduzir a chamada: **o saldo de crédito da conta da Anthropic
  acabou** ("Your credit balance is too low…"). Não é defeito do pipeline;
  parar foi o comportamento certo (princípio 1).
- **Retomada:** par processado sem valor encontrado continua `nao_buscado`,
  então rodar de novo refazia e pagava de novo todos eles. Agora
  `extrair_tudo()` pula os pares que já têm chamada em `chamadas_valor`
  (teste no mesmo arquivo). O par interrompido (*P. caete* ×
  `eyes_positioning`, 1 de 2 trechos chamado) teve a chamada apagada, para
  ser refeito inteiro.
- **Até aqui:** 95 registros `bruto`, 14 em `conflito` (vão para humano), 29
  `rejeitado` (span não confere); 57 pares `eyes_positioning` e 39
  `snout_shape_lv` extraídos. Faltam 147 pares em 39 obras (~US$ 1,5–2).
- Backup antes da extração: `girinos_antes_extracao_20261003.duckdb`.

**Retomada (03/10/2026), com crédito reposto:** US$ 0,40 em 4,9 min, sem
refazer nenhum par já chamado. **Total da rodada: US$ 2,41.** Resultado
final: 112 registros `bruto` com span literal conferido (71 espécies, 31
obras): `eyes_positioning` dorsal 36, lateral 27, dorsolateral 5;
`snout_shape_lv` rounded 30, truncated 10, sloped 7, "rounded or truncated" 2.
Mais 14 em `conflito` (vão para humano) e 32 `rejeitado` (span não confere).
A plausibilidade marcou 1 categoria fora do vocabulário. 101 pares não têm
trecho candidato (o BM25 não achou espécie e termo juntos): nenhuma chamada,
continuam `nao_buscado`. Backup antes da retomada:
`girinos_antes_retomada_20261003.duckdb`.

### Conferência humana do corpus (03/10/2026)

`Claude outputs/conferencia_corpus/` (fora do git): `conferencia_corpus.xlsx`,
`LEIA-ME.txt` e os 31 PDFs. São 118 linhas, uma por artigo × espécie ×
caractere com valor: 6 no bloco 1 (dois valores no mesmo artigo) e 112 no
bloco 2. Gerada por `gerar_conferencia_corpus()` (`R/conferencia.R`), no mesmo
formato da conferência do piloto; texto do leia-me em
`inst/conferencia_corpus_LEIA-ME.txt`. Os rejeitados (span que não confere)
ficam de fora. Página achada pela frase em 87 linhas; nas 31 restantes, quase
todas da monografia de 63 espécies com frases curtas como "Eyes dorsal.", vão
as páginas em que a espécie é citada. Ler a volta com
`ler_conferencia(arquivo, carregar_traits("inst/traits.csv"))`.

Achado lateral: a obra *The Tadpole of Physalaemus erikae…* está com ano 2026
no banco (veio assim da busca), e o nome do PDF sai com "2026".

### Planilha de vocabulário dos traits abertos (03/10/2026)

`Claude outputs/vocabulario/vocabulario_traits_para_grupo.xlsx` (fora do
git), gerada por `planilha_vocabulario()` (`R/vocabulario.R`) a partir de
`inst/traits.csv` e da base do livro em Darwin Core. Para o grupo revisar.
São 46 traits: 36 categóricos da planilha (801 valores distintos), 2
numéricos da planilha (dieta, que é híbrida, e profundidade) e 8 novos sem
dado.

- Aba `traits`: o que existe hoje, em cinza, e em amarelo o que o grupo
  decide: definição, unidade, limites, `valores_aceitos`, `termos_busca`
  (pt/en/es), `regra_extracao` e decisão (fechar / discutir / fora do
  escopo). Ordem: do menor vocabulário para o maior.
- Aba `valores`: 832 linhas, uma por valor observado (com nº de registros e
  até 3 espécies de exemplo); em amarelo, `valor_padronizado`, que diz em
  qual estado da lista final o valor entra. O mesmo mapeamento serve depois
  para padronizar a base do livro.
- Nenhum agrupamento é sugerido pelo programa: juntar sinônimos é decisão
  científica. Mas as colunas amarelas vêm **pré-preenchidas** com o que já
  existe (pedido do Diogo): definição, unidade e limites atuais, a lista de
  valores observados (do mais frequente para o menos) em `valores_aceitos`, e
  o próprio valor em `valor_padronizado`. O grupo edita em vez de digitar;
  nada fecha sem `decisao = "fechar"`. Os 2 traits já fechados vão no topo
  como exemplo de linha pronta.

**Quando voltar:** aplicar as decisões numa função nova em
`R/decisoes_traits.R` (como as da Denise), marcar `status = "fechado"` nos
traits fechados e rodar `semear_estado_par()` com eles.

## Feito — a planilha está fechada

- Base do livro em Darwin Core: 376 táxons, 695 ocorrências, 18.220 medidas.
  **Auditoria em zero achados.**
- 37.496 correções com registro célula a célula (`dwca/correcoes_aplicadas.csv`),
  regras R1–R14 em `R/corrigir_planilha.R`.
- Todas as fontes com DOI, ISBN ou URL estável; nenhuma ocorrência sem `eventID`.
- Dieta reestruturada (29/09): métrica única `percentage_of_items` (R12), cada
  corpo d'água do SAJH 2011 como amostra própria (R13), rótulo contraditório
  `dietItens` removido (R14). As 28 amostras somam 71,7–100,8%.
- Lacunas que são da fonte, e não da transcrição, viajam com o registro
  (`inst/notas_registro.csv` → `measurementRemarks`).

**Pendência pequena, sem pressa:** a planilha de trabalho ainda chama a coluna
do número de `measurementAccuracy`. O arquivo publicado já usa
`measurementValue`. Renomear na planilha exige trocar os nomes de duas colunas
ao mesmo tempo (hoje `measurementValue` guarda a métrica), o que confunde mais
do que ajuda enquanto ninguém estiver digitando linhas novas de dieta.

## Estamos prontos para o piloto? Ainda não.

A planilha está limpa no **formato**. O que falta é o **vocabulário**, e ele é
trabalho científico do grupo, não código.

### Trava 1 — os vocabulários categóricos não estão fechados (a maior)

Os 38 traits categóricos acumulam **898 valores distintos** na planilha;
mediana de 13,5 por trait, máximo de 108 (`submarginal_papillae_distribution`).
Catorze traits passam de 20 valores. Exemplo, `body_shape_dv`:

> elliptical · ellliptical · elongated elliptical · elliptical elongated ·
> elliptical or ovoid · ovoid or elliptical · retangular …

São erros de digitação, sinônimos em ordem trocada e combinações "X ou Y" que,
para o extrator, contam como categorias diferentes. Como o agente de valor
escolhe dentro de uma lista fechada (`type_enum`), extrair em cima dessa lista
faz a precisão despencar por um problema que não é do modelo — e provavelmente
explica parte da concordância de 48–55% entre as três descrições de
*O. cultripes*.

**Agora isso é travado no código.** `tipo_valor()` em `R/agentes.R` recusa
extrair um trait categórico se `status` não for `fechado` ou se a lista ainda
tiver o sufixo `[+N outros]` que o esqueleto coloca quando trunca. Antes, esse
sufixo teria virado uma categoria válida no enum.

**Caso especial:** `tooth_row_formulae` (67 valores) não deveria ser lista. É
uma fórmula com gramática (`2(2)/3`, `/` e `|` com significado próprio), e se
valida com um padrão, não com vocabulário fechado.

### Trava 2 — `termos_busca` vazio em todas as 48 linhas

Não serve só para a busca de artigos. `recuperar_candidatos()` usa esses termos
para achar, **dentro de cada PDF**, o trecho que fala do caractere. Sem eles,
nem o piloto com PDFs já conhecidos roda.

### Trava 3 — infraestrutura: **resolvida em 01/10/2026**

`verificar_infra()` passa nas sete checagens:

- 18 pacotes presentes (`cld3` ausente, opcional — ver abaixo).
- Chave de API no `.Renviron`, aceita pela API.
- Os quatro agentes apontam para modelos que a chave enxerga:
  `claude-haiku-4-5-20251001` (triagem), `claude-sonnet-5-5` (valor e
  contexto), `claude-opus-5-5` (escalonamento).
- Chamada real com saída estruturada funcionando, **e o span devolvido
  conferido contra o texto** — a barreira contra valor inventado está de pé.
- GROBID 0.9.1-crf em `http://localhost:8070`, no Docker.
- `girinos.duckdb` abre e escreve.
- 2 traits liberados para extração.

Três notas de operação:

**`cld3` é dispensável por enquanto.** Ele só preenche a coluna `idioma` dos
trechos, e nada a jusante lê esse campo — os agentes trabalham no idioma
original por instrução no prompt. A ausência dele deixa um buraco de metadado,
não quebra extração.

**Zerar `encoder_local` no `config.yml` até existir modelo treinado.** Com o
caminho preenchido, `extrair_par()` tenta carregar o encoder a cada trecho
categórico, falha, e cai no LLM por um `tryCatch`. Funciona, mas é tentativa
desperdiçada em todo trecho.

**Só o Haiku tem data no id.** Os outros três são apelidos, que podem passar a
apontar para outra versão. Como o id entra na procedência de cada valor, anotar
a data da rodada junto com o id na metodologia.

### Achado de 01/10/2026: a recuperação descartava o parágrafo certo

Com o GROBID de pé, rodei o parser e a recuperação sobre o TEI real de
Conte et al. (2007), o artigo de *Scinax catharinae*. O parser foi bem: 32
trechos, 20 de texto, 5 tabelas, 7 legendas, com a seção `Material and methods`
isolada — que é o que o agente de contexto precisa.

A recuperação, não. `recuperar_candidatos()` exigia o nome da espécie **no texto
do trecho**, e num artigo de descrição o parágrafo diagnóstico não repete o
binômio — quem carrega o nome é o cabeçalho:

    seção: "Description of the tadpole of Scinax catharinae"
    texto: "External morphology. (...) Snout rounded in dorsal and lateral
            views. Eyes large, dorsally positioned, dorsolaterally directed."

Esse é o único parágrafo do artigo com os caracteres, e era descartado. Sobravam
as menções de passagem da Discussão e as tabelas. A rede de segurança que manda
as tabelas quando não há candidato também não salvava, porque candidato havia —
só não era o certo.

Corrigido: a espécie passa a ser procurada no cabeçalho da seção junto com o
texto. Com a correção, `eyes_positioning` passou de 3 candidatos sem o parágrafo
para 4 com ele.

**Mas ele entra em último lugar dos quatro.** O BM25 favorece as tabelas, que
repetem os termos muitas vezes num trecho curto. Com `k = 4` ele passa; com
`k = 3` teria ficado de fora. Vale medir no piloto em que posição o trecho certo
costuma cair, e considerar dar peso ao tipo de trecho (texto de seção de
descrição acima de tabela) ou simplesmente subir o `k`.

O TEI ficou guardado em `inst/exemplo/conte2007.tei.xml` para esse caso virar
teste de regressão.

### Teste de fumaça: rodou, e funcionou (01/10/2026)

Primeira execução do pipeline de extração, ponta a ponta, sobre Conte et al.
(2007) — *Scinax catharinae*, espécie que **não está** entre as 376 da
planilha, então é extração de verdade e não conferência.

GROBID: 1,7 s, 43 trechos (31 texto, 5 tabela, 7 legenda), com
`Material and methods` isolada. Agente de contexto: `estagio = Gosner 31-38`,
`ambiente = campo`, `n = 40`, `temperatura_c = NULL` (o artigo não traz, e ele
não inventou), com span literal:

> "Forty S. catharinae tadpoles in stages 31-38 (Gosner, 1960) were used for
> the description, and incorporated to the Amphibian Collection (DZSJRP)..."

Quatro trechos candidatos por caractere; **3 registros, 3 aprovados no span,
0 rejeitados**, 28 s no total:

| trait | valor | conf. | span |
|---|---|---|---|
| `eyes_positioning` | dorsal | 0,85 | "Eyes large, dorsally positioned, dorsolaterally directed." |
| `snout_shape_lv` | rounded | 0,90 | "Snout rounded in dorsal and lateral views." |
| `snout_shape_lv` | rounded | 0,96 | parágrafo de comparação da Discussão |

Três acertos que não são triviais:

1. **`dorsal`, não `dorsolateral`.** As duas palavras estão na mesma frase. O
   caractere é o *posicionamento*; `dorsolateral` ali é a *direção* do olho.
2. **Atribuição correta em parágrafo multiespecífico.** O registro de 0,96 vem
   da Discussão, onde as outras espécies do grupo são descritas como
   *truncate*. Atribuir o caractere à espécie errada num parágrafo comparativo
   é o erro mais provável de um extrator de literatura, e ele não cometeu.
3. **Herança de contexto.** Os três valores saíram com estágio e *n* vindos dos
   Métodos, não em branco.

**Nada dessa rodada chegaria ao arquivo publicado**, e isso é a trava
funcionando: `escrever_dwc()` filtra `status = 'aprovado'`, os três estão
`bruto`, e `aplicar_limiares()` depende da tabela `limiares`, que tem zero
linhas até o conjunto-ouro existir.

### O que o teste de fumaça expôs: faltava reconciliação dentro da obra

`snout_shape_lv = rounded` saiu **duas vezes**, de dois trechos do mesmo
artigo. Como `extracao_id = id_de(obra_id, trecho_id, taxon_id, trait_id,
extrator)` inclui o `trecho_id`, os dois persistem como registros
independentes — e nada a jusante os reconciliava:

- `escrever_dwc()` emite uma linha de MeasurementOrFact **por extração**: duas
  medidas para a mesma coisa, e quem usar a base conta a espécie duas vezes.
- `calibrar_limiares()` casa as duas com a **mesma** linha do conjunto-ouro: o
  par entra duplicado no denominador da precisão, e o limiar sai enviesado para
  o lado dos artigos que repetem o caractere.
- `marcar_fonte_secundaria()` agrupa por `(taxon_id, trait_id, valor)` — **pelo
  valor**. Valores iguais caem no mesmo grupo; valores *diferentes* caem em
  grupos diferentes e nunca são comparados. Divergência interna passava sem
  aviso nenhum.

Aqui foi inócuo porque os dois concordaram. No piloto não vai ser.

**Corrigido:** `reconciliar_internas()` em `R/validacao.R`, novo target
`reconciliacao` entre `plausibilidade` e `fontes`. Agrupa por
`(obra_id, taxon_id, trait_id)` entre os registros `bruto` e:

- **valores concordantes** → fica um registro (o de maior confiança, desempate
  pelo `extracao_id` para ser determinístico); os outros viram `rejeitado` com
  motivo `duplicado_na_obra`;
- **valores divergentes** → **todos** vão para `status = 'conflito'` e entram
  inteiros na fila humana (`fila = "conflito_interno"`), sem passar por limiar.
  Divergência dentro do mesmo artigo é informação — ou a recuperação trouxe o
  trecho errado, ou o artigo é ambíguo —, não ruído a descartar.

"Mesmo valor" usa a tolerância relativa de 5% para numérico e comparação sem
caixa para categórico, a mesma de `calibrar_limiares()` e de
`concordancia_ouro()`, para os três critérios não discordarem entre si.

Duas decisões deliberadas de **não** fazer: a confiança do registro que fica
não sobe por causa da corroboração (ela precisa continuar significando o que o
modelo relatou, senão o limiar calibrado passa a medir outra coisa); e não há
preferência por tipo de trecho (texto de descrição acima de tabela) — seria
palpite, e é o piloto que diz se compensa.

Mudanças de acompanhamento, de uma linha cada: `calibrar_limiares()` exclui
`conflito`; `amostrar_para_revisao()` inclui `conflito`; e em
`importar_revisao()` o veredito `ambiguo` passa a **manter** o status em vez de
voltar para `bruto` — senão um conflito que o revisor não resolveu voltaria a
ser elegível para aprovação automática.

Teste: `Rscript tests/teste_reconciliacao.R` — 27 checagens, sem API, sem
GROBID e sem banco.

### Pendências que o teste de fumaça deixou abertas

**Custo não foi medido.** Só os 28 s. O piloto precisa de tokens de entrada e
saída por chamada, senão não há como projetar a rodada grande.

**`estado_par` fica vazio no teste de fumaça.** Ele chama `extrair_par()`
direto, e `atualizar_estado_par()` vive dentro de `extrair_tudo()`. Esperado
aqui; no piloto, `lacunas.txt` (a distinção entre "não tem dado" e "não foi
buscado") só existe se `semear_estado_par()` rodar antes.

### Achado de 01/10/2026: a busca devolvia zero, e nunca tinha rodado

Antes de gastar chamada de modelo na fase de busca, testei a consulta que
`montar_consultas()` montava contra a OpenAlex de verdade — de graça, sem LLM.
Usando *Physalaemus barrioi* como caso (espécie que não está entre as 376):

| consulta | resultados |
|---|---|
| como o pipeline montava (3 cláusulas, 33 termos, 607 caracteres) | **0** |
| sem a 3ª cláusula: `"Physalaemus barrioi" AND (tadpole OR larva OR …)` | **23**, com *Redescription of Physalaemus barrioi* em 1º |
| 3ª cláusula reduzida a 2 termos (`eyes OR snout`) | 7, e o artigo certo **não** está entre eles |
| 3ª cláusula só com `focinho, vista lateral` (vírgula interna) | **0** |

A terceira cláusula AND vinha dos `termos_busca` dos traits. Além de zerar a
busca, ela injetava o literal `NA` na consulta, porque 46 das 48 linhas de
`traits.csv` têm `termos_busca` vazio e `strsplit(NA, ";")` passa `NA` adiante.

O erro é conceitual, não de sintaxe: termo de trait serve para achar o
**parágrafo dentro do PDF** (`recuperar_candidatos()`), não para achar o
**artigo**. Um artigo que descreve o girino da espécie é relevante mesmo que o
resumo não diga "snout" — e resumo de artigo de descrição quase nunca diz.
Quem decide relevância é `triar_obras()`, que lê título, periódico e ano.

**Corrigido:** `montar_consultas(taxa, idiomas)` monta só binômio + termos de
girino. Perdeu o argumento `traits`.

### E o CROSS JOIN em `extrair_tudo()`

Investigando a busca, apareceu o defeito mais caro do pipeline.
`executar_busca()` sabe para qual espécie achou cada obra, mas **descarta** o
`taxon_id` ao gravar — `obras` não tem essa coluna. `semear_corpus()` faz o
mesmo com as referências da BT 5.0, que trazem `taxon_id`. Sem o vínculo,
`extrair_tudo()` só podia cruzar **toda obra com todo par pendente**:

```sql
FROM trechos t CROSS JOIN estado_par e
```

No piloto completo isso é 376 espécies × 48 traits × nº de obras. E não é só
custo: como `recuperar_candidatos()` cai nas tabelas da obra quando nenhum
trecho cita a espécie, o agente de valor era chamado para a espécie X em cima
de tabela de artigo sobre a espécie Y. A validação de span e a recusa do modelo
seguram o valor errado, mas a chamada é paga de todo jeito.

**Corrigido:** nova tabela `obra_taxon (obra_id, taxon_id, fonte)`, gravada
por `executar_busca()` e por `semear_corpus()` — em ambos os casos **antes** do
`distinct`, senão uma obra achada para duas espécies (artigo de gênero, revisão,
lista faunística) perderia um dos vínculos. `extrair_tudo()` passou a fazer
INNER JOIN nela.

Teste: `Rscript tests/teste_busca.R` — 28 checagens, sem API e sem banco.

**Sessão de R com função velha.** A primeira tentativa do teste da busca
estourou com `$ operator is invalid for atomic vectors`: a sessão ainda tinha
o `montar_consultas()` antigo em memória, e `garantir_projeto()` só recarregava
se faltasse alguma de seis funções-sentinela — que existiam, da rodada
anterior. Agora os pontos de entrada recarregam o projeto **sempre**.

### Ainda não medido na busca

**Tipo de registro: filtrado na API desde 01/10/2026.** Sem filtro, 4 dos 8
primeiros resultados do Crossref para *P. barrioi* eram `dataset`: projetos do
MorphoBank (`10.7934/p544`, `p725`, `p840`) e fichas da IUCN Red List. Um deles
tem o **mesmo título** do artigo ("Redescription of Physalaemus barrioi"), então
nem a triagem por título separaria com segurança — e cada um custaria uma
chamada. Agora `buscar_openalex()` e `buscar_crossref()` mandam uma lista do que
**entra** (`TIPOS_OPENALEX`, `TIPOS_CROSSREF` em `R/busca.R`): artigo, revisão,
livro, capítulo, tese/dissertação, preprint, relatório. Ficaram de fora de
propósito: anais de congresso, verbetes e data papers — decisão do grupo, fácil
de reverter. Conferido ao vivo: no Crossref os `dataset` somem e o artigo certo
(`10.1643/ch-10-142`) sobe da 12ª para a 7ª posição; na OpenAlex o filtro não
tira nenhum resultado legítimo (23 → 23).

**Crossref: só entra se o título citar a espécie (01/10/2026).** O filtro por
tipo funcionou — sem ele vinham 33 registros-lixo (18 `dataset`, 12
`component`, 2 `peer-review`, 1 `grant`), com ele zero —, mas o total *subiu*
(185 → 195), porque o corte de 100 por consulta passa a ser preenchido com mais
artigos de girino **de outras espécies**. A triagem não sabe a espécie-alvo e
aprovaria todos, e o `obra_taxon` os ligaria a *P. barrioi*. Agora o Crossref
só entra se o título trouxer o binômio (ou sinônimo, ou gênero abreviado):
**195 → 1**, e esse 1 é o artigo certo. Binômio, não só epíteto: "barrioi"
sozinho deixaria passar *Leptodactylus barrioi* e *Apostolepis barrioi*, uma
serpente. A OpenAlex **não** passa pelo filtro, porque casa a frase exata no
resumo e no texto e traz com razão obras sem o nome no título (listas
faunísticas, descrições de espécies próximas que comparam com esta). Decisão
do grupo em 01/10/2026: é improvável uma obra estar só no Crossref e não na
OpenAlex.

**Triagem: primeiro número real (01/10/2026).** Diogo classificou as 23 obras
de *P. barrioi* **antes** de ver o modelo. Lendo só título, ano e DOI, o Haiku
teve especificidade 14/14 e **sensibilidade 5/9**: perdeu a própria
*Redescription of Physalaemus barrioi* ("redescrição de espécie adulta"),
*Canopy cover…* (adivinhou "anuros adultos"), *A new species of Physalaemus…*
e *The Larva… of Bokermannohyla ahenea* — esta por uma distribuição geográfica
que o modelo **inventou** ("México/América Central"; a espécie é endêmica da
mesma serra que *P. barrioi*). Todos os negativos, certos e errados, saíram com
probabilidade 0,05–0,20: a margem 0,35–0,75 que manda para humano nunca
disparou. Três mudanças, aprovadas pelo grupo:

1. **Obra com o binômio da espécie-alvo no título entra direto**, sem modelo
   (`decidido_por = "regra:binomio_no_titulo"`).
2. **A triagem lê o resumo.** A OpenAlex já o devolve na busca (como índice
   invertido; `resumo_openalex()` remonta). Nova coluna `obras.resumo`, por
   `ALTER TABLE … ADD COLUMN IF NOT EXISTS` — o banco antigo continua valendo.
   Dos 4 perdidos, 3 citam girino ou larva no resumo; *A new species…* não
   cita nem no resumo — é o limite de qualquer triagem por metadado.
3. **Prompt novo:** decide só pelo título e resumo, sem conhecimento próprio
   sobre distribuição ou taxonomia, e na dúvida fica com a obra.

**Resultado, mesmas 23 obras e mesma classificação humana:**

| | só título | regra + resumo + prompt novo |
|---|---|---|
| sensibilidade | 5/9 | **8/9** |
| especificidade | 14/14 | 13/14 |
| chamadas ao modelo | 23 | 21 (2 pela regra) |

O falso negativo que sobrou é o previsto: *A new species of Physalaemus…
Misiones* não menciona larva nem no resumo. O falso positivo é a tese *Uso de
recursos e padrão de co-ocorrência… comunidades… de girinos* (2009), que o
modelo aprovou pelo título; custa um download. Ressalvas: uma espécie, 23
obras, um avaliador — indica a direção, não fecha o número. E as
probabilidades seguem bimodais (0,05–0,15 ou 0,85–0,99): a margem 0,35–0,75
ainda não mandou nenhuma obra para humano, então ela não está sendo testada.

**Aquisição: primeiro teste (01/10/2026).** Das 8 obras relevantes de
*P. barrioi*, 2 vieram por download automático (FUP e repositório da UNESP).
3 são de acesso aberto mas a editora bloqueia download por script (BioOne
devolveu uma página HTML de ~1 KB, Brill um arquivo vazio); 3 não têm acesso
aberto (Copeia, J. Herpetology, o pôster no F1000). Ou seja: **para literatura
de girino, a maior parte dos PDFs vai chegar por mão humana**, e o pipeline
precisava de uma porta de entrada para isso. Três mudanças:

- `baixar()` baixa para arquivo temporário e só copia para `pdf/` se o
  cabeçalho for `%PDF`. Antes gravava direto e aceitava > 10 KB: deixou três
  arquivos falsos com extensão `.pdf` na pasta.
- `exportar_sem_pdf()` traz o link de acesso aberto (para abrir no navegador)
  e uma coluna `arquivo` vazia. `importar_pdfs_manuais()` lê essa planilha
  (vírgula ou ponto e vírgula), confere que é PDF, **copia** para
  `pdf/<obra_id>.pdf` — o original não é tocado — e marca `pdf_manual`. Se o
  Excel tiver estragado um `obra_id` (hexadecimal com "e" vira notação
  científica), acha a obra pelo DOI.
- `precisa_ocr()` sem o `pdftools` avisa e devolve FALSE, em vez de mandar
  todo PDF para OCR.

**Fontes de PDF além do acesso aberto (01/10/2026).** O PDF da redescrição de
*P. barrioi* estava no ResearchGate, e o de *Pseudopaludicola* no Academia.edu.
Nenhum dos dois entra no pipeline: os termos de uso dos dois proíbem coleta
automática, e o link do Academia é assinado e expira (`Expires=`), então nem
serve como fonte registrável. Ficam como caminho humano, via
`importar_pdfs_manuais()` — que registrou 6 de 6 na primeira rodada. Testei
também as cópias em repositório institucional que a OpenAlex lista além do
"melhor" local (UNESP, CONICET, LA Referencia): nenhuma entregou PDF — eram
registros só de metadado ou recusaram conexão. Não vale implementar por ora.

**Temperatura: só onde o modelo aceita.** Na terceira rodada da triagem,
*Canopy cover…* foi de "sim" (0,85) para "não" (0,15) com entrada idêntica: o
modelo estava sorteando. Tentei `temperature = 0` em todos os agentes, e
`verificar_infra()` mostrou que o Haiku 4.5 aceita, mas o **Sonnet 5.5 e o Opus
5.5 recusam com HTTP 400** ("temperature is deprecated for this model"). Agora
a temperatura é um campo opcional por agente no `config.yml`, só no da
triagem. Para os agentes de valor e contexto a variação entre rodadas não é
controlável por parâmetro — **tem de ser medida**: no piloto zero, rodar a
extração duas vezes e reportar a concordância entre as rodadas.

**Erro de API virava "não encontrado" (01/10/2026).** Com o HTTP 400 acima,
toda chamada ao Sonnet e ao Opus falhou — e `teste_de_fumaca_extracao()`
relatou "0 registros" nas 8 obras, sem aviso. `com_escalonamento()` engolia o
erro e devolvia `NULL`, que seguia como resposta vazia. Pior: o agente de
contexto também falhou, e o contexto vazio ficou **guardado** em
`contexto_obra`, que é reaproveitado — a rodada seguinte teria todo valor sem
estágio. Agora erro de API para a rodada com a mensagem da API (parar é
seguro: o par que falhou continua pendente e a próxima rodada retoma). Teste:
`tests/teste_agentes.R`, conferido também com o defeito antigo recolocado
(5 verificações falham, como deveriam).

**O `rows = 100` do Crossref é o filtro de fato.** A consulta devolveu
`total-results: 3.871.868` — `query.bibliographic` ignora os operadores
booleanos e faz ranqueamento por relevância. O corte em 100 é o que seleciona,
e por isso `n_resultados` no `busca_log` não significa "quantos existem".

### Como rodar o teste de fumaça da busca

`R/fumaca_busca.R` cobre a fase que `R/fumaca.R` não cobre: consulta, APIs,
triagem e download, para **uma** espécie. A triagem é opcional, então o teste
roda **sem gastar um centavo** e ainda responde o que importa.

```r
source("R/fumaca_busca.R")
r <- teste_de_fumaca_busca("Physalaemus barrioi",
                           esperado = "Redescription of Physalaemus barrioi")
```

Ele imprime as consultas, o número de obras por fonte e os 10 primeiros
títulos na ordem em que vieram; com `esperado` informado, diz em que posição do
ranking o artigo que você sabe que existe caiu. Sem conjunto-ouro, é a única
forma de medir a busca. Depois, com `triar = TRUE, baixar_pdf = TRUE`, entram a
triagem e o Unpaywall. `limpar_fumaca_busca(con, "TESTEBUSCA001")` apaga tudo —
e apaga só as obras que ficaram órfãs, porque outra espécie pode compartilhar a
mesma obra.

**O que olhar, nesta ordem:**

1. A consulta impressa faz sentido? Cláusula AND demais zera o resultado.
2. O artigo que você sabe que existe está na lista, e em que posição? Se não
   está, triar não resolve — o problema é na consulta.
3. Quanto lixo veio (datasets, fichas da IUCN, registros de projeto)? É o que
   a triagem vai ter de pagar para rejeitar.
4. Das obras relevantes, quantas têm PDF acessível? `status = "sem_pdf"` é fila
   para pedir aos autores, não erro.

### Como rodar o teste de fumaça

`R/fumaca.R` roda um PDF só, de ponta a ponta, fora do `{targets}` e fora da
fase de busca, e imprime cada registro com o trecho que o sustenta.

```r
source("R/fumaca.R")
r <- teste_de_fumaca("pdf/conte2007.pdf",
                     especie  = "Scinax catharinae", ano = 2007,
                     taxon_id = "TESTE001",
                     aliases  = c("Ololygon catharinae"))
```

Ele monta no banco o mínimo que `extrair_par()` espera (a espécie em `alvo`, os
traits fechados em `traits`, a obra em `obras`), chama o GROBID, grava os
trechos, roda o agente de contexto sobre os Métodos e o agente de valor sobre
os trechos recuperados. `limpar_fumaca(con, "TESTE001")` apaga tudo depois.

**O que olhar, nesta ordem:**

1. A seção de Métodos foi identificada? Sem ela o agente de contexto não tem o
   que ler, e todo valor sai sem estágio.
2. Quantos trechos candidatos por trait? Zero é problema de recuperação, não do
   modelo. Muitos, e o custo sobe à toa.
3. **Cada span, contra o PDF.** É o único jeito de saber se o valor veio do
   artigo ou da cabeça do modelo. Registro com `status = rejeitado` e motivo
   `span_nao_encontrado_no_trecho` é a trava funcionando, não defeito.
4. O estágio de Gosner que o agente de contexto devolveu bate com o artigo?

5. Dois valores para o mesmo par (espécie, trait) no mesmo artigo? Se forem
   iguais, `reconciliar_internas()` colapsa; se divergirem, param em
   `conflito`. Os dois casos aparecem no relatório do target `reconciliacao`.

## Como destravar sem esperar os 48 traits

### Piloto estreito

Não é preciso fechar os 38 vocabulários para começar. Escolher **cinco traits**
de vocabulário pequeno e definição clássica, fechar só esses e escrever
`termos_busca` só para eles:

| trait | valores hoje | observação |
|---|---|---|
| `eyes_positioning` | 3 | dorsal, lateral, dorsolateral — já fechado na prática |
| `cloacal_opening` | 8 | medial / dextral, caractere clássico |
| `lower_jaw_shape` | 8 | V / U |
| `snout_shape_dv` | 6 | |
| `maximumDephInMeters` | numérico | limites já definidos (0–5 m) |

Isso reduz a Trava 1 de 898 valores para ~30, e a Trava 2 de 48 linhas para 5.

### Piloto zero: os 11 artigos que já estão na planilha

As 11 fontes da planilha já foram extraídas à mão, **antes** de qualquer IA
entrar no projeto. Rodar o extrator nesses mesmos PDFs e comparar com a planilha
dá um primeiro número de desempenho sem nenhum trabalho humano novo, e testa a
cadeia inteira (GROBID → recuperação → agentes → validação de span).

Ressalva: é comparação com **um** extrator humano, não com o conjunto-ouro
duplo-cego. Mede concordância, não acurácia, e o teto de 48–55% de
*O. cultripes* diz até onde dá para esperar. Serve para achar defeito no
pipeline, não para calibrar limiar.

## Sequência proposta

1. ~~**Grupo:** fechar o vocabulário dos 5 traits do piloto estreito.~~ Feito
   para `eyes_positioning` e `snout_shape_lv`; faltam 4 pendências em
   `cloacal_opening` e `lower_jaw_shape`.
2. ~~**Diogo:** chave de API, ids de modelo, GROBID.~~ Feito em 01/10/2026.
3. ~~**Teste de fumaça:** 1 artigo, ponta a ponta, revisão de cada registro.~~
   Feito em 01/10/2026 — 3 registros, 3 aprovados no span, todos corretos
   contra o artigo.
4. **Testar a busca online** com `R/fumaca_busca.R`, uma espécie só
   (*Physalaemus barrioi*), antes do piloto zero. A consulta já foi corrigida
   em 01/10/2026 — ver abaixo —, mas a fase ainda não rodou de ponta a ponta.
5. **Piloto zero:** os 11 artigos da planilha × 5 traits. Medir concordância,
   **custo e tempo por artigo** — nada disso foi medido ainda.
6. **Piloto:** 20 artigos novos da BT 5.0, com conjunto-ouro de dois revisores
   em extração cega e **sem assistência de IA** — senão a precisão medida vira
   concordância entre duas IAs.
7. Em paralelo a 4–6, o grupo fecha os outros 33 vocabulários categóricos.

## Depois do piloto

- **Produção:** rodadas por lote de espécies, priorizadas por cobertura;
  revisão humana da fila a cada rodada; ~500 exemplos revisados por trait
  para treinar o encoder local.
- **Publicação:** `stageMin`/`stageMax` (Gosner) no lugar do texto livre; o
  remendo do `eventID` com sufixo vira core de Event; EML; GBIF Data Validator;
  IPT; Zenodo; data paper com precisão, recall e F1 por trait, uso de IA
  descrito no método conforme COPE e CNPq/CAPES.

### Candidato a base do encoder local: LAYA (avaliado em 02/10/2026)

Avaliação feita só pelo README de
[NandhaKishorM/laya](https://github.com/NandhaKishorM/laya), sem rodar o
código; os benchmarks citados lá são do próprio autor e não foram conferidos.

**O que é.** Encoder (ModernBERT-large em inglês; mmBERT-base multilíngue,
que cobre pt e es) que responde perguntas tipadas numa passada só, sem gerar
texto: `choice` (um rótulo entre vários), `score` (ordinal) e `noul`
(sim/não), com probabilidade calibrada. Apache 2.0, roda em CPU, aceita
fine-tuning no domínio. É a alternativa aberta ao **Jev** (TypeSafe AI), que
é API hospedada e fechada.

**Jev: descartado.** Mandaria texto completo de artigo com direito autoral a
mais um terceiro, é pago e não tem vantagem sobre o LAYA para o nosso uso.

**Onde o LAYA não entra.** Na extração de valor como extrator autônomo: não
devolve span literal (no máximo, a janela de tokens que decidiu, em
`predict_long`), e o `validar_span()` não pode ser afrouxado. Também não
extrai número nem texto livre, então traits numéricos e o agente de contexto
continuam no LLM.

**Onde pode entrar, em ordem de interesse:**

1. **Checkpoint-base do encoder local (item 12).** A vaga já existe:
   `python/encoder.py` treina um classificador por trait sobre
   `xlm-roberta-base`, e `extrair_par()` já resolve a falta de span com busca
   literal da classe no trecho (`R/extracao.R`). Hoje `encoder_local` está
   vazio no `config.yml`. A vantagem esperada do LAYA é precisar de menos
   exemplos (já vem treinado para escolher entre rótulos descritos) e sair
   calibrado, o que conversa com `calibrar_limiares()`. Limite: o desempenho
   cai acima de ~20 rótulos por pergunta (segundo o README); conferir o
   número de classes de cada trait categórico.
2. **Triagem por título e resumo** (`noul` local no lugar do Haiku). Ganho
   pequeno, porque o Haiku já é barato, e risco de falso negativo silencioso
   (princípio 1). Só com decisões humanas de triagem para medir.
3. **Pré-filtro de trechos antes do Sonnet.** Não recomendado agora: o custo
   medido é baixo (US$ 0,083 para 8 obras × 2 traits) e o filtro sem
   calibração cria falso negativo silencioso.

**Condição para testar.** Depende do conjunto-ouro e de exemplos revisados
(`exportar_treino()`). Quando existirem: comparar XLM-R × LAYA no mesmo
conjunto-ouro, com precisão por trait e calibração (ECE). Tudo local, sem
gasto de API. Medir antes de trocar (princípio 3).

## Travas

- Piloto estreito depende de: 5 vocabulários fechados + seus termos + infra.
- Piloto completo depende do conjunto-ouro: sem ele não há limiar calibrado, e
  sem limiar calibrado a extração automática não aprova nada sozinha.
