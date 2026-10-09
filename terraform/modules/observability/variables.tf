variable "project_id" {
  description = "ID del proyecto de GCP donde se crean los recursos."
  type        = string
}
variable "env" {
  description = "Identificador del ambiente (dev, qa o prod). Se usa en nombres, etiquetas y decisiones condicionales."
  type        = string
}
variable "region" {
  description = "Region de GCP donde se despliegan los recursos regionales."
  type        = string
}
variable "name_prefix" {
  description = "Prefijo comun de los nombres de recurso del modulo."
  type        = string
}

variable "api_service_name" {
  description = "Nombre del servicio de Cloud Run del API, para filtrar sus metricas en las alertas y el dashboard."
  type        = string
}
variable "api_max_instances" {
  description = "Techo de escalado del API. Se usa para calcular el umbral de la alerta de saturacion."
  type        = number
}
variable "db_instance_name" {
  description = "Nombre de la instancia de Cloud SQL, para filtrar sus metricas en las alertas."
  type        = string
}
variable "dlq_subscription_name" {
  description = "Suscripcion de la cola de mensajes fallidos que vigila la alerta de DLQ."
  type        = string
}

variable "health_path" {
  description = <<-EOT
    Ruta de salud que expone la aplicacion. Es CONTRATO con el equipo de
    desarrollo y se usa en tres sitios (uptime check, exclusion de logs y
    enrutado del balanceador), asi que viaja como variable y no escrita a mano
    en cada uno.
  EOT
  type        = string
}

variable "log_index_fields" {
  description = <<-EOT
    Campos del jsonPayload que se indexan en el bucket de logs. Son propios del
    dominio de la aplicacion (identificadores de pedido, de proveedor), no de la
    infraestructura, de modo que los decide quien conoce el modelo de datos.
  EOT
  type        = list(string)
  default     = []
}

variable "uptime_check_regions" {
  description = "Regiones desde las que se comprueba la disponibilidad."
  type        = list(string)
  default     = ["EUROPE", "USA", "SOUTH_AMERICA"]
}

variable "db_cpu_threshold" {
  description = "Fraccion de CPU de Cloud SQL que dispara la alerta."
  type        = number
  default     = 0.8
}

variable "db_disk_threshold" {
  description = "Fraccion de disco de Cloud SQL que dispara la alerta."
  type        = number
  default     = 0.85
}

variable "run_saturation_ratio" {
  description = "Fraccion de max_instances a partir de la cual se alerta."
  type        = number
  default     = 0.8
}

variable "alert_emails" {
  description = "Mapa etiqueta => email. Mapa y no lista para que renombrar uno no recree los demas."
  type        = map(string)
  default = {
  }
}

variable "uptime_check_host" {
  description = "Host publico a comprobar. null desactiva el check (dev sin DNS)."
  type        = string
  default     = null
}

variable "log_retention_days" {
  description = "Dias que se conservan los logs en el bucket central."
  type        = number
  default     = 30
}

variable "enable_bigquery_sink" {
  description = "Exporta los logs a BigQuery para analitica con SQL. Solo se justifica en produccion."
  type        = bool
  default     = false
}

variable "bigquery_location" {
  description = "Ubicacion del dataset de analitica de logs."
  type        = string
  default     = "EU"
}

variable "bigquery_table_expiration_days" {
  description = "Dias tras los que caducan las tablas particionadas de logs en BigQuery."
  type        = number
  default     = 90
}

variable "error_rate_threshold" {
  description = "Peticiones 5xx por segundo que disparan la alerta."
  type        = number
  default     = 1
}

variable "latency_p95_threshold_ms" {
  description = "Latencia p95 en milisegundos que dispara la alerta de degradacion."
  type        = number
  default     = 2000
}

variable "labels" {
  description = "Etiquetas aplicadas a los recursos que las admiten, para repartir costes y filtrar en facturacion."
  type        = map(string)
  default     = {}
}
