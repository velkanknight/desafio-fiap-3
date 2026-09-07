output "table_name" { value = aws_dynamodb_table.main.name }

output "table_arn" {
  description = "Usado pelo módulo irsa_analytics em main.tf para restringir a permissão só a esta tabela"
  value       = aws_dynamodb_table.main.arn
}
