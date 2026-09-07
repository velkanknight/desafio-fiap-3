# ============================================================
# VARIÁVEIS DE ENTRADA (root module)
#
# Uma "variable" é um parâmetro configurável de fora — você define o
# valor real dela no arquivo terraform.tfvars (que NÃO é commitado,
# veja terraform.tfvars.example), e o Terraform usa esse valor em vez
# do "default" sempre que ele existir.
#
# Cada variável abaixo é repassada, dentro de main.tf, pra um ou mais
# módulos (é assim que o valor "viaja" do tfvars até o recurso real).
# ============================================================

variable "aws_region" {
  description = "Região AWS onde TUDO vai ser criado (VPC, EKS, RDS, etc.)"
  type        = string
  default     = "us-east-1"
}

variable "vpc_cidr" {
  description = "Bloco de IPs (CIDR) de toda a VPC. As subnets são fatias desse bloco."
  type        = string
  default     = "10.0.0.0/16" # ~65 mil IPs possíveis dentro da VPC
}

variable "kubernetes_version" {
  description = "Versão do Kubernetes que o cluster EKS vai rodar"
  type        = string
  default     = "1.33"
}

variable "eks_node_instance_type" {
  description = "Tipo de máquina EC2 usada pelos nodes (workers) do cluster EKS"
  type        = string
  default     = "t3.medium" # 2 vCPU / 4GB RAM — suficiente pros 5 microsserviços
}

variable "eks_desired_size" {
  description = "Quantos nodes (máquinas EC2) o cluster já sobe tendo"
  type        = number
  default     = 2
}

variable "eks_min_size" {
  description = "Nunca deixa o cluster ter menos nodes que isso"
  type        = number
  default     = 1
}

variable "eks_max_size" {
  description = "Teto de nodes, mesmo sob muita carga (autoscaling do cluster)"
  type        = number
  default     = 4
}

variable "use_academy_lab_role" {
  description = <<-EOT
    Chave que decide o "modo" de permissões do projeto:
      false (padrão) = conta AWS PESSOAL -> o Terraform cria as IAM
        Roles do zero (módulo eks/) e também o OIDC do GitHub Actions
        (módulo github-oidc/).
      true = conta AWS ACADEMY -> reaproveita a "LabRole" que já vem
        pronta na conta, porque no Academy não dá pra criar roles/
        OIDC provider novos (falta permissão de IAM).
  EOT
  type    = bool
  default = false
}

variable "db_username" {
  description = "Usuário administrador usado nos 3 bancos RDS (auth_db, flag_db, targeting_db). NÃO pode ser 'admin'/'rdsadmin' etc. — são palavras reservadas do PostgreSQL e o RDS recusa."
  type        = string
  sensitive   = true # o Terraform esconde esse valor nos logs/outputs de `plan`/`apply`
  default     = "toggleadmin"
}

variable "db_password" {
  description = "Senha dos 3 bancos RDS. SEM default de propósito — você é OBRIGADO a definir no terraform.tfvars, nunca commite esse arquivo."
  type        = string
  sensitive   = true
}

variable "db_instance_class" {
  description = "Tamanho da máquina de cada instância RDS (ex: db.t3.micro = grátis/barato, bom pra estudo)"
  type        = string
  default     = "db.t3.micro"
}

variable "github_org" {
  description = "Usuário ou organização dona do repositório no GitHub. Usado dentro do módulo github-oidc para restringir QUEM pode assumir a IAM Role da pipeline (trust policy)."
  type        = string
  default     = "velkanknight"
}

variable "github_repo" {
  description = "Nome do repositório GitHub onde os workflows de CI/CD (.github/workflows/*.yml) rodam. Junto com github_org, forma a condição 'repo:ORG/REPO:*' que a AWS confere antes de liberar o token OIDC."
  type        = string
  default     = "desafio-fiap-3"
}
