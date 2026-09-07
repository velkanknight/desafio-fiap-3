#!/usr/bin/env bash
# ============================================================
# BOOTSTRAP — roda isso UMA VEZ SÓ, na SUA máquina (não na pipeline),
# ANTES de qualquer `terraform apply` ou pipeline rodar.
#
# Ele resolve o problema do "ovo e da galinha": o Terraform vai
# rodar DENTRO de uma pipeline do GitHub Actions
# (.github/workflows/terraform.yml), e essa pipeline precisa de
# credenciais AWS pra funcionar. Só que a forma "certa" de dar
# credenciais AWS pro GitHub Actions (OIDC, sem senha fixa) exige
# que já exista, na sua conta AWS:
#
#   1. Um bucket S3 pra guardar o state do Terraform (backend remoto)
#   2. Um "Identity Provider" OIDC cadastrado, confiando no GitHub
#   3. Uma IAM Role que a pipeline de Terraform vai assumir
#
# Nenhuma dessas 3 coisas pode ser criada PELO PRÓPRIO Terraform,
# porque ele ainda não tem onde rodar / com o que se autenticar antes
# delas existirem. Por isso são criadas aqui, manualmente, uma vez só.
# TUDO O RESTO (VPC, EKS, RDS, ECR, as roles mais estreitas de cada
# pipeline de serviço, IRSA, etc.) é criado pelo Terraform depois,
# rodando dentro da pipeline.
#
# Pré-requisito: AWS CLI instalado e configurado com as credenciais
# da SUA conta pessoal (`aws configure`), com permissão de admin —
# essas credenciais SÓ são usadas aqui, na sua máquina, uma vez; elas
# nunca vão pro GitHub nem pra lugar nenhum.
#
# Uso:
#   GITHUB_ORG=seu-usuario GITHUB_REPO=desafio-fiap-3 ./scripts/bootstrap.sh
# ============================================================
set -euo pipefail

# -e  -> para o script imediatamente se qualquer comando falhar
# -u  -> erro se usar uma variável que não foi definida (evita
#        continuar com um valor vazio por engano, ex: bucket sem nome)
# -o pipefail -> se um comando de um pipe (a | b) falhar, o pipe
#        inteiro é considerado falho (por padrão o bash ignora isso)

# --- parâmetros obrigatórios -------------------------------------------
# ":?mensagem" faz o script parar com erro claro se a variável não
# foi definida, em vez de seguir em frente com "" (string vazia).
: "${GITHUB_ORG:?defina GITHUB_ORG=seu-usuario-ou-org-do-github}"
: "${GITHUB_REPO:?defina GITHUB_REPO=desafio-fiap-3}"

# Região onde tudo vai ser criado (pode sobrescrever exportando AWS_REGION
# antes de rodar o script). Tem que bater com terraform/variables.tf.
AWS_REGION="${AWS_REGION:-us-east-1}"

# Descobre o ID da conta AWS logada (evita digitar/errar o número na mão).
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Nome do bucket de state. Inclui o account ID pra ser único globalmente
# (nome de bucket S3 é único no mundo todo, não só na sua conta) — mesma
# convenção que já estava documentada no backend.tf original.
BUCKET_NAME="togglemaster-terraform-state-${AWS_ACCOUNT_ID}"

# Nome da Role AMPLA que a pipeline de Terraform vai assumir. É
# diferente da Role mais estreita ("togglemaster-github-actions", só
# ECR push) que o próprio Terraform cria depois no módulo github-oidc/
# pra uso das 5 pipelines de aplicação.
ROLE_NAME="togglemaster-terraform-ci"

echo "Conta AWS ......... $AWS_ACCOUNT_ID"
echo "Região ............ $AWS_REGION"
echo "Bucket de state ... $BUCKET_NAME"
echo "Role da pipeline .. $ROLE_NAME"
echo "Repositório ........ ${GITHUB_ORG}/${GITHUB_REPO}"
echo ""

# ------------------------------------------------------------------
# 1. Bucket S3 pra guardar o terraform.tfstate remoto
# ------------------------------------------------------------------
# head-bucket só funciona (exit 0) se o bucket já existe e você tem
# acesso — usamos isso pra tornar o script seguro de rodar de novo
# (idempotente) sem quebrar caso já tenha sido executado antes.
if aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
  echo "[1/3] Bucket $BUCKET_NAME já existe — pulando criação."
