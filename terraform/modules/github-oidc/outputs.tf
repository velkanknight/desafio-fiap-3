output "role_arn" {
  description = "Cole este valor no Secret AWS_ROLE_ARN do GitHub — é o que os workflows usam em 'role-to-assume'"
  value       = aws_iam_role.github_actions.arn
}
