# Infraestrutura — como montar

Estado em 30/09/2026. Três coisas: chave de API, ids de modelo e GROBID.
Nenhuma envolve decisão científica, e todas são conferíveis com um comando só.

Ao final, `verificar_infra()` responde se está tudo de pé.

---

## 1. Chave de API

A chave vai no **ambiente**, nunca no `config.yml` nem num script — o
`config.yml` está no git, e chave em repositório é problema mesmo em repositório
privado.

```r
usethis::edit_r_environ()     # abre ~/.Renviron
```

Acrescente a linha, salve, e **reinicie o R** (o `.Renviron` só é lido na
inicialização):

```
ANTHROPIC_API_KEY=sk-ant-...
```

Confira sem imprimir o valor:

```r
nchar(Sys.getenv("ANTHROPIC_API_KEY"))   # > 0
```

A chave sai do console da Anthropic (platform.claude.com), em API keys. Vale
criar uma chave só para este projeto: se vazar ou se o consumo disparar, você
revoga essa e não derruba o resto.

**Antes de rodar em volume**, ponha um limite de gasto mensal na conta. Um erro
de laço num pipeline que faz milhares de chamadas é caro, e o limite é a única
coisa que segura isso sem supervisão.

## 2. Ids de modelo

O `config.yml` tem quatro agentes com `PREENCHER`. O id exato entra na
procedência de cada valor extraído, então trocar o modelo fica registrado na
base — é de propósito.

Consultados na documentação oficial em 30/09/2026:

| id | preço entrada / saída (por milhão de tokens) |
|---|---|
| `claude-haiku-4-5-20251001` | US$ 1 / US$ 5 |
| `claude-sonnet-5-5` | US$ 2 / US$ 10 |
| `claude-opus-5-5` | US$ 4 / US$ 20 |
| `claude-fable-5-1` | US$ 10 / US$ 50 |

Sugestão para os quatro papéis:

```yaml
  agentes:
    triagem:  {provedor: "anthropic", modelo: "claude-haiku-4-5-20251001"}
    valor:    {provedor: "anthropic", modelo: "claude-sonnet-5-5"}
    contexto: {provedor: "anthropic", modelo: "claude-sonnet-5-5"}
    forte:    {provedor: "anthropic", modelo: "claude-opus-5-5"}
```

A triagem é uma pergunta de sim/não sobre o artigo inteiro e roda uma vez por
obra: é onde o modelo barato paga. O agente de valor roda por trecho e por
trait, é o grosso do custo, e é onde a qualidade decide o resultado. O `forte`
só é chamado no escalonamento, quando um campo crítico volta vazio.

**Prefira o id com data quando existir** (`claude-haiku-4-5-20251001` em vez de
um apelido). Um apelido aponta para versões diferentes ao longo do tempo, e a
base ficaria registrando um nome que não identifica o que de fato extraiu. Para
os outros três a documentação lista o id sem data; conferir no próprio
`verificar_infra()`, que imprime os ids que a sua chave enxerga.

Não é preciso decidir isso de uma vez: o `prompt_versao` e o id do modelo estão
na procedência, então dá para trocar entre rodadas e comparar.

## 3. GROBID

Converte o PDF em TEI/XML com as seções separadas. É o que permite ler só os
Métodos para o agente de contexto, e tratar tabela como unidade inteira em vez
de picada em pedaços.

### Imagem

```bash
docker run --rm --init --ulimit core=0 -p 8070:8070 grobid/grobid:0.9.1-crf
```

Existem duas imagens. A **completa** (`0.9.1-full`) usa modelos de aprendizado
profundo, é mais precisa em referências bibliográficas e pesa vários GB. A
**CRF** (`0.9.1-crf`) usa só os modelos clássicos, é bem mais leve e rápida, e é
a certa aqui: queremos a estrutura do texto, não o parsing fino das referências.

**No seu Mac (Apple Silicon)**, se a imagem reclamar de plataforma, a
documentação manda forçar a emulação:

```bash
docker run --rm --init --ulimit core=0 --platform linux/amd64 -p 8070:8070 grobid/grobid:0.9.1-crf
```

Vale tentar primeiro sem o `--platform`: se funcionar nativo, roda bem mais
rápido. Memória: a documentação recomenda **4 GB** para estruturar o documento
inteiro (`/api/processFulltextDocument`, que é o que o pipeline usa). Com 48 GB
na máquina, basta não limitar o Docker abaixo disso.

### `zsh: command not found: docker`

