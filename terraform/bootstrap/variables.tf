variable "project_id" {
  description = "ID del proyecto de GCP del ambiente sobre el que se ejecuta el bootstrap."
  type        = string
}
variable "env" {
  description = "Identificador del ambiente (dev, qa o prod)."
  type        = string
}

variable "region" {
  description = "Region donde se crea el bucket de state."
  type        = string
  default     = "europe-west1"
}

variable "github_repository" {
  description = "owner/repo exacto. Acota quien puede federar identidad."
  type        = string
}

variable "protected_branch" {
  description = "Rama desde la que se permite desplegar en prod."
  type        = string
  default     = "main"
}

variable "kms_key_name" {
  description = "Clave CMEK para el bucket de state. null usa la clave de Google."
  type        = string
  default     = null
}

variable "state_admin_members" {
  description = "Personas o grupos con acceso al state, ademas del pipeline."
  type        = map(string)
  default = {
  }
}

variable "terraform_sa_roles" {
  description = <<-EOT
    Roles de la SA de Terraform. Son amplios porque gestiona red, IAM y datos,
    pero siguen sin incluir roles basicos: ni owner ni editor.
  EOT
  type        = list(string)
  default = [
    "roles/compute.networkAdmin",
    "roles/compute.securityAdmin",
    "roles/compute.loadBalancerAdmin",
    "roles/run.admin",
    "roles/cloudsql.admin",
    "roles/storage.admin",
    "roles/artifactregistry.admin",
    "roles/pubsub.admin",
    "roles/cloudscheduler.admin",
    "roles/secretmanager.admin",
    "roles/iam.serviceAccountAdmin",
    "roles/resourcemanager.projectIamAdmin",
    "roles/logging.admin",
    "roles/monitoring.admin",
    "roles/serviceusage.serviceUsageAdmin",
    "roles/bigquery.admin",
    "roles/iam.serviceAccountUser",
  ]
}

# --- Nombres. El prefijo de la organizacion no se escribe a mano: el bucket de
#     state y la service account de Terraform se derivan de el, igual que en la
#     plataforma. Asi un cambio de nombre es una variable, no una busqueda.

variable "name_prefix" {
  description = "Prefijo de la organizacion. Debe coincidir con el bucket del backend.hcl."
  type        = string
  default     = "proveedores"
}

variable "tf_sa_prefix" {
  description = "Prefijo de la service account que ejecuta Terraform."
  type        = string
  default     = "tf-infra"
}

variable "wif_pool_prefix" {
  description = "Prefijo del pool de Workload Identity Federation."
  type        = string
  default     = "github"
}

variable "state_keep_versions" {
  description = "Versiones archivadas del state que se conservan."
  type        = number
  default     = 20
}

variable "allowed_workflows" {
  description = <<-EOT
    Ficheros de .github/workflows/ autorizados a federar identidad. Es una lista
    blanca: un workflow que no este aqui no obtiene token, aunque viva en el
    repositorio autorizado.

    Es la defensa contra un repositorio comprometido en el que el atacante anade
    un workflow propio. No defiende de que modifique uno de estos tres: para eso
    hace falta proteccion de rama con revision obligatoria (D16).
  EOT
  type        = list(string)
  default     = ["infra.yml", "backend.yml", "frontend.yml"]

  validation {
    condition     = length(var.allowed_workflows) > 0
    error_message = "Debe autorizarse al menos un workflow, o ningun pipeline podra desplegar."
  }
}
