# ============================================================
# MÓDULO: DynamoDB
#
# Banco NoSQL "sem servidor" (você não gerencia máquina nenhuma) —
# o analytics-service grava aqui cada evento de avaliação de flag
# que consome da fila SQS. Ideal pra esse caso porque o volume de
# escrita é alto (write-heavy) e o "schema" de cada evento é simples
# e não muda.
# ============================================================

resource "aws_dynamodb_table" "main" {
  # Nome FIXO (não usa var.prefix) porque o enunciado da Fase 3 exige
  # exatamente esse nome, e o código do analytics-service já espera
  # essa tabela via a variável de ambiente AWS_DYNAMODB_TABLE.
  name = "ToggleMasterAnalytics"

  # PAY_PER_REQUEST = você paga só pelo que usar (sem precisar prever
  # capacidade de leitura/escrita com antecedência) — ideal pra carga
  # imprevisível/baixa como esse challenge.
  billing_mode = "PAY_PER_REQUEST"

  # "hash_key" é a chave primária da tabela — cada evento tem um
  # event_id (UUID) único gerado pelo analytics-service.
  hash_key = "event_id"

  attribute {
    name = "event_id"
    type = "S" # "S" = String
  }

  tags = { Name = "${var.prefix}-analytics" }
}
