# ---------------------------------------------------------------------------
# Procesamiento asincrono con Pub/Sub.
#
# Requisito: "Un mecanismo para que el backend pueda publicar eventos o trabajos
# que sean procesados posteriormente."
#
# Topologia: el API publica en un topic por dominio de evento; cada topic tiene
# una suscripcion PUSH que entrega al worker de Cloud Run autenticando con OIDC.
#
# Push frente a pull: con push, Pub/Sub provoca el escalado de Cloud Run por si
# solo y no hace falta un proceso siempre vivo haciendo polling (que en Cloud
# Run obligaria a min_instances > 0 pagando el valle). El coste es que el worker
# debe ser idempotente y responder rapido.
# ---------------------------------------------------------------------------

# Topic de mensajes fallidos. Uno compartido: lo que importa es no perder el
# mensaje y poder inspeccionarlo, y un unico sitio simplifica la alerta.
resource "google_pubsub_topic" "dlq" {
  project = var.project_id
  name    = "${var.name_prefix}-dlq"
  labels  = var.labels

  message_retention_duration = var.dlq_retention_duration
}

resource "google_pubsub_subscription" "dlq" {
  project = var.project_id
  name    = "${var.name_prefix}-dlq-sub"
  topic   = google_pubsub_topic.dlq.id
  labels  = var.labels

  # Suscripcion de retencion: mantiene los mensajes para inspeccion manual.
  message_retention_duration = var.dlq_retention_duration
  retain_acked_messages      = false
  expiration_policy {
    ttl = "" # nunca expira: si expirase, se perderia el buzon de errores
  }
}

resource "google_pubsub_topic" "topics" {
  for_each = var.topics

  project = var.project_id
  name    = "${var.name_prefix}-${each.key}"
  labels  = var.labels

  message_retention_duration = each.value.retention_duration

  # Validacion de esquema opcional: evita que un publicador rompa el contrato
  # del evento y el fallo aparezca solo en el consumidor.
  dynamic "schema_settings" {
    for_each = each.value.schema_id == null ? [] : [1]
    content {
      schema   = each.value.schema_id
      encoding = "JSON"
    }
  }
}

resource "google_pubsub_subscription" "push" {
  for_each = var.topics

  project = var.project_id
  name    = "${var.name_prefix}-${each.key}-sub"
  topic   = google_pubsub_topic.topics[each.key].id
  labels  = var.labels

  ack_deadline_seconds       = each.value.ack_deadline_seconds
  message_retention_duration = each.value.retention_duration
  # Orden por clave cuando el dominio lo exige (p. ej. transiciones de estado
  # de un mismo pedido). Se activa por suscripcion, no globalmente, porque
  # ordenar reduce el paralelismo de consumo.
  enable_message_ordering = each.value.ordered

  push_config {
    push_endpoint = "${var.worker_url}${each.value.path}"

    # El worker valida este token: ningun tercero puede inyectar mensajes
    # llamando a la URL del worker.
    oidc_token {
      service_account_email = var.pubsub_invoker_service_account_email
      audience              = var.worker_url
    }

    attributes = {
      "x-goog-version" = "v1"
    }
  }

  # Backoff exponencial: ante un fallo transitorio del worker o de la BBDD, no
  # se reintenta en bucle cerrado.
  retry_policy {
    minimum_backoff = var.retry_minimum_backoff
    maximum_backoff = var.retry_maximum_backoff
  }

  # Tras N intentos el mensaje va al DLQ en lugar de reintentarse para siempre.
  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.dlq.id
    max_delivery_attempts = each.value.max_delivery_attempts
  }

  expiration_policy {
    ttl = "" # las suscripciones de la plataforma no deben autodestruirse
  }
}

# ---------------------------------------------------------------------------
# Permisos de Pub/Sub.
# ---------------------------------------------------------------------------

# El API solo publica; no puede leer ni administrar suscripciones.
resource "google_pubsub_topic_iam_member" "publisher" {
  for_each = var.topics

  project = var.project_id
  topic   = google_pubsub_topic.topics[each.key].name
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${var.publisher_service_account_email}"
}

# El agente de servicio de Pub/Sub necesita poder publicar en el DLQ y confirmar
# en la suscripcion de origen para que el reenvio a DLQ funcione. Es un
# requisito del propio mecanismo, no una ampliacion de permisos de la app.
resource "google_pubsub_topic_iam_member" "dlq_publisher" {
  project = var.project_id
  topic   = google_pubsub_topic.dlq.name
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:service-${var.project_number}@gcp-sa-pubsub.iam.gserviceaccount.com"
}

resource "google_pubsub_subscription_iam_member" "dlq_subscriber" {
  for_each = var.topics

  project      = var.project_id
  subscription = google_pubsub_subscription.push[each.key].name
  role         = "roles/pubsub.subscriber"
  member       = "serviceAccount:service-${var.project_number}@gcp-sa-pubsub.iam.gserviceaccount.com"
}

# Identidad con la que Pub/Sub firma el token OIDC hacia el worker.
resource "google_service_account_iam_member" "pubsub_token_creator" {
  service_account_id = var.pubsub_invoker_service_account_id
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "serviceAccount:service-${var.project_number}@gcp-sa-pubsub.iam.gserviceaccount.com"
}
