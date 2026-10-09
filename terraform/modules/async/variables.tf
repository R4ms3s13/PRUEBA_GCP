variable "project_id" {
  description = "ID del proyecto de GCP donde se crean los topics y las suscripciones."
  type        = string
}

variable "project_number" {
  description = "Necesario para construir el email del agente de servicio de Pub/Sub."
  type        = string
}

variable "env" {
  description = "Identificador del ambiente (dev, qa o prod). Se usa en nombres, etiquetas y decisiones condicionales."
  type        = string
}
variable "name_prefix" {
  description = "Prefijo comun de los nombres de recurso del modulo."
  type        = string
}

variable "worker_url" {
  description = "URL base del servicio worker de Cloud Run (destino del push)."
  type        = string
}

variable "publisher_service_account_email" {
  description = "Identidad del API backend, unica autorizada a publicar."
  type        = string
}

variable "pubsub_invoker_service_account_email" {
  description = "SA con la que Pub/Sub firma el OIDC e invoca al worker."
  type        = string
}

variable "pubsub_invoker_service_account_id" {
  description = "ID completo de esa SA, para el binding de tokenCreator."
  type        = string
}

variable "topics" {
  description = <<-EOT
    Un topic por dominio de evento, con su suscripcion push al worker.
    "path" es la ruta del worker que procesa ese evento.
  EOT
  type = map(object({
    path                  = string
    ack_deadline_seconds  = optional(number, 60)
    retention_duration    = optional(string, "604800s")
    max_delivery_attempts = optional(number, 5)
    ordered               = optional(bool, false)
    schema_id             = optional(string)
  }))
}

variable "labels" {
  description = "Etiquetas aplicadas a los recursos que las admiten, para repartir costes y filtrar en facturacion."
  type        = map(string)
  default     = {}
}

# --- Cola de mensajes fallidos ---

variable "dlq_retention_duration" {
  description = <<-EOT
    Tiempo que un mensaje fallido se conserva para inspeccion y reinyeccion.
    Debe cubrir al menos un fin de semana largo: si el DLQ caduca antes de que
    alguien lo mire, el evento se pierde de verdad.
  EOT
  type        = string
  default     = "604800s" # 7 dias
}

# --- Reintentos ---

variable "retry_minimum_backoff" {
  description = "Espera minima antes de reintentar una entrega fallida."
  type        = string
  default     = "10s"
}

variable "retry_maximum_backoff" {
  description = "Espera maxima entre reintentos. Evita castigar a un sistema de terceros que ya esta caido."
  type        = string
  default     = "600s"
}
