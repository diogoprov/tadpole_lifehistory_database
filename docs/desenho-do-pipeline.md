# Desenho do pipeline: por que cada peça existe

Documento de referência do grupo. A figura correspondente está em
`docs/pipeline_girinos_traits.pdf`.

## Entrada

A lista-alvo vem da **Brazilian Tadpoles 5.0 (The Rossa-Feres Tadpole
Database)**, de `assets/data/species.json` (1.063 espécies na versão 5.1.1), e
define quais espécies são buscadas e qual é o nome aceito de cada uma. O campo
`id` do próprio arquivo é usado como `taxon_id`.

O `species.json` entrega três coisas de uma vez:

1. a lista de espécies com família, gênero e epíteto;
2. o *status* de cada conjunto de caracteres (`ext_morph`, `internal_oral`,
   `chondrocranium`: `described` / `not_described`) — as lacunas já mapeadas;
3. as **referências** de cada descrição, com autor, ano, título, periódico e
   DOI — que o pipeline usa como corpus-semente, entrando direto na tabela de
   obras e dispensando triagem de relevância.

A sinonímia vem da **ASW**, via pacote `AmphiNom`, só para descobrir sob que
outros nomes cada espécie aparece na literatura antiga. O nome aceito continua
sendo o da lista-alvo. `inst/sinonimos.csv` fica como complemento manual
(grafias erradas recorrentes, `cf.`/`aff.`, nomes de trabalho em teses).

## Onde cada melhoria acordada está implementada

| # | Melhoria | Onde |
|---|---|---|
| 3 | Proibir geração, exigir âncora textual | `R/agentes.R` (`span_verbatim` é campo obrigatório do tipo) + `R/extracao.R::validar_span()` — a frase tem que existir letra por letra no trecho, senão a linha nasce `rejeitado`; a coluna é `NOT NULL` no banco |
| 4 | Limiar de confiança calibrado por trait | `R/validacao.R::calibrar_limiares()` — varre limiares contra o conjunto-ouro e escolhe o menor que atinge `precisao_alvo`; trait que não atinge em limiar nenhum vira `revisao_integral` |
| 5 | Conjunto-ouro com dupla extração cega | `R/revisao.R::preparar_ouro()`, `importar_ouro()`, `concordancia_ouro()` — uma planilha vazia por revisor; só entra na calibração o item em que os dois concordaram |
| 6 | Tabelas e material suplementar | `R/parse.R` (GROBID separa texto, tabela e legenda em tipos de trecho) + `R/aquisicao.R` (baixa suplementar via Unpaywall) + `R/recuperacao.R` (tabela é candidata mesmo sem o nome da espécie no corpo do texto) |
| – | Corpus-semente | `R/lista_alvo.R::carregar_referencias()` e `semear_corpus()` — as refs do `species.json` entram como obras já triadas |
| 7 | Contexto junto com a medida | `R/agentes.R::agente_contexto()` lê os Métodos uma vez por artigo; `contexto_obra` guarda; cada valor herda e vai para `measurementRemarks` em `R/dwc.R` |
| 8 | Rastrear a fonte primária | `R/validacao.R::marcar_fonte_secundaria()` — detecta citação dentro da frase-fonte e valor repetido entre obras; o mais antigo fica `primaria`, os demais `secundaria` com `fonte_primaria_doi` |
| 9 | Multilíngue de verdade | `R/busca.R::TERMOS_GIRINO` (pt/es/en) + `R/parse.R::detectar_idioma()` + extração no idioma original (o prompt diz "não traduza") + encoder multilíngue em `python/encoder.py` |
| 10 | Registrar os negativos | tabela `estado_par` (`nao_buscado` / `buscado_sem_dado` / `extraido` / `revisado`), `R/busca.R::fechar_rodada()` e `dwca/lacunas.txt` publicado junto com os dados |
| 12 | Encoder local para o volume, agente só no difícil | `R/extracao.R::extrair_par()` roteia por confiança; `python/encoder.py` treina e serve o modelo local; `modelo_versao` e `prompt_versao` gravados em cada linha |
| 14 | Aprendizado ativo e priorização | `R/revisao.R::exportar_treino()` (correções viram dado de treino) e `R/busca.R::priorizar_taxa()` (espécies com menos cobertura entram primeiro) |

