variable "prefix"          { type = string } # nome/identificador da instância (ex: "togglemaster-auth")
variable "db_name"         { type = string } # nome do banco dentro da instância (ex: "auth_db")
variable "username"        { type = string }
variable "password"        { type = string }
variable "vpc_id"          { type = string } # em qual VPC o Security Group vive
variable "vpc_cidr"        { type = string } # de onde é permitido conectar (só de dentro da VPC)
variable "private_subnets" { type = list(string) } # onde a instância fica de fato
variable "instance_class"  { type = string } # tamanho da máquina do banco
