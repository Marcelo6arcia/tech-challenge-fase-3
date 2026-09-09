# Arquitetura — ToggleMaster Fase 3

Este documento registra **o que foi construído e por quê**. Cada seção termina
com a decisão tomada e a alternativa descartada, porque em uma banca de avaliação
o raciocínio vale tanto quanto o resultado.

---

## 1. Visão geral

O ToggleMaster é uma plataforma de *feature flags* composta por cinco
microsserviços. A Fase 3 não muda a aplicação: muda **como ela chega ao ar**.

| Serviço | Linguagem | Dependência de dados | Papel |
|---|---|---|---|
| `auth-service` | Go | RDS PostgreSQL | Emite e valida API keys (SHA-256 no banco) |
| `flag-service` | Python | RDS PostgreSQL | CRUD das flags |
| `targeting-service` | Python | RDS PostgreSQL | Regras de segmentação (JSONB) |
| `evaluation-service` | Go | ElastiCache Redis + SQS | Decide se a flag está ligada para um usuário; publica o evento |
| `analytics-service` | Python | SQS + DynamoDB | Consome os eventos e persiste para análise |

Fluxo de uma avaliação:

```
cliente → Ingress → evaluation-service
                        ├─ cache Redis (TTL 30s)
                        ├─ flag-service      (miss)
                        ├─ targeting-service (miss)
                        └─ SQS ──► analytics-service ──► DynamoDB
```

---

## 2. Rede

- VPC `10.0.0.0/16`, duas Availability Zones.
- Duas subnets públicas (`10.0.0.0/24`, `10.0.1.0/24`) e duas privadas
  (`10.0.2.0/24`, `10.0.3.0/24`).
- Internet Gateway, route table pública e uma route table privada por AZ.
- VPC Flow Logs no CloudWatch, retenção de 7 dias.

**Decisão: NAT Gateway desligado por padrão.** Os nós do EKS ficam em subnet
pública com IP público e saem para a internet pelo IGW; RDS e ElastiCache ficam
em subnet privada, sem rota para a internet e com Security Group que só aceita
tráfego vindo do Security Group do cluster.

*Por quê:* um NAT Gateway custa cerca de US$ 32/mês por AZ mais o tráfego —
quase metade do custo do ambiente inteiro, para um laboratório que é destruído
ao fim de cada sessão. A postura de produção continua disponível: basta
`enable_nat_gateway = true`, e o módulo automaticamente move os nós para as
subnets privadas e cria as rotas.

*Alternativa descartada:* VPC Endpoints para ECR/S3/CloudWatch em vez de NAT.
Reduziria o custo, mas são quatro endpoints com cobrança por hora e por GB, e a
complexidade não se paga em um ambiente efêmero.

---

## 3. Cluster EKS

- Kubernetes 1.31, `authentication_mode = API_AND_CONFIG_MAP`.
- Managed Node Group com Launch Template próprio.
- Add-ons gerenciados: `vpc-cni`, `coredns`, `kube-proxy`, `metrics-server`.
- Logs de `api`, `audit` e `authenticator` no CloudWatch.

Dois detalhes do Launch Template merecem destaque:

- `http_tokens = required` força **IMDSv2**. Sem isso, um SSRF na aplicação
  conseguiria ler as credenciais da instância pelo endpoint de metadados.
- `http_put_response_hop_limit = 2` porque um pod está a um salto de rede a mais
  do que o host; com o padrão `1`, o SDK da AWS dentro do container não alcança
  o IMDS.

**Decisão: `metrics-server` como add-on gerenciado do EKS**, em vez do
`kubectl apply` da release do GitHub usado na Fase 2. O HPA depende dele, e um
componente instalado por script é exatamente o tipo de coisa que "não está no
código".

---

## 4. Identidade e permissões — o maior salto em relação à Fase 2

Na Fase 2, a role dos nós recebia `AmazonSQSFullAccess` e
`AmazonDynamoDBFullAccess`. Na prática, **qualquer pod do cluster** — inclusive
um comprometido — podia esvaziar a fila e escrever na tabela.

Na Fase 3 a role dos nós tem apenas o mínimo para ser um nó (`WorkerNodePolicy`,
`CNI_Policy`, `ECR ReadOnly`, `SSM`). Cada workload que precisa da AWS ganha uma
role própria via **IRSA**:

| ServiceAccount | Permissões |
|---|---|
| `togglemaster/evaluation-service` | `sqs:SendMessage` **apenas** na fila do projeto |
| `togglemaster/analytics-service` | `sqs:ReceiveMessage`/`DeleteMessage` na fila + `dynamodb:PutItem`/`Query` **apenas** na tabela do projeto |
| `external-secrets/external-secrets` | `secretsmanager:GetSecretValue` **apenas** nos 6 segredos do projeto |

A condição de trust amarra a role a um `system:serviceaccount:<ns>:<sa>`
específico: nem outro namespace nem outro ServiceAccount conseguem assumi-la.

---

## 5. Gestão de segredos

O enunciado cita "credenciais do banco passadas em arquivos de texto sem
segurança". O caminho escolhido elimina a categoria inteira do problema:

```
Terraform                    AWS Secrets Manager          Cluster EKS
─────────                    ───────────────────          ───────────
random_password    ──put──►  togglemaster/dev/...   ◄─get─  External Secrets
(nunca sai do state                                          Operator (IRSA)
 cifrado no S3)                                                   │
                                                                  ▼
                                                          Secret do Kubernetes
                                                                  │
                                                                  ▼
                                                            envFrom no pod
```

- As senhas do RDS são geradas por `random_password` e nunca são digitadas por
  ninguém.
- Nenhum `terraform output` expõe senha.
- O repositório GitOps versiona o **ExternalSecret** (a referência), nunca o
  Secret com valor.
