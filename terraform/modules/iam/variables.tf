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

variable "uploads_bucket_name" {
  description = "Bucket de archivos subidos por los usuarios."
  type        = string
}

variable "exports_bucket_name" {
  description = "Bucket de salidas de los procesos batch."
  type        = string
}

variable "db_backups_bucket_name" {
  description = "Bucket de volcados logicos de la base de datos."
  type        = string
}

variable "frontend_bucket_name" {
  description = "Bucket del build estatico. Solo CI/CD escribe en el."
  type        = string
}

variable "registry_repository_id" {
  description = "ID del repositorio de Artifact Registry con las imagenes."
  type        = string
}

variable "deployer_wif_principal" {
  description = <<-EOT
    Principal de Workload Identity Federation autorizado a impersonar la SA
    deployer, en formato principalSet://... Lo construye el modulo raiz a partir
    del pool que crea el bootstrap.

    Si queda vacio no se crea el binding, y entonces el pipeline de GitHub
    Actions NO puede autenticarse: ese es el caso de quien despliega solo con
    Cloud Build, que usa la SA directamente y no federa identidad.
  EOT
  type        = string
  default     = ""
}
