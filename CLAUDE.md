# CLAUDE.md — Tech Challenge Fase 3 (ToggleMaster)

Contexto para qualquer sessão futura que trabalhe neste repositório.

## O projeto

Fase 3 de 5 da pós-tech em DevOps e Arquitetura Cloud da FIAP. O ToggleMaster é
uma plataforma fictícia de *feature flags*. Histórico das fases:

- **Fase 1** — monólito Flask em EC2 + RDS (`../tech-challenge-fase-1`)
- **Fase 2** — quebra em 5 microsserviços, Docker e EKS, com infra provisionada
  parcialmente à mão (`../tech-challenge-fase-2`)
- **Fase 3** — IaC completa, pipelines DevSecOps e GitOps (**este repositório**)

Vale 90% da nota das disciplinas da fase.

## Ambiente alvo

**Opção B do enunciado — conta AWS pessoal.** Há liberdade para criar IAM, o que
habilita IRSA e a federação OIDC com o GitHub. Os módulos continuam compatíveis
com o AWS Academy: `create_iam_roles = false` no módulo `eks` permite injetar a
LabRole.

## Os dois repositórios

| Repositório | Conteúdo |
|---|---|
| `tech-challenge-fase-3` | código dos 5 serviços, Terraform, workflows de CI |
| `togglemaster-gitops` | manifestos Kustomize + Applications do Argo CD |

Fisicamente ficam lado a lado em `~/Documents/fiap/`.

## Regras que valem para qualquer alteração aqui

1. **Nada de `kubectl apply` manual.** Alteração no cluster é commit no
   repositório GitOps. O Argo CD tem `selfHeal: true` e desfaz o resto.
2. **Nenhum segredo em arquivo.** Senhas são geradas pelo Terraform e vão para o
   AWS Secrets Manager; o cluster as recebe via External Secrets Operator. O que
   se versiona é o `ExternalSecret`, nunca o `Secret`.
3. **Nenhuma permissão ampla de IAM.** Nada de `*FullAccess` na role dos nós.
   Workload que precisa da AWS ganha uma role IRSA com os ARNs exatos.
4. **A porta de qualidade não se contorna.** Achado CRITICAL bloqueia o build.
   A resposta certa é corrigir a dependência, não afrouxar o gate.
5. **`terraform fmt -recursive terraform/` antes de commitar** — o pipeline de
   IaC checa.

## Detalhes que costumam pegar

- Os serviços Go herdaram `go.sum` incompleto das fases anteriores. Rode
  `go mod tidy` e commite o `go.sum` — o pipeline também roda `tidy`, mas o
  `golangci-lint` fica mais estável com o arquivo correto no repositório.
- `terraform/envs/dev` é dividido em `infra` e `platform` **de propósito**: os
  providers `helm` e `kubernetes` não podem ser configurados no mesmo state que
  cria o cluster.
- O `evaluation-service` usa SHA-256 (não SHA-1) no `getDeterministicBucket`; a
  troca veio de um achado do gosec (G505).
- O `analytics-service` roda com `--workers 1` no gunicorn: o worker do SQS é
  uma thread de background por processo, e mais de um worker duplicaria o
  consumo da fila.
- O rewrite do Ingress remove o prefixo. `/flag/flags` chega ao serviço como
  `/flags`.
- Nos testes Python, `conftest.py` substitui o pool de conexões e o `boto3`
  **antes** de importar `app`, porque os módulos se conectam já no import.

## Comandos frequentes

```bash
# Infra
terraform -chdir=terraform/envs/dev/infra plan
terraform -chdir=terraform/envs/dev/infra output -json gitops_wiring

# Testes
cd auth-service && go test ./... -race -cover
cd flag-service && pytest

# Validar os manifestos GitOps
for d in ../togglemaster-gitops/apps/overlays/dev/*/; do kustomize build "$d" >/dev/null && echo "OK $d"; done

# Ciclo completo
./scripts/bootstrap.sh
./scripts/smoke-test.sh
./scripts/destroy.sh
```

## Documentação

`docs/ARQUITETURA.md` (decisões), `docs/DEVSECOPS.md` (pipeline),
`docs/RUNBOOK.md` (operação), `docs/ROTEIRO_VIDEO.md` (demonstração),
`docs/CHECKLIST_ENTREGA.md` (requisito por requisito), `docs/CUSTOS.md`.
