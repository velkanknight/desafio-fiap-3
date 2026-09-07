output "endpoint" {
  description = "Host do banco (sem a porta) — combine com 'port' abaixo para montar o DATABASE_URL"
  value       = aws_db_instance.main.address
}

output "port" {
  value = aws_db_instance.main.port
}

output "security_group_id" {
  value = aws_security_group.rds.id
}

output "subnet_group_name" {
  value = aws_db_subnet_group.main.name
}
