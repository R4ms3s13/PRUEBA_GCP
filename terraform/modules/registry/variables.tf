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

variable "repository_id" {
  description = "Identificador del repositorio de Artifact Registry. Las referencias de imagen del pipeline se derivan de el, de modo que cambiarlo exige republicar."
  type        = string
  default     = "plataforma"
}

variable "tracked_images" {
  description = "Nombres de imagen cuyo historico se conserva."
  type        = list(string)
  default     = ["api", "worker", "batch"]
}

variable "keep_recent_versions" {
  description = "Numero de versiones recientes que la politica de limpieza conserva de cada imagen seguida. Es lo que permite revertir a un release anterior."
  type        = number
  default     = 10
}

variable "untagged_ttl_days" {
  description = "Dias que sobrevive una imagen sin etiqueta antes de borrarse. Las imagenes huerfanas de builds fallidos son la principal fuente de crecimiento del registro."
  type        = number
  default     = 7
}

variable "immutable_tags" {
  description = "Impide reescribir una etiqueta ya publicada. Garantiza que el digest desplegado es exactamente el que se construyo y se probo."
  type        = bool
  default     = false
}

variable "cleanup_dry_run" {
  description = "true evalua las politicas sin borrar nada. Util al estrenarlas."
  type        = bool
  default     = false
}
