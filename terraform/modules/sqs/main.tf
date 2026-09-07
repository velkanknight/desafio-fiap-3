# ============================================================
# MÓDULO: SQS (fila de mensagens)
#
# É o "correio" entre evaluation-service (produtor) e
# analytics-service (consumidor): desacopla os dois — se o
# analytics-service cair, as mensagens ficam esperando na fila em
# vez de se perderem, e são processadas quando ele voltar.
#
# Fila do tipo STANDARD (não FIFO): o código dos serviços não usa
# "MessageGroupId" (exigido em filas FIFO), então uma fila FIFO
# quebraria o envio de mensagens. Standard também é mais barata e
# tem throughput maior — não precisamos de ordenação garantida aqui.
# ============================================================

resource "aws_sqs_queue" "main" {
  name                      = "${var.prefix}-events"
  message_retention_seconds = 86400  # mensagem não processada expira em 1 dia
  max_message_size          = 262144 # tamanho máximo de cada mensagem, em bytes (256KB, o teto do SQS)

  # "redrive_policy" manda a mensagem pra uma fila de erro (DLQ,
  # abaixo) depois de "maxReceiveCount" tentativas de processamento
  # sem sucesso — evita que uma mensagem "podre" fique reprocessando
  # pra sempre e travando a fila principal.
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = 3
  })

  tags = { Name = "${var.prefix}-events" }
}

# DLQ = "Dead Letter Queue": fila separada só pra guardar mensagens
# que falharam repetidamente — dá pra inspecionar depois o que deu
# errado, sem perder o dado.
resource "aws_sqs_queue" "dlq" {
  name = "${var.prefix}-events-dlq"
  tags = { Name = "${var.prefix}-events-dlq" }
}
