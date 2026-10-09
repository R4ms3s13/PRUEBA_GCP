variable "project_id" {
  description = "ID del proyecto de GCP donde se crean los recursos."
  type        = string
}

variable "project_number" {
  description = "Se usa como sufijo para que los nombres de bucket sean globalmente unicos."
  type        = string
}

variable "env" {
  description = "Identificador del ambiente (dev, qa o prod). Se usa en nombres, etiquetas y decisiones condicionales."
  type        = string
}
variable "name_prefix" {
  description = "Prefijo comun de todos los nombres de recurso del modulo. Hace que los recursos de un ambiente se reconozcan de un vistazo."
  type        = string
}

variable "location" {
  description = "Ubicacion de los buckets operativos (region o multi-region)."
  type        = string
}

variable "backup_location" {
  description = "Ubicacion de los backups. En prod, distinta de la region principal."
  type        = string
}

variable "cors_origins" {
  description = "Origenes permitidos para subida directa con URL firmada."
  type        = list(string)
  default     = []
}

variable "frontend_keep_versions" {
  description = "Versiones del build estatico que se conservan para poder revertir."
  type        = number
  default     = 5
}

variable "uploads_retention_days" {
  description = "Retencion inmutable de los archivos subidos. 0 la desactiva (dev/qa)."
  type        = number
  default     = 0
}

variable "exports_retention_days" {
  description = "Dias que se conservan las salidas de los procesos batch. Son regenerables, de modo que no se guardan indefinidamente."
  type        = number
  default     = 30
}

variable "db_backup_retention_days" {
  description = "Dias que se conservan los volcados logicos de la base de datos."
  type        = number
  default     = 30
}

variable "force_destroy" {
  description = "Permite destruir buckets con contenido. Debe ser false en prod."
  type        = bool
  default     = false
}

# --- Ciclo de vida de los archivos subidos ---

variable "uploads_storage_class_transitions" {
  description = <<-EOT
    Transiciones de clase de almacenamiento por edad. El acceso a documentos de
    pedidos cae con el tiempo, asi que bajarlos de clase es ahorro directo sin
    perder disponibilidad.
  EOT
  type = list(object({
    age_days      = number
    storage_class = string
  }))
  default = [
    { age_days = 90, storage_class = "NEARLINE" },
    { age_days = 365, storage_class = "COLDLINE" },
  ]
}

variable "uploads_keep_versions" {
  description = "Versiones archivadas que se conservan de cada objeto."
  type        = number
  default     = 3
}

# --- CORS para subida directa con URL firmada ---

variable "cors_methods" {
  description = "Metodos HTTP permitidos en las peticiones CORS al bucket de subidas. PUT y POST son los que usa la subida directa con URL firmada."
  type        = list(string)
  default     = ["GET", "PUT", "POST", "HEAD"]
}

variable "cors_response_headers" {
  description = "Cabeceras que el navegador puede leer en la respuesta del bucket. Content-MD5 permite al cliente verificar la integridad de lo subido."
  type        = list(string)
  default     = ["Content-Type", "Content-MD5", "x-goog-resumable"]
}

variable "cors_max_age_seconds" {
  description = "Tiempo que el navegador cachea la respuesta preflight de CORS, evitando una peticion OPTIONS por cada subida."
  type        = number
  default     = 3600
}
