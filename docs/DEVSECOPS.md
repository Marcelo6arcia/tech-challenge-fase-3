# Pipeline DevSecOps

Como o pipeline funciona, o que cada ferramenta procura e — a parte que a
avaliação pede explicitamente — **como demonstrar o pipeline falhando por
segurança e depois passando**.

---

## 1. Estrutura

Cinco workflows chamadores (`ci-<servico>.yml`), um workflow reutilizável
(`_reusable-ci.yml`) e um workflow de infraestrutura (`terraform.yml`).

Cada `ci-<servico>.yml` tem filtro de caminho: alterar `flag-service/app.py`
dispara **só** o pipeline do `flag-service`. Isso mantém o feedback rápido e
evita reconstruir cinco imagens por causa de um typo.

```
                  ┌──────────────┐
                  │ build & test │──┐
                  ├──────────────┤  │
Pull Request ────►│    lint      │──┤
   ou push        ├──────────────┤  ├──► image ──► update-gitops
   na main        │    SAST      │──┤   (build,     (kustomize edit
                  ├──────────────┤  │    scan,       + commit)
                  │    SCA       │──┘    push)
                  └──────────────┘
                                        só na main ───────────────►
```

---

## 2. Os estágios

### 2.1 Build & Unit Test

| Linguagem | Comandos |
|---|---|
| Go | `go mod tidy`, `go build ./...`, `go test ./... -race -coverprofile` |
| Python | `pip install -r requirements-dev.txt`, `pytest --cov` |

`-race` liga o detector de corrida do Go — relevante porque o
`evaluation-service` consulta `flag-service` e `targeting-service` em goroutines
paralelas.

Testes existentes:

- `auth-service/key_test.go` — formato, unicidade e determinismo da API key; o
  hash tem exatamente 64 caracteres, que é o limite da coluna `key_hash`.
- `evaluation-service/evaluator_test.go` — bucketing determinístico, faixa
  0–99, distribuição, rollout de 0% e 100%, valor de regra inválido resultando
  em `false` (*fail closed*).
- `flag-service`, `targeting-service` — health check sem autenticação, 401 sem
  chave, 503 com o `auth-service` fora do ar, 504 em timeout.
- `analytics-service` — mensagem válida vira item no DynamoDB; mensagem
  malformada **não** é removida da fila (não vira perda silenciosa de dado).

### 2.2 Linter

- **Go**: `go vet` + `golangci-lint` (errcheck, staticcheck, ineffassign,
  bodyclose, gosec, misspell). Configuração em `.golangci.yml`.
- **Python**: `flake8` em dois modos — erros de sintaxe e nomes indefinidos
  quebram o build; estilo é informativo — mais `ruff`.

### 2.3 SAST — código-fonte

| Linguagem | Ferramenta | Porta de qualidade |
|---|---|---|
| Go | `gosec` | achados de severidade **HIGH** derrubam o build |
| Python | `bandit` | `-lll -ii` (severidade HIGH, confiança média ou alta) |

O relatório completo do gosec sobe como SARIF para a aba **Security** do
repositório; o do bandit fica como artefato JSON.

### 2.3.1 Achados triados como falso positivo

Nem todo achado vira correção — mas todo achado vira decisão registrada. Estes
foram analisados e conscientemente não bloqueiam o build:

| Regra | Onde | Por que não é risco |
|---|---|---|
| `S104` / `B104` — bind em `0.0.0.0` | `app.run()` dos serviços Python | Dentro de um container é o comportamento correto; e esse bloco `if __name__ == '__main__'` nem executa em produção, onde o entrypoint é o gunicorn |
| `S608` / `B608` — SQL montado por f-string | `update_flag()` do flag-service | Os fragmentos concatenados são literais fixos no código (`"description = %s"`, `"is_enabled = %s"`); os valores do usuário vão por placeholder `%s` do psycopg2 |
| `G505` — SHA-1 | `getDeterministicBucket()` do evaluation-service | **Este foi corrigido**, não suprimido: trocado por SHA-256. O uso não era criptográfico, mas um alerta permanente é um alerta que a equipe aprende a ignorar |

Os dois primeiros ficam fora do `select` do ruff (ver `ruff.toml`), e não do
bandit: no bandit eles aparecem como MEDIUM e a porta de qualidade é `-lll`
(HIGH). Ou seja, continuam sendo reportados — só não derrubam a entrega.

### 2.4 SCA — dependências e segredos

`Trivy` em modo `fs`, duas passagens:

1. **Relatório** — `MEDIUM,HIGH,CRITICAL`, `exit-code: 0`, saída SARIF enviada
   para a aba Security. Serve para acompanhar a dívida.
2. **Porta de qualidade** — apenas `CRITICAL`, `ignore-unfixed: true`,
   `exit-code: 1`. É o que **derruba o build**.

`ignore-unfixed` evita travar a entrega por uma CVE que ainda não tem correção
publicada — nesse caso não há ação possível além de aceitar e monitorar.

