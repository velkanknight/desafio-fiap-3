# ============================================================
# BACKEND REMOTO DO TERRAFORM
#
# O "state" é o arquivo (terraform.tfstate) onde o Terraform guarda
# o que ele já criou na AWS — é assim que ele sabe a diferença entre
# "criar do zero" e "atualizar o que já existe". Por padrão esse
# arquivo fica LOCAL, na sua máquina, o que é perigoso: se seu
# notebook quebrar, ou se dois devs (ou a pipeline + uma pessoa)
# rodarem `apply` ao mesmo tempo, vira bagunça. É exatamente o
# requisito da Fase 3: "o terraform.tfstate não pode ficar local".
#
# A solução é guardar esse arquivo dentro de um bucket S3 (backend
# remoto). Assim qualquer pessoa do time, ou a pipeline de CI, lê o
# mesmo state compartilhado.
#
# IMPORTANTE - problema do "ovo e galinha": o Terraform não consegue
# criar o próprio bucket onde ele vai gravar o state (ele precisaria
# do backend configurado ANTES de rodar, mas o backend ainda não
# existe). Por isso o bucket é criado manualmente, uma única vez,
# ANTES do primeiro `terraform init` — é exatamente o que
# scripts/bootstrap.sh faz.
#
# REPARE que o campo "bucket" NÃO aparece aqui embaixo. Isso é de
# propósito: um bloco `backend` não aceita variáveis (`var.xxx`) do
# Terraform normal, porque ele é lido ANTES de qualquer variável ser
# processada — então não dá pra usar `var.aws_account_id` aqui, por
# exemplo. Mas o Terraform permite um "backend parcial": você deixa
# de fora os campos que mudam por ambiente/conta, e completa eles na
# hora do `terraform init` com a flag `-backend-config`. É assim que
# o MESMO código funciona pra qualquer conta AWS, sem precisar editar
# este arquivo:
#
#   terraform init -backend-config="bucket=NOME_DO_SEU_BUCKET"
#
# A pipeline (.github/workflows/terraform.yml) faz exatamente isso,
# lendo o nome do bucket do Secret TF_STATE_BUCKET do GitHub. Se for
# rodar localmente também, use o mesmo comando (ver README.md).
# ============================================================
terraform {
  # Bloco "backend" diz ao Terraform ONDE guardar o state.
  # "s3" = usar um bucket S3 como armazenamento do state.
  backend "s3" {
    # Caminho (como se fosse uma pasta) DENTRO do bucket onde o
    # arquivo de state fica salvo. Útil se um dia você tiver mais de
    # um ambiente (ex: "dev/terraform.tfstate", "prod/terraform.tfstate").
    key = "fase3/terraform.tfstate"

    # Região AWS onde o bucket foi criado.
    region = "us-east-1"

    # Criptografa o arquivo de state em repouso dentro do S3
    # (o state pode conter dados sensíveis, como senhas de banco).
    encrypt = true

    # LOCK: impede que duas pessoas (ou a pipeline + uma pessoa)
    # rodem "terraform apply" ao mesmo tempo e corrompam o state.
    # "use_lockfile" é o lock NATIVO do backend S3 (arquivo de lock
    # dentro do próprio bucket, via escrita condicional) — só existe
    # a partir do Terraform 1.10. É a alternativa mais simples ao
    # método antigo, que exigia criar uma tabela DynamoDB só para
    # controlar o lock.
    use_lockfile = true

    # bucket = "definido via -backend-config na hora do init"
  }
}
