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

variable "frontend_bucket_name" {
  description = "Bucket con el build estatico del SPA."
  type        = string
}

variable "api_service_name" {
  description = "Nombre del servicio Cloud Run del API al que apunta el NEG."
  type        = string
}

variable "domains" {
  description = "Dominios del certificado gestionado. Vacio en dev (solo HTTP)."
  type        = list(string)
  default     = []
}

variable "enable_https" {
  description = "false permite probar en dev sin tener DNS delegado todavia."
  type        = bool
  default     = true
}

variable "api_timeout_sec" {
  description = "Tiempo que el balanceador espera la respuesta del API antes de cortar la conexion."
  type        = number
  default     = 60
}

# --- Cloud Armor ---

variable "enable_cloud_armor" {
  description = "Activa el WAF y la limitacion de tasa delante del punto de entrada publico."
  type        = bool
  default     = true
}

variable "waf_preview_mode" {
  description = <<-EOT
    true deja las reglas del WAF en modo observacion: registran lo que
    bloquearian sin bloquear. Es como deben estrenarse en prod, revisando
    falsos positivos antes de aplicar.
  EOT
  type        = bool
  default     = true
}

variable "rate_limit_requests" {
  description = "Peticiones por IP y por intervalo antes de aplicar el baneo temporal."
  type        = number
  default     = 300
}

variable "enable_adaptive_protection" {
  description = <<-EOT
    Deteccion adaptativa de DDoS de capa 7. Requiere suscripcion a Cloud Armor
    Enterprise; sin ella el apply falla. Desactivado por defecto a proposito.
  EOT
  type        = bool
  default     = false
}

variable "rate_limit_interval_sec" {
  description = "Ventana en segundos sobre la que se cuenta el limite de tasa."
  type        = number
  default     = 60
}

# --- Contrato con la aplicacion ---

variable "health_path" {
  description = "Ruta de salud que expone el API. Contrato con desarrollo."
  type        = string
  default     = "/healthz"
}

variable "api_path_patterns" {
  description = "Rutas que el balanceador enruta al API en lugar del bucket."
  type        = list(string)
  default     = ["/api", "/api/*"]
}

# --- Cache del CDN ---
#
# Los assets del SPA llevan hash en el nombre, de modo que pueden cachearse
# mucho tiempo; index.html se publica con no-cache desde el pipeline para que un
# despliegue se vea de inmediato.

variable "cdn_cache_mode" {
  description = "Politica de cache del CDN. CACHE_ALL_STATIC cachea el contenido estatico detectado automaticamente."
  type        = string
  default     = "CACHE_ALL_STATIC"

  validation {
    condition     = contains(["USE_ORIGIN_HEADERS", "FORCE_CACHE_ALL", "CACHE_ALL_STATIC"], var.cdn_cache_mode)
    error_message = "cdn_cache_mode debe ser USE_ORIGIN_HEADERS, FORCE_CACHE_ALL o CACHE_ALL_STATIC."
  }
}

variable "cdn_client_ttl" {
  description = "Tiempo que el navegador conserva el recurso en su cache local."
  type        = number
  default     = 3600
}

variable "cdn_default_ttl" {
  description = "Tiempo por defecto que el CDN conserva un recurso sin cabecera de cache explicita."
  type        = number
  default     = 3600
}

variable "cdn_max_ttl" {
  description = "Techo del tiempo de cache, aunque el origen pida mas."
  type        = number
  default     = 86400
}

variable "cdn_serve_while_stale" {
  description = "Segundos que se sirve contenido caducado mientras revalida."
  type        = number
  default     = 86400
}

variable "cdn_negative_ttl" {
  description = "Cache de respuestas 404."
  type        = number
  default     = 60
}

# --- TLS ---

variable "ssl_profile" {
  description = "Perfil de suites criptograficas. MODERN rechaza las obsoletas."
  type        = string
  default     = "MODERN"

  validation {
    condition     = contains(["COMPATIBLE", "MODERN", "RESTRICTED", "CUSTOM"], var.ssl_profile)
    error_message = "ssl_profile debe ser COMPATIBLE, MODERN, RESTRICTED o CUSTOM."
  }
}

variable "min_tls_version" {
  description = "Version minima de TLS aceptada."
  type        = string
  default     = "TLS_1_2"

  validation {
    condition     = contains(["TLS_1_0", "TLS_1_1", "TLS_1_2"], var.min_tls_version)
    error_message = "min_tls_version debe ser TLS_1_0, TLS_1_1 o TLS_1_2."
  }
}

variable "rate_limit_ban_seconds" {
  description = "Duracion del baneo temporal tras superar el limite de tasa."
  type        = number
  default     = 300
}
