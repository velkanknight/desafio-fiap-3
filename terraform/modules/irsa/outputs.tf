output "role_arn" {
  description = "Cole na annotation eks.amazonaws.com/role-arn da ServiceAccount correspondente, em gitops/service-accounts.yaml"
  value       = aws_iam_role.this.arn
}
