# ============================================================
# ARQUIVO PRINCIPAL — é o "orquestrador": não cria recursos AWS
# diretamente (quase tudo mora dentro de modules/), ele só CHAMA
# cada módulo na ordem certa e conecta as saídas (outputs) de um
# módulo como entradas (inputs) do próximo.
#
# COMO AS CAMADAS SE ENCAIXAM (leia de cima para baixo, é a ordem
# de dependência real):
#
#   1. vpc            -> cria a rede (sem rede, nada mais existe)
#   2. eks             -> cria o cluster Kubernetes DENTRO da vpc
#   3. rds_* / elasticache / dynamodb / sqs / ecr
#                      -> criam os "data stores" e a fila, também
#                         DENTRO da vpc (menos DynamoDB/ECR, que são
#                         serviços "sem servidor" e não vivem numa VPC)
#   4. github_oidc     -> permite que o GitHub Actions (fora da AWS)
#                         se autentique na AWS pra publicar imagens
#                         no ECR criado no passo 3
#   5. irsa_evaluation / irsa_analytics
#                      -> dão permissão pros PODS dentro do cluster
#                         EKS (passo 2) acessarem SQS/DynamoDB (passo 3)
#                         sem precisar de senha/access key fixa
#
# Depois que esse Terraform roda, o que sobra pra fazer é: instalar o
# ArgoCD dentro do cluster e apontar ele pro repositório GitOps (isso
# é feito com kubectl/helm, não com Terraform — ver README.md).
# ============================================================

