# ============================================================
# OUTPUTS (root module)
#
# Um "output" é um valor que o Terraform IMPRIME na tela depois do
# `terraform apply` (e que também fica salvo no state, podendo ser
# lido depois com `terraform output <nome>`).
#
# Aqui eles servem pra pegar informação que só existe DEPOIS de criar
# o recurso na AWS (ex: o endpoint de um banco RDS só é gerado quando
# a AWS efetivamente cria a instância) — e usar esse valor manualmente
# nos próximos passos manuais: Secrets do GitHub, ConfigMap do
# Kubernetes, annotation das ServiceAccounts (veja o README.md).
# ============================================================

output "vpc_id" {
  value = module.vpc.vpc_id
}

output "eks_cluster_name" {
  value = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  description = "URL da API do Kubernetes (usada pelo kubectl)"
  value       = module.eks.cluster_endpoint
}

output "eks_oidc_provider_arn" {
  description = "ARN do OIDC provider do cluster — não precisa usar manualmente, é consumido internamente pelos módulos irsa_*"
  value       = module.eks.oidc_provider_arn
}

output "rds_auth_endpoint" {
  description = "Endereço (host:porta) do banco do auth-service — vai dentro do DATABASE_URL do secrets-reais.yaml"
  value       = module.rds_auth.endpoint
}

output "rds_flag_endpoint" {
  description = "Endereço do banco do flag-service"
  value       = module.rds_flag.endpoint
}

output "rds_targeting_endpoint" {
  description = "Endereço do banco do targeting-service"
  value       = module.rds_targeting.endpoint
}

output "elasticache_redis_url" {
  description = "URL completa (redis://host:porta) pra colocar direto na variável REDIS_URL do evaluation-service"
  value       = module.elasticache.redis_url
}

output "dynamodb_table_name" {
  description = "Nome da tabela DynamoDB (sempre 'ToggleMasterAnalytics', fixo por exigência do enunciado)"
  value       = module.dynamodb.table_name
}

output "sqs_queue_url" {
  description = "URL da fila SQS — vai no ConfigMap gitops/configmap.yaml (chave AWS_SQS_URL)"
  value       = module.sqs.queue_url
}

output "sqs_queue_arn" {
  value = module.sqs.queue_arn
}

output "ecr_repository_urls" {
  description = "Mapa {nome-do-serviço => URL do repositório ECR}, ex: para usar em docker push manual"
  value       = module.ecr.repository_urls
}

output "github_actions_role_arn" {
  description = "Cole este valor no Secret AWS_ROLE_ARN do repositório GitHub (Settings -> Secrets and variables -> Actions)"
  value       = module.github_oidc.role_arn
}

output "evaluation_service_role_arn" {
  description = "Cole na annotation eks.amazonaws.com/role-arn da ServiceAccount 'evaluation-service' em gitops/service-accounts.yaml"
  value       = module.irsa_evaluation.role_arn
}

output "analytics_service_role_arn" {
  description = "Cole na annotation eks.amazonaws.com/role-arn da ServiceAccount 'analytics-service' em gitops/service-accounts.yaml"
  value       = module.irsa_analytics.role_arn
}
