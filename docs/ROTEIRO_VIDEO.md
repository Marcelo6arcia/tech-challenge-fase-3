# Roteiro do vídeo — 20 minutos

O enunciado pede quatro blocos: **IaC**, **pipeline DevSecOps falhando e
passando**, **GitOps** e **Argo CD sincronizando**. O roteiro abaixo cobre os
quatro com folga e deixa margem para imprevisto.

> Grave com o ambiente **já provisionado**. `terraform apply` do EKS leva 15
> minutos e não cabe no tempo — mostre o `plan` ao vivo e o resultado na AWS.

---

## Antes de gravar — checklist

- [ ] `terraform apply` concluído; `kubectl get nodes` respondendo
- [ ] Argo CD com as 7 Applications `Synced`/`Healthy` (root, platform, 5 serviços)
- [ ] Branch `demo/vulnerabilidade` **preparada mas não enviada**
- [ ] Abas abertas: console AWS (VPC, EKS, RDS, ECR), GitHub Actions, repositório GitOps, UI do Argo CD, dois terminais
- [ ] Zoom do terminal aumentado (fonte 16pt ou mais)
- [ ] `./scripts/smoke-test.sh` testado antes, para não descobrir problema no ar

---

## 0:00 – 1:30 · Abertura

Nome dos integrantes, RMs e o problema da fase, na linguagem do enunciado:

> "A DevOps Solutions Inc. aprovou a arquitetura da Fase 2, mas a operação ficou
> insustentável: deploy manual da máquina de cada dev, senha em arquivo de
> texto, biblioteca vulnerável indo para produção e homologação que leva dias
> para ser recriada. A ordem é: se não está no código, não existe."

Mostre o diagrama do `README.md` e anuncie os quatro blocos.

---

## 1:30 – 6:00 · Bloco 1: Infraestrutura como Código

**Estrutura (1 min)**

```bash
# `tree` nao vem no macOS. Instale antes (brew install tree) ou use:
find terraform -maxdepth 3 -not -path '*/.terraform/*' | sort
```

Aponte: `bootstrap/` (o state), `modules/` (10 módulos reutilizáveis) e
`envs/dev/` dividido em `infra` e `platform`. Explique em uma frase por que são
dois states: os providers `helm` e `kubernetes` precisam do cluster já existindo.

**Backend remoto (1 min)**

Abra `terraform/envs/dev/infra/versions.tf` e mostre `backend "s3" {}` com a
configuração parcial. Depois o `backend.hcl`:

```hcl
bucket       = "togglemaster-tfstate-a1b2c3d4"
key          = "togglemaster/dev/infra.tfstate"
use_lockfile = true
```

Frase-chave: *"o state não é mais local; o lock é nativo do S3, sem tabela
DynamoDB."* Mostre o bucket no console, com versionamento e criptografia
ligados.

**Plan ao vivo (1,5 min)**

```bash
cd terraform/envs/dev/infra
terraform plan
```

Com tudo aplicado, aparece `No changes`. É exatamente o que queremos mostrar:
**o código descreve o ambiente real**. Se preferir mostrar movimento, altere
`node_desired_size` de 3 para 4 e rode o plan — 1 recurso a modificar.

> **Confira antes de gravar.** `No changes` só aparece se nao houver apply
> pendente. Rode `terraform -chdir=terraform/envs/dev/infra plan` e confirme.
> Se sobrar mudanca, ou aprove o `Terraform Apply` que estiver parado no
> environment `aws-dev`, ou troque a fala — um plan com pendencia contradiz a
> frase "o codigo descreve o ambiente real" na frente do avaliador.

**Resultado na AWS (1,5 min)**

No console, passe rápido por: VPC com 4 subnets, cluster EKS, 3 instâncias RDS,
ElastiCache, DynamoDB, SQS + DLQ e os 5 repositórios ECR. Todos com a tag
`ManagedBy = Terraform`.

Feche o bloco no Secrets Manager, mostrando `togglemaster/dev/auth-service/database`:

> "A senha foi gerada pelo Terraform e ninguém nunca a digitou. Ela não está no
> repositório, não está em YAML e não aparece em `terraform output`."

---

## 6:00 – 12:00 · Bloco 2: Pipeline DevSecOps

**Anatomia (1,5 min)**

Abra `.github/workflows/_reusable-ci.yml` e percorra os seis jobs. Destaque as
duas passagens do Trivy: a de relatório e a porta de qualidade que bloqueia em
`CRITICAL`.

Mostre um run verde recente e o grafo dos jobs.

**A falha (3 min)**

```bash
./scripts/demo-vulnerabilidade.sh inserir flag-service
git diff
```

Uma linha: `PyYAML==5.3.1`.

```bash
git checkout -b demo/vulnerabilidade
git commit -am "test: dependencia com CVE critica"
git push -u origin demo/vulnerabilidade
```

Abra o Pull Request. Enquanto o pipeline roda, explique a diferença entre SCA
(dependência de terceiro) e SAST (código escrito pela equipe).

Quando o job **SCA** ficar vermelho, abra o log e aponte na tabela do Trivy:

```
pyyaml  CVE-2020-14343  CRITICAL  5.3.1  ->  5.4
```

Volte ao grafo do workflow: `image` e `update-gitops` em cinza.

> "A imagem não foi construída, não foi publicada e não chegou ao repositório
> GitOps. O deploy foi bloqueado por uma dependência vulnerável — exatamente o
> caso que a empresa relatou como acidente na Fase 2."

