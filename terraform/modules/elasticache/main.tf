# ============================================================
# MÓDULO: ElastiCache (Redis)
#
# Usado só pelo evaluation-service: um cache em memória, com latência
# de ~1ms, pra ele não precisar chamar flag-service + targeting-
# -service via HTTP a cada avaliação de flag (isso seria lento demais
# pro "hot path" de alta performance).
# ============================================================

# Security Group do Redis — mesma lógica do RDS: só libera a porta
# do Redis (6379) pra quem estiver dentro da VPC.
resource "aws_security_group" "elasticache" {
  name        = "${var.prefix}-elasticache-sg"
  description = "Security group para ElastiCache ${var.prefix}"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 6379
    to_port     = 6379
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.prefix}-elasticache-sg" }
}

# Assim como o RDS precisa de um "db subnet group", o ElastiCache
# precisa saber em quais subnets ele pode ser colocado.
resource "aws_elasticache_subnet_group" "main" {
  name       = "${var.prefix}-cache-subnet"
  subnet_ids = var.private_subnets
}

# O cluster Redis em si — "cluster" aqui é meio enganoso, com
# num_cache_nodes = 1 é só UM nó Redis (suficiente pro challenge;
# em produção de verdade você usaria replicação/cluster-mode).
resource "aws_elasticache_cluster" "main" {
  cluster_id           = "${var.prefix}-redis"
  engine               = "redis"
  node_type            = "cache.t3.micro" # tamanho da máquina
  num_cache_nodes      = 1
  parameter_group_name = "default.redis7" # configurações padrão do Redis 7
  port                 = 6379
  security_group_ids   = [aws_security_group.elasticache.id]
  subnet_group_name    = aws_elasticache_subnet_group.main.name
}
