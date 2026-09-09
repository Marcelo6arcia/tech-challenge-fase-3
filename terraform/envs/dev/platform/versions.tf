terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.17"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.35"
    }
  }

  backend "s3" {}
}

provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile
}

# -----------------------------------------------------------------------------
# Por que uma camada separada?
# -----------------------------------------------------------------------------
# Os providers helm e kubernetes precisam do endpoint e do token do cluster para
# se configurarem. Se estivessem no mesmo state que cria o cluster, o Terraform
# tentaria configurar o provider com valores ainda desconhecidos no plan — erro
# clássico de "provider configuration with unknown values". Separar em duas
# camadas (infra -> platform) resolve isso de forma limpa e ainda permite
# destruir a plataforma sem derrubar os dados.
# -----------------------------------------------------------------------------

data "terraform_remote_state" "infra" {
  backend = "s3"
  config  = var.infra_state_config
}

data "aws_eks_cluster" "this" {
  name = data.terraform_remote_state.infra.outputs.eks_cluster_name
}

data "aws_eks_cluster_auth" "this" {
  name = data.terraform_remote_state.infra.outputs.eks_cluster_name
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.this.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.this.token
}

provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.this.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.this.token
  }
}
