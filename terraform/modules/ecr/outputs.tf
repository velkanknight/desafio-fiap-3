# Ambos os outputs abaixo retornam um MAPA (dicionário), no formato
# { "auth-service" => "...", "flag-service" => "...", ... } — um
# valor por serviço, graças ao for_each usado no main.tf deste módulo.

output "repository_urls" {
  description = "URL de cada repositório ECR — usada nos Deployments do gitops/ e no docker push da pipeline"
  value = {
    for svc, repo in aws_ecr_repository.services :
    svc => repo.repository_url
  }
}

output "repository_arns" {
  description = "ARN de cada repositório — usado pelo módulo github-oidc/ para restringir a permissão de push só a estes 5 repositórios"
  value = {
    for svc, repo in aws_ecr_repository.services :
    svc => repo.arn
  }
}
