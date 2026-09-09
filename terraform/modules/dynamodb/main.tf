# =============================================================================
# MÓDULO: dynamodb
# Tabela de eventos de avaliação de flags consumida pelo analytics-service.
# =============================================================================

resource "aws_dynamodb_table" "this" {
  name         = var.table_name
  billing_mode = var.billing_mode
  hash_key     = "event_id"
  range_key    = "timestamp"

  attribute {
    name = "event_id"
    type = "S"
  }

  attribute {
    name = "timestamp"
    type = "S"
  }

  attribute {
    name = "flag_name"
    type = "S"
  }

  # Consulta "quantas avaliações a flag X teve no período Y"
  global_secondary_index {
    name            = "flag_name-timestamp-index"
    hash_key        = "flag_name"
    range_key       = "timestamp"
    projection_type = "ALL"
  }

  point_in_time_recovery {
    enabled = var.point_in_time_recovery
  }

  server_side_encryption {
    enabled = true
  }

  deletion_protection_enabled = var.deletion_protection

  tags = merge(var.tags, {
    Name    = var.table_name
    Service = "analytics-service"
  })
}
