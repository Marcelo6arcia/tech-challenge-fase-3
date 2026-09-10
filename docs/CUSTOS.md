# Estimativa de custos — ambiente dev

Região **us-east-1**, preços on-demand, mês de 730 horas.

> **Os valores abaixo são uma estimativa de referência.** O entregável exige o
> print da AWS Pricing Calculator: monte a estimativa em
> <https://calculator.aws> com os itens desta tabela, exporte o PDF e anexe ao
> relatório. Preços mudam; a tabela serve para você conferir se esqueceu algum
> recurso, não para substituir a calculadora.

---

## Recursos provisionados

| Recurso | Configuração | Qtd. | Estimativa/mês |
|---|---|---:|---:|
| EKS — control plane | US$ 0,10/hora, versão em suporte padrão | 1 | US$ 73,00 |
| EC2 — worker nodes | `t3a.medium`, on-demand | 3 | US$ 82,35 |
| EBS gp3 — nós | 30 GB por nó | 90 GB | US$ 7,20 |
| RDS PostgreSQL | `db.t3.micro`, single-AZ | 3 | US$ 39,42 |
| RDS — armazenamento | 20 GB gp3 por instância | 60 GB | US$ 6,90 |
| ElastiCache Redis | `cache.t3.micro` | 1 | US$ 12,41 |
| Network Load Balancer | ingress-nginx + LCU | 1 | US$ 21,00 |
| DynamoDB | on-demand, volume de laboratório | 1 | US$ 1,00 |
| SQS | dentro do free tier de 1 M requisições | 1 | US$ 0,00 |
| ECR — armazenamento | ~10 GB (lifecycle mantém 10 imagens) | 5 | US$ 1,00 |
| Secrets Manager | US$ 0,40 por segredo | 6 | US$ 2,40 |
| CloudWatch Logs | EKS control plane + VPC Flow Logs, 7 dias | — | US$ 2,00 |
| S3 — state do Terraform | poucos MB versionados | 1 | US$ 0,10 |
| Transferência de dados | saída moderada | — | US$ 5,00 |
| **Total estimado** | | | **≈ US$ 253,78** |

NAT Gateway: **US$ 0,00** — desligado por padrão (`enable_nat_gateway = false`).
Ligá-lo acrescenta cerca de **US$ 65/mês** (2 AZs) mais o tráfego processado.

**Versão do Kubernetes:** um cluster rodando versão fora do suporte padrão do
EKS custa **US$ 0,60/hora** no control plane em vez de US$ 0,10 — US$ 438/mês
contra US$ 73/mês, sozinho maior que todo o resto do ambiente somado. Por isso a
versão não é fixada no código: o `terraform/envs/dev/infra` descobre a versão
padrão da AWS em tempo de plan, e um `terraform_data` com precondition reprova o
apply se alguém fixar uma versão em extended support.

---

## Onde o dinheiro está

```
EC2 (nós)        ████████████████████████████  32%
EKS control      ████████████████████████      29%
RDS (3 bancos)   ████████████████              18%
NLB              ████████                       8%
ElastiCache      ████                           5%
Demais           ████                           8%
```

Três itens somam quase 80% da conta: nós, control plane e bancos.

---

## Como reduzir

| Ação | Economia estimada | Custo da decisão |
|---|---:|---|
| `capacity_type = "SPOT"` nos nós | ~US$ 55/mês | Nós podem ser reciclados com 2 min de aviso |
| 2 nós em vez de 3 | ~US$ 27/mês | Menos margem para o HPA e para *rolling updates* |
| Um único RDS com 3 bancos lógicos | ~US$ 30/mês | Quebra o isolamento por serviço (um banco por microsserviço) |
| `destroy` fora das horas de trabalho | até 70% | ~20 min para recriar — viável justamente porque tudo é IaC |

A última linha é o argumento mais forte da fase: **o ambiente inteiro é
descartável**. `./scripts/destroy.sh` à noite e `./scripts/bootstrap.sh` no dia
seguinte reproduzem o ambiente byte a byte — o oposto da homologação que "levava
dias porque foi feita manualmente no console".

---

## Como montar o print para o relatório

1. Abra <https://calculator.aws> e crie a estimativa "ToggleMaster - Fase 3".
2. Adicione, na ordem: EKS, EC2 (3 × t3a.medium + 90 GB gp3), RDS (3 ×
   db.t3.micro + 20 GB cada), ElastiCache, ELB (1 NLB), DynamoDB on-demand,
   SQS, ECR, Secrets Manager e CloudWatch Logs.
3. Exporte em PDF e capture a tela do resumo.
4. Anexe ao `RELATORIO_ENTREGA` — é item obrigatório do entregável.
