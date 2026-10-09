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
  description = "Prefijo comun de todos los nombres de recurso del modulo. Hace que los recursos de un ambiente se reconozcan de un vistazo."
  type        = string
}

variable "network_id" {
  description = "VPC donde se publica la IP privada de la instancia."
  type        = string
}

variable "database_version" {
  description = "Version del motor de PostgreSQL. Subirla es una operacion con reinicio, asi que se fija explicitamente en lugar de dejar el valor por defecto del provider."
  type        = string
  default     = "POSTGRES_16"
}

variable "tier" {
  description = "Tipo de maquina. Dimensionado por ambiente desde el tfvars."
  type        = string
}

variable "edition" {
  description = "Edicion de Cloud SQL. ENTERPRISE_PLUS admite mas conexiones y mejor cache por vCPU, a mayor precio unitario."
  type        = string
  default     = "ENTERPRISE"

  validation {
    condition     = contains(["ENTERPRISE", "ENTERPRISE_PLUS"], var.edition)
    error_message = "edition debe ser ENTERPRISE o ENTERPRISE_PLUS."
  }
}

variable "highly_available" {
  description = "REGIONAL (standby sincrono en otra zona) frente a ZONAL."
  type        = bool
  default     = false
}

variable "disk_size_gb" {
  description = "Tamano inicial del disco. Crece solo con disk_autoresize, de modo que este valor es el punto de partida y no un limite."
  type        = number
  default     = 20
}

variable "disk_autoresize_limit_gb" {
  description = "Techo del crecimiento automatico de disco. 0 = sin limite."
  type        = number
  default     = 100
}

variable "database_name" {
  description = "Nombre de la base de datos logica que usa la aplicacion."
  type        = string
  default     = "proveedores"
}

variable "app_db_user" {
  description = "Usuario administrativo con contrasena, reservado a migraciones y mantenimiento. Los runtimes no lo usan: se conectan con autenticacion IAM."
  type        = string
  default     = "app"
}

# --- Backups y recuperacion ---

variable "backup_start_time" {
  description = "Hora UTC de inicio de la ventana de backup."
  type        = string
  default     = "02:00"
}

variable "backup_location" {
  description = "Region o multi-region donde se guardan los backups."
  type        = string
  default     = null
}

variable "point_in_time_recovery" {
  description = "PITR via WAL. Imprescindible en prod."
  type        = bool
  default     = false
}

variable "transaction_log_retention_days" {
  description = "Ventana de PITR en dias (1-35)."
  type        = number
  default     = 7

  validation {
    condition     = var.transaction_log_retention_days >= 1 && var.transaction_log_retention_days <= 35
    error_message = "transaction_log_retention_days debe estar entre 1 y 35: es el limite de la ventana de PITR en Cloud SQL."
  }
}

variable "retained_backups" {
  description = "Numero de backups automaticos que se conservan."
  type        = number
  default     = 7
}

# --- Mantenimiento ---

variable "maintenance_day" {
  description = "1 = lunes ... 7 = domingo."
  type        = number
  default     = 7

  validation {
    condition     = var.maintenance_day >= 1 && var.maintenance_day <= 7
    error_message = "maintenance_day debe estar entre 1 (lunes) y 7 (domingo)."
  }
}

variable "maintenance_hour" {
  description = "Hora UTC de inicio de la ventana de mantenimiento."
  type        = number
  default     = 3
}

# --- Parametros del motor ---

variable "max_connections" {
  description = "Limite de conexiones simultaneas del motor. Se fija junto al maximo de instancias de Cloud Run: es lo que impide que el autoescalado agote la base de datos."
  type        = number
  default     = 100
}

variable "log_min_duration_ms" {
  description = "Umbral de consulta lenta registrada en Cloud Logging."
  type        = number
  default     = 1000
}

variable "extra_database_flags" {
  description = "Flags adicionales del motor, para que un ambiente pueda afinar sin modificar el modulo."
  type        = map(string)
  default = {
  }
}

# --- Identidades ---

variable "iam_db_users" {
  description = "Emails de service account que se conectan con autenticacion IAM."
  type        = map(string)
  default = {
  }
}

variable "secret_accessor_members" {
  description = "Service accounts que pueden leer los secretos de la BBDD."
  type        = map(string)
  default = {
  }
}

variable "password_rotation_token" {
  description = "Cambiar este valor fuerza la regeneracion de la contrasena."
  type        = string
  default     = "v1"
}

# --- Protecciones ---

variable "deletion_protection" {
  description = "Impide destruir la instancia desde Terraform y desde la consola. Debe estar activo en produccion."
  type        = bool
  default     = true
}

variable "labels" {
  description = "Etiquetas aplicadas a los recursos que las admiten, para repartir costes y filtrar en los informes de facturacion."
  type        = map(string)
  default = {
  }
}

# --- Parametros del esquema ---

variable "charset" {
  description = "Juego de caracteres de la base de datos."
  type        = string
  default     = "UTF8"
}

variable "collation" {
  description = <<-EOT
    Collation de la base de datos. Afecta al ORDER BY de los textos, asi que
    conviene elegirla segun el idioma de los datos y NO cambiarla despues:
    hacerlo obliga a reconstruir indices.
  EOT
  type        = string
  default     = "en_US.UTF8"
}

variable "ssl_mode" {
  description = "ENCRYPTED_ONLY exige TLS en toda conexion."
  type        = string
  default     = "ENCRYPTED_ONLY"

  validation {
    condition     = contains(["ALLOW_UNENCRYPTED_AND_ENCRYPTED", "ENCRYPTED_ONLY", "TRUSTED_CLIENT_CERTIFICATE_REQUIRED"], var.ssl_mode)
    error_message = "ssl_mode debe ser ALLOW_UNENCRYPTED_AND_ENCRYPTED, ENCRYPTED_ONLY o TRUSTED_CLIENT_CERTIFICATE_REQUIRED."
  }
}

variable "query_insights_string_length" {
  description = "Longitud maxima de la consulta capturada por Query Insights. Mas largo da mas contexto para diagnosticar; tambien mas volumen."
  type        = number
  default     = 1024
}

# --- Generacion de la contrasena administrativa ---

variable "password_length" {
  description = "Longitud de la contrasena generada para el usuario administrativo."
  type        = number
  default     = 32
}

variable "password_special_chars" {
  description = "Conjunto de caracteres especiales permitidos por PostgreSQL en una contrasena."
  type        = string
  default     = "!#%*()-_=+[]{}<>:?"
}
