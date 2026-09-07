# Outputs que outros módulos (eks, rds, elasticache) vão consumir
# como input, pra saber em qual VPC/subnet criar seus recursos.

output "vpc_id" {
  value = aws_vpc.main.id
}

output "private_subnets" {
  description = "IDs das 2 subnets privadas — onde o EKS, RDS e Redis rodam"
  value       = aws_subnet.privada[*].id # [*] pega o id de TODAS as subnets criadas pelo count
}

output "public_subnets" {
  description = "IDs das 2 subnets públicas — onde fica o Load Balancer do Ingress"
  value       = aws_subnet.publica[*].id
}

output "nat_gateway_id" {
  value = aws_nat_gateway.main[0].id
}
