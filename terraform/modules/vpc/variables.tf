# Inputs que este módulo espera receber de quem o chama (main.tf da raiz).

variable "vpc_cidr" {
  description = "Bloco de IPs de toda a VPC, ex: 10.0.0.0/16"
  type        = string
}

variable "prefix" {
  description = "Prefixo usado no nome (tag Name) de todos os recursos deste módulo"
  type        = string
}
