# ============================================================
# MÓDULO: VPC (rede)
#
# É a CAMADA MAIS BAIXA de toda a infraestrutura. Uma VPC (Virtual
# Private Cloud) é a sua "rede privada" dentro da AWS — sem ela,
# nenhum outro recurso (EKS, RDS, Redis) tem onde morar.
#
# O padrão usado aqui é o clássico "2 tipos de subnet":
#   - subnets PÚBLICAS: têm rota direta pra internet (via Internet
#     Gateway). Só o Load Balancer do Ingress do Kubernetes fica aqui.
#   - subnets PRIVADAS: NÃO são alcançáveis diretamente da internet.
#     É onde ficam os Pods do EKS, os bancos RDS e o Redis — mais
#     seguro, porque ninguém de fora consegue bater direto neles.
#
# Criamos 2 de cada (pública e privada), em 2 "Availability Zones"
# (AZs) diferentes, pra ter alta disponibilidade — se uma AZ cair,
# a outra continua de pé.
# ============================================================

# A VPC em si: só define o bloco de IPs (CIDR) que ela cobre.
resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr

  enable_dns_hostnames = true # dá nome DNS interno às instâncias (necessário pro EKS)
  enable_dns_support   = true # habilita a resolução de DNS dentro da VPC

  tags = { Name = "${var.prefix}-vpc" }
}

# Internet Gateway: é o "portão de saída/entrada" da VPC pra
# internet. Sem ele, NADA na VPC (nem as subnets públicas) consegue
# falar com a internet.
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.prefix}-igw" }
}

# Subnets PÚBLICAS (2, uma por AZ).
# "count = 2" cria 2 cópias deste bloco; use count.index (0, 1) pra
# diferenciar cada uma.
resource "aws_subnet" "publica" {
  count = 2

  vpc_id = aws_vpc.main.id

  # cidrsubnet() faz o "fatiamento" do bloco da VPC. Aqui pegamos um
  # /24 (256 IPs) começando no offset 10 (fica 10.0.10.0/24,
  # 10.0.11.0/24, ...) — só uma convenção pra não colidir com as
  # subnets privadas, que usam o offset 1, 2, ... (definidas abaixo).
  cidr_block = cidrsubnet(var.vpc_cidr, 8, 10 + count.index)

  # Cada subnet mora numa Availability Zone diferente (data source
  # abaixo lista as AZs disponíveis na região, ex: us-east-1a, 1b).
  availability_zone = data.aws_availability_zones.available.names[count.index]

  # Instâncias criadas nesta subnet recebem IP público automaticamente.
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.prefix}-publica-${count.index + 1}"
    # Tags especiais que o AWS Load Balancer Controller / Nginx
    # Ingress usam pra descobrir sozinhos em qual subnet colocar o
    # Load Balancer público.
    "kubernetes.io/role/elb"              = "1"
    "kubernetes.io/cluster/${var.prefix}" = "shared"
  }
}

# Subnets PRIVADAS (2, uma por AZ) — onde o EKS/RDS/Redis realmente vivem.
resource "aws_subnet" "privada" {
  count = 2

  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 1) # 10.0.1.0/24, 10.0.2.0/24
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name = "${var.prefix}-privada-${count.index + 1}"
    # Equivalente ao de cima, mas pra Load Balancers INTERNOS
    # (ex: se algum dia você quiser um Ingress só interno).
    "kubernetes.io/role/internal-elb"     = "1"
    "kubernetes.io/cluster/${var.prefix}" = "shared"
  }
}

# Elastic IP (IP público fixo) que o NAT Gateway abaixo vai usar.
resource "aws_eip" "nat" {
  count  = 1
  domain = "vpc"
}

# NAT Gateway: fica numa subnet PÚBLICA e permite que recursos nas
# subnets PRIVADAS iniciem conexões pra internet (ex: baixar uma
# imagem Docker de fora, ou instalar pacotes) SEM ficarem expostos
# a conexões vindas de fora. É diferente do Internet Gateway (que
# permite os dois sentidos) — o NAT só permite "sair", não "entrar".
resource "aws_nat_gateway" "main" {
  count         = 1
  allocation_id = aws_eip.nat[0].id
  subnet_id     = aws_subnet.publica[0].id # mora numa subnet pública

  depends_on = [aws_internet_gateway.main] # precisa do IGW já existir

  tags = { Name = "${var.prefix}-nat" }
}

# Tabela de rotas das subnets PÚBLICAS: manda todo tráfego externo
# (0.0.0.0/0 = "qualquer destino") direto pro Internet Gateway.
resource "aws_route_table" "publica" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = { Name = "${var.prefix}-publica-rt" }
}

# Tabela de rotas das subnets PRIVADAS: manda tráfego externo pro
# NAT Gateway (não pro Internet Gateway!) — assim elas conseguem
# "sair" mas ninguém de fora consegue "entrar" diretamente.
resource "aws_route_table" "privada" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main[0].id
  }

  tags = { Name = "${var.prefix}-privada-rt" }
}

# Associa cada subnet pública à tabela de rotas pública (sem isso, a
# tabela de rotas existe mas não vale pra ninguém).
resource "aws_route_table_association" "publica" {
  count          = 2
  subnet_id      = aws_subnet.publica[count.index].id
  route_table_id = aws_route_table.publica.id
}

# Mesma ideia, para as subnets privadas.
resource "aws_route_table_association" "privada" {
  count          = 2
  subnet_id      = aws_subnet.privada[count.index].id
  route_table_id = aws_route_table.privada.id
}

# Lista as Availability Zones disponíveis na região configurada
# (ex: us-east-1a, us-east-1b, ...) — usamos os 2 primeiros nomes
# dessa lista pra espalhar as subnets acima.
data "aws_availability_zones" "available" {
  state = "available"
}
