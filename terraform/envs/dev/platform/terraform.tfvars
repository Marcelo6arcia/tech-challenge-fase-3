aws_region  = "us-east-1"
aws_profile = "fiap"

infra_state_config = {
  bucket  = "togglemaster-tfstate-50f10e14"
  key     = "togglemaster/dev/infra.tfstate"
  region  = "us-east-1"
  profile = "fiap"
}

gitops_repo_url      = "https://github.com/Marcelo6arcia/togglemaster-gitops.git"
gitops_repo_revision = "main"
gitops_root_path     = "argocd/applications"

# Repositório GitOps é público — o Argo CD lê sem credencial.
argocd_ingress_enabled = false
