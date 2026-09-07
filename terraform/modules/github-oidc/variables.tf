variable "prefix"     { type = string }
variable "github_org"  { type = string } # dono do repositório (usuário/organização) no GitHub
variable "github_repo" { type = string } # nome do repositório — os dois juntos formam a condição de trust policy "repo:org/repo:*"

variable "ecr_repository_arns" {
  description = "ARNs dos 5 repositórios ECR (vindos do módulo ecr/) que esta Role tem permissão de publicar imagem"
  type        = list(string)
}