O scanner `secret` também roda: uma chave da AWS commitada por engano falha o
pipeline.

### 2.5 Docker build, scan do container e push

1. `docker buildx build --load` (sem push ainda).
2. Trivy `image` — relatório SARIF + porta de qualidade em CRITICAL.
3. SBOM em CycloneDX publicado como artefato, retido por 30 dias.
4. **Só então** o push para o ECR — e apenas em push na `main`.

Tag: `v1.0.0-<sha-curto>`, exatamente o formato pedido no enunciado. Os
repositórios ECR estão com `image_tag_mutability = IMMUTABLE`: uma tag publicada
não pode ser sobrescrita, então o commit no repositório GitOps descreve com
precisão o bit que está rodando.

### 2.6 Atualização do repositório GitOps

O passo final não fala com o cluster:

```bash
cd apps/overlays/dev/<servico>
kustomize edit set image <servico>=<ecr>/<servico>:v1.0.0-<sha>
git commit -m "deploy(<servico>): v1.0.0-<sha>"
git push
```

Um `concurrency group` serializa os cinco pipelines no mesmo repositório GitOps,
e o push tem retry com `git pull --rebase` para o caso de dois serviços
terminarem ao mesmo tempo.

---

## 3. Pipeline da infraestrutura

`terraform.yml`:

| Etapa | Ferramenta |
|---|---|
| Formatação | `terraform fmt -check -recursive` |
| Validação | `terraform validate` em cada módulo |
| Lint | `tflint --recursive` |
| Segurança do IaC | `Checkov` (SARIF na aba Security) + `Trivy config` (bloqueia em CRITICAL) |
| Plano | `terraform plan`, comentado automaticamente no Pull Request |
| Aplicação | `terraform apply` só na `main`, com aprovação manual no Environment `aws-dev` |

---

## 4. Demonstração da falha de segurança (para o vídeo)

O enunciado pede: introduzir uma vulnerabilidade, mostrar o pipeline falhando e
depois mostrar passando. O script `scripts/demo-vulnerabilidade.sh` automatiza a
inserção e a remoção.

### Opção A — dependência vulnerável em Python (recomendada)

```bash
./scripts/demo-vulnerabilidade.sh inserir flag-service
git checkout -b demo/vulnerabilidade
git commit -am "test: dependencia com CVE critica"
git push -u origin demo/vulnerabilidade
# abra o Pull Request
```

Acrescenta `PyYAML==5.3.1` ao `requirements.txt`. Essa versão carrega a
**CVE-2020-14343 (CVSS 9.8, CRITICAL)** — execução arbitrária de código via
`yaml.full_load`. O job **SCA** falha em segundos, com a tabela do Trivy
mostrando a CVE, a versão instalada e a versão corrigida. Os jobs `image` e
`update-gitops` nem chegam a rodar: nenhuma imagem é publicada, nenhum deploy
acontece.

A correção:

```bash
./scripts/demo-vulnerabilidade.sh remover flag-service
git commit -am "fix: remove dependencia vulneravel"
git push
```

O mesmo Pull Request fica verde e, ao ser mesclado na `main`, a imagem é
publicada e o repositório GitOps recebe o commit.

### Opção B — falha de SAST no código Go

```bash
./scripts/demo-vulnerabilidade.sh inserir auth-service
```

Insere no `auth-service` um handler que executa `exec.Command` com entrada
recebida do usuário. O **gosec** acusa **G204 — Subprocess launched with a
potential tainted input**, severidade HIGH, e o job SAST falha.

Vale gravar as duas: a Opção A mostra o controle de **dependências** (SCA), a
Opção B mostra o controle do **código escrito pela equipe** (SAST). São
categorias diferentes de risco e o enunciado pede as duas ferramentas.

### O que mostrar na tela

1. O job vermelho na aba Actions, com o nome do estágio.
2. O log do Trivy/gosec com o identificador da CVE ou da regra.
3. O grafo do workflow: `image` e `update-gitops` em cinza (*skipped*).
4. O ECR **sem** a nova tag.
5. Depois da correção: tudo verde, a tag no ECR, o commit no repositório GitOps
   e o Argo CD sincronizando.

---

## 5. Configuração necessária no GitHub

Secrets do repositório `tech-challenge-fase-3`:

| Secret | Origem |
|---|---|
| `AWS_ROLE_ARN` | `terraform output github_actions_role_arn` |
| `AWS_ROLE_ARN_APPLY` | o mesmo ARN, ou uma role separada com mais permissões |
| `TF_STATE_BUCKET` | `terraform output` do módulo bootstrap |
| `GITOPS_TOKEN` | Personal Access Token (fine-grained) com **Contents: Read and write** apenas no repositório `togglemaster-gitops` |

Environment `aws-dev` com *required reviewers* — é o que segura o
`terraform apply` até alguém aprovar.
