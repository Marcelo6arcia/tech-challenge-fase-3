# Runbook — do zero ao cluster sincronizado

Tempo total: cerca de **40 minutos**, dos quais ~20 são o EKS subindo.

Pré-requisitos: Terraform ≥ 1.10, AWS CLI v2 configurado, kubectl, Docker,
Git, Go ≥ 1.23 e Python ≥ 3.12 (só para rodar os testes localmente).

---

## Passo 0 — Preparar os dois repositórios no GitHub

```bash
# Repositório de aplicação + IaC + CI
cd ~/Documents/fiap/tech-challenge-fase-3
git init && git add . && git commit -m "feat: Fase 3 - IaC, DevSecOps e GitOps"
gh repo create tech-challenge-fase-3 --public --source=. --push

# Repositório GitOps (só manifestos)
cd ~/Documents/fiap/togglemaster-gitops
git init && git add . && git commit -m "feat: manifestos GitOps do ToggleMaster"
gh repo create togglemaster-gitops --public --source=. --push
```

> O repositório GitOps público simplifica a demonstração — o Argo CD não precisa
> de credencial para lê-lo. Sendo privado, ligue `gitops_repo_private = true` na
> camada `platform` e informe um PAT de leitura.

**Rode `terraform fmt` antes do primeiro push.** O pipeline de IaC checa
formatação e falha com qualquer desalinhamento:

```bash
terraform fmt -recursive terraform/
```

**Gere o `go.sum` dos serviços Go antes do primeiro push.** O código herdado das
fases anteriores veio sem `go.sum` no `auth-service` e com um incompleto no
`evaluation-service`.

```bash
cd auth-service       && go mod tidy && cd ..
cd evaluation-service && go mod tidy && cd ..
git add */go.sum */go.mod && git commit -m "chore: atualiza dependencias Go"
```

Sem o Go instalado na máquina, a imagem oficial resolve — só é preciso Docker:

```bash
for svc in auth-service evaluation-service; do
  docker run --rm -v "$PWD/$svc":/src -w /src golang:1.25-alpine go mod tidy
done
```

Por que isso importa: com o `go.sum` versionado, o CI roda `go mod download`,
que **verifica o checksum** de cada módulo baixado. Sem ele, o pipeline cai
para `go mod tidy` e aceita o que o proxy de módulos servir — o job emite um
aviso explícito quando isso acontece.

---

## Passo 1 — Backend remoto do Terraform

```bash
cd terraform/bootstrap
terraform init
terraform apply
terraform output backend_config_snippet
```

Copie a saída para `terraform/envs/dev/infra/backend.hcl` e ajuste o `key` para
`togglemaster/dev/infra.tfstate`. Faça o mesmo em
`terraform/envs/dev/platform/backend.hcl` com `.../platform.tfstate`.

O script `./scripts/bootstrap.sh` faz os passos 1 a 3 encadeados, gerando os
dois `backend.hcl` automaticamente.

---

## Passo 2 — Infraestrutura

```bash
cd terraform/envs/dev/infra
cp terraform.tfvars.example terraform.tfvars
# ajuste: github_owner, github_app_repo, state_bucket_name, aws_profile

terraform init -backend-config=backend.hcl
terraform plan      # é este plan que vai para o vídeo
terraform apply
```

Cria: VPC com 2 AZs, EKS 1.31 + node group, 3 RDS PostgreSQL, ElastiCache Redis,
DynamoDB, SQS com DLQ, 5 repositórios ECR, provider OIDC do GitHub, 3 roles IRSA
e 6 segredos no Secrets Manager.

O EKS leva de 12 a 18 minutos. As instâncias RDS sobem em paralelo.

```bash
aws eks update-kubeconfig --region us-east-1 --profile fiap \
  --name "$(terraform output -raw eks_cluster_name)" \
  --alias togglemaster-dev

kubectl config current-context   # precisa dizer: togglemaster-dev
kubectl get nodes
```

