aws_region = "us-east-1"

# aws_profile NAO entra aqui. Este arquivo e versionado, e um .tfvars e
# carregado automaticamente e vence qualquer TF_VAR_ do ambiente -- entao
# declarar o profile aqui obriga o runner do GitHub a ter um profile "fiap",
# que ele nao tem: o CI autentica por OIDC. O plan quebrava com
# "failed to get shared config profile, fiap" e o CI nao tinha como sobrescrever.
#
# Na sua maquina, exporte antes de rodar:
#
#   export AWS_PROFILE=fiap
#
# Com aws_profile nulo o provider usa a cadeia padrao de credenciais, que
# respeita AWS_PROFILE. O backend.hcl continua com profile = "fiap" porque o
# CI nao o usa: la o backend e configurado por -backend-config na linha de
# comando.

project_name = "togglemaster"
environment  = "dev"

# Nós em subnet pública, sem NAT Gateway (~US$ 65/mês economizados).
# RDS e ElastiCache seguem em subnet privada, sem rota para a internet.
enable_nat_gateway = false

# kubernetes_version fica ausente de propósito: o Terraform descobre a versão
# padrão do EKS em tempo de plan. Fixar aqui uma versão fora do suporte padrão
# faz o apply falhar, com o custo explicado na mensagem.

node_instance_types = ["t3a.medium"]
node_min_size       = 2
node_desired_size   = 3
node_max_size       = 5

github_owner    = "Marcelo6arcia"
github_app_repo = "tech-challenge-fase-3"

state_bucket_name = "togglemaster-tfstate-50f10e14"

# Endpoint publico da API do EKS restrito. Se o IP mudar, atualize aqui e na
# variavel de repositorio PUBLIC_ACCESS_CIDRS do GitHub.
# Marcelo (200.205.17.91) e Vinicius (187.89.10.3), que grava a demonstracao.
public_access_cidrs = ["200.205.17.91/32", "187.89.10.3/32"]
