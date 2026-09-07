# ============================================================
# MÓDULO: RDS (banco de dados PostgreSQL)
#
# Este módulo é GENÉRICO: cria UMA instância de PostgreSQL por
# chamada. Ele é usado 3 VEZES em main.tf (raiz) — uma pra
# auth-service, uma pra flag-service, uma pra targeting-service —
# cada chamada gerando um banco totalmente isolado das outras.
# ============================================================

# Security Group = "firewall" da instância RDS: define quem pode
# conectar nela e em qual porta.
resource "aws_security_group" "rds" {
  name        = "${var.prefix}-rds-sg"
  description = "Security group para RDS ${var.prefix}"
  vpc_id      = var.vpc_id # o SG pertence à mesma VPC do banco

  # Regra de ENTRADA: só libera a porta do Postgres (5432), e só pra
  # quem estiver DENTRO da própria VPC (var.vpc_cidr) — ninguém de
  # fora da rede consegue conectar direto no banco, nem com usuário/senha certos.
  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # Regra de SAÍDA: libera tudo (padrão comum — o RDS raramente
  # precisa "iniciar" conexões pra fora, mas deixamos aberto por
  # simplicidade/compatibilidade).
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1" # "-1" = qualquer protocolo
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.prefix}-rds-sg" }
}

# RDS precisa saber EM QUAIS subnets ele pode ser colocado — como
# são bancos internos, usamos só as subnets PRIVADAS.
resource "aws_db_subnet_group" "main" {
  name       = "${var.prefix}-subnet-group"
  subnet_ids = var.private_subnets
}

# A instância do banco em si.
resource "aws_db_instance" "main" {
  identifier     = var.prefix          # nome da instância na AWS (ex: "togglemaster-auth")
  engine         = "postgres"
  engine_version = "15" # major apenas: a AWS escolhe o minor suportado mais recente (15.4 foi descontinuado)
  instance_class = var.instance_class  # tamanho da máquina (ex: db.t3.micro)
  allocated_storage = 20               # espaço em disco, em GB

  db_name  = var.db_name               # nome do banco DENTRO da instância (ex: "auth_db")
  username = var.username
  password = var.password

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  # Em produção de verdade você NÃO quereria isso — sem snapshot
  # final, ao destruir a instância os dados somem de vez. Pra um
  # ambiente de estudo/challenge, evita custo de snapshot esquecido.
  skip_final_snapshot = true
}
