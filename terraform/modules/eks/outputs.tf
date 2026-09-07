output "cluster_name" {
  description = "Nome do cluster — usado em 'aws eks update-kubeconfig --name ...'"
  value       = aws_eks_cluster.main.name
}

output "cluster_endpoint" {
  description = "URL da API do Kubernetes"
  value       = aws_eks_cluster.main.endpoint
}

output "cluster_arn" {
  value = aws_eks_cluster.main.arn
}

output "oidc_provider_arn" {
  description = "ARN do Identity Provider OIDC do cluster — consumido pelo módulo irsa/ para montar a trust policy de cada Role de Pod"
  value       = aws_iam_openid_connect_provider.eks.arn
}

output "oidc_issuer_url" {
  description = "URL do issuer OIDC do cluster, SEM o prefixo https:// (a sintaxe de condição de trust policy do IAM não aceita o https://)"
  value       = replace(aws_eks_cluster.main.identity[0].oidc[0].issuer, "https://", "")
}
