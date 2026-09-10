# ============================================================
# MÓDULO: ECR (registro de imagens Docker)
#
# Cria 1 repositório por microsserviço. A pipeline de CI
# (.github/workflows/*.yml) faz "docker push" pra cá depois de
# buildar cada imagem; os Deployments do Kubernetes (gitops/) puxam
# ("docker pull") a imagem daqui pra rodar os Pods.
# ============================================================

resource "aws_ecr_repository" "services" {
  # for_each roda este bloco UMA VEZ PRA CADA valor do conjunto —
  # aqui, cria 5 repositórios, um pra cada nome nesta lista.
  # "each.value" dentro do bloco é o nome atual da iteração.
  for_each = toset([
    "auth-service",
    "flag-service",
    "targeting-service",
    "evaluation-service",
    "analytics-service"
  ])

  name = "${var.prefix}/${each.value}" # ex: "togglemaster/auth-service"

  # Permite o "terraform destroy" apagar o repositório mesmo que ele
  # ainda contenha imagens (a CI enche isso de tags). Sem isto, o
  # destroy falha com RepositoryNotEmptyException.
  force_delete = true

  # Faz a AWS escanear a imagem automaticamente por vulnerabilidades
  # conhecidas toda vez que uma nova versão é enviada (push).
  image_scanning_configuration {
    scan_on_push = true
  }

  tags = { Name = "${var.prefix}-${each.value}" }
}

# Política de "faxina" automática: apaga imagens SEM TAG (imagens
# "soltas", geralmente sobras de builds antigos) com mais de 14 dias
# — evita acumular lixo e custo de armazenamento no ECR.
resource "aws_ecr_lifecycle_policy" "cleanup" {
  for_each = aws_ecr_repository.services # uma policy de limpeza por repositório

  repository = each.value.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Remove untagged images older than 14 days"
      selection = {
        tagStatus   = "untagged"
        countType   = "sinceImagePushed"
        countUnit   = "days"
        countNumber = 14
      }
      action = {
        type = "expire" # "expire" = apagar
      }
    }]
  })
}
