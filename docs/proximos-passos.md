# Próximos passos

Estado em 01/10/2026.

## Onde paramos (leia primeiro)

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