else
  echo "[1/3] Criando bucket $BUCKET_NAME..."
  # us-east-1 é um caso especial da API do S3: é a ÚNICA região que
  # NÃO aceita o parâmetro --create-bucket-configuration (as outras
  # regiões exigem, senão o bucket seria criado em us-east-1 por
  # padrão mesmo pedindo outra região).
  if [ "$AWS_REGION" = "us-east-1" ]; then
    aws s3api create-bucket --bucket "$BUCKET_NAME" --region "$AWS_REGION"
  else
    aws s3api create-bucket --bucket "$BUCKET_NAME" --region "$AWS_REGION" \
      --create-bucket-configuration LocationConstraint="$AWS_REGION"
  fi

  # Versionamento: se o state for sobrescrito/corrompido por engano,
  # dá pra restaurar uma versão anterior do arquivo.
  aws s3api put-bucket-versioning --bucket "$BUCKET_NAME" \
    --versioning-configuration Status=Enabled

  # Criptografia em repouso por padrão (o state pode conter dados
  # sensíveis, como senha de banco, em texto plano).
  aws s3api put-bucket-encryption --bucket "$BUCKET_NAME" \
    --server-side-encryption-configuration \
    '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

  # Bloqueia qualquer tentativa de tornar o bucket público — o state
  # nunca deve ser acessível pela internet.
  aws s3api put-public-access-block --bucket "$BUCKET_NAME" \
    --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
fi

# ------------------------------------------------------------------
# 2. Identity Provider OIDC do GitHub Actions
# ------------------------------------------------------------------
# O ARN de um provedor OIDC segue um formato fixo e previsível —
# construímos ele aqui pra poder checar se já existe antes de criar
# de novo (a AWS não deixa ter dois provedores com a mesma URL).
OIDC_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/token.actions.githubusercontent.com"

if aws iam get-open-id-connect-provider --open-id-connect-provider-arn "$OIDC_ARN" >/dev/null 2>&1; then
  echo "[2/3] Provedor OIDC do GitHub já existe — pulando criação."
else
  echo "[2/3] Criando provedor OIDC do GitHub..."
  aws iam create-open-id-connect-provider \
    --url "https://token.actions.githubusercontent.com" \
    --client-id-list "sts.amazonaws.com" \
    --thumbprint-list \
      "6938fd4d98bab03faadb97b34396831e3780aea1" \
      "1c58a3a8518e8759bf075b76b750d4f2df264fcd"
fi

# ------------------------------------------------------------------
# 3. IAM Role ampla que a pipeline de Terraform (terraform.yml) assume
# ------------------------------------------------------------------
# Trust policy: define QUEM pode assumir essa Role. Igual à lógica do
# módulo terraform/modules/github-oidc/main.tf, mas escrita direto em
# JSON aqui porque ainda não temos Terraform rodando pra gerar isso.
#
# A condição "sub" restringe pra só workflows rodando NO SEU
# repositório (${GITHUB_ORG}/${GITHUB_REPO}) conseguirem assumir essa
# Role — nenhum outro repositório, nem seu nem de mais ninguém, passa
# nessa condição.
TRUST_POLICY=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": { "Federated": "${OIDC_ARN}" },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:${GITHUB_ORG}/${GITHUB_REPO}:*"
        }
      }
    }
  ]
}
EOF
)

if aws iam get-role --role-name "$ROLE_NAME" >/dev/null 2>&1; then
  echo "[3/3] Role $ROLE_NAME já existe — atualizando a trust policy..."
  aws iam update-assume-role-policy --role-name "$ROLE_NAME" --policy-document "$TRUST_POLICY"
else
  echo "[3/3] Criando role $ROLE_NAME..."
  aws iam create-role --role-name "$ROLE_NAME" \
    --assume-role-policy-document "$TRUST_POLICY" \
    --description "Assumida via OIDC pela pipeline .github/workflows/terraform.yml para rodar terraform plan/apply"

  # AdministratorAccess: aceitável aqui porque esta é uma conta AWS
  # PESSOAL, usada só para este projeto de estudo — simplifica o
  # bootstrap, já que os módulos deste projeto mexem em muitos
  # serviços diferentes (VPC, EKS, RDS, ElastiCache, DynamoDB, SQS,
  # ECR, IAM). Numa conta de empresa de verdade, com outras cargas de
  # trabalho rodando, o certo seria trocar por uma policy customizada
  # contendo só as ações que os módulos deste projeto realmente usam.
  aws iam attach-role-policy --role-name "$ROLE_NAME" \
    --policy-arn "arn:aws:iam::aws:policy/AdministratorAccess"
fi

ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${ROLE_NAME}"

echo ""
echo "============================================================"
echo " Bootstrap concluído. Configure estes 3 Secrets no GitHub:"
echo " (Settings > Secrets and variables > Actions, no repo ${GITHUB_REPO})"
echo "============================================================"
echo "AWS_ROLE_ARN_TERRAFORM = $ROLE_ARN"
echo "TF_STATE_BUCKET        = $BUCKET_NAME"
echo "DB_PASSWORD             = <escolha uma senha forte>"
echo ""
echo "Depois disso, dê push na branch main (ou abra um PR) mexendo em"
echo "algo dentro de terraform/ para disparar o workflow terraform.yml."
