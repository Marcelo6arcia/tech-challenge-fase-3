variable "aws_region" {
  description = "Região da AWS"
  type        = string
  default     = "us-east-1"
}

variable "aws_profile" {
  description = "Profile do AWS CLI. Deixe null no CI (as credenciais vêm do OIDC)."
  type        = string
  default     = null
}

variable "project_name" {
  description = "Nome do projeto, usado como prefixo dos recursos"
  type        = string
  default     = "togglemaster"
}

variable "environment" {
  description = "Nome do ambiente"
  type        = string
  default     = "dev"
}

# --- Rede --------------------------------------------------------------------
variable "vpc_cidr" {
  description = "CIDR da VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "enable_nat_gateway" {
  description = "Cria NAT Gateway (custo adicional ~US$ 32/mês por AZ)"
  type        = bool
  default     = false
}

# --- EKS ---------------------------------------------------------------------
variable "kubernetes_version" {
  description = <<-EOT
    Versão do Kubernetes. Deixe null (padrão) para usar a versão padrão do EKS,
    descoberta em tempo de plan — ela está sempre em suporte padrão.
    Fixar uma versão fora do suporte padrão faz o apply falhar de propósito:
    o control plane passa a custar seis vezes mais.
  EOT
  type        = string
  default     = null
}

variable "node_instance_types" {
  description = "Tipos de instância dos worker nodes"
  type        = list(string)
  default     = ["t3a.medium"]
}

variable "node_desired_size" {
  description = "Nós desejados"
  type        = number
  default     = 3
}

variable "node_min_size" {
  description = "Mínimo de nós"
  type        = number
  default     = 2
}

variable "node_max_size" {
  description = "Máximo de nós"
  type        = number
  default     = 5
}

variable "cluster_admin_principal_arns" {
  description = "ARNs IAM que recebem acesso admin ao cluster (além de quem criou)"
  type        = list(string)
  default     = []
}

# --- Bancos ------------------------------------------------------------------
variable "postgres_version" {
  description = "Versão do PostgreSQL nas instâncias RDS"
  type        = string
  default     = "16.4"
}

variable "rds_instance_class" {
  description = "Classe das instâncias RDS"
  type        = string
  default     = "db.t3.micro"
}

# --- GitHub OIDC -------------------------------------------------------------
variable "github_owner" {
  description = "Usuário ou organização dona dos repositórios no GitHub"
  type        = string
  default     = "Marcelo6arcia"
}

variable "github_app_repo" {
  description = "Repositório com o código das aplicações e do Terraform"
  type        = string
  default     = "tech-challenge-fase-3"
}

variable "github_owner_id" {
  description = "ID numerico do owner no GitHub, usado no subject do OIDC."
  type        = string
  default     = "71568242"
}

variable "github_repo_id" {
  description = "ID numerico do repositorio no GitHub, usado no subject do OIDC."
  type        = string
  default     = "1363085368"
}

variable "public_access_cidrs" {
  description = "CIDRs autorizados a alcancar o endpoint publico da API do EKS."
  type        = list(string)

  # Fica fora do git de proposito: o valor real e o IP residencial de quem
  # opera, muda sozinho e este repositorio e publico. Localmente vem do
  # terraform.tfvars; no CI, de TF_VAR_public_access_cidrs, alimentado pela
  # variavel de repositorio PUBLIC_ACCESS_CIDRS.
  default = []
}

variable "state_bucket_name" {
  description = "Bucket de state (concede acesso ao papel OIDC para rodar plan no CI)"
  type        = string
  default     = ""
}

# --- Nomes de recursos -------------------------------------------------------
variable "dynamodb_table_name" {
  description = "Nome da tabela DynamoDB de analytics"
  type        = string
  default     = "ToggleMasterAnalytics"
}

variable "sqs_queue_name" {
  description = "Nome da fila SQS"
  type        = string
  default     = "togglemaster-flag-events"
}

variable "app_namespace" {
  description = "Namespace Kubernetes das aplicações (usado nas condições de IRSA)"
  type        = string
  default     = "togglemaster"
}
