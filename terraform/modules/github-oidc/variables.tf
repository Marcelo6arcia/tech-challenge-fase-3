variable "role_name" {
  description = "Nome da role assumida pelo GitHub Actions"
  type        = string
  default     = "togglemaster-github-actions"
}

variable "create_oidc_provider" {
  description = "Cria o OIDC provider do GitHub. Use false se a conta já tiver um."
  type        = bool
  default     = true
}

variable "existing_oidc_provider_arn" {
  description = "ARN do OIDC provider existente (quando create_oidc_provider = false)"
  type        = string
  default     = null
}

variable "allowed_subjects" {
  description = <<-EOT
    Padrões de "sub" do token OIDC autorizados a assumir a role.
    Exemplos:
      repo:Marcelo6arcia/tech-challenge-fase-3:ref:refs/heads/main
      repo:Marcelo6arcia/tech-challenge-fase-3:pull_request
      repo:Marcelo6arcia/tech-challenge-fase-3:*   (qualquer ref do repositório)
  EOT
  type        = list(string)
}

variable "ecr_repository_arns" {
  description = "ARNs dos repositórios ECR onde o CI pode publicar imagens"
  type        = list(string)
}

variable "enable_terraform_plan_access" {
  description = "Concede leitura do state S3 e dos recursos para rodar terraform plan no CI"
  type        = bool
  default     = true
}

variable "state_bucket_name" {
  description = "Nome do bucket de state (necessário quando enable_terraform_plan_access = true)"
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags aplicadas aos recursos"
  type        = map(string)
  default     = {}
}
