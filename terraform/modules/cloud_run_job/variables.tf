variable "project_id" {
  description = "ID del proyecto de GCP donde se crean los recursos."
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

variable "image" {
  description = "Imagen de contenedor que ejecutan los jobs. La actualiza el pipeline de aplicacion, no el de infraestructura."
  type        = string
}
variable "service_account_email" {
  description = "Identidad con la que se ejecutan los jobs."
  type        = string
}
variable "scheduler_service_account_email" {
  description = "Identidad con la que Cloud Scheduler invoca los jobs. Recibe run.invoker sobre cada job concreto, no sobre el proyecto."
  type        = string
}

variable "api_service_account_email" {
  description = "Si se indica, el API puede lanzar ejecuciones bajo demanda."
  type        = string
  default     = null
}

variable "network_id" {
  description = "VPC a la que se conectan las ejecuciones."
  type        = string
}
variable "subnet_id" {
  description = "Subred de la que toman IP las ejecuciones. La interna es la unica con salida a Internet."
  type        = string
}

variable "network_tags" {
  description = "Etiquetas de red de las instancias de los jobs."
  type        = list(string)
  default     = []
}

variable "jobs" {
  description = <<-EOT
    Definicion de cada proceso batch. schedule = null lo deja solo bajo demanda.
    El cron se interpreta en var.time_zone.
  EOT
  type = map(object({
    description     = string
    command         = optional(list(string))
    args            = optional(list(string))
    schedule        = optional(string)
    cpu             = optional(string, "1")
    memory          = optional(string, "1Gi")
    task_count      = optional(number, 1)
    parallelism     = optional(number, 1)
    max_retries     = optional(number, 2)
    timeout_seconds = optional(number, 3600)
    vpc_egress      = optional(string, "ALL_TRAFFIC")
    env_vars        = optional(map(string), {})
  }))
}

variable "common_env_vars" {
  description = "Variables de entorno comunes a todos los jobs del ambiente."
  type        = map(string)
  default     = {}
}

variable "secret_env_vars" {
  description = "Variables cuyo valor se resuelve desde Secret Manager en el arranque de la ejecucion."
  type = map(object({
    secret_id = string
    version   = string
  }))
  default = {}
}

variable "time_zone" {
  description = "Zona horaria en la que se interpretan las expresiones cron de Cloud Scheduler."
  type        = string
  default     = "Europe/Madrid"
}

variable "labels" {
  description = "Etiquetas aplicadas a los recursos que las admiten, para repartir costes y filtrar en facturacion."
  type        = map(string)
  default     = {}
}