Imputação ficou de fora, por decisão do grupo.

## O que veio do pipeline de revisão sistemática do Paulo Mateus

Quatro coisas foram adaptadas do pipeline multi-agente em R usado naquela
revisão sistemática (Screening Agent → Core Extraction Agent → Methodology
Agent, com escalonamento para modelo mais capaz):

1. **`ellmer` no lugar de chamadas HTTP escritas à mão.** Tipos declarados
   (`type_object`, `type_enum`, …), saída estruturada garantida e troca de
   provedor sem reescrever o pipeline.
2. **Um modelo por agente**, dimensionado à tarefa (`config.yml: agentes`).
   Triagem é barata e roda sobre título; extração de valor é média; contexto é
   média; o modelo forte só aparece no escalonamento.
3. **Escalonamento por campo crítico vazio** (`com_escalonamento()`): se o
   `span_verbatim` volta vazio, repete com o modelo forte e um prompt mais
   explícito. O caro foi conseguir o PDF, não a segunda chamada.
4. **Agente de contexto separado** (`agente_contexto()`): lê a seção de Métodos
   uma vez por artigo e extrai estágio, temperatura, campo/laboratório, *n* e
   medida de dispersão. O contexto quase nunca está na mesma frase do valor, e
   pedir os dois na mesma chamada convida o modelo a preencher o que não está
   ali.

E uma coisa foi deliberadamente **não** adaptada: eles removem as citações no
texto para economizar token. Aqui as citações no texto são sinal, não ruído: é
por elas que `marcar_fonte_secundaria()` detecta valor recitado de outro
trabalho. A economia de token vem da recuperação BM25, que já seleciona os
trechos antes de qualquer chamada. Remover a seção de Referências, sim; as
citações no corpo, não.

Também foi adotada a lógica de validação **por campo**: se um trait não alcança
a precisão alvo em limiar nenhum, ele é marcado `revisao_integral` e nenhum
valor dele entra na base sem passar por humano — o equivalente ao que eles
fizeram com `traits`, `trait category` e `elevation-related driver`.

## Limitações conhecidas

- Os nomes das colunas devolvidas por `AmphiNom::getSynonyms()` variam entre
  versões do pacote. `sincronizar_sinonimos()` espera `species` e `synonym` e
  para com uma mensagem clara se forem outros.
- Nome ambíguo na ASW não entra na tabela de sinônimos: sai em
  `revisao/asw_ambiguos.csv`. Um casamento errado aqui atribui o dado de uma
  espécie a outra, o que é pior do que não ter o dado.
- A chamada ao BHL segue o formato `api3?op=...`; confira os parâmetros na
  documentação corrente antes de ligar a fonte.
- Usar `MeasurementOrFact` sobre um Taxon core é uma escolha pragmática: a
  extensão foi desenhada para *occurrence*/*event*. Confirmar com o
  administrador do IPT antes de publicar.
- O encoder local só cobre traits categóricos. Trait numérico vai direto ao
  agente enquanto não houver um modelo de pergunta-resposta local treinado.

## Referências de método

- Domazetoski V., Kreft H., Bestova H., Wieder P., Koynov R., Zarei A.,
  Weigelt P. (2025). Using large language models to extract plant functional
  traits from unstructured text. *Applications in Plant Sciences* 13(3):
  e70011. doi:10.1002/aps3.70011
- Coleman D., Gallagher R.V., Falster D., Sauquet H., Wenk E. (2023). A
  workflow to create trait databases from collections of textual taxonomic
  descriptions. *Ecological Informatics* 78: 102312.
  doi:10.1016/j.ecoinf.2023.102312
- Liedtke H.C. (2019). AmphiNom: an amphibian systematics tool. *Systematics
  and Biodiversity* 17(1). doi:10.1080/14772000.2018.1518935
