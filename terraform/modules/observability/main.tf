# ---------------------------------------------------------------------------
# Observabilidad.
#
# Requisito: centralizar logs, recopilar metricas, monitorear servicios,
# detectar errores y generar alertas basicas.
#
# Que aporta cada pieza (y por que esta):
#   - Log bucket dedicado : retencion propia y consultas sobre el historico sin
#                           depender de la retencion por defecto de 30 dias.
#   - Sink a BigQuery     : solo en prod. Analitica de negocio sobre los logs
#                           (pedidos por hora, errores por proveedor) con SQL.
#   - Metricas basadas en : convierten patrones de log en series temporales
#     log                   alertables, sin instrumentar la aplicacion.
#   - Uptime check        : vigila desde fuera. Es la unica senal que detecta
#                           una caida del propio balanceador o del DNS.
#   - Alert policies       : el minimo accionable. Mas alertas que capacidad de
#                           respuesta produce ruido y se dejan de mirar.
#   - Dashboard           : una sola pantalla con el estado de los 4 planos.
# ---------------------------------------------------------------------------

# --- Canales de notificacion ----------------------------------------------
resource "google_monitoring_notification_channel" "email" {
  for_each = var.alert_emails

  project      = var.project_id
  display_name = "Email ${each.key} (${var.env})"
  type         = "email"

  labels = {
    email_address = each.value
  }
}

locals {
  notification_channels = [
    for c in google_monitoring_notification_channel.email : c.id
  ]
}

# ---------------------------------------------------------------------------
# Centralizacion de logs
# ---------------------------------------------------------------------------
resource "google_logging_project_bucket_config" "central" {
  project        = var.project_id
  location       = var.region
  bucket_id      = "${var.name_prefix}-logs"
  retention_days = var.log_retention_days
  description    = "Logs centralizados de la plataforma (${var.env})"

  # Indexa campos consultados a menudo para que las busquedas no recorran todo.
  # Que campos son depende del modelo de datos de la aplicacion, no de la
  # infraestructura: llegan como variable.
  dynamic "index_configs" {
    for_each = toset(var.log_index_fields)
    content {
      field_path = index_configs.value
      type       = "INDEX_TYPE_STRING"
    }
  }
}

# Todo el log de los componentes de la plataforma va al bucket dedicado.
resource "google_logging_project_sink" "central" {
  project                = var.project_id
  name                   = "${var.name_prefix}-sink-central"
  destination            = "logging.googleapis.com/projects/${var.project_id}/locations/${var.region}/buckets/${google_logging_project_bucket_config.central.bucket_id}"
  unique_writer_identity = true

  filter = <<-EOT
    resource.type = "cloud_run_revision" OR
    resource.type = "cloud_run_job" OR
    resource.type = "cloudsql_database" OR
    resource.type = "http_load_balancer" OR
    resource.type = "pubsub_subscription"
  EOT
}

# Con unique_writer_identity el sink escribe con una identidad propia, que por
# si sola NO puede escribir en el bucket de destino. Sin este binding el sink
# se crea sin error y simplemente no entrega nada: un fallo silencioso.
resource "google_project_iam_member" "sink_bucket_writer" {
  project = var.project_id
  role    = "roles/logging.bucketWriter"
  member  = google_logging_project_sink.central.writer_identity
}

# Sink analitico. Solo prod: en dev/qa el coste no se justifica.
resource "google_bigquery_dataset" "logs" {
  count = var.enable_bigquery_sink ? 1 : 0

  project                     = var.project_id
  dataset_id                  = replace("${var.name_prefix}_logs", "-", "_")
  location                    = var.bigquery_location
  description                 = "Logs de la plataforma para analitica"
  default_table_expiration_ms = var.bigquery_table_expiration_days * 86400000

  labels = var.labels
}

