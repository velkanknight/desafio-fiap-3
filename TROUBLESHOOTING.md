# Troubleshooting — Fase 3 (deploy da infraestrutura)

Registro dos problemas encontrados ao rodar a pipeline `.github/workflows/terraform.yml`
pela primeira vez e como cada um foi resolvido.

Conta AWS: `676861816305` · Região: `us-east-1` · Repo: `velkanknight/desafio-fiap-3`

---

## 1. OIDC — `Not authorized to perform sts:AssumeRoleWithWebIdentity`

**Sintoma:** job `plan` falhava no step *"Autentica na AWS via OIDC"* com
`Could not assume role with OIDC: Not authorized to perform sts:AssumeRoleWithWebIdentity`.
A trust policy da Role `togglemaster-terraform-ci` parecia correta (`aws iam get-role`).

**Causa raiz (confirmada via CloudTrail):** o repositório emite o token OIDC com
**identificadores numéricos imutáveis** no claim `sub`:

```
repo:velkanknight@9701335/desafio-fiap-3@1360497373:ref:refs/heads/main
```

O `bootstrap.sh` gravou a condição no formato clássico
`repo:velkanknight/desafio-fiap-3:*`, que **não casa** com o `sub` acima (os
`@9701335` / `@1360497373` no meio quebram o `StringLike`). Não tinha nada a ver
com espaço/typo no secret `AWS_ROLE_ARN_TERRAFORM`.

**Correção aplicada:**
- Trust policy da Role `togglemaster-terraform-ci` atualizada manualmente
  (`aws iam update-assume-role-policy`) para:
  `token.actions.githubusercontent.com:sub` = `repo:velkanknight*/desafio-fiap-3*:*`
  (o `*` depois do org e do repo absorve os IDs numéricos).
- `terraform/modules/github-oidc/main.tf` — mesmo ajuste no `sub` da Role estreita
  (`repo:${var.github_org}*/${var.github_repo}*:*`), senão as 5 pipelines de
  aplicação (Passo 5/8) iam falhar com o mesmo erro.
- `scripts/bootstrap.sh` **ainda gera o formato antigo** — se rodar o bootstrap de
  novo numa conta limpa, aplicar o mesmo ajuste lá (linha do `token.actions.githubusercontent.com:sub`).

**Status:** ✅ resolvido (auth passou na run seguinte).

---

## 2. `terraform validate` — `An argument named "vpc_id" is not expected here`

**Sintoma:** job `plan` passava da autenticação e falhava no step
*"Terraform Validate"*:

```
Error: Unsupported argument
  on main.tf line 99, in module "eks":
  99:   vpc_id = module.vpc.vpc_id
```

**Causa:** o `module "eks"` recebia `vpc_id`, mas o módulo `terraform/modules/eks`
não declara nem usa essa variável (o cluster só precisa das subnets —
`aws_eks_cluster` recebe `subnet_ids`).

**Correção aplicada:** removida a linha `vpc_id = module.vpc.vpc_id` da chamada do
módulo `eks` em `terraform/main.tf`. `terraform validate` passa localmente (TF 1.14.4).

**Status:** ✅ resolvido.

---

## 3. EKS `version = "1.30"` — versão fora de suporte

**Sintoma:** ainda não chegou a rodar (seria erro no `apply`).

**Causa:** `aws eks describe-cluster-versions` em `us-east-1` só oferece
`1.31 … 1.36`. A 1.30 já saiu até do suporte estendido — `terraform apply`
falharia ao criar o cluster.

**Correção aplicada:** `variable "kubernetes_version"` default `1.30` → `1.33`
(`terraform/variables.tf`).

**Status:** ✅ corrigido no código (aguardando `apply`).

---

## 4. RDS `engine_version = "15.4"` — minor do Postgres descontinuado

**Sintoma:** ainda não chegou a rodar (seria erro no `apply` das 3 instâncias RDS).

**Causa:** `aws rds describe-db-engine-versions --engine postgres` não lista mais
o `15.4` (menor disponível hoje: `15.7`). Criar instância nova com `15.4` retorna
`InvalidParameterValue: Cannot find version 15.4 for postgres`.

**Correção aplicada:** `terraform/modules/rds/main.tf` — `engine_version = "15"`
(só o major; a AWS escolhe o minor suportado mais recente).

**Status:** ✅ corrigido no código (aguardando `apply`).

---

## 5. RDS — `MasterUsername admin ... is a reserved word used by the engine`

**Sintoma:** no `apply` (run `34160340362`), depois de criar VPC + EKS 1.33 +
node group + OIDC + IRSA com sucesso, as 3 instâncias RDS falharam:

```
InvalidParameterValue: MasterUsername *** cannot be used as it is a reserved
word used by the engine
  with module.rds_auth.aws_db_instance.main (idem flag e targeting)
```

**Causa:** `var.db_username` era `"admin"`. O PostgreSQL (15+) trata `admin`
como palavra reservada e o RDS recusa usá-la como master username.

