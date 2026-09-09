# ToggleMaster — Tech Challenge Fase 3

Plataforma de *Feature Flag as a Service* da DevOps Solutions Inc. (empresa
fictícia), agora com infraestrutura imutável, pipelines DevSecOps e entrega
contínua por GitOps.

> **Regra da fase:** *"Se não está no código, não existe."*
> Nenhum recurso é criado pelo console, nenhum `kubectl apply` sai de máquina de
> desenvolvedor e nenhuma senha existe em arquivo de texto.

---

## O problema que a Fase 3 resolve

| Dor levantada no enunciado | Como foi resolvida |
|---|---|
| Devs rodando `kubectl apply` da máquina local | Argo CD é o único ator com acesso de escrita ao cluster. O CI apenas faz commit no repositório GitOps. |
| Credenciais de banco em arquivo de texto | Senhas geradas pelo Terraform, guardadas no AWS Secrets Manager e injetadas em runtime pelo External Secrets Operator. Nenhum segredo no Git. |
| Vulnerabilidade em biblioteca Go que foi para produção | Pipeline com SCA (Trivy), SAST (gosec/bandit) e scan de container. Achado CRITICAL derruba o build antes do push da imagem. |
| Ambiente de homologação leva dias para ser recriado | `terraform apply` recria toda a infraestrutura. Backend remoto em S3 com lock nativo. |

---

## Arquitetura em uma tela

```
 Pull Request ─┐
               │   GitHub Actions (CI + DevSecOps)
 Push na main ─┤   build → lint → SAST → SCA → docker build → scan → push ECR
               │                                                        │
               │                                          commit da nova tag
               ▼                                                        ▼
        terraform.yml                                    repo togglemaster-gitops
   plan no PR / apply na main                             (Kustomize, sem segredos)
               │                                                        │
               ▼                                                        │ watch
   ┌───────────────────────────────────────────────┐                   │
   │  AWS — tudo criado por Terraform              │◄──────────────────┘
   │                                               │        Argo CD
   │  VPC · 2 AZ · subnets públicas e privadas     │      (sync automático)
   │  EKS 1.31 + Managed Node Group                │
   │  3× RDS PostgreSQL · ElastiCache Redis        │
   │  DynamoDB · SQS (+DLQ) · 5× ECR               │
   │  Secrets Manager · IRSA por workload          │
   └───────────────────────────────────────────────┘
```

Detalhes e decisões em [`docs/ARQUITETURA.md`](docs/ARQUITETURA.md).

---

## Estrutura do repositório

```
tech-challenge-fase-3/
├── auth-service/            Go     — emissão e validação de API keys
├── flag-service/            Python — CRUD de feature flags
├── targeting-service/       Python — regras de segmentação
├── evaluation-service/      Go     — avaliação da flag (cache Redis, publica no SQS)
├── analytics-service/       Python — consome SQS e grava no DynamoDB
│
├── .github/workflows/
│   ├── _reusable-ci.yml     Pipeline DevSecOps (workflow reutilizável)
│   ├── ci-<servico>.yml     5 chamadores, um por microsserviço
│   └── terraform.yml        fmt, validate, tflint, Checkov, plan no PR, apply na main
│
├── terraform/
│   ├── bootstrap/           Bucket S3 do state remoto (roda uma vez)
│   ├── modules/             network · eks · rds · elasticache · dynamodb
│   │                        sqs · ecr · irsa · github-oidc · gitops
│   └── envs/dev/
│       ├── infra/           Rede, cluster, dados, registries, IAM
│       └── platform/        Argo CD, ingress-nginx, External Secrets
│
├── docs/                    Arquitetura, runbook, DevSecOps, roteiro do vídeo
├── scripts/                 bootstrap, smoke test, demo de vulnerabilidade, destroy
└── docker-compose.yml       Ambiente local (9 containers)
```

Os manifestos Kubernetes **não** ficam aqui: eles vivem no repositório
[`togglemaster-gitops`](https://github.com/Marcelo6arcia/togglemaster-gitops).
Essa separação é o coração do GitOps — o repositório de aplicação descreve
*como construir*, o de GitOps descreve *o que está rodando*.

---

## Começando

Pré-requisitos: Terraform ≥ 1.10, AWS CLI v2, kubectl, Docker, Git e uma conta
AWS com permissão para criar IAM.

```bash
# 1. Backend remoto (uma única vez)
cd terraform/bootstrap
terraform init && terraform apply
terraform output backend_config_snippet   # copie para ../envs/dev/infra/backend.hcl

# 2. Infraestrutura
cd ../envs/dev/infra
cp terraform.tfvars.example terraform.tfvars   # ajuste github_owner e state_bucket_name
terraform init -backend-config=backend.hcl
terraform plan
terraform apply

# 3. Plataforma (Argo CD, ingress, External Secrets)
cd ../platform
cp terraform.tfvars.example terraform.tfvars
terraform init -backend-config=backend.hcl
terraform apply
```

O passo a passo completo, incluindo a configuração dos secrets do GitHub e a
validação ponta a ponta, está em [`docs/RUNBOOK.md`](docs/RUNBOOK.md).

---

## Ambiente local

```bash
cp .env.example .env    # preencha DB_PASSWORD e MASTER_KEY
docker compose up --build
```

Sobe 9 containers: os 5 microsserviços, 2 PostgreSQL, 1 Redis e o LocalStack
(SQS + DynamoDB).

---

## Testes

```bash
# Go
cd auth-service       && go test ./... -race -cover
cd evaluation-service && go test ./... -race -cover

# Python
cd flag-service && pip install -r requirements-dev.txt && pytest
```

Os mesmos comandos rodam no pipeline, no job `Build & Unit Test`.

---

## Documentação

| Documento | Conteúdo |
|---|---|
| [`docs/ARQUITETURA.md`](docs/ARQUITETURA.md) | Decisões de arquitetura e o porquê de cada uma |
| [`docs/DEVSECOPS.md`](docs/DEVSECOPS.md) | Estágios do pipeline, ferramentas e regra de bloqueio |
| [`docs/RUNBOOK.md`](docs/RUNBOOK.md) | Passo a passo de provisionamento e operação |
| [`docs/ROTEIRO_VIDEO.md`](docs/ROTEIRO_VIDEO.md) | Roteiro cronometrado da demonstração |
| [`docs/CUSTOS.md`](docs/CUSTOS.md) | Estimativa de custo mensal na AWS |
| [`docs/CHECKLIST_ENTREGA.md`](docs/CHECKLIST_ENTREGA.md) | Requisito por requisito, com o arquivo que o comprova |
| [`docs/ENUNCIADO_FASE_3.md`](docs/ENUNCIADO_FASE_3.md) | Enunciado original da fase |