resource "google_logging_project_sink" "bigquery" {
  count = var.enable_bigquery_sink ? 1 : 0

  project                = var.project_id
  name                   = "${var.name_prefix}-sink-bq"
  destination            = "bigquery.googleapis.com/projects/${var.project_id}/datasets/${google_bigquery_dataset.logs[0].dataset_id}"
  unique_writer_identity = true

  # Solo peticiones del LB y errores: el resto no se analiza y si se paga.
  filter = <<-EOT
    resource.type = "http_load_balancer" OR
    (resource.type = "cloud_run_revision" AND severity >= ERROR)
  EOT

  bigquery_options {
    use_partitioned_tables = true
  }
}

resource "google_bigquery_dataset_iam_member" "sink_writer" {
  count = var.enable_bigquery_sink ? 1 : 0

  project    = var.project_id
  dataset_id = google_bigquery_dataset.logs[0].dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = google_logging_project_sink.bigquery[0].writer_identity
}

# Exclusion de ruido: los health checks son el 99% del volumen y no informan
# de nada. Reducirlos es la medida de ahorro mas directa en Cloud Logging.
resource "google_logging_project_exclusion" "health_checks" {
  project     = var.project_id
  name        = "${var.name_prefix}-excl-health"
  description = "Descarta accesos de health check del balanceador"

  filter = <<-EOT
    resource.type = "http_load_balancer" AND
    httpRequest.requestUrl : "${var.health_path}" AND
    httpRequest.status = 200
  EOT
}

# ---------------------------------------------------------------------------
# Metricas basadas en log
# ---------------------------------------------------------------------------

# Errores no controlados de la aplicacion, con el nombre del servicio como
# etiqueta para poder alertar por componente.
resource "google_logging_metric" "app_errors" {
  project = var.project_id
  name    = "${var.name_prefix}/app_errors"
  filter  = <<-EOT
    resource.type = "cloud_run_revision" AND
    severity >= ERROR
  EOT

  description = "Errores de aplicacion por servicio"

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
    unit        = "1"

    labels {
      key         = "service"
      value_type  = "STRING"
      description = "Servicio Cloud Run que emite el error"
    }
  }

  label_extractors = {
    "service" = "EXTRACT(resource.labels.service_name)"
  }
}

# Fallos de autenticacion: un pico es senal de ataque de credenciales.
resource "google_logging_metric" "auth_failures" {
  project = var.project_id
  name    = "${var.name_prefix}/auth_failures"
  filter  = <<-EOT
    resource.type = "http_load_balancer" AND
    httpRequest.status = 401
  EOT

  description = "Respuestas 401 en el punto de entrada"

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
    unit        = "1"
  }
}

# Consultas lentas registradas por el flag log_min_duration_statement.
resource "google_logging_metric" "slow_queries" {
  project = var.project_id
  name    = "${var.name_prefix}/slow_queries"
  filter  = <<-EOT
    resource.type = "cloudsql_database" AND
    textPayload : "duration:"
  EOT

  description = "Consultas que superan el umbral de duracion"

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
    unit        = "1"
  }
}

# ---------------------------------------------------------------------------
# Comprobacion desde el exterior
# ---------------------------------------------------------------------------
resource "google_monitoring_uptime_check_config" "public" {
  count = var.uptime_check_host == null ? 0 : 1

  project      = var.project_id
  display_name = "Disponibilidad publica (${var.env})"
  timeout      = "10s"
  period       = "60s"

  http_check {
    path         = var.health_path
    port         = 443
    use_ssl      = true
    validate_ssl = true

    accepted_response_status_codes {
      status_class = "STATUS_CLASS_2XX"
    }
  }

  monitored_resource {
    type = "uptime_url"
    labels = {
      project_id = var.project_id
      host       = var.uptime_check_host
    }
  }

  # Desde varias regiones: evita declarar caida por un problema de red local.
  selected_regions = var.uptime_check_regions
}

# ---------------------------------------------------------------------------
# Alertas. Criterio: cada una debe tener una accion clara asociada.
# ---------------------------------------------------------------------------

