# ============================================================
# MÓDULO: OIDC do GitHub Actions
#
# PROBLEMA que este módulo resolve: a pipeline de CI/CD precisa
# autenticar na AWS pra publicar imagem no ECR. O jeito "antigo" e
# inseguro seria criar um usuário IAM com access key fixa e colar
# essa chave como Secret do GitHub — o problema é que essa chave
# NUNCA expira sozinha, e se vazar (ex: log mal configurado, repo
# público sem querer), o AWS_ACCESS_KEY_ID vazado vale pra sempre.
#
# SOLUÇÃO (OIDC / OpenID Connect): o GitHub gera um "token de
# identidade" novo e temporário TODA VEZ que um workflow roda,
# provando "eu sou o workflow X, do repositório Y, rodando agora".
# A AWS confia nesse token (porque registramos o GitHub como um
# "Identity Provider" abaixo) e troca ele por credenciais AWS
# temporárias (que expiram em minutos) — sem NENHUMA senha fixa
# guardada em lugar nenhum.
#
# Isso só funciona em conta AWS PESSOAL (para criar um Identity
# Provider e uma IAM Role você precisa de permissão de IAM, que o
# AWS Academy não dá).
# ============================================================

# ------------------------------------------------------------------
# ATENÇÃO — isto é um "data source" (SÓ CONSULTA), não um "resource"
# (que criaria algo novo). O provedor OIDC do GitHub NÃO é criado por
# aqui: ele já foi criado UMA ÚNICA VEZ, manualmente, pelo script
# scripts/bootstrap.sh, ANTES do primeiro `terraform apply`.
#
# Por quê? Dois motivos:
#
#   1. Problema do "ovo e da galinha": este projeto agora roda o
#      `terraform apply` DENTRO de uma pipeline do GitHub Actions
#      (.github/workflows/terraform.yml). Só que ESSA pipeline
#      precisa, ela mesma, se autenticar na AWS via OIDC — ou seja,
#      o provedor OIDC (e uma Role que confie nele) precisam existir
#      ANTES da primeira vez que o Terraform roda. Não dá pra usar o
#      Terraform pra criar a própria credencial que o Terraform usa
#      pra rodar.
#
#   2. A AWS permite só UM provedor OIDC por URL por conta inteira.
#      Se o `bootstrap.sh` já criou
#      "token.actions.githubusercontent.com" manualmente e este
#      módulo tentasse criar de novo com `resource`, o segundo
#      `terraform apply` quebraria com erro "EntityAlreadyExists".
#
# Este módulo continua sendo dono da Role mais ESTREITA (só ECR push)
# usada pelas 5 pipelines de aplicação — a Role AMPLA usada pela
# pipeline de Terraform é outra, criada pelo bootstrap.sh (ver
# scripts/bootstrap.sh e a seção "Credenciais da pipeline" do README).
# ------------------------------------------------------------------
data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

# "data source" que MONTA (mas não cria nada ainda) o JSON da trust
# policy — ou seja, a regra de "quem pode assumir esta Role".
data "aws_iam_policy_document" "trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"] # a "versão OIDC" do AssumeRole

    # O "principal" (quem pode tentar assumir) é o Identity Provider
    # que acabamos de registrar acima — ou seja, só tokens emitidos
    # PELO GitHub (e confirmados por ele) chegam nesta regra.
    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github.arn]
    }

    # Confirma que o token foi emitido especificamente pra se
    # autenticar na AWS (evita "replay" de um token do GitHub feito
    # pra outro propósito).
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # A condição MAIS IMPORTANTE de segurança: restringe pra que só
    # workflows RODANDO NO REPOSITÓRIO "github_org/github_repo"
    # consigam assumir essa Role — um workflow de outro repositório
    # qualquer (mesmo de outra conta) não passa por essa condição.
    # O "*" no final aceita qualquer branch/PR/tag desse repo; pra
    # restringir só à branch main, troque por "ref:refs/heads/main".
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_org}/${var.github_repo}:*"]
    }
  }
}

# A IAM Role que o workflow do GitHub Actions assume (é o valor que
# vai no Secret AWS_ROLE_ARN, usado pelo "role-to-assume" da action
# aws-actions/configure-aws-credentials nos workflows).
resource "aws_iam_role" "github_actions" {
  name               = "${var.prefix}-github-actions"
  assume_role_policy = data.aws_iam_policy_document.trust.json # a regra montada acima
}

# Agora definimos O QUE essa Role pode FAZER (permissões de verdade,
# diferente da trust policy acima, que só define QUEM pode assumi-la).
data "aws_iam_policy_document" "ci_permissions" {
  # "GetAuthorizationToken" é uma ação especial do ECR que não aceita
  # restringir por recurso específico (por isso Resource = "*") — é
  # só o "login" no registro, não dá acesso a nenhuma imagem sozinho.
  statement {
    sid       = "ECRAuth"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  # Aqui sim restringimos: a pipeline só pode empurrar (push) imagem
  # PROS 5 REPOSITÓRIOS ECR criados no módulo ecr/ — nenhum outro
  # repositório ECR da conta, mesmo que exista.
  statement {
    sid    = "ECRPush"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
      "ecr:PutImage",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:DescribeRepositories",
      "ecr:DescribeImageScanFindings",
    ]
    resources = var.ecr_repository_arns # lista de ARNs vinda do módulo ecr/ (via main.tf da raiz)
  }
}

# Anexa essa política DIRETO na role (política "inline", só existe
# atrelada a esta Role específica — mais simples que criar uma
# managed policy separada pra usar só aqui).
resource "aws_iam_role_policy" "ci_permissions" {
  name   = "${var.prefix}-github-actions-ecr"
  role   = aws_iam_role.github_actions.id
  policy = data.aws_iam_policy_document.ci_permissions.json
}