terraform {
  # Versão mínima do Terraform. 1.10+ é exigido pelo "use_lockfile"
  # que usamos no backend.tf (recurso novo, não existe em versões antigas).
  required_version = ">= 1.10.0"

  # "required_providers" declara quais plugins (providers) o Terraform
  # precisa baixar para conseguir criar os recursos deste projeto.
  required_providers {
    # Provider oficial da AWS — sem ele não dá pra criar nada na AWS.
    aws = {
      source  = "hashicorp/aws" # de onde baixar o plugin
      version = "~> 5.0"        # aceita qualquer versão 5.x (5.1, 5.42, etc.)
    }
    # Provider "tls" — usado dentro do módulo eks/ só para ler o
    # certificado do OIDC do cluster (necessário pra criar o
    # OIDC Provider do EKS, que por sua vez viabiliza o IRSA).
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

# Configura o provider AWS: em qual região da AWS os recursos vão
# ser criados. O valor vem da variável aws_region (variables.tf),
# que tem "us-east-1" como padrão.
provider "aws" {
  region = var.aws_region
}

# "data" busca informação de algo que JÁ EXISTE na AWS (não cria
# nada). Aqui, pega o ID da conta AWS que está autenticada — usado
# só como referência/local (não é obrigatório usá-lo, mas é comum
# precisar do account_id para montar ARNs ou nomes únicos).
data "aws_caller_identity" "current" {}

# "locals" são variáveis internas de conveniência (não são
# parametrizáveis de fora como as variables). Aqui, "prefix" é usado
# em quase todo módulo para nomear os recursos de forma consistente
# (ex: "togglemaster-auth-role", "togglemaster-events", etc.).
locals {
  account_id = data.aws_caller_identity.current.account_id
  prefix     = "togglemaster"
}

# ─────────────────────────────────────────────────────────
# CAMADA 1: REDE (VPC)
# Cria a VPC, subnets públicas/privadas, Internet Gateway, NAT
# Gateway e as tabelas de rota. Toda a infraestrutura das próximas
# camadas (EKS, RDS, Redis) roda DENTRO dessa rede.
# ─────────────────────────────────────────────────────────
module "vpc" {
  source = "./modules/vpc" # caminho local do módulo (pasta terraform/modules/vpc)

  vpc_cidr = var.vpc_cidr # bloco de IPs da VPC inteira (ex: 10.0.0.0/16)
  prefix   = local.prefix # prefixo usado no nome dos recursos
}

# ─────────────────────────────────────────────────────────
# CAMADA 2: CLUSTER KUBERNETES (EKS)
# Cria o control plane do Kubernetes gerenciado pela AWS + o grupo
# de máquinas EC2 (node group) que efetivamente rodam os Pods.
# Repare que ele CONSOME as subnets que a VPC (camada 1) criou.
# ─────────────────────────────────────────────────────────
module "eks" {
  source = "./modules/eks"

  prefix          = local.prefix
  cluster_version = var.kubernetes_version    # versão do Kubernetes, ex: "1.30"
  aws_region      = var.aws_region
  vpc_id          = module.vpc.vpc_id          # <- output do módulo vpc virando input aqui
  private_subnets = module.vpc.private_subnets # os nodes/pods rodam nas subnets PRIVADAS
  public_subnets  = module.vpc.public_subnets  # necessário pro control plane multi-AZ
  instance_type   = var.eks_node_instance_type # tipo de máquina EC2 dos nodes (ex: t3.medium)
  desired_size    = var.eks_desired_size       # quantos nodes o cluster começa tendo
  min_size        = var.eks_min_size
  max_size        = var.eks_max_size
  use_lab_role    = var.use_academy_lab_role   # true só em conta AWS Academy
}

# ─────────────────────────────────────────────────────────
# CAMADA 3a: BANCOS DE DADOS RELACIONAIS (RDS)
# O módulo "rds" é genérico (uma instância de PostgreSQL por
# chamada); aqui chamamos ele 3 VEZES, uma para cada microsserviço
# que precisa do seu PRÓPRIO banco (auth, flag, targeting). Cada
# instância é isolada — se um serviço "sujar" o schema dele, não
# afeta os outros dois.
# ─────────────────────────────────────────────────────────
module "rds_auth" {
  source = "./modules/rds"

  prefix          = "${local.prefix}-auth" # -> "togglemaster-auth"
  db_name         = "auth_db"              # nome do banco DENTRO da instância Postgres
  username        = var.db_username
  password        = var.db_password
  vpc_id          = module.vpc.vpc_id
  vpc_cidr        = var.vpc_cidr           # usado pra liberar acesso só de dentro da VPC
  private_subnets = module.vpc.private_subnets
  instance_class  = var.db_instance_class  # tamanho da máquina do banco (ex: db.t3.micro)
}

module "rds_flag" {
  source = "./modules/rds"

  prefix          = "${local.prefix}-flag"
  db_name         = "flag_db"
  username        = var.db_username
  password        = var.db_password
  vpc_id          = module.vpc.vpc_id
  vpc_cidr        = var.vpc_cidr
  private_subnets = module.vpc.private_subnets
  instance_class  = var.db_instance_class
}

module "rds_targeting" {
  source = "./modules/rds"

  prefix          = "${local.prefix}-targeting"
  db_name         = "targeting_db"
  username        = var.db_username
  password        = var.db_password
  vpc_id          = module.vpc.vpc_id
  vpc_cidr        = var.vpc_cidr
  private_subnets = module.vpc.private_subnets
  instance_class  = var.db_instance_class
}

# ─────────────────────────────────────────────────────────
# CAMADA 3b: CACHE (ElastiCache / Redis)
# Usado só pelo evaluation-service, no "hot path" (caminho de alta
# performance), pra não precisar bater no banco/outros serviços a
# cada avaliação de flag.
# ─────────────────────────────────────────────────────────
module "elasticache" {
  source = "./modules/elasticache"

  prefix          = local.prefix
  vpc_id          = module.vpc.vpc_id
  vpc_cidr        = var.vpc_cidr
  private_subnets = module.vpc.private_subnets
}

# ─────────────────────────────────────────────────────────
# CAMADA 3c: BANCO NoSQL (DynamoDB)
# Onde o analytics-service grava os eventos de avaliação. Não vive
# dentro de uma VPC (é um serviço gerenciado "serverless" da AWS,
# acessado via API/SDK, não por IP dentro da rede).
# ─────────────────────────────────────────────────────────
module "dynamodb" {
  source = "./modules/dynamodb"

  prefix = local.prefix
}

# ─────────────────────────────────────────────────────────
# CAMADA 3d: FILA DE MENSAGENS (SQS)
# O evaluation-service PRODUZ mensagens aqui (evento "flag X foi
# avaliada pro usuário Y"); o analytics-service CONSOME essas
# mensagens e grava no DynamoDB acima. É o que desacopla os dois
# serviços — se o analytics cair, as mensagens ficam esperando na fila.
# ─────────────────────────────────────────────────────────
module "sqs" {
  source = "./modules/sqs"

  prefix = local.prefix
}

# ─────────────────────────────────────────────────────────
# CAMADA 3e: REGISTRO DE IMAGENS DOCKER (ECR)
# Cria 1 repositório por microsserviço. É pra onde a pipeline de CI
# (.github/workflows/*.yml) faz `docker push` depois de buildar cada
# imagem, e de onde o Kubernetes puxa a imagem pra rodar os Pods.
# ─────────────────────────────────────────────────────────
module "ecr" {
  source = "./modules/ecr"

  prefix = local.prefix
}

# ─────────────────────────────────────────────────────────
# CAMADA 4: AUTENTICAÇÃO DA PIPELINE (OIDC do GitHub Actions)
# Cria a "ponte de confiança" entre o GitHub Actions e a AWS: em vez
# de guardar uma senha (access key) fixa como Secret do GitHub — que
# pode vazar e nunca expira sozinha — o GitHub gera um token
# temporário a cada execução do workflow, e a AWS confia nesse token
# (via OIDC) pra dar permissão de publicar imagem no ECR (camada 3e).
# ─────────────────────────────────────────────────────────
module "github_oidc" {
  source = "./modules/github-oidc"

  prefix      = local.prefix
  github_org  = var.github_org  # dono do repositório no GitHub (usuário ou organização)
  github_repo = var.github_repo # nome do repositório onde os workflows rodam

  # A pipeline só pode publicar imagem NOS 5 repositórios ECR criados
  # acima — princípio do menor privilégio (nada de acesso total ao ECR).
  ecr_repository_arns = values(module.ecr.repository_arns)
}

# ─────────────────────────────────────────────────────────
# CAMADA 5a: PERMISSÃO DO POD evaluation-service (IRSA)
# IRSA = "IAM Role for Service Accounts": deixa um Pod específico
# (via sua ServiceAccount do Kubernetes) assumir uma IAM Role da AWS
# com permissões mínimas, sem precisar de access key dentro do Pod.
# O evaluation-service só PRODUZ mensagem na fila SQS (camada 3d) —
# não pode ler nem apagar mensagem, só mandar.
# ─────────────────────────────────────────────────────────
module "irsa_evaluation" {
  source = "./modules/irsa"

  role_name = "${local.prefix}-evaluation-role"

  # Estes dois vêm do módulo eks: é o OIDC do PRÓPRIO cluster
  # Kubernetes (diferente do OIDC do GitHub usado na camada 4!) —
  # é o que permite o Kubernetes "provar" pra AWS qual ServiceAccount
  # está pedindo a credencial.
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_issuer       = module.eks.oidc_issuer_url

  namespace            = "togglemaster"      # namespace do Kubernetes onde o pod roda
  service_account_name = "evaluation-service" # tem que bater com o metadata.name do ServiceAccount no gitops/service-accounts.yaml

  # Política IAM (JSON) com a permissão exata que essa Role tem.
  # jsonencode() transforma o mapa do Terraform num JSON de verdade.
  policy_json = jsonencode({
    Version = "2012-10-17" # versão fixa da sintaxe de política IAM (sempre esse valor)
    Statement = [{
      Effect   = "Allow"
      Action   = ["sqs:SendMessage"] # só pode ENVIAR mensagem
      Resource = module.sqs.queue_arn # só NESSA fila específica, nenhuma outra
    }]
  })
}

# ─────────────────────────────────────────────────────────
# CAMADA 5b: PERMISSÃO DO POD analytics-service (IRSA)
# Esse Pod CONSOME da fila (lê + apaga a mensagem depois de
# processar) e GRAVA no DynamoDB. Duas permissões, um só Role.
# ─────────────────────────────────────────────────────────
module "irsa_analytics" {
  source = "./modules/irsa"

  role_name = "${local.prefix}-analytics-role"

  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_issuer       = module.eks.oidc_issuer_url

  namespace            = "togglemaster"
  service_account_name = "analytics-service"

  policy_json = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",     # ler mensagem da fila
          "sqs:DeleteMessage",      # apagar depois de processar (senão ela volta pra fila)
          "sqs:GetQueueAttributes", # ver metadados da fila (ex: quantas mensagens tem)
        ]
        Resource = module.sqs.queue_arn
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem", # gravar um novo evento
          "dynamodb:GetItem", # ler um evento específico
          "dynamodb:Scan",    # listar/varrer a tabela inteira (usado em debug/relatório)
        ]
        Resource = module.dynamodb.table_arn # só NESSA tabela, nenhuma outra
      },
    ]
  })
}
