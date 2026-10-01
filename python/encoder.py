# Encoder local: faz o volume da extracao categorica sem chamar API (item 12).
# Multilingue de proposito (item 9): os artigos estao em pt, es e en, e
# traduzir antes de extrair perde precisao.
#
# Chamado do R por reticulate (R/extracao.R). Rodar o fine-tuning uma vez:
#   python python/encoder.py treinar modelo/treino.csv modelo/xlmr-girinos
#
# O checkpoint base e um parametro de propósito: escolha um encoder
# multilingue disponivel no HuggingFace e registre o id exato no config.yml,
# porque ele entra na proveniencia de cada valor extraido.

import json
import os
import sys

import numpy as np
import pandas as pd
import torch
from transformers import (AutoModelForSequenceClassification, AutoTokenizer,
                          Trainer, TrainingArguments)

BASE = os.environ.get("ENCODER_BASE", "xlm-roberta-base")


class Conjunto(torch.utils.data.Dataset):
    def __init__(self, enc, y):
        self.enc, self.y = enc, y

    def __len__(self):
        return len(self.y)

    def __getitem__(self, i):
        item = {k: torch.tensor(v[i]) for k, v in self.enc.items()}
        item["labels"] = torch.tensor(self.y[i])
        return item


def treinar(csv_treino, saida, epocas=4):
    """csv com colunas: texto, trait_id, rotulo, veredito.

    Usa so o que passou por revisor humano - inclusive o que o revisor marcou
    como errado, com o rotulo corrigido. E o ciclo de aprendizado ativo.
    """
    d = pd.read_csv(csv_treino).dropna(subset=["texto", "rotulo"])
    for trait_id, g in d.groupby("trait_id"):
        classes = sorted(g["rotulo"].astype(str).unique())
        idx = {c: i for i, c in enumerate(classes)}
        tok = AutoTokenizer.from_pretrained(BASE)
        enc = tok(list(g["texto"]), truncation=True, padding=True, max_length=512)
        y = [idx[str(v)] for v in g["rotulo"]]

        modelo = AutoModelForSequenceClassification.from_pretrained(
            BASE, num_labels=len(classes))
        destino = os.path.join(saida, trait_id)
        Trainer(
            model=modelo,
            args=TrainingArguments(output_dir=destino + "/_tmp",
                                   num_train_epochs=epocas,
                                   per_device_train_batch_size=8,
                                   learning_rate=2e-5,
                                   logging_steps=50,
                                   save_strategy="no"),
            train_dataset=Conjunto(enc, y),
        ).train()

        os.makedirs(destino, exist_ok=True)
        modelo.save_pretrained(destino)
        tok.save_pretrained(destino)
        with open(os.path.join(destino, "classes.json"), "w") as f:
            json.dump(classes, f)
        print(f"{trait_id}: {len(g)} exemplos, {len(classes)} classes -> {destino}")


def carregar_modelo(diretorio):
    """Devolve um dicionario trait_id -> (tokenizer, modelo, classes)."""
    modelos = {}
    if not os.path.isdir(diretorio):
        return modelos
    for trait_id in os.listdir(diretorio):
        d = os.path.join(diretorio, trait_id)
        if not os.path.isfile(os.path.join(d, "classes.json")):
            continue
        with open(os.path.join(d, "classes.json")) as f:
            classes = json.load(f)
        modelos[trait_id] = (AutoTokenizer.from_pretrained(d),
                             AutoModelForSequenceClassification.from_pretrained(d).eval(),
                             classes)
    return modelos


def prever_categorico(modelos, textos, trait_id):
    """Classe mais provavel e sua probabilidade, por texto.

    Trait sem modelo treinado devolve probabilidade 0: o R entende isso como
    'nao sei' e manda o trecho para o LLM.
    """
    if isinstance(textos, str):
        textos = [textos]
    if trait_id not in modelos:
        return {"classe": [None] * len(textos), "prob": [0.0] * len(textos)}

    tok, modelo, classes = modelos[trait_id]
    enc = tok(list(textos), truncation=True, padding=True,
              max_length=512, return_tensors="pt")
    with torch.no_grad():
        p = torch.softmax(modelo(**enc).logits, dim=-1).numpy()
    return {"classe": [classes[i] for i in p.argmax(axis=1)],
            "prob": [float(v) for v in p.max(axis=1)]}


if __name__ == "__main__":
    if len(sys.argv) >= 4 and sys.argv[1] == "treinar":
        treinar(sys.argv[2], sys.argv[3])
    else:
        print(__doc__)
