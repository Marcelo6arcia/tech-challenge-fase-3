# =============================================================================
# MÓDULO: github-oidc
# Federação OIDC entre o GitHub Actions e a AWS.
# =============================================================================
#
# Elimina AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY dos secrets do repositório.
# O workflow recebe um token OIDC de vida curta emitido pelo próprio GitHub e o
# troca por credenciais temporárias na AWS. Uma chave estática vazada continua
# valendo até ser revogada; um token OIDC expira em minutos e só é emitido para
# os repositórios/branches declarados na condição de trust abaixo.
# =============================================================================

data "aws_caller_identity" "current" {}

resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_provider ? 1 : 0

  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
  # Thumbprint da CA da Actions. A AWS valida a cadeia TLS desde 2023, mas o
  # campo continua obrigatório na API.
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]

  tags = var.tags
}

locals {
  oidc_arn = var.create_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : var.existing_oidc_provider_arn
}

data "aws_iam_policy_document" "assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Restringe quais repositórios e refs podem assumir a role
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = var.allowed_subjects
    }
  }
}

resource "aws_iam_role" "ci" {
  name                 = var.role_name
  description          = "Role assumida pelo GitHub Actions via OIDC"
  assume_role_policy   = data.aws_iam_policy_document.assume_role.json
  max_session_duration = 3600

  tags = merge(var.tags, { Name = var.role_name })
}

# --- Push de imagens no ECR ---------------------------------------------------
data "aws_iam_policy_document" "ecr_push" {
  statement {
    sid       = "ECRAuthToken"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid     = "ECRPushPull"
    effect  = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:CompleteLayerUpload",
      "ecr:DescribeImages",
      "ecr:DescribeImageScanFindings",
      "ecr:GetDownloadUrlForLayer",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
    ]
    resources = var.ecr_repository_arns
  }
}

resource "aws_iam_policy" "ecr_push" {
  name        = "${var.role_name}-ecr-push"
  description = "Push de imagens nos repositorios ECR do ToggleMaster"
  policy      = data.aws_iam_policy_document.ecr_push.json

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "ecr_push" {
  role       = aws_iam_role.ci.name
  policy_arn = aws_iam_policy.ecr_push.arn
}

# --- Terraform plan no CI (somente leitura + state) ---------------------------
data "aws_iam_policy_document" "terraform_plan" {
  count = var.enable_terraform_plan_access ? 1 : 0

  statement {
    sid     = "TerraformStateAccess"
    effect  = "Allow"
    actions = [
      "s3:ListBucket",
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
    ]
    resources = [
      "arn:aws:s3:::${var.state_bucket_name}",
      "arn:aws:s3:::${var.state_bucket_name}/*",
    ]
  }

  statement {
    sid       = "ReadOnlyForPlan"
    effect    = "Allow"
    actions   = ["ec2:Describe*", "eks:Describe*", "eks:List*", "rds:Describe*", "elasticache:Describe*", "dynamodb:Describe*", "sqs:Get*", "sqs:List*", "ecr:Describe*", "iam:Get*", "iam:List*", "logs:Describe*", "secretsmanager:Describe*", "secretsmanager:List*"]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "terraform_plan" {
  count = var.enable_terraform_plan_access ? 1 : 0

  name        = "${var.role_name}-terraform-plan"
  description = "Leitura do estado e dos recursos para rodar terraform plan no CI"
  policy      = data.aws_iam_policy_document.terraform_plan[0].json

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "terraform_plan" {
  count = var.enable_terraform_plan_access ? 1 : 0

  role       = aws_iam_role.ci.name
  policy_arn = aws_iam_policy.terraform_plan[0].arn
}