- A `SERVICE_API_KEY` do `evaluation-service` é gerada pelo Terraform; o
  `auth-service` recebe apenas o SHA-256 dela, cadastrado pelo Job de bootstrap.
  A chave em claro nunca toca o cluster fora do Secret injetado.

*Alternativa descartada:* Sealed Secrets ou SOPS. Ambos funcionam, mas guardam
o segredo cifrado **no Git** — se a chave privada vazar, todo o histórico vaza
junto. O Secrets Manager mantém o segredo fora do repositório desde o começo,
com rotação e auditoria pelo CloudTrail.

---

## 6. Estado do Terraform

Backend S3 com:

- versionamento (permite voltar um state corrompido),
- criptografia AES-256 em repouso,
- bloqueio total de acesso público,
- bucket policy negando qualquer requisição sem TLS,
- expiração de versões antigas em 90 dias,
- **`use_lockfile = true`** — lock nativo do S3, disponível a partir do
  Terraform 1.10, que dispensa a tabela DynamoDB historicamente usada para isso.

A configuração do backend é **parcial** (`backend "s3" {}`): o nome do bucket
entra via `-backend-config=backend.hcl`. Assim nada específico da conta fica
versionado, e o mesmo código serve para qualquer conta.

**Decisão: dois states, `infra` e `platform`.** Os providers `helm` e
`kubernetes` precisam do endpoint e do token do cluster para se configurarem. Se
estivessem no mesmo state que cria o cluster, o Terraform tentaria configurar o
provider com valores desconhecidos durante o `plan` — o erro clássico de
*provider configuration with unknown values*. Separar em camadas resolve isso
sem gambiarra de `-target` e ainda permite recriar a plataforma sem tocar nos
bancos.

---

## 7. Pipeline DevSecOps

Detalhado em [`DEVSECOPS.md`](DEVSECOPS.md). Em resumo, para cada um dos cinco
serviços, a cada Pull Request e a cada push na `main`:

```
build & unit test ─┐
lint               ├─► build da imagem → scan do container → push no ECR → commit no GitOps
SAST               │
SCA                ─┘
```

Os quatro primeiros jobs rodam em paralelo; o build da imagem só começa se os
quatro passarem. **Um achado CRITICAL em qualquer um deles impede o push da
imagem** — logo, impede o deploy, porque o Argo CD só implanta o que existe no
registry.

**Decisão: autenticação na AWS por OIDC**, sem `AWS_ACCESS_KEY_ID` nos secrets
do repositório. Uma chave estática vazada continua válida até alguém revogar;
um token OIDC dura minutos e só é emitido para os repositórios e refs declarados
na condição de trust da role.

---

## 8. GitOps

Dois repositórios:

| Repositório | Responde à pergunta |
|---|---|
| `tech-challenge-fase-3` | *Como este software é construído?* |
| `togglemaster-gitops` | *O que está rodando agora no cluster?* |

O CI **nunca** roda `kubectl`. Ele termina com um `kustomize edit set image` e um
commit. O Argo CD observa o repositório GitOps e sincroniza o cluster.

Consequências práticas:

- `git log` do repositório GitOps é o histórico de deploys, com autor e data.
- Rollback é `git revert`.
- `selfHeal: true` desfaz qualquer alteração manual feita com `kubectl` —
  a máquina do desenvolvedor deixa de ser um caminho para produção.
- O `ApplicationSet` com gerador de diretórios cria uma Application por pasta em
  `apps/overlays/dev/*`. Um sexto microsserviço é uma pasta nova, sem alteração
  de configuração do Argo CD.

**Decisão: Kustomize em vez de Helm.** O comando `kustomize edit set image` é a
forma oficial de trocar a tag, e o diff que aparece na UI do Argo CD mostra o
objeto Kubernetes final — não um template a ser renderizado. Em uma demonstração,
isso é a diferença entre mostrar o mecanismo e mostrar uma caixa-preta.

---

## 9. Endurecimento das aplicações

| Item | Fase 2 | Fase 3 |
|---|---|---|
| Base Python | `python:3.11-slim` | `python:3.12-slim` |
| Base Go | `golang:1.21` / `alpine:latest` | `golang:1.23` / `alpine:3.21` |
| Usuário do container | root | UID 10001, sem privilégio |
| Sistema de arquivos | leitura/escrita | `readOnlyRootFilesystem: true` |
| Capabilities | padrão | `drop: [ALL]` |
| Probes | readiness + liveness | + `startupProbe` |
| Disponibilidade | — | PodDisruptionBudget e topology spread por AZ |
| Flask / Werkzeug / gunicorn / requests | versões com CVE conhecido | versões corrigidas |

A troca de SHA-1 por SHA-256 no `getDeterministicBucket` do
`evaluation-service` veio de um achado do gosec (regra G505). O uso não era
criptográfico e o risco real era nulo, mas manter SHA-1 no código deixaria um
alerta permanente no pipeline — e um alerta que a equipe aprende a ignorar é
pior do que alerta nenhum.

---

## 10. O que ficou de fora, e por quê

- **Multi-AZ no RDS e Redis em modo cluster.** Dobrariam o custo sem acrescentar
  nada à avaliação. As flags existem nos módulos (`multi_az`).
- **AWS Load Balancer Controller com Ingress do tipo ALB.** O ingress-nginx com
  NLB atende o roteamento por prefixo exigido e tem menos partes móveis.
- **Cosign / assinatura de imagens.** O SBOM em CycloneDX já é gerado e
  publicado como artefato; a assinatura seria o passo seguinte natural em um
  ambiente com política de admissão.
- **Prometheus e Grafana.** Fora do escopo desta fase; o `metrics-server` cobre
  o que o HPA precisa.