> **O `--profile fiap` nao e opcional.** Ele nao afeta so este comando: o
> `update-kubeconfig` grava o profile DENTRO do contexto, como
> `env: AWS_PROFILE`, e e esse valor que o `kubectl` usa depois para pedir o
> token. Sem a flag, o contexto nasce amarrado ao profile padrao da maquina.
>
> O sintoma e confuso: `aws sts get-caller-identity --profile fiap` responde
> certo, o `update-kubeconfig` falha com "Token has expired and refresh failed"
> referindo-se a OUTRO profile, e um `kubectl get nodes` pode ate funcionar --
> usando um contexto antigo que ja estava correto. Da a impressao de que esta
> tudo bem quando o contexto novo nasceu quebrado.
>
> Confira com:
> `kubectl config view --minify --context=togglemaster-dev -o json | jq '.users[0].user.exec.env'`

> O `--alias` não é cosmético. Sem ele o contexto fica com o ARN do cluster, e
> numa máquina com vários EKS na mesma região é fácil rodar um `kubectl delete`
> no cluster errado. O `scripts/destroy.sh` recusa rodar se o contexto ativo não
> for `togglemaster-dev`.

---

## Passo 3 — Plataforma

```bash
cd ../platform
cp terraform.tfvars.example terraform.tfvars
# preencha infra_state_config com o bucket do passo 1
# e gitops_repo_url com a URL do seu repositório GitOps

terraform init -backend-config=backend.hcl
terraform apply
```

Instala ingress-nginx (com NLB), External Secrets Operator (autenticado por
IRSA), Argo CD e a Application raiz que aponta para `argocd/applications` do
repositório GitOps.

Verificação:

```bash
kubectl -n argocd get pods
kubectl -n external-secrets get pods
kubectl -n ingress-nginx get svc            # anote o hostname do NLB
kubectl -n argocd get applications          # root, platform e os 5 serviços
```

Acesso à UI do Argo CD:

```bash
kubectl -n argocd port-forward svc/argocd-server 8080:80
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d; echo
# http://localhost:8080  — usuário: admin
```

---

## Passo 4 — Ajustar o repositório GitOps com os valores da conta

```bash
cd ../../..
terraform -chdir=terraform/envs/dev/infra output -json gitops_wiring
```

No repositório `togglemaster-gitops`, substitua `ACCOUNT_ID` pelo ID da conta em
todos os overlays:

```bash
cd ~/Documents/fiap/togglemaster-gitops
ACCOUNT_ID=123456789012
grep -rl 'ACCOUNT_ID' apps/ | xargs sed -i '' "s/ACCOUNT_ID/${ACCOUNT_ID}/g"   # macOS
# Linux: sed -i "s/ACCOUNT_ID/${ACCOUNT_ID}/g"

git commit -am "chore: aponta os overlays para o registry da conta"
git push
```

---

## Passo 5 — Secrets do GitHub

No repositório `tech-challenge-fase-3`, em *Settings → Secrets and variables →
Actions*:

| Secret | Valor |
|---|---|
| `AWS_ROLE_ARN` | `terraform -chdir=terraform/envs/dev/infra output -raw github_actions_role_arn` |
| `AWS_ROLE_ARN_APPLY` | `terraform -chdir=terraform/envs/dev/infra output -raw github_actions_apply_role_arn` |
| `TF_STATE_BUCKET` | `terraform -chdir=terraform/bootstrap output -raw state_bucket_name` |
| `GITOPS_TOKEN` | PAT fine-grained com **Contents: Read and write** em `togglemaster-gitops` |

Nao aponte `AWS_ROLE_ARN_APPLY` para a mesma role do `AWS_ROLE_ARN`. Sao duas
roles distintas de proposito: a de plan e somente leitura e roda em qualquer
push ou PR; a de apply so e assumivel pelo subject `environment:aws-dev`, ou
seja, depois da aprovacao manual. Igualar as duas anula o portao.

Na mesma tela, aba **Variables** (nao Secrets), crie:

| Variável | Valor |
|---|---|
| `PUBLIC_ACCESS_CIDRS` | `["SEU.IP.PUBLICO/32"]` — descubra com `curl -s https://checkip.amazonaws.com` |

Ela alimenta `TF_VAR_public_access_cidrs` e define quem alcanca o endpoint da
API do EKS. **Sem ela o `terraform plan` do CI reprova**, de proposito: o
modulo `eks` tem uma `validation` que barra lista vazia, porque lista vazia faz
o EKS aplicar `0.0.0.0/0` sem avisar. Nao vai para o `.tfvars` porque o arquivo
e gitignored e o valor e um IP residencial num repositorio publico.

