#!/usr/bin/env bash
# =============================================================================
# destroy.sh — derruba o ambiente na ordem inversa do bootstrap.
#
#   ./scripts/destroy.sh
#
# ATENÇÃO: apaga os bancos de dados. Sem confirmação dupla não roda.
# O bucket de state NÃO é destruído (force_destroy = false no bootstrap):
# apague-o manualmente quando tiver certeza de que não precisa mais do histórico.
# =============================================================================
set -euo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF="${RAIZ}/terraform"

# Guarda de contexto: este script roda `kubectl delete` e `kubectl patch`.
# Numa maquina com varios clusters, apontar para o errado e desastre.
CONTEXTO=$(kubectl config current-context 2>/dev/null || echo "nenhum")
if [ "$CONTEXTO" != "togglemaster-dev" ]; then
  echo "ERRO: o contexto do kubectl e '${CONTEXTO}', nao 'togglemaster-dev'."
  echo "Rode:  aws eks update-kubeconfig --region us-east-1 \\"
  echo "         --name togglemaster-dev-eks --alias togglemaster-dev"
  exit 1
fi

echo "Contexto do kubectl: ${CONTEXTO}"
echo
echo "Isto vai destruir o ambiente dev do ToggleMaster:"
echo "  - cluster EKS e tudo que roda nele"
echo "  - 3 instâncias RDS (dados perdidos)"
echo "  - ElastiCache, DynamoDB, SQS, ECR"
echo
read -r -p "Digite DESTRUIR para confirmar: " CONFIRMA
[[ "$CONFIRMA" == "DESTRUIR" ]] || { echo "Cancelado."; exit 0; }

# ── 1. Plataforma ────────────────────────────────────────────────────────────
echo
echo ">>> Removendo a plataforma (Argo CD, ingress, External Secrets)..."
terraform -chdir="${TF}/envs/dev/platform" destroy -input=false -auto-approve || \
  echo "AVISO: destroy da plataforma falhou; seguindo mesmo assim."

# O Argo CD tem finalizers nas Applications: sem removê-los, o namespace fica
# preso em Terminating e o destroy da VPC trava mais adiante.
echo ">>> Limpando finalizers de Applications remanescentes..."
for app in $(kubectl -n argocd get applications -o name 2>/dev/null || true); do
  kubectl -n argocd patch "$app" -p '{"metadata":{"finalizers":null}}' --type=merge || true
done

# O NLB criado pelo Service do ingress-nginx é um recurso "órfão" do ponto de
# vista do Terraform: quem o criou foi o cloud-controller do Kubernetes.
echo ">>> Removendo o Service do ingress (libera o NLB)..."
kubectl -n ingress-nginx delete svc ingress-nginx-controller --ignore-not-found --timeout=180s || true
echo ">>> Aguardando a AWS liberar o load balancer..."
sleep 60

# ── 2. Infraestrutura ────────────────────────────────────────────────────────
echo
echo ">>> Destruindo a infraestrutura..."
terraform -chdir="${TF}/envs/dev/infra" destroy -input=false -auto-approve

echo
echo "Ambiente destruído."
echo "O bucket de state foi preservado. Para removê-lo:"
echo "  terraform -chdir=${TF}/bootstrap destroy"
echo "  (é preciso esvaziar o bucket antes, inclusive as versões antigas)"
