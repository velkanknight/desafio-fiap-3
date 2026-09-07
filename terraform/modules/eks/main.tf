# ============================================================
# MÓDULO: EKS (cluster Kubernetes)
#
# Este módulo cria 3 coisas relacionadas, mas distintas:
#   1. As IAM Roles que o EKS e os nodes (EC2) PRECISAM ter pra
#      funcionar (control plane e workers rodam "como" essas roles).
#   2. O cluster EKS em si + o node group (as máquinas EC2 workers).
#   3. Um OIDC Provider APONTANDO PRO PRÓPRIO CLUSTER — não confundir
#      com o OIDC do GitHub Actions (módulo github-oidc/, que é outra
#      coisa completamente separada). Este aqui é o que possibilita o
#      IRSA (módulo irsa/): dar permissão AWS pra um Pod específico.
# ============================================================

# ------------------------------------------------------------
# 1. IAM ROLES do cluster e dos nodes
#
# Toda coisa na AWS que "faz algo" (cria, lê, apaga recursos)
# precisa de uma IAM Role/usuário com permissão pra isso. O EKS
# control plane precisa de uma role pra gerenciar recursos AWS em
# nome do cluster; os nodes (EC2) precisam de outra pra puxar imagem
# do ECR, se registrar no cluster, etc.
#
# Em conta AWS PESSOAL: criamos essas roles do zero (padrão).
# Em conta AWS ACADEMY: NÃO é possível criar roles novas — é
# obrigatório reaproveitar uma role pronta chamada "LabRole"
# (função do var.use_lab_role abaixo).
# ------------------------------------------------------------

# "data" (em vez de "resource") só LÊ uma role que já existe na AWS —
# só roda se use_lab_role = true (o "count = condição ? 1 : 0" é o
# jeito do Terraform fazer um recurso "opcional": 1 = cria/lê, 0 = ignora).
data "aws_iam_role" "lab_role" {
  count = var.use_lab_role ? 1 : 0
  name  = "LabRole"
}

# Role que o CONTROL PLANE do EKS assume. Só existe se use_lab_role = false.
resource "aws_iam_role" "cluster" {
  count = var.use_lab_role ? 0 : 1
  name  = "${var.prefix}-eks-cluster-role"

  # "assume_role_policy" (a "trust policy") diz QUEM pode assumir
  # essa role. Aqui: só o próprio serviço eks.amazonaws.com — ou
  # seja, só a AWS, operando o EKS por trás dos panos, pode usá-la.
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
      Action    = "sts:AssumeRole" # "sts:AssumeRole" = "pegar emprestada" essa identidade temporariamente
    }]
  })
}

# Anexa à role do cluster a policy PRONTA da AWS com as permissões
# mínimas que o control plane do EKS precisa (gerenciar ENIs,
# security groups, etc.) — não escrevemos essa policy do zero,
# usamos uma "managed policy" oficial da AWS.
resource "aws_iam_role_policy_attachment" "cluster_policy" {
  count      = var.use_lab_role ? 0 : 1
  role       = aws_iam_role.cluster[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# Role que os NODES (máquinas EC2 workers) assumem.
resource "aws_iam_role" "node" {
  count = var.use_lab_role ? 0 : 1
  name  = "${var.prefix}-eks-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" } # aqui quem assume é a própria EC2
      Action    = "sts:AssumeRole"
    }]
  })
}

