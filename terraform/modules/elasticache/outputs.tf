output "redis_endpoint" {
  description = "host:porta do nó Redis (sem o prefixo redis://)"
  value       = "${aws_elasticache_cluster.main.cache_nodes[0].address}:${aws_elasticache_cluster.main.cache_nodes[0].port}"
}

output "redis_url" {
  description = "URL completa (redis://host:porta), pronta pra jogar direto na variável REDIS_URL do evaluation-service"
  value       = "redis://${aws_elasticache_cluster.main.cache_nodes[0].address}:${aws_elasticache_cluster.main.cache_nodes[0].port}"
}

output "subnet_group_name" { value = aws_elasticache_subnet_group.main.name }
output "security_group_id" { value = aws_security_group.elasticache.id }
