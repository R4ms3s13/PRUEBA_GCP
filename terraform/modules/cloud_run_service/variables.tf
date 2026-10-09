variable "project_id" {
  description = "ID del proyecto de GCP donde se crean los recursos."
  type        = string
}
variable "region" {
  description = "Region de GCP donde se despliegan los recursos regionales."
  type        = string
}
variable "service_name" {
  description = "Nombre del servicio de Cloud Run. Es tambien el identificador por el que se filtran sus metricas y sus logs."
  type        = string
}

variable "image" {
  description = "Imagen completa. El pipeline la sustituye por digest en cada release."
  type        = string
}

variable "service_account_email" {
  description = "Identidad con la que se ejecuta el servicio. Determina a que puede acceder y es la base del privilegio minimo."
  type        = string
}

variable "network_id" {
  description = "VPC a la que se conectan las instancias mediante Direct VPC egress."
  type        = string
}
variable "subnet_id" {
  description = "Subred de la que las instancias toman IP. Determina si tienen salida a Internet, segun este o no cubierta por Cloud NAT."
  type        = string
}

variable "vpc_egress" {
  description = <<-EOT
    ALL_TRAFFIC envia toda la salida por la VPC, de forma que la presencia o
    ausencia de Cloud NAT en la subnet determina si hay Internet. Es lo que se
    usa aqui. PRIVATE_RANGES_ONLY dejaria el trafico publico por la ruta
    gestionada de Google, esquivando ese control.
  EOT
  type        = string
  default     = "ALL_TRAFFIC"

  validation {
    condition     = contains(["ALL_TRAFFIC", "PRIVATE_RANGES_ONLY"], var.vpc_egress)
    error_message = "vpc_egress debe ser ALL_TRAFFIC o PRIVATE_RANGES_ONLY."
  }
}

variable "network_tags" {
  description = "Etiquetas de red de las instancias, para reglas de firewall dirigidas."
  type        = list(string)
  default     = []
}

variable "ingress" {
  description = <<-EOT
    INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER: solo balanceador y fuentes internas.
    INGRESS_TRAFFIC_INTERNAL_ONLY: solo fuentes internas (worker).
    INGRESS_TRAFFIC_ALL: expuesto en su URL run.app (no usar en prod).
  EOT
  type        = string
  default     = "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER"

  validation {
    condition     = contains(["INGRESS_TRAFFIC_ALL", "INGRESS_TRAFFIC_INTERNAL_ONLY", "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER"], var.ingress)
    error_message = "ingress debe ser INGRESS_TRAFFIC_ALL, INGRESS_TRAFFIC_INTERNAL_ONLY o INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER."
  }
}

# --- Dimensionado ---

variable "cpu" {
  description = "vCPU por instancia."
  type        = string
  default     = "1"
}

variable "memory" {
  description = "Memoria por instancia. El volumen temporal en memoria cuenta contra este limite."
  type        = string
  default     = "512Mi"
}

variable "min_instances" {
  description = "Instancias siempre activas. > 0 en prod para eliminar arranques en frio."
  type        = number
  default     = 0
}

variable "max_instances" {
  description = "Techo de escalado. Protege a la BBDD de un exceso de conexiones."
  type        = number
  default     = 10
}

variable "max_concurrency" {
  description = "Peticiones simultaneas que atiende una instancia. Node.js aprovecha valores altos por su E/S asincrona."
  type        = number
  default     = 80
}

variable "cpu_idle" {
  description = "true = CPU solo durante la request. false para trabajo en background."
  type        = bool
  default     = true
}

variable "startup_cpu_boost" {
  description = "Asigna CPU adicional durante el arranque, lo que acorta el tiempo hasta la primera peticion servida."
  type        = bool
  default     = true
}

variable "execution_environment" {
  description = "Generacion del entorno de ejecucion. GEN2 da soporte completo de sistema de ficheros y mejor rendimiento de red."
  type        = string
  default     = "EXECUTION_ENVIRONMENT_GEN2"

  validation {
    condition     = contains(["EXECUTION_ENVIRONMENT_GEN1", "EXECUTION_ENVIRONMENT_GEN2"], var.execution_environment)
    error_message = "execution_environment debe ser EXECUTION_ENVIRONMENT_GEN1 o EXECUTION_ENVIRONMENT_GEN2."
  }
}

variable "request_timeout_seconds" {
  description = "Tiempo maximo de una peticion. Un valor bajo libera instancias antes y acota el dano de una consulta colgada."
  type        = number
  default     = 60
}

# --- Configuracion de la aplicacion ---

variable "container_port" {
  description = "Puerto en el que escucha el contenedor. Contrato con el equipo de desarrollo."
  type        = number
  default     = 8080
}

variable "health_path" {
  description = "Ruta de salud que expone la aplicacion, usada por las sondas de arranque y vivacidad. Contrato con el equipo de desarrollo."
  type        = string
  default     = "/healthz"
}

variable "startup_probe_delay" {
  description = "Segundos de espera antes de la primera sonda de arranque."
  type        = number
  default     = 5
}

variable "startup_probe_failures" {
  description = "Fallos consecutivos de la sonda de arranque antes de dar la instancia por fallida."
  type        = number
  default     = 12
}

variable "env_vars" {
  description = "Variables de entorno NO sensibles."
  type        = map(string)
  default = {
  }
}

variable "secret_env_vars" {
  description = "Variables cuyo valor se resuelve desde Secret Manager."
  type = map(object({
    secret_id = string
    version   = string
  }))
  default = {}
}

variable "volume_mounts" {
  description = "Mapa nombre_volumen => ruta de montaje (scratch en memoria)."
  type        = map(string)
  default = {
  }
}

variable "tmp_size_limit" {
  description = <<-EOT
    Tamano del volumen temporal en memoria. CUENTA CONTRA var.memory: un tmpfs
    de 256Mi en una instancia de 512Mi deja la mitad de la RAM para el proceso
    y puede provocar OOM. Por eso el valor por defecto es conservador; subirlo
    solo cuando memory lo permita.
  EOT
  type        = string
  default     = "64Mi"
}

# --- Acceso ---

variable "invoker_members" {
  description = "Miembros IAM con roles/run.invoker sobre este servicio."
  type        = map(string)
  default = {
  }
}

variable "deletion_protection" {
  description = "Impide destruir el servicio desde Terraform. Debe estar activo en produccion."
  type        = bool
  default     = false
}

variable "labels" {
  description = "Etiquetas aplicadas a los recursos que las admiten, para repartir costes y filtrar en facturacion."
  type        = map(string)
  default     = {}
}