# 3 policies gerenciadas, todas obrigatórias pra um node do EKS funcionar:
resource "aws_iam_role_policy_attachment" "node_worker" {
  count      = var.use_lab_role ? 0 : 1
  role       = aws_iam_role.node[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy" # deixa o node se registrar/operar no cluster
}

resource "aws_iam_role_policy_attachment" "node_cni" {
  count      = var.use_lab_role ? 0 : 1
  role       = aws_iam_role.node[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy" # permite o plugin de rede (VPC CNI) atribuir IPs aos Pods
}

resource "aws_iam_role_policy_attachment" "node_ecr" {
  count      = var.use_lab_role ? 0 : 1
  role       = aws_iam_role.node[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly" # permite puxar (pull) imagem Docker do ECR
}

# "locals" escolhe, EM TEMPO DE PLAN, qual ARN de role usar: a que
# acabamos de criar (conta pessoal) ou a LabRole existente (Academy).
# Isso evita repetir esse "if" em todo lugar que precisa da role.
locals {
  cluster_role_arn = var.use_lab_role ? data.aws_iam_role.lab_role[0].arn : aws_iam_role.cluster[0].arn
  node_role_arn    = var.use_lab_role ? data.aws_iam_role.lab_role[0].arn : aws_iam_role.node[0].arn
}

# ------------------------------------------------------------
# 2. CLUSTER EKS + NODE GROUP
# ------------------------------------------------------------

# O control plane do Kubernetes em si (API server, etcd, scheduler —
# tudo isso é gerenciado pela AWS, você não vê essas máquinas).
resource "aws_eks_cluster" "main" {
  name     = var.prefix               # nome do cluster (usado no kubectl / aws eks update-kubeconfig)
  role_arn = local.cluster_role_arn   # a role escolhida acima
  version  = var.cluster_version      # versão do Kubernetes

  vpc_config {
    # O control plane precisa enxergar TANTO as subnets privadas
    # (onde os Pods rodam) QUANTO as públicas (multi-AZ / ENIs).
    subnet_ids = concat(var.private_subnets, var.public_subnets)

    endpoint_public_access  = true # permite `kubectl` funcionar da sua máquina/CI, via internet
    endpoint_private_access = true # e também de dentro da própria VPC
  }

  # Só cria o cluster DEPOIS que a policy da role já estiver anexada
  # (sem isso, a criação pode falhar por falta de permissão ainda
  # não propagada).
  depends_on = [
    aws_iam_role_policy_attachment.cluster_policy
  ]
}

# O grupo de máquinas EC2 que efetivamente rodam os Pods (o control
# plane acima NÃO roda Pod nenhum, só orquestra).
resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.prefix}-default"
  node_role_arn   = local.node_role_arn
  subnet_ids      = var.private_subnets # nodes ficam nas subnets PRIVADAS (mais seguro)

  # Configuração de autoscaling do GRUPO DE NODES (diferente do HPA,
  # que escala PODS — aqui escala MÁQUINAS).
  scaling_config {
    desired_size = var.desired_size
    max_size     = var.max_size
    min_size     = var.min_size
  }

  instance_types = [var.instance_type]

  depends_on = [
    aws_eks_cluster.main,
    aws_iam_role_policy_attachment.node_worker,
    aws_iam_role_policy_attachment.node_cni,
    aws_iam_role_policy_attachment.node_ecr,
  ]
}

# ------------------------------------------------------------
# 3. OIDC PROVIDER DO PRÓPRIO CLUSTER (base do IRSA)
#
# Todo cluster EKS expõe um "issuer" OIDC próprio (uma URL). Se você
# registrar esse issuer como um "Identity Provider" dentro do IAM da
# AWS, fica possível uma ServiceAccount do Kubernetes "provar" pra
# AWS quem ela é e pedir emprestada uma IAM Role — isso é o IRSA,
# usado pelo módulo irsa/ para dar permissão ao evaluation-service e
# analytics-service (SQS/DynamoDB) sem access key fixa no Pod.
# ------------------------------------------------------------

# Busca o certificado TLS do endpoint OIDC do cluster — a AWS exige
# o "thumbprint" (impressão digital) desse certificado pra registrar
# o Identity Provider com segurança.
data "tls_certificate" "eks" {
  url = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  url             = aws_eks_cluster.main.identity[0].oidc[0].issuer
  client_id_list  = ["sts.amazonaws.com"] # quem pode pedir token usando esse provider
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]
}

# ------------------------------------------------------------
# EXTRA: atualiza o kubeconfig local automaticamente
# ------------------------------------------------------------

# "null_resource" com "local-exec" roda um comando no seu terminal
# (não cria nada na AWS) — aqui, configura o kubectl da máquina que
# rodou `terraform apply` pra já conseguir falar com o cluster novo,
# sem precisar rodar o comando manualmente depois.
resource "null_resource" "update_kubeconfig" {
  triggers = {
    cluster_name = aws_eks_cluster.main.name # roda de novo se o nome do cluster mudar
  }

  provisioner "local-exec" {
    # "|| true" evita que o `apply` inteiro falhe se, por exemplo, o
    # AWS CLI não estiver instalado em quem rodou o apply (ex: um
    # runner de CI) — nesse caso, só pula essa conveniência.
    command = "aws eks update-kubeconfig --name ${aws_eks_cluster.main.name} --region ${var.aws_region} || true"
  }

  depends_on = [aws_eks_node_group.main]
}
