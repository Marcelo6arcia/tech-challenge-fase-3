# Checklist de entrega — requisito por requisito

Cada linha do enunciado, com o artefato que a comprova. Use na revisão final e
como guia do que apontar no vídeo.

---

## 1. Infraestrutura como Código (Terraform)

| Requisito | Onde está | OK |
|---|---|:--:|
| Projeto organizado, preferencialmente com módulos | `terraform/modules/` — 10 módulos: network, eks, rds, elasticache, dynamodb, sqs, ecr, irsa, github-oidc, gitops | ☐ |
| VPC, subnets públicas e privadas, IGW, Route Tables | `terraform/modules/network/main.tf` | ☐ |
| Cluster EKS e Node Groups | `terraform/modules/eks/main.tf` | ☐ |
| 3 instâncias RDS PostgreSQL | `terraform/envs/dev/infra/main.tf` — módulo `rds` instanciado 3× | ☐ |
| 1 cluster ElastiCache Redis | `terraform/modules/elasticache/main.tf` | ☐ |
| 1 tabela DynamoDB | `terraform/modules/dynamodb/main.tf` | ☐ |
| 1 fila SQS | `terraform/modules/sqs/main.tf` (+ DLQ) | ☐ |
| 5 repositórios ECR (opcional, recomendado) | `terraform/modules/ecr/main.tf` | ☐ |
| **Backend remoto em bucket S3** | `terraform/envs/dev/*/versions.tf` + `terraform/bootstrap/` | ☐ |
| **`use_lockfile` para lock** | `backend.hcl.example` — `use_lockfile = true` | ☐ |
| Compatibilidade com LabRole (AWS Academy) | `terraform/modules/eks/variables.tf` — `create_iam_roles`, `cluster_role_arn`, `node_role_arn` | ☐ |

## 2. Pipeline de CI e DevSecOps

| Requisito | Onde está | OK |
|---|---|:--:|
| Workflow para cada um dos 5 microsserviços | `.github/workflows/ci-<servico>.yml` | ☐ |
| Roda a cada Pull Request e push na main | bloco `on:` de cada workflow | ☐ |
| **Build & Unit Test** | job `build-test`; testes em `key_test.go`, `evaluator_test.go`, `tests/` | ☐ |
| **Linter / Static Analysis** | job `lint` — golangci-lint (Go), flake8 + ruff (Python) | ☐ |
| **SCA** (dependências) | job `sca` — Trivy `fs` com scanners `vuln,secret` | ☐ |
| **SAST** (código-fonte) | job `sast` — gosec (Go), bandit (Python) | ☐ |
| **Regra de bloqueio: CRITICAL derruba o pipeline** | `severity: CRITICAL` + `exit-code: 1` nos passos de porta de qualidade | ☐ |
| Docker build | job `image`, `docker/build-push-action` | ☐ |
| **Scan de vulnerabilidade na imagem** | job `image` — Trivy `image`, bloqueia em CRITICAL | ☐ |
| Login no ECR | `aws-actions/amazon-ecr-login` (autenticação por OIDC) | ☐ |
| **Push com tag do commit hash** (`v1.0.0-a1b2c3d`) | step `Calcular a tag da imagem` | ☐ |

## 3. Entrega Contínua e GitOps

| Requisito | Onde está | OK |
|---|---|:--:|
| **Repositório GitOps separado** | `github.com/<owner>/togglemaster-gitops` | ☐ |
| Contém apenas manifestos Kubernetes | `apps/` (Kustomize) e `platform/` | ☐ |
| **Argo CD instalado no EKS** | `terraform/modules/gitops/main.tf` — `helm_release.argocd` | ☐ |
| **CI atualiza a tag no repositório GitOps** | job `update-gitops` — `kustomize edit set image` + commit | ☐ |
| **Argo CD monitora e sincroniza automaticamente** | `syncPolicy.automated` com `prune` e `selfHeal` | ☐ |
| **UI do Argo CD gerenciando os 5 microsserviços** | `ApplicationSet` em `argocd/applications/togglemaster-services.yaml` | ☐ |

## 4. Entregáveis

