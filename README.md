# ToggleMaster — Fase 3 (IaC, CI/CD DevSecOps e GitOps)

Automação completa da infraestrutura e do ciclo de vida dos 5 microsserviços
do ToggleMaster (auth, flag, targeting, evaluation, analytics), usando
Terraform, GitHub Actions (DevSecOps) e ArgoCD (GitOps).

## Estrutura

```
auth-service/          # código-fonte (copiado da Fase 2, sem o sufixo -main)
flag-service/
targeting-service/
evaluation-service/
analytics-service/
terraform/             # IaC modular (VPC, EKS, RDS, ElastiCache, DynamoDB, SQS, ECR, OIDC, IRSA)
scripts/bootstrap.sh   # setup manual único, ANTES da primeira pipeline rodar (ver Passo 1)
.github/workflows/     # pipelines de CI/CD: 1 de infraestrutura (terraform.yml) + 1 por serviço
gitops/                # conteúdo que vai virar o repo togglemaster-gitops (ArgoCD)
secrets.example.yaml   # referência de quais Secrets criar manualmente (NUNCA commitar valores reais)
```

**Como o `terraform apply` roda:** não é executado na sua máquina — quem
roda é a pipeline `.github/workflows/terraform.yml`, dentro de um runner do
GitHub Actions, toda vez que algo em `terraform/` muda (plan em PR, apply em
push na `main`). Isso é o que a Fase 3 pede ("infraestrutura como código,
com pipeline própria"). A sua máquina só entra em cena UMA VEZ, no Passo 1,
pra criar as 3 coisas que a própria pipeline não consegue criar sozinha.

## Pré-requisitos

- Conta AWS **pessoal** (este projeto cria IAM roles e um OIDC provider —
  não funciona em conta AWS Academy sem antes trocar `use_academy_lab_role = true`
  no `terraform.tfvars`, o que também exige revisar a autenticação da pipeline).
- Terraform >= 1.10 (por causa do `use_lockfile` no backend S3) — só
  necessário se você quiser rodar `terraform plan` localmente também; a
  pipeline já instala a versão certa sozinha.
- AWS CLI configurado localmente (`aws configure`) — usado **só no Passo 1**
  (bootstrap), uma única vez.
- kubectl, Helm
- Uma conta no GitHub com permissão para criar repositórios e configurar Secrets

---

## Passo 1 — Bootstrap (uma vez só, local)

A pipeline de Terraform (`.github/workflows/terraform.yml`) precisa se
autenticar na AWS pra rodar `plan`/`apply` — mas a forma segura e recomendada
de dar credencial AWS pro GitHub Actions (OIDC, sem senha fixa) exige que já
existam, na sua conta: o bucket S3 do state, o provedor OIDC do GitHub, e a
IAM Role que a pipeline vai assumir. Nenhuma dessas 3 coisas pode ser criada
pelo próprio Terraform (ele ainda não tem onde/com o que rodar antes delas
existirem) — é o clássico problema do "ovo e da galinha". Por isso existe o
script `scripts/bootstrap.sh`, que cria essas 3 coisas manualmente, uma
única vez, usando as SUAS credenciais AWS locais (que nunca saem da sua
máquina):

```bash
chmod +x scripts/bootstrap.sh
GITHUB_ORG=seu-usuario GITHUB_REPO=desafio-fiap-3 ./scripts/bootstrap.sh
```

O script imprime, no final, os 3 valores que você vai usar no próximo passo.
Depois deste ponto, você não precisa mais rodar Terraform localmente — tudo
o resto acontece pela pipeline.

## Passo 2 — Configurar os Secrets de infraestrutura no GitHub

No repositório do código (`desafio-fiap-3`), em **Settings → Secrets and
variables → Actions**, crie:

```
AWS_ROLE_ARN_TERRAFORM = <impresso pelo bootstrap.sh>
TF_STATE_BUCKET        = <impresso pelo bootstrap.sh>
DB_PASSWORD             = <escolha uma senha forte — vira a senha dos 3 RDS>
GH_PAT                  = Personal Access Token com permissão de push no repo togglemaster-gitops
```

`AWS_ROLE_ARN_TERRAFORM` é uma Role **ampla** (criada pelo bootstrap, com
`AdministratorAccess`, aceitável numa conta pessoal de estudo) — diferente
do Secret `AWS_ROLE_ARN` do Passo 5, que é uma Role **estreita** (só ECR
push), criada pelo próprio Terraform e usada pelas 5 pipelines de aplicação.
Separar os dois segue o princípio de menor privilégio.

## Passo 3 — Criar o repositório GitOps

A pipeline de Terraform (job `apply`, ao final) e as 5 pipelines de
aplicação escrevem neste repositório — ele precisa existir ANTES do
primeiro push na `main` do repositório de código:

```bash
gh repo create togglemaster-gitops --private --confirm
git clone https://github.com/SEU_USER/togglemaster-gitops.git
cp -r gitops/* togglemaster-gitops/
cd togglemaster-gitops
git add .
git commit -m "chore: manifests iniciais"
git push -u origin main
cd ..
```

## Passo 4 — Subir o projeto e deixar a pipeline criar a infraestrutura

```bash
git init   # se ainda não for um repo git
git add .
git commit -m "chore: infra, pipelines e gitops da fase 3"
git remote add origin https://github.com/SEU_USER/desafio-fiap-3.git
git push -u origin main
```

O push em `main` mexendo em `terraform/` dispara `.github/workflows/terraform.yml`:
job `plan` (mostra o que vai ser criado) e, em seguida, job `apply` — que
cria de fato: VPC, EKS + node group, 3x RDS PostgreSQL, 1x ElastiCache
Redis, 1x DynamoDB (`ToggleMasterAnalytics`), 1x SQS, 5x ECR, a Role estreita
de ECR-push usada pelas pipelines de aplicação, e as IRSA roles do
evaluation-service/analytics-service.

Se você configurou `environment: production` com revisor obrigatório
(**Settings → Environments → production → Required reviewers** — recomendado,
já que isso cria recursos reais e cobrados na AWS), o job `apply` fica
pausado esperando sua aprovação manual antes de rodar.

Ao final do `apply`, a própria pipeline já escreve os ARNs das IRSA roles e a
URL da fila SQS no repositório `togglemaster-gitops` (nos lugares dos
`REPLACE_WITH_TERRAFORM_OUTPUT_*`) — você não precisa editar isso manualmente.

Acompanhe pela aba **Actions** do GitHub, ou depois, localmente:

```bash
aws eks update-kubeconfig --name togglemaster --region us-east-1
kubectl get nodes
```

## Passo 5 — Configurar o Secret das pipelines de aplicação

Depois que o Passo 4 concluir, pegue o output `github_actions_role_arn`
(aba Actions → job apply → step "Mostra os outputs", ou rodando
`terraform output github_actions_role_arn` localmente se preferir) e
cadastre em **Settings → Secrets and variables → Actions**:

```
AWS_ROLE_ARN = <output github_actions_role_arn>
```

Esse é o Secret que as 5 pipelines de aplicação (`auth-service.yml`,
`flag-service.yml`, etc.) usam pra autenticar e dar push de imagem no ECR —
é a Role **estreita**, diferente da `AWS_ROLE_ARN_TERRAFORM` do Passo 2.

## Passo 6 — Criar os Secrets sensíveis direto no cluster (NUNCA no Git)

Preencha os placeholders de `secrets.example.yaml` com os endpoints reais
(outputs `rds_*_endpoint`, `elasticache_redis_url` — veja no log do job
`apply` ou rode `terraform output`) e aplique diretamente, sem commitar:

```bash
cp secrets.example.yaml secrets-reais.yaml
# edite secrets-reais.yaml com os valores reais
kubectl create namespace togglemaster
kubectl apply -f secrets-reais.yaml
rm secrets-reais.yaml
```

## Passo 7 — Instalar o ArgoCD

```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

kubectl patch svc argocd-server -n argocd -p '{"spec":{"type":"LoadBalancer"}}'
kubectl get svc argocd-server -n argocd   # pegue o EXTERNAL-IP/hostname

kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d
```

No `gitops/argocd-application.yaml` (dentro do repo `togglemaster-gitops`),
troque `SEU_USER` pelo seu usuário do GitHub. Depois:

```bash
kubectl apply -f gitops/argocd-application.yaml
```

O ArgoCD vai sincronizar automaticamente os 5 microsserviços a partir do
repositório GitOps.

## Passo 8 — Disparar as pipelines de aplicação

Qualquer push em `main` que mexa em `auth-service/`, `flag-service/`,
`targeting-service/`, `evaluation-service/` ou `analytics-service/`
dispara o workflow daquele serviço: build/testes → lint → security
(SAST + SCA, com bloqueio em vulnerabilidade CRÍTICA/HIGH) → build e push
da imagem no ECR → scan da imagem → atualização automática da tag no
repo GitOps → ArgoCD detecta e sincroniza no cluster.

Para demonstrar o bloqueio de segurança pedido na Fase 3: introduza uma
dependência com vulnerabilidade crítica conhecida (ex: uma lib desatualizada
no `requirements.txt`/`go.mod`) num Pull Request e mostre o job `security`
falhando; depois corrija e mostre passando. O mesmo vale pro job `plan` de
`terraform.yml`: dá pra demonstrar a revisão de infraestrutura abrindo um PR
que mexe em `terraform/` e mostrando o comentário automático com o plano.

---

## Notas de design

- **Credenciais da pipeline de Terraform vs. pipelines de aplicação:**
  são DUAS Roles IAM diferentes, por menor privilégio. `AWS_ROLE_ARN_TERRAFORM`
  (ampla, criada manualmente uma vez pelo `scripts/bootstrap.sh`) é assumida
  só por `terraform.yml`, que precisa criar/alterar praticamente qualquer
  recurso AWS do projeto. `AWS_ROLE_ARN` (estreita, só `ecr:*` nos 5
  repositórios do projeto) é criada PELO PRÓPRIO Terraform
  (`terraform/modules/github-oidc/`) e usada só pelas 5 pipelines de
  aplicação, que não precisam — e por isso não podem — mexer em mais nada.
  As duas reaproveitam o MESMO provedor OIDC do GitHub (criado uma vez no
  bootstrap; o módulo `github-oidc` só o consulta via `data source`, nunca
  tenta recriá-lo — a AWS permite só um por conta).
- **Autenticação:** 100% OIDC (GitHub ↔ AWS), sem access keys fixas em
  nenhum Secret — só funciona em conta pessoal. Se for rodar em conta AWS
  Academy, troque `use_academy_lab_role = true` e adapte os workflows para
  usar `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` como Secrets (a LabRole
  não confia no provedor OIDC do GitHub, e não é possível editar sua trust
  policy no Academy).
- **Regra de bloqueio de segurança:** o Trivy bloqueia em severidade
  CRITICAL (SCA de dependências e do container). gosec/bandit não têm o
  conceito de "crítico" — usamos HIGH como equivalente para o SAST.
  Achados de qualquer severidade continuam visíveis na aba Security do
  GitHub (upload do SARIF completo), só o gate de bloqueio é mais estrito.
- **Segredos fora do Git:** ao contrário do `secrets.yaml` com valores
  reais commitados na Fase 2, aqui os Secrets são aplicados manualmente
  no cluster e o ArgoCD nunca os gerencia — resolve exatamente a queixa
  do enunciado ("credenciais em arquivo de texto sem segurança"). A
  pipeline de Terraform escreve outputs no repo GitOps ao final do apply,
  mas só valores não-sensíveis (ARNs de IAM Role, URL da fila SQS) — nunca
  senha ou connection string completa.
- **Backend do Terraform sem bucket hardcoded:** `terraform/backend.tf`
  deixa o campo `bucket` de fora de propósito (bloco `backend` não aceita
  variáveis do Terraform) e ele é passado via `-backend-config` tanto pela
  pipeline (lendo o Secret `TF_STATE_BUCKET`) quanto localmente, se você
  quiser rodar `terraform plan` na sua máquina para conferir algo:
  `terraform init -backend-config="bucket=$(terraform output -raw 2>/dev/null || echo SEU_BUCKET)"`
  — na prática, mais simples: `terraform init -backend-config="bucket=NOME_DO_BUCKET"`
  usando o nome impresso pelo `bootstrap.sh`.
