# Inputs deste módulo. A maioria vem direto das variables.tf da raiz
# (repassadas em main.tf), exceto vpc_id/private_subnets/public_subnets
# que vêm do OUTPUT do módulo vpc.

variable "prefix"          { type = string } # nome do cluster e prefixo das roles
variable "cluster_version" { type = string } # versão do Kubernetes
variable "aws_region"      { type = string } # usado só no comando local-exec do kubeconfig
variable "private_subnets" { type = list(string) } # onde os nodes/pods rodam
variable "public_subnets"  { type = list(string) } # necessário pro control plane multi-AZ
variable "instance_type"   { type = string } # tipo de máquina EC2 dos nodes
variable "desired_size"    { type = number } # nodes ao subir o cluster
variable "min_size"        { type = number } # piso do autoscaling de nodes
variable "max_size"        { type = number } # teto do autoscaling de nodes

variable "use_lab_role" {
  description = "true = conta AWS Academy (reaproveita a LabRole existente). false = conta pessoal (cria roles IAM próprias)."
  type        = bool
  default     = false
}