Inclua o IP de **todo mundo que precisa de `kubectl`** — quem ficar de fora
perde acesso ao cluster assim que o apply rodar.

Em *Settings → Environments*, crie o environment **`aws-dev`** e marque
*Required reviewers* — é o que segura o `terraform apply` do pipeline.

---

## Passo 6 — Primeiro deploy pelo pipeline

Alterações em `<servico>/**` disparam só o pipeline daquele serviço. Um commit
vazio **nao dispara nada**: os workflows filtram por `paths`, e sem arquivo
alterado nenhum filtro casa.

Para publicar os cinco, use *Actions → CI &lt;servico&gt; → Run workflow* em cada
um, ou pela linha de comando:

```bash
cd ~/Documents/fiap/tech-challenge-fase-3
for s in auth flag targeting evaluation analytics; do
  gh workflow run "ci-$s-service.yml" --ref main
done
```

O `workflow_dispatch` na `main` publica no ECR e commita no repositorio GitOps,
igual a um push. Ate 2026-09-10 nao publicava — a condicao exigia
`event_name == 'push'` e o job terminava verde sem efeito.

Acompanhe:

1. **Actions** — os quatro jobs de validação em paralelo, depois `image` e
   `update-gitops`.
2. **Repositório GitOps** — um commit `deploy(<servico>): v1.0.0-<sha>` por
   serviço.
3. **Argo CD** — as Applications saem de `OutOfSync` para `Synced`/`Healthy`.

---

## Passo 7 — Validação ponta a ponta

```bash
./scripts/smoke-test.sh
```

Cria uma flag, uma regra de 100%, avalia para um usuário e confirma o evento no
DynamoDB.

Teste manual do HPA:

```bash
HOST=$(kubectl -n ingress-nginx get svc ingress-nginx-controller \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

kubectl -n togglemaster run carga --image=williamyeh/hey --restart=Never -- \
  -z 3m -c 50 "http://${HOST}/evaluation/evaluate?flag_name=minha-flag&user_id=u1"

watch kubectl -n togglemaster get hpa,pods
```

---

## Operação do dia a dia

| Necessidade | Como fazer |
|---|---|
| Publicar uma nova versão | commit na `main` do serviço; o resto é automático |
| Rollback | `git revert` do commit de deploy no repositório GitOps |
| Ver o que está rodando | `git log` do repositório GitOps, ou a UI do Argo CD |
| Trocar uma variável de ambiente | editar o `configmap.yaml` da base e commitar |
| Rotacionar a senha de um banco | `terraform taint 'module.rds_auth.random_password.master'` + apply; o ESO propaga em até 1h ou no próximo sync |
| Alterar a infraestrutura | Pull Request em `terraform/`; o plan aparece como comentário no PR |

---

## Problemas comuns

**Application `OutOfSync` que não sincroniza**
Veja `kubectl -n argocd logs deploy/argocd-repo-server`. Quase sempre é
`ACCOUNT_ID` não substituído no overlay, ou o `AppProject` não permitindo o
`repoURL`.

**Pod em `CreateContainerConfigError`**
O Secret ainda não foi materializado. Diagnostique com:
```bash
kubectl -n togglemaster get externalsecrets
kubectl -n togglemaster describe externalsecret <nome>
```
Se aparecer `AccessDenied`, a role IRSA do External Secrets não cobre o ARN do
segredo.

**`terraform destroy` travado na VPC**
Um Network Load Balancer criado pelo Kubernetes ainda existe. Rode
`./scripts/destroy.sh`, que apaga o Service do ingress e espera a AWS liberar o
NLB antes do destroy.

**Job `db-bootstrap` em `Error`**
Os bancos RDS ainda estavam subindo. O `backoffLimit: 10` cobre o caso; se
persistir, confira o Security Group do RDS e o `DATABASE_URL` no Secret.

**Pipeline falha no `golangci-lint` por `go.sum`**
Rode `go mod tidy` no serviço e commite o `go.sum` (ver Passo 0).