# 1. El servicio no responde desde fuera. Es la alerta de mayor prioridad.
resource "google_monitoring_alert_policy" "uptime" {
  count = var.uptime_check_host == null ? 0 : 1

  project      = var.project_id
  display_name = "[${upper(var.env)}] Plataforma no disponible"
  combiner     = "OR"
  severity     = "CRITICAL"

  conditions {
    display_name = "Uptime check fallando"

    condition_threshold {
      filter = join(" AND ", [
        "metric.type = \"monitoring.googleapis.com/uptime_check/check_passed\"",
        "resource.type = \"uptime_url\"",
        "metric.labels.check_id = \"${google_monitoring_uptime_check_config.public[0].uptime_check_id}\"",
      ])

      # Con REDUCE_COUNT_FALSE la serie cuenta comprobaciones FALLIDAS, asi que
      # la condicion es "mas de una region reportando fallo", no "< 1".
      comparison      = "COMPARISON_GT"
      threshold_value = 1
      duration        = "180s"

      aggregations {
        alignment_period     = "60s"
        per_series_aligner   = "ALIGN_NEXT_OLDER"
        cross_series_reducer = "REDUCE_COUNT_FALSE"
        group_by_fields      = ["resource.label.host"]
      }

      trigger { count = 1 }
    }
  }

  notification_channels = local.notification_channels

  documentation {
    content   = <<-EOT
      El uptime check externo falla durante mas de 3 minutos.

      Comprobar en este orden:
        1. Estado del servicio Cloud Run del API (revisiones y errores de arranque).
        2. Backend service del LB: health del serverless NEG.
        3. Certificado gestionado (si esta en FAILED_NOT_VISIBLE, revisar DNS).
        4. Cloud SQL: una BBDD caida deja ${var.health_path} en 503.
    EOT
    mime_type = "text/markdown"
  }

  alert_strategy {
    auto_close = "1800s"
  }
}

# 2. Tasa de error 5xx. Mide lo que sufre el usuario, no la salud interna.
resource "google_monitoring_alert_policy" "error_rate_5xx" {
  project      = var.project_id
  display_name = "[${upper(var.env)}] Tasa de errores 5xx elevada"
  combiner     = "OR"
  severity     = "ERROR"

  conditions {
    display_name = "5xx por encima del umbral"

    condition_threshold {
      filter = join(" AND ", [
        "metric.type = \"loadbalancing.googleapis.com/https/request_count\"",
        "resource.type = \"https_lb_rule\"",
        "metric.labels.response_code_class = \"500\"",
      ])

      comparison      = "COMPARISON_GT"
      threshold_value = var.error_rate_threshold
      duration        = "300s"

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }

  notification_channels = local.notification_channels

  documentation {
    content   = "Revisar Error Reporting y los logs del API en el bucket central."
    mime_type = "text/markdown"
  }
}

# 3. Latencia percentil 95. El promedio esconde la cola.
resource "google_monitoring_alert_policy" "latency_p95" {
  project      = var.project_id
  display_name = "[${upper(var.env)}] Latencia p95 degradada"
  combiner     = "OR"
  severity     = "WARNING"

  conditions {
    display_name = "p95 de latencia del API"

    condition_threshold {
      filter = join(" AND ", [
        "metric.type = \"run.googleapis.com/request_latencies\"",
        "resource.type = \"cloud_run_revision\"",
        "resource.labels.service_name = \"${var.api_service_name}\"",
      ])

      comparison      = "COMPARISON_GT"
      threshold_value = var.latency_p95_threshold_ms
      duration        = "300s"

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_PERCENTILE_95"
      }
    }
  }

  notification_channels = local.notification_channels
}

# 4. Mensajes en el DLQ. Significa trabajo asincrono perdido: siempre se mira.
resource "google_monitoring_alert_policy" "dlq_messages" {
  project      = var.project_id
  display_name = "[${upper(var.env)}] Mensajes en cola de fallidos (DLQ)"
  combiner     = "OR"
  severity     = "ERROR"

  conditions {
    display_name = "DLQ con mensajes sin confirmar"

    condition_threshold {
      filter = join(" AND ", [
        "metric.type = \"pubsub.googleapis.com/subscription/num_undelivered_messages\"",
        "resource.type = \"pubsub_subscription\"",
        "resource.labels.subscription_id = \"${var.dlq_subscription_name}\"",
      ])

      comparison      = "COMPARISON_GT"
      threshold_value = 0
      duration        = "300s"

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MAX"
      }
    }
  }

  notification_channels = local.notification_channels

  documentation {
    content   = <<-EOT
      Hay eventos que no se han podido procesar tras agotar los reintentos.

      Procedimiento: inspeccionar los mensajes del DLQ, corregir la causa y
      reinyectar con un "subscription seek" o republicando al topic de origen.
    EOT
    mime_type = "text/markdown"
  }
}