**Correção aplicada:**
- `terraform/variables.tf` — default de `db_username` `"admin"` → `"toggleadmin"`.
- `terraform/terraform.tfvars.example` e `secrets.example.yaml` (3 DATABASE_URL)
  atualizados para `toggleadmin`.

**O que já existe na AWS depois dessa run:** VPC, EKS `togglemaster` (1.33),
node group, OIDC provider do cluster, roles `togglemaster-evaluation-role` /
`togglemaster-analytics-role` — o state foi salvo, o próximo `apply` só cria o
que faltou (RDS, ElastiCache, e o que depender deles).

**Status:** ✅ corrigido no código (aguardando novo `apply`).

---

## 6. RDS — `MasterUserPassword ... shorter than 8 characters`

**Sintoma:** run `34162731165`, apply falha em 18s nos 3 RDS:
`InvalidParameterValue: The parameter MasterUserPassword is not a valid
password because it is shorter than 8 characters`.

**Causa:** o secret `DB_PASSWORD` no GitHub tinha menos de 8 caracteres.
Não é código — é valor de secret.

**Correção:** secret `DB_PASSWORD` atualizado para 8+ caracteres.

**Status:** ✅ resolvido — na run `34163759388` os 3 RDS subiram
(`Apply complete! Resources: 3 added`).

---

## 6b. GitHub Actions bloqueado — email não verificado

**Sintoma:** runs de `workflow_dispatch` terminavam em `startup_failure` em 1s.

**Causa:** o email da conta GitHub estava sem verificar; o GitHub bloqueia
Actions nesse caso. Adicionar o email de novo dava "email already in use"
porque ele já estava na conta (só não verificado).

**Correção:** Settings → Emails → **Resend verification email** → clicar no
link recebido (não "Add email").

**Status:** ✅ resolvido.

---

## 7. Job falha no passo "Atualiza outputs no repositório GitOps" — 403

**Sintoma:** na run `34163759388`, `terraform apply` conclui com sucesso
(infra criada), mas o último passo falha:

```
remote: Permission to velkanknight/togglemaster-gitops.git denied to velkanknight
fatal: ... The requested URL returned error: 403
```

**Causa:** o secret `GH_PAT` não tem permissão de escrita no repositório
`togglemaster-gitops`. O clone/commit funcionam, só o `git push` é negado.
**Não afeta a infra** — ela já está criada e no state.

**Causa detalhada:** os tokens tentados eram **fine-grained** (`github_pat_...`),
que nascem sem repositório e sem permissão selecionados — não escrevem em nada.

**Correção:** gerado um PAT **classic** (`ghp_...`) com escopo `repo` + `workflow`
e colado no secret `GH_PAT` (`desafio-fiap-3` → Settings → Secrets and variables
→ Actions). As 5 pipelines de aplicação também usam esse secret.

**Status:** ✅ resolvido — run `34165598074` verde de ponta a ponta
(`Apply complete! 0 added` + push no `togglemaster-gitops` OK).

---

## Resultado final

Run `34165598074` (2026-09-07 ~22:08): **Plan ✅ + Apply ✅**. Infraestrutura
completa no ar e o repo `togglemaster-gitops` com os ARNs/SQS URL preenchidos.

Recursos criados: VPC `vpc-0aa01033dfa495e1c`, EKS `togglemaster` (1.33) +
node group, 3× RDS PostgreSQL 15, ElastiCache Redis, DynamoDB
`ToggleMasterAnalytics`, SQS `togglemaster-events` (+ DLQ), 5× ECR, OIDC
provider do cluster, roles IRSA `togglemaster-evaluation-role` /
`togglemaster-analytics-role`, role `togglemaster-github-actions` (ECR push).

Próximos passos: 5 a 8 do `README.md` (secret `AWS_ROLE_ARN`, secrets no
cluster, ArgoCD — agora via workflow `argocd.yml` — e pipelines de app).

---

## Pendências / pontos de atenção ainda não atingidos

Não bloqueiam a pipeline de Terraform, mas provavelmente aparecem nos passos
seguintes do README:

- **`scripts/bootstrap.sh`** ainda monta o `sub` no formato antigo (ver item 1) —
  ajustar se for reexecutar o bootstrap.
- **Pipelines de aplicação (Passo 8)** — `go-version: '1.22'` nos workflows pode
  não bater com o `go.mod` de cada serviço; `golangci-lint-action@v4` + `version: latest`
  pode quebrar por mudança de config do golangci-lint v2; `aquasecurity/trivy-action@master`
  está sem pin de versão.
- **Custo/tempo do `apply`:** cria NAT Gateway, 3× RDS, EKS + node group e
  ElastiCache — ~15–20 min e recursos cobrados na conta pessoal. Lembrar de
  `terraform destroy` ao final da entrega.
- **Aprovação manual:** se `Settings → Environments → production` tiver
  *required reviewers*, o job `apply` fica pausado esperando aprovação.

---

## Ordem para retomar

1. `git add -A && git commit && git push` na `main` (dispara a pipeline).
2. Acompanhar job `plan` → `apply` na aba Actions.
3. Seguir Passo 5 em diante do `README.md`.
