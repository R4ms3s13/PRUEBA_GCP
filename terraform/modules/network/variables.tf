variable "project_id" {
  description = "ID del proyecto de GCP donde se crea la VPC."
  type        = string
}
variable "env" {
  description = "Identificador del ambiente (dev, qa o prod). Se usa en nombres, etiquetas y decisiones condicionales."
  type        = string
}
variable "region" {
  description = "Region donde se crean las subredes, el router y el NAT."
  type        = string
}
variable "name_prefix" {
  description = "Prefijo comun de los nombres de recurso de red."
  type        = string
}

variable "subnet_app_cidr" {
  description = <<-EOT
    Subnet del componente EXPUESTO (el API, alcanzable desde el balanceador).
    Deliberadamente SIN Cloud NAT: sin ruta a Internet.
  EOT
  type        = string
}

variable "subnet_internal_cidr" {
  description = <<-EOT
    Subnet de los componentes INTERNOS (worker y jobs batch), que si necesitan
    salir a Internet para el intercambio con aplicaciones de terceros. Es la
    unica subnet que Cloud NAT traduce.
  EOT
  type        = string
}

variable "psa_cidr" {
  description = "Direccion base del rango reservado para Private Service Access (Cloud SQL)."
  type        = string
}

variable "psa_prefix_length" {
  description = "Longitud del prefijo del rango de Private Service Access. /20 da holgura para que Google despliegue la instancia de Cloud SQL y sus replicas."
  type        = number
  default     = 20
}

variable "enable_nat" {
  description = "Cloud NAT para salida a Internet desde recursos sin IP publica."
  type        = bool
  default     = true
}

variable "nat_min_ports_per_vm" {
  description = "Puertos de origen que Cloud NAT reserva por instancia. Si se agotan, las conexiones salientes fallan de forma intermitente y dificil de diagnosticar."
  type        = number
  default     = 64
}

variable "flow_sampling" {
  description = "Fraccion de flujos VPC registrados. Mas alto en prod, mas bajo en dev por coste."
  type        = number
  default     = 0.1

  validation {
    condition     = var.flow_sampling >= 0 && var.flow_sampling <= 1
    error_message = "flow_sampling es una fraccion entre 0 y 1."
  }
}
