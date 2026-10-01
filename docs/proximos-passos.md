# Próximos passos

Estado em 29/09/2026.

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

### E uma coisa que ninguém fez ainda

O pipeline de extração **nunca foi executado**. `R/fumaca.R` existe para isso:
roda um PDF só, de ponta a ponta, fora do `{targets}` e fora da fase de busca,
e imprime cada registro com o trecho que o sustenta.

```r
source("R/fumaca.R")
r <- teste_de_fumaca("pdf/conte2007.pdf",
                     especie  = "Scinax catharinae",
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

*Scinax catharinae* é um bom primeiro caso: a espécie **não está** entre as 376
da planilha, então é extração de verdade, não conferência contra o que já
temos. O TEI dele está guardado em `inst/exemplo/`.

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

1. **Grupo:** fechar o vocabulário dos 5 traits do piloto estreito e escrever
   seus `termos_busca` (pt, en, es). Marcar `status = fechado`.
2. **Diogo:** chave de API, ids de modelo, GROBID.
3. **Teste de fumaça:** 1 artigo da planilha, ponta a ponta, revisão de cada
   registro.
4. **Piloto zero:** os 11 artigos da planilha × 5 traits. Medir concordância,
   custo e tempo por artigo.
5. **Piloto:** 20 artigos novos da BT 5.0, com conjunto-ouro de dois revisores
   em extração cega e **sem assistência de IA** — senão a precisão medida vira
   concordância entre duas IAs.
6. Em paralelo a 3–5, o grupo fecha os outros 33 vocabulários categóricos.

## Depois do piloto

- **Produção:** rodadas por lote de espécies, priorizadas por cobertura;
  revisão humana da fila a cada rodada; ~500 exemplos revisados por trait
  para treinar o encoder local.
- **Publicação:** `stageMin`/`stageMax` (Gosner) no lugar do texto livre; o
  remendo do `eventID` com sufixo vira core de Event; EML; GBIF Data Validator;
  IPT; Zenodo; data paper com precisão, recall e F1 por trait, uso de IA
  descrito no método conforme COPE e CNPq/CAPES.

## Travas

- Piloto estreito depende de: 5 vocabulários fechados + seus termos + infra.
- Piloto completo depende do conjunto-ouro: sem ele não há limiar calibrado, e
  sem limiar calibrado a extração automática não aprova nada sozinha.