Confirme no ECR que não há tag nova.

**A correção (1,5 min)**

```bash
./scripts/demo-vulnerabilidade.sh corrigir flag-service
git commit -am "fix: sobe PyYAML para 6.0.2, corrigindo a CVE-2020-14343"
git push
```

> **Use `corrigir`, e nunca `remover`, aqui.** `remover` desfaz exatamente o que
> `inserir` fez, então o saldo líquido do Pull Request é **zero**: o merge na
> `main` não altera arquivo nenhum, os workflows filtram por `paths`, nenhum
> filtro casa e **o pipeline da main não roda**. O Bloco 3 fica sem o commit de
> deploy para mostrar — foi o que aconteceu no primeiro ensaio.
>
> `corrigir` sobe a dependência para a versão com patch. O saldo passa a ser
> real, o merge dispara o pipeline inteiro, a imagem vai para o ECR e o commit
> aparece no repositório GitOps.
>
> E a fala fica melhor: a resposta a uma CVE é **subir a dependência**, não
> remover a dependência nem afrouxar o portão. É a regra 4 do `CLAUDE.md` na
> prática.
>
> O `remover` continua existindo para a limpeza depois da gravação.

Mesmo Pull Request, agora verde. Merge na `main`.

---

## 12:00 – 16:00 · Bloco 3: GitOps

**O commit automático (1,5 min)**

Com o merge, o pipeline da `main` roda por inteiro. No job `update-gitops`,
mostre o log:

```
kustomize edit set image flag-service=<conta>.dkr.ecr.us-east-1.amazonaws.com/flag-service:v1.0.0-a1b2c3d
[main abc1234] deploy(flag-service): v1.0.0-a1b2c3d
```

**No repositório GitOps (1,5 min)**

Abra o commit `deploy(flag-service): v1.0.0-a1b2c3d`. O diff tem duas linhas:

```diff
   - name: flag-service
     newName: 123456789012.dkr.ecr.us-east-1.amazonaws.com/flag-service
-    newTag: v1.0.0-0000000
+    newTag: v1.0.0-a1b2c3d
```

> "Este é o deploy inteiro. O pipeline não roda `kubectl` em nenhum momento — ele
> faz um commit. E o `git log` deste repositório é o histórico de deploys, com
> autor, data e o commit de origem."

**Separação de responsabilidades (1 min)**

Mostre lado a lado: `tech-challenge-fase-3` responde *como o software é
construído*; `togglemaster-gitops` responde *o que está rodando agora*.

Mostre também o `ApplicationSet`: uma Application por pasta em
`apps/overlays/dev/*`. Um sexto microsserviço seria uma pasta nova.

---

## 16:00 – 19:00 · Bloco 4: Argo CD sincronizando

**A UI (1 min)**

Mostre as 7 Applications e abra a árvore de recursos do **evaluation-service**:
Deployment, Service, ConfigMap, ServiceAccount, HPA, PDB.

> Abra esta e nao outra: `evaluation-service` e o unico servico que tem HPA
> **e** PDB ao mesmo tempo. HPA existe so nele e no analytics-service; o
> analytics nao tem PDB, porque roda com uma replica so.

**A sincronização ao vivo (1,5 min)**

Com a UI aberta, a Application vai para `OutOfSync` — mas **isso leva ate 3
minutos**, nao 30 segundos: `timeout.reconciliation` no `argocd-cm` esta em
`180s` e nao ha webhook configurado. Tres minutos de silencio no ar sao
mortais, entao **clique em Refresh na UI** para forcar a checagem na hora, ou
encha o tempo explicando o ApplicationSet enquanto espera. Abra o **App Diff** — a única diferença é a tag da imagem. Em
seguida ela sincroniza sozinha e volta a `Synced`/`Healthy`, com o rolling
update dos pods visível na árvore.

```bash
kubectl -n togglemaster get pods -w
```

**Self-heal (30 s) — o momento mais forte da demonstração**

```bash
kubectl -n togglemaster scale deploy/flag-service --replicas=5
```

O Argo CD detecta a divergência e volta para 2 réplicas sozinho.

> "Isto é o fim do `kubectl apply` da máquina do desenvolvedor: qualquer
> alteração fora do Git é desfeita. O Git é a fonte da verdade, não um espelho
> dela."

---

## 19:00 – 20:00 · Fechamento

Cinco itens, um de cada vez:

1. Infraestrutura inteira em Terraform modular, state remoto com lock nativo.
2. Pipeline DevSecOps com quatro portas de qualidade; CRITICAL bloqueia o deploy.
3. Sem chave estática da AWS no CI — federação OIDC.
4. Sem senha em texto — Secrets Manager + External Secrets + IRSA por workload.
5. Deploy é commit; rollback é `git revert`; desvio manual é revertido sozinho.

Encerre com o custo estimado (`docs/CUSTOS.md`) e os links do repositório.

---

## Plano B

| Se falhar | Faça |
|---|---|
| Pipeline demora demais | Mostre um run anterior já concluído (grave-o antes) |
| Argo CD não sincroniza na hora | Clique em **Refresh**: o polling e de 180 s (`timeout.reconciliation`), entao esperar e ruim no ar |
| NLB fora do ar | Use `kubectl port-forward` direto no Service do serviço |
| Internet instável | Tenha gravado à parte um clipe de cada bloco crítico |
