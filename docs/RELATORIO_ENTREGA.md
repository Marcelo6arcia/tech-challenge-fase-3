# Relatório Final — Tech Challenge Fase 3

**ToggleMaster — Feature Flag as a Service**
POSTECH FIAP · DevOps e Arquitetura Cloud

---

## Integrantes do grupo

| Nome | RM | Discord |
|---|---|---|
| Marcelo Vinicius Morais Garcia | 371988 | marcelovinicius6arcia |
| Vinícius Barbosa Caiana | 371851 | vinicius_makweb |

---

## Links de entrega

| Item | Link |
|---|---|
| Repositório de aplicação, IaC e CI | `https://github.com/Marcelo6arcia/tech-challenge-fase-3` |
| Repositório GitOps | `https://github.com/Marcelo6arcia/togglemaster-gitops` |
| Vídeo de demonstração | *(preencher — YouTube, não listado)* |
| Documentação de arquitetura | `docs/ARQUITETURA.md` do repositório principal |

---

## O desafio da fase

A arquitetura de microsserviços entregue na Fase 2 estava aprovada, mas a
operação havia se tornado insustentável por quatro motivos concretos:
`kubectl apply` disparado das máquinas dos desenvolvedores, credenciais de banco
trafegando em arquivos de texto, uma vulnerabilidade em biblioteca Go que chegou
à produção sem ser notada, e um ambiente de homologação que levava dias para ser
recriado porque havia sido montado à mão no console.

A resposta da Fase 3 foi tratar os quatro como o mesmo problema: **falta de
código como fonte da verdade**.

---

## O que foi construído

**Infraestrutura como Código.** Dez módulos Terraform reutilizáveis provisionam
VPC com duas AZs, cluster EKS 1.31 com Managed Node Group, três instâncias RDS
PostgreSQL, ElastiCache Redis, tabela DynamoDB, fila SQS com Dead Letter Queue,
cinco repositórios ECR e toda a camada de identidade. O state vive em bucket S3
versionado e criptografado, com lock nativo (`use_lockfile`).

**Pipeline DevSecOps.** Um workflow reutilizável, consumido pelos cinco
microsserviços, executa em paralelo build com testes unitários, linter, SAST
(gosec / bandit) e SCA (Trivy). Só depois dos quatro passarem é que a imagem é
construída, escaneada e publicada no ECR com a tag `v1.0.0-<sha>`. Um achado de
severidade CRITICAL interrompe o pipeline antes da publicação.

**Entrega contínua por GitOps.** O CI não fala com o cluster. Ele termina
alterando a tag da imagem em um repositório separado de manifestos Kustomize e
fazendo commit. O Argo CD, instalado via Terraform, observa esse repositório e
sincroniza o cluster com `prune` e `selfHeal` ativados.

---

## Principais decisões

**Dois repositórios em vez de monorepo.** O repositório de aplicação responde
"como este software é construído"; o de GitOps responde "o que está rodando
agora". Separar torna o `git log` do segundo um histórico de deploys legível e
elimina o risco de um commit de deploy disparar o próprio CI.

**Kustomize em vez de Helm.** `kustomize edit set image` é o mecanismo oficial
para trocar a tag, e o diff exibido pelo Argo CD mostra o objeto Kubernetes
final em vez de um template — o que torna a demonstração compreensível.

**Dois states do Terraform (`infra` e `platform`).** Os providers `helm` e
`kubernetes` precisam do endpoint do cluster para se configurarem; no mesmo
state, o Terraform tentaria configurá-los com valores desconhecidos durante o
plan. A separação resolve isso sem recorrer a `-target` e ainda permite recriar
a plataforma sem tocar nos bancos.

**NAT Gateway desligado por padrão.** Custaria cerca de US$ 65/mês em duas AZs —
aproximadamente um quarto do custo total — em um ambiente que é destruído todo
dia. Os nós ficam em subnet pública com Security Group restritivo; RDS e Redis
permanecem em subnet privada, sem rota para a internet. A postura de produção é
uma flag: `enable_nat_gateway = true`.

**IRSA por workload.** Na Fase 2, `AmazonSQSFullAccess` e
`AmazonDynamoDBFullAccess` estavam anexados à role dos nós, o que dava a
qualquer pod do cluster acesso total à fila e à tabela. Agora cada ServiceAccount
tem uma role própria, restrita aos ARNs que usa.

**Secrets Manager com External Secrets Operator.** Sealed Secrets e SOPS foram
considerados, mas ambos guardam o segredo cifrado dentro do Git — se a chave
privada vazar, todo o histórico vaza junto. Com o Secrets Manager, o segredo
nunca entra no repositório: o que está versionado é a referência a ele.

---

## Desafios encontrados

**A ordem de criação entre cluster e providers Kubernetes.** Primeira tentativa
com tudo em um state só resultou no erro *provider configuration with unknown
values*. A separação em duas camadas foi a solução, e acabou trazendo o benefício
lateral de permitir destruir a plataforma sem perder os bancos.

**Dependências herdadas com CVE.** O SCA reprovou o código como veio das fases
anteriores: Flask 2.2.2, Werkzeug 2.2.2, gunicorn 20.1.0, requests 2.28.1 e Go
1.21 acumulavam vulnerabilidades conhecidas. A correção exigiu subir para Flask
3.0.3 / Werkzeug 3.0.6 / gunicorn 23.0.0 / requests 2.32.3 e Go 1.23, verificando
compatibilidade a cada passo. Foi o momento em que o pipeline provou o próprio
valor: encontrou, em minutos, exatamente a classe de problema que o enunciado
descreve como um acidente de produção.

**SHA-1 apontado pelo SAST.** O `evaluation-service` usava SHA-1 para calcular o
bucket determinístico do rollout percentual. O uso não é criptográfico e o risco
real era nulo, mas o gosec marca a regra G505 como severidade alta. Optamos por
migrar para SHA-256 em vez de suprimir o alerta: um alerta que a equipe aprende
a ignorar é pior do que alerta nenhum.

**O `deploy.sh` da Fase 2.** Eram cerca de 120 linhas que aplicavam migrações,
geravam a chave de serviço via `curl` e faziam `kubectl patch` em Secrets — o
oposto de "se não está no código, não existe". Foi substituído por um Job
declarativo registrado como hook de sync do Argo CD, com a chave gerada pelo
Terraform e apenas o hash SHA-256 semeado no banco.

**Concorrência entre os cinco pipelines.** Os cinco escrevem no mesmo repositório
GitOps e podem terminar ao mesmo tempo. Resolvido com um `concurrency group` no
job `update-gitops` e retry com `git pull --rebase` no push.

---

## Estimativa de custos

Ambiente completo em us-east-1: **aproximadamente US$ 254/mês** com o NAT
Gateway desligado. Os detalhes item a item estão em `docs/CUSTOS.md`.

> **Anexar aqui o print da AWS Pricing Calculator.**

Como todo o ambiente é código, a estratégia adotada é destruí-lo fora das horas
de trabalho: `./scripts/destroy.sh` à noite e `./scripts/bootstrap.sh` no dia
seguinte reproduzem o ambiente em cerca de 20 minutos — o contrário exato da
homologação que "levava dias porque foi feita manualmente no console".

---

## Como validar a entrega

```bash
# 1. Provisionar
./scripts/bootstrap.sh

# 2. Validar a stack ponta a ponta
./scripts/smoke-test.sh

# 3. Demonstrar a porta de qualidade do pipeline
./scripts/demo-vulnerabilidade.sh inserir flag-service
```

O checklist completo, requisito por requisito, está em
`docs/CHECKLIST_ENTREGA.md`.
