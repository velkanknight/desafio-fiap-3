# ============================================================
# MÓDULO: IRSA (IAM Role for Service Accounts)
#
# Resolve um problema parecido com o do módulo github-oidc/, mas
# para dentro do CLUSTER: como dar permissão AWS (SQS, DynamoDB) pra
# um POD específico, sem colocar AWS_ACCESS_KEY_ID/SECRET dentro
# dele (que ficaria em texto simples num ConfigMap/Secret, e valeria
# pra sempre se vazasse)?
#
# A resposta é a mesma ideia de "confiança via OIDC", só que agora
# quem emite o token de identidade é O PRÓPRIO CLUSTER EKS (o OIDC
# provider criado no módulo eks/), não o GitHub. Quando um Pod usa
# uma ServiceAccount anotada com "eks.amazonaws.com/role-arn", o
# Kubernetes injeta automaticamente um token temporário nele, e o
# SDK da AWS (boto3, aws-sdk-go) sabe usar esse token pra virar
# credenciais AWS de verdade — de novo, sem senha fixa.
#
# Este módulo é GENÉRICO (só monta UMA Role) — é chamado 2 vezes em
# main.tf: uma pro evaluation-service, outra pro analytics-service,
# cada uma com uma política de permissão diferente.
# ============================================================

# Monta a trust policy: só a ServiceAccount exata
# "namespace:nome-da-service-account" pode assumir esta Role.
data "aws_iam_policy_document" "trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    # O provider aqui é o OIDC DO CLUSTER (module.eks.oidc_provider_arn
    # em main.tf) — bem diferente do OIDC do GitHub usado no outro módulo.
    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_issuer}:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Esta é a condição que "amarra" a Role a UMA ServiceAccount
    # específica: o formato "system:serviceaccount:<namespace>:<nome>"
    # é como o Kubernetes identifica uma ServiceAccount de forma
    # única dentro do cluster inteiro. Só Pods que usam ESSA
    # ServiceAccount exata (definida em gitops/service-accounts.yaml)
    # conseguem token válido pra esta Role.
    condition {
      test     = "StringEquals"
      variable = "${var.oidc_issuer}:sub"
      values   = ["system:serviceaccount:${var.namespace}:${var.service_account_name}"]
    }
  }
}

resource "aws_iam_role" "this" {
  name               = var.role_name
  assume_role_policy = data.aws_iam_policy_document.trust.json
}

# A permissão de verdade (o "o que pode fazer") é passada de FORA
# (var.policy_json), porque cada chamada deste módulo precisa de uma
# permissão diferente — evaluation-service só envia mensagem SQS;
# analytics-service lê/apaga da fila e grava no DynamoDB. Ver main.tf
# da raiz para o conteúdo exato de cada policy.
resource "aws_iam_role_policy" "this" {
  name   = "${var.role_name}-policy"
  role   = aws_iam_role.this.id
  policy = var.policy_json
}
