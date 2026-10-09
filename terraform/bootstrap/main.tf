# ---------------------------------------------------------------------------
# BOOTSTRAP. Se aplica UNA vez por ambiente, antes que la plataforma, y con
# state local (no puede guardar su state en un bucket que el mismo crea).
#
# Crea lo que el resto del repositorio da por existente:
#   1. El bucket del state remoto de Terraform.
#   2. La federacion de identidad (Workload Identity Federation) para que el
#      CI/CD se autentique SIN claves de service account descargadas.
#
# Esto ultimo es la pieza que permite cumplir "no credenciales en codigo duro"
# tambien en el pipeline: GitHub presenta su token OIDC y GCP lo intercambia por
# un token de acceso de corta duracion.
# ---------------------------------------------------------------------------

provider "google" {
  project = var.project_id
  region  = var.region
}

# ---------------------------------------------------------------------------
# State remoto
# ---------------------------------------------------------------------------
resource "google_storage_bucket" "tfstate" {
  project  = var.project_id
  name     = "${var.name_prefix}-tfstate-${var.env}"
  location = var.region

  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  # El state contiene valores sensibles (entre ellos la contrasena generada de
  # la BBDD): versionado para poder recuperar un state corrupto, y sin borrado.
  versioning { enabled = true }

  lifecycle_rule {
    condition {
      num_newer_versions = var.state_keep_versions
      with_state         = "ARCHIVED"
    }
    action { type = "Delete" }
  }

  # Cifrado en reposo con clave gestionada por el cliente si se aporta.
  dynamic "encryption" {
    for_each = var.kms_key_name == null ? [] : [1]
    content {
      default_kms_key_name = var.kms_key_name
    }
  }

  force_destroy = false
}

# Solo el pipeline y los administradores de plataforma tocan el state.
resource "google_storage_bucket_iam_member" "tfstate_admin" {
  for_each = var.state_admin_members

  bucket = google_storage_bucket.tfstate.name
  role   = "roles/storage.objectAdmin"
  member = each.value
}

# ---------------------------------------------------------------------------
# Workload Identity Federation para GitHub Actions
# ---------------------------------------------------------------------------
resource "google_iam_workload_identity_pool" "github" {
  project                   = var.project_id
  workload_identity_pool_id = "${var.wif_pool_prefix}-${var.env}"
  display_name              = "GitHub Actions (${var.env})"
  description               = "Federacion sin claves para el pipeline de CI/CD"
}

resource "google_iam_workload_identity_pool_provider" "github" {
  project                            = var.project_id
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "github-oidc"
  display_name                       = "GitHub OIDC"

  attribute_mapping = {
    "google.subject"         = "assertion.sub"
    "attribute.repository"   = "assertion.repository"
    "attribute.ref"          = "assertion.ref"
    "attribute.workflow_ref" = "assertion.job_workflow_ref"
  }

  # DOS condiciones, y la segunda es la que defiende de un repositorio
  # comprometido:
  #
  # 1. El repositorio. Sin esto, CUALQUIER repositorio de GitHub podria obtener
  #    un token para este proyecto.
  #
  # 2. El fichero de workflow concreto. `job_workflow_ref` es el claim que dice
  #    QUE workflow se esta ejecutando. Sin fijarlo, quien consiga escribir en el
  #    repositorio anade un workflow nuevo y obtiene el mismo token con los
  #    mismos permisos: la condicion de repositorio no le estorba, porque el
  #    repositorio sigue siendo el autorizado. Con la lista blanca, un workflow
  #    inyectado no federa.
  #
  # Lo que esto NO cubre: modificar uno de los workflows ya autorizados. Eso solo
  # lo para la proteccion de rama con revision obligatoria, que es un control de
  # GitHub y no de Terraform. Documentado en D16.
  attribute_condition = join(" && ", [
    "assertion.repository == \"${var.github_repository}\"",
    "(${join(" || ", [
      for w in var.allowed_workflows :
      "assertion.job_workflow_ref.startsWith(\"${var.github_repository}/.github/workflows/${w}@\")"
    ])})"
  ])

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

# Identidad que asume el pipeline de INFRAESTRUCTURA. Tiene permisos amplios por
# necesidad (crea redes, IAM, bases de datos), y por eso se protege por dos
# lados: el proveedor de arriba acota REPOSITORIO y WORKFLOW, y el binding de
# abajo acota la RAMA en prod.
resource "google_service_account" "terraform" {
  project      = var.project_id
  account_id   = "${var.tf_sa_prefix}-${var.env}"
  display_name = "Terraform infraestructura (${var.env})"
}

resource "google_project_iam_member" "terraform_roles" {
  for_each = toset(var.terraform_sa_roles)

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.terraform.email}"
}

resource "google_storage_bucket_iam_member" "terraform_state" {
  bucket = google_storage_bucket.tfstate.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.terraform.email}"
}

# Quien puede impersonar la SA de Terraform: solo workloads del repositorio
# autorizado. En prod se restringe ademas a la rama principal.
resource "google_service_account_iam_member" "terraform_wif" {
  service_account_id = google_service_account.terraform.name
  role               = "roles/iam.workloadIdentityUser"
  member = var.env == "prod" ? (
    "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.ref/refs/heads/${var.protected_branch}"
    ) : (
    "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${var.github_repository}"
  )
}
