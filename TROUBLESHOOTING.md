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
