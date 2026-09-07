output "queue_url" {
  description = "Vai na env AWS_SQS_URL do evaluation-service e do analytics-service (via ConfigMap)"
  value       = aws_sqs_queue.main.url
}

output "queue_arn" {
  description = "Usado pelos módulos irsa_evaluation/irsa_analytics em main.tf pra restringir a permissão só a esta fila"
  value       = aws_sqs_queue.main.arn
}

output "dlq_url" { value = aws_sqs_queue.dlq.url }