### Vídeo (até 20 min)

| Requisito | Bloco do roteiro | OK |
|---|---|:--:|
| `terraform plan`/`apply` ou o resultado na AWS | 1:30 – 6:00 | ☐ |
| Pipeline falhando no passo de segurança | 6:00 – 10:30 | ☐ |
| Correção e pipeline passando | 10:30 – 12:00 | ☐ |
| CI atualizando a tag no repositório GitOps | 12:00 – 16:00 | ☐ |
| Argo CD detectando e sincronizando | 16:00 – 19:00 | ☐ |

### Código-fonte

| Requisito | OK |
|---|:--:|
| Todo o Terraform, estruturado e componentizado | ☐ |
| Workflows do GitHub Actions com os passos DevSecOps | ☐ |
| Manifestos Kubernetes ajustados para GitOps | ☐ |

### Relatório (PDF ou TXT)

| Requisito | Onde | OK |
|---|---|:--:|
| Nomes dos participantes (e RMs) | `RELATORIO_ENTREGA.md` | ☐ |
| Link da documentação e do vídeo | `RELATORIO_ENTREGA.md` | ☐ |
| Resumo dos desafios e decisões | `RELATORIO_ENTREGA.md` + `ARQUITETURA.md` | ☐ |
| **Print da estimativa de custos da AWS** | gerar em calculator.aws — ver `CUSTOS.md` | ☐ |

---

## Diferenciais além do exigido

Itens que não constam do enunciado e que sustentam a nota máxima. Vale citar
cada um, em uma frase, durante o vídeo:

| Diferencial | Por que conta |
|---|---|
| **IRSA por workload** | A Fase 2 dava SQS/DynamoDB FullAccess à role dos nós — todo pod tinha acesso total. Agora cada ServiceAccount tem só o que usa. |
| **Secrets Manager + External Secrets** | Nenhuma senha no Git, em YAML ou em `.tfvars`. Ataca diretamente a dor citada no enunciado. |
| **OIDC entre GitHub e AWS** | Zero chave estática nos secrets do repositório. |
| **Pipeline de IaC** (`terraform.yml`) | `fmt`, `validate`, tflint, Checkov e Trivy config; plan comentado no PR; apply com aprovação manual. |
| **SBOM em CycloneDX** | Gerado a cada build e retido por 30 dias — rastreabilidade de supply chain. |
| **SARIF na aba Security** | Achados de SAST, SCA e container ficam na interface nativa do GitHub. |
| **ECR com tag imutável** | O commit no repositório GitOps descreve exatamente o bit que roda. |
| **Job de bootstrap como hook PreSync** | Substitui as ~120 linhas de `deploy.sh` da Fase 2 por algo declarativo e idempotente. |
| **Endurecimento dos pods** | `runAsNonRoot`, `readOnlyRootFilesystem`, `drop: [ALL]`, seccomp `RuntimeDefault`. |
| **PDB e topology spread** | Disponibilidade preservada durante upgrades e distribuição entre AZs. |
| **21 testes unitários** | Cobrem hash da API key, bucketing determinístico, *fail closed* e a garantia de que mensagem malformada não sai da fila. |
| **Backend S3 com lock nativo** | `use_lockfile`, versionamento, criptografia e policy negando não-TLS. |

---

## Revisão final antes de enviar

- [ ] `terraform fmt -recursive terraform/` sem alterações pendentes
- [ ] `go mod tidy` rodado nos dois serviços Go e `go.sum` commitado
- [ ] Nenhum `.tfvars`, `.env` ou `terraform.tfstate` versionado (`git status --ignored`)
- [ ] Nenhum `ACCOUNT_ID` sobrando nos overlays do repositório GitOps
- [ ] Os 5 pipelines verdes na `main`
- [ ] As 7 Applications do Argo CD `Synced`/`Healthy`
- [ ] `./scripts/smoke-test.sh` passando
- [ ] Vídeo publicado como **não listado** e o link testado em aba anônima
- [ ] Repositórios públicos (ou o avaliador com acesso)
- [ ] Print da calculadora de custos anexado ao relatório