# 5. CPU de la base de datos. Antecede a la degradacion general.
resource "google_monitoring_alert_policy" "db_cpu" {
  project      = var.project_id
  display_name = "[${upper(var.env)}] CPU de Cloud SQL alta"
  combiner     = "OR"
  severity     = "WARNING"

  conditions {
    display_name = "CPU sostenida por encima del umbral"

    condition_threshold {
      filter = join(" AND ", [
        "metric.type = \"cloudsql.googleapis.com/database/cpu/utilization\"",
        "resource.type = \"cloudsql_database\"",
        "resource.labels.database_id = \"${var.project_id}:${var.db_instance_name}\"",
      ])

      comparison      = "COMPARISON_GT"
      threshold_value = var.db_cpu_threshold
      duration        = "600s"

      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }

  notification_channels = local.notification_channels
}

# 6. Disco de la base de datos. Un disco lleno es una caida total.
resource "google_monitoring_alert_policy" "db_disk" {
  project      = var.project_id
  display_name = "[${upper(var.env)}] Disco de Cloud SQL al limite"
  combiner     = "OR"
  severity     = "CRITICAL"

  conditions {
    display_name = "Utilizacion de disco por encima del umbral"

    condition_threshold {
      filter = join(" AND ", [
        "metric.type = \"cloudsql.googleapis.com/database/disk/utilization\"",
        "resource.type = \"cloudsql_database\"",
        "resource.labels.database_id = \"${var.project_id}:${var.db_instance_name}\"",
      ])

      comparison      = "COMPARISON_GT"
      threshold_value = var.db_disk_threshold
      duration        = "300s"

      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }

  notification_channels = local.notification_channels
}

# 7. Instancias de Cloud Run cerca del techo: sintoma de saturacion o de un
#    max_instances mal dimensionado tras el crecimiento previsto.
resource "google_monitoring_alert_policy" "run_saturation" {
  project      = var.project_id
  display_name = "[${upper(var.env)}] Cloud Run cerca del maximo de instancias"
  combiner     = "OR"
  severity     = "WARNING"

  conditions {
    display_name = "Instancias activas cerca del limite"

    condition_threshold {
      filter = join(" AND ", [
        "metric.type = \"run.googleapis.com/container/instance_count\"",
        "resource.type = \"cloud_run_revision\"",
        "resource.labels.service_name = \"${var.api_service_name}\"",
      ])

      comparison      = "COMPARISON_GT"
      threshold_value = var.api_max_instances * var.run_saturation_ratio
      duration        = "300s"

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MAX"
      }
    }
  }

  notification_channels = local.notification_channels
}

# 8. Fallos de los procesos batch. Un batch que falla en silencio es peor que
#    uno que no se ejecuta.
resource "google_monitoring_alert_policy" "batch_failures" {
  project      = var.project_id
  display_name = "[${upper(var.env)}] Fallo en proceso batch"
  combiner     = "OR"
  severity     = "ERROR"

  conditions {
    display_name = "Ejecucion de job completada con fallo"

    condition_threshold {
      filter = join(" AND ", [
        "metric.type = \"run.googleapis.com/job/completed_task_attempt_count\"",
        "resource.type = \"cloud_run_job\"",
        "metric.labels.result = \"failed\"",
      ])

      comparison      = "COMPARISON_GT"
      threshold_value = 0
      duration        = "60s"

      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_SUM"
      }
    }
  }

  notification_channels = local.notification_channels
}