Instalar o Docker Desktop não basta para o comando aparecer no terminal. No
macOS os executáveis vão para `$HOME/.docker/bin`, e essa pasta só entra no
`PATH` quando o Docker Desktop **roda pela primeira vez** — e a mudança só vale
em terminais abertos **depois** disso.

Diagnóstico, nessa ordem:

```bash
ls -l ~/.docker/bin/docker          # o executável existe?
ls -d /Applications/Docker.app      # o aplicativo foi instalado?
echo $PATH | tr ':' '\n' | grep docker   # a pasta está no PATH?
```

- **O executável existe mas não está no PATH** → abra o Docker Desktop pelo
  Launchpad, espere a baleia aparecer na barra de menus, **feche o terminal e
  abra outro**. Para resolver na hora, sem fechar nada:
  `export PATH="$HOME/.docker/bin:$PATH"`.
- **O executável não existe** → o Docker Desktop foi baixado mas não instalado,
  ou instalado e nunca aberto. Abra o aplicativo uma vez: é ele que instala os
  comandos de linha.
- **Nem o aplicativo existe** → baixe a versão **Apple Silicon** (não Intel) em
  docker.com/products/docker-desktop e arraste para Aplicativos.

Conta no Docker Hub não tem relação com isso: ela serve para baixar imagens
privadas, e a do GROBID é pública.

Depois que o comando responder, o próximo erro possível é
`Cannot connect to the Docker daemon`. Aí o `PATH` está certo e o que falta é o
Docker Desktop estar **aberto** — ele é quem roda o serviço.

Se o Docker Desktop incomodar, `brew install colima docker` é uma alternativa
mais leve e só de linha de comando (`colima start` e pronto). E o GROBID também
roda sem Docker nenhum, direto do código-fonte com Java — mais trabalhoso, mas
é saída se nada der certo.

### Conferir

```bash
curl http://localhost:8070/api/isalive      # responde "true"
```

A interface em `http://localhost:8070` aceita um PDF arrastado e mostra o TEI
resultante — bom para olhar com os próprios olhos o que o pipeline vai receber.

### Quando o PDF é digitalizado

GROBID não faz OCR. Artigo antigo escaneado sai quase vazio. O `config.yml` já
prevê `ocr: "ocrmypdf"`; instalar com `brew install ocrmypdf`. O
`verificar_infra()` avisa quando um PDF devolve menos de cinco trechos, que é o
sintoma.

## 4. Conferir tudo

```r
source("R/diagnostico.R")
verificar_infra()                          # sem tocar em PDF
verificar_infra(pdf = "pdf/exemplo.pdf")   # inclui o teste do GROBID
```

Sete checagens: pacotes, chave, ids de modelo conferidos contra a sua chave, uma
chamada real com saída estruturada, GROBID vivo (e um PDF de verdade, se você
passar um), banco abre e escreve, e quais traits estão liberados para extração.

A quarta checagem é a que importa mais do que parece: ela não testa só se a
chave funciona, testa se a **saída estruturada** funciona e se o trecho devolvido
existe literalmente no texto. Essa validação de span é a única barreira
automática do pipeline contra valor inventado. Se ela falhar aqui, falha na
extração.

## 5. Ordem sugerida

1. Chave no `.Renviron`, limite de gasto na conta.
2. `verificar_infra()` — vai reclamar dos modelos.
3. Preencher os quatro ids no `config.yml`, rodar de novo.
4. Subir o GROBID, rodar de novo.
5. Pôr um PDF conhecido em `pdf/` e rodar `verificar_infra(pdf = ...)`.
6. Teste de fumaça: **um** artigo, ponta a ponta, conferindo registro a registro.

Com `eyes_positioning` e `snout_shape_lv` fechados, o passo 6 já tem o que
extrair. `cloacal_opening` e `lower_jaw_shape` entram quando as quatro
pendências voltarem.

## Custo

Não dá para prever sem medir — depende do tamanho dos artigos, de quantos
trechos cada trait recupera e de quanto o escalonamento é acionado. Por isso o
piloto mede custo e tempo **por artigo** antes de qualquer rodada grande. A
conta de guardanapo com os preços acima dá na casa de centavos de dólar por
artigo por trait no agente de valor, mas o número que vale é o medido.

---

Fontes dos ids e preços: documentação de modelos da Anthropic
(https://platform.claude.com/docs/en/models/overview). Comandos e recomendação
de memória do GROBID: https://grobid.readthedocs.io/en/latest/Grobid-docker/
