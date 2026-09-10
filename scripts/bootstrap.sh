#!/usr/bin/env bash
# =============================================================================
# bootstrap.sh — provisiona o ambiente completo, em ordem.
#
#   ./scripts/bootstrap.sh
#
# Ao contrário do deploy.sh da Fase 2, este script NÃO faz build de imagem, NÃO
# roda kubectl apply e NÃO cria segredo nenhum. Ele só encadeia os três
# terraform apply. Aplicações são responsabilidade do CI + Argo CD.
# =============================================================================
set -euo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF="${RAIZ}/terraform"

titulo() { echo; echo "=============================================="; echo " $1"; echo "=============================================="; }
confirmar() { read -r -p "$1 (s/N): " r; [[ "$r" == "s" || "$r" == "S" ]]; }

command -v terraform >/dev/null || { echo "terraform não encontrado no PATH."; exit 1; }
command -v aws       >/dev/null || { echo "aws cli não encontrado no PATH.";  exit 1; }

# ── 1. Backend remoto ────────────────────────────────────────────────────────
titulo "1/4 — Backend remoto (bucket S3 do state)"

if [[ -f "${TF}/bootstrap/terraform.tfstate" ]]; then
  echo "Bootstrap já executado. Reaproveitando o bucket existente."
else
  confirmar "Criar o bucket de state agora?" || { echo "Cancelado."; exit 0; }
  terraform -chdir="${TF}/bootstrap" init -input=false
  terraform -chdir="${TF}/bootstrap" apply -input=false
fi

BUCKET=$(terraform -chdir="${TF}/bootstrap" output -raw state_bucket_name)
echo "Bucket de state: ${BUCKET}"

# ── 2. backend.hcl das duas camadas ──────────────────────────────────────────
titulo "2/4 — Gerando os arquivos backend.hcl"

REGIAO="${AWS_REGION:-us-east-1}"
PERFIL="${AWS_PROFILE:-fiap}"

for camada in infra platform; do
  destino="${TF}/envs/dev/${camada}/backend.hcl"
  cat > "$destino" <<EOF
bucket       = "${BUCKET}"
key          = "togglemaster/dev/${camada}.tfstate"
region       = "${REGIAO}"
encrypt      = true
use_lockfile = true
profile      = "${PERFIL}"
EOF
  echo "  gerado: ${destino}"
done

# ── 3. Infraestrutura ────────────────────────────────────────────────────────
titulo "3/4 — Infraestrutura (rede, EKS, RDS, Redis, DynamoDB, SQS, ECR, IAM)"

[[ -f "${TF}/envs/dev/infra/terraform.tfvars" ]] || {
  echo "Crie ${TF}/envs/dev/infra/terraform.tfvars a partir do .example antes de continuar."
  exit 1
}

terraform -chdir="${TF}/envs/dev/infra" init -input=false -backend-config=backend.hcl
terraform -chdir="${TF}/envs/dev/infra" plan  -input=false

confirmar "Aplicar a infraestrutura? (leva ~20 min)" || { echo "Cancelado."; exit 0; }
terraform -chdir="${TF}/envs/dev/infra" apply -input=false -auto-approve

CLUSTER=$(terraform -chdir="${TF}/envs/dev/infra" output -raw eks_cluster_name)
echo
echo "Configurando o kubectl para o cluster ${CLUSTER}..."
# --alias fixa um nome inconfundivel para o contexto. Sem isso o kubectl usa o
# ARN do cluster, que numa maquina com varios EKS na mesma regiao e facil de
# confundir — e os passos seguintes rodam kubectl delete e kubectl patch.
# --profile usa $PERFIL, e nao $AWS_PROFILE: o backend.hcl acima ja foi escrito
# com o default "fiap", e usar variaveis diferentes nos dois lugares fazia o
# state apontar para um profile e o contexto do kubectl para outro. Quem rodasse
# sem exportar AWS_PROFILE ganhava um contexto amarrado ao profile padrao da
# maquina, e o kubectl get nodes da linha seguinte falhava por credencial.
aws eks update-kubeconfig \
  --region "${REGIAO}" \
  --name "${CLUSTER}" \
  --alias "togglemaster-dev" \
  --profile "${PERFIL}"

echo "  contexto ativo: $(kubectl config current-context)"
kubectl get nodes

# ── 4. Plataforma ────────────────────────────────────────────────────────────
titulo "4/4 — Plataforma (ingress-nginx, External Secrets, Argo CD)"

[[ -f "${TF}/envs/dev/platform/terraform.tfvars" ]] || {
  echo "Crie ${TF}/envs/dev/platform/terraform.tfvars a partir do .example antes de continuar."
  exit 1
}

terraform -chdir="${TF}/envs/dev/platform" init  -input=false -backend-config=backend.hcl
terraform -chdir="${TF}/envs/dev/platform" apply -input=false -auto-approve

# ── Resumo ───────────────────────────────────────────────────────────────────
titulo "Pronto"

cat <<EOF
Próximos passos:

  1. Configure os secrets do repositório no GitHub:
       AWS_ROLE_ARN      = $(terraform -chdir="${TF}/envs/dev/infra" output -raw github_actions_role_arn)
       TF_STATE_BUCKET   = ${BUCKET}
       GITOPS_TOKEN      = PAT com escrita no repositorio togglemaster-gitops

  2. Ajuste ACCOUNT_ID nos overlays do repositório GitOps:
       terraform -chdir=${TF}/envs/dev/infra output -json gitops_wiring

  3. Faça um push na main de qualquer microsserviço. O pipeline publica a
     imagem no ECR e faz commit no repositório GitOps; o Argo CD sincroniza.

  4. Acesse a UI do Argo CD:
       $(terraform -chdir="${TF}/envs/dev/platform" output -raw argocd_port_forward_command)
       senha: $(terraform -chdir="${TF}/envs/dev/platform" output -raw argocd_initial_password_command)

  5. Valide a stack:
       ./scripts/smoke-test.sh
EOF
