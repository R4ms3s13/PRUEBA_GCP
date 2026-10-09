# ---------------------------------------------------------------------------
# Una service account por componente. El objetivo es que el compromiso de un
# componente no otorgue nada de lo que necesitan los demas, y que los permisos
# de cada identidad se lean de un vistazo.
#
# Regla aplicada: ningun rol basico (owner/editor/viewer) y ningun permiso a
# nivel de proyecto cuando existe el equivalente a nivel de recurso.
# ---------------------------------------------------------------------------

locals {
  # Roles a nivel de PROYECTO. Deliberadamente minimos: solo lo que no puede
  # concederse sobre un recurso concreto (telemetria y conexion a Cloud SQL).
  project_roles = {
    api = [
      "roles/cloudsql.client",       # abrir conexion a la instancia
      "roles/cloudsql.instanceUser", # autenticacion IAM en la BBDD
      "roles/logging.logWriter",
      "roles/monitoring.metricWriter",
      "roles/cloudtrace.agent",
      "roles/errorreporting.writer",
    ]
    worker = [
      "roles/cloudsql.client",
      "roles/cloudsql.instanceUser",
      "roles/logging.logWriter",
      "roles/monitoring.metricWriter",
      "roles/cloudtrace.agent",
      "roles/errorreporting.writer",
    ]
    batch = [
      "roles/cloudsql.client",
      "roles/cloudsql.instanceUser",
      "roles/logging.logWriter",
      "roles/monitoring.metricWriter",
      "roles/errorreporting.writer",
    ]
    scheduler = [
      "roles/logging.logWriter",
    ]
    # Identidad con la que Pub/Sub firma el OIDC hacia el worker. No necesita
    # ningun rol de proyecto: solo run.invoker sobre el worker concreto.
    pubsub = []
    deployer = [
      "roles/run.developer",
      "roles/artifactregistry.writer",
      "roles/logging.logWriter",
    ]
  }

  # Producto cartesiano aplanado para poder usar un unico recurso con for_each.
  project_bindings = flatten([
    for sa, roles in local.project_roles : [
      for role in roles : {
        key  = "${sa}-${replace(role, "roles/", "")}"
        sa   = sa
        role = role
      }
    ]
  ])
}

resource "google_service_account" "sa" {
  for_each = {
    api       = "Runtime del API backend (Node.js)"
    worker    = "Consumidor de Pub/Sub para procesos asincronos"
    batch     = "Ejecuciones de procesos batch (Cloud Run Jobs)"
    scheduler = "Identidad con la que Cloud Scheduler invoca los jobs"
    pubsub    = "Identidad con la que Pub/Sub entrega los push al worker"
    deployer  = "Identidad de CI/CD para construir y desplegar revisiones"
  }

  project      = var.project_id
  account_id   = "${var.name_prefix}-${each.key}"
  display_name = "${upper(var.env)} | ${each.value}"
  description  = each.value
}

resource "google_project_iam_member" "bindings" {
  for_each = { for b in local.project_bindings : b.key => b }

  project = var.project_id
  role    = each.value.role
  member  = "serviceAccount:${google_service_account.sa[each.value.sa].email}"
}

# ---------------------------------------------------------------------------
# Separacion de permisos sobre los buckets: el API firma y sube, el batch solo
# lee. Se concede a nivel de recurso, no de proyecto.
# ---------------------------------------------------------------------------
resource "google_storage_bucket_iam_member" "uploads_api" {
  bucket = var.uploads_bucket_name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.sa["api"].email}"
}

resource "google_storage_bucket_iam_member" "uploads_worker" {
  bucket = var.uploads_bucket_name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.sa["worker"].email}"
}

resource "google_storage_bucket_iam_member" "uploads_batch" {
  bucket = var.uploads_bucket_name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.sa["batch"].email}"
}

# El batch escribe sus salidas (informes, exportaciones) en su propio bucket.
resource "google_storage_bucket_iam_member" "exports_batch" {
  bucket = var.exports_bucket_name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.sa["batch"].email}"
}

# El batch deposita ahi el volcado logico de la BBDD.
resource "google_storage_bucket_iam_member" "db_backups_batch" {
  bucket = var.db_backups_bucket_name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.sa["batch"].email}"
}

# CI/CD publica el build del SPA en el bucket del frontend. Sin esto el paso
# "publicar frontend" del pipeline falla con 403: es el unico bucket sobre el
# que el deployer necesita escribir, y solo sobre ese.
resource "google_storage_bucket_iam_member" "frontend_deployer" {
  bucket = var.frontend_bucket_name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.sa["deployer"].email}"
}

# Invalidar la cache del CDN tras publicar index.html.
resource "google_project_iam_member" "deployer_cdn_invalidate" {
  project = var.project_id
  role    = "roles/compute.loadBalancerAdmin"
  member  = "serviceAccount:${google_service_account.sa["deployer"].email}"
}

# ---------------------------------------------------------------------------
# Imagenes de contenedor: CI escribe, los runtimes solo leen.
# ---------------------------------------------------------------------------
resource "google_artifact_registry_repository_iam_member" "readers" {
  for_each = toset(["api", "worker", "batch"])

  project    = var.project_id
  location   = var.region
  repository = var.registry_repository_id
  role       = "roles/artifactregistry.reader"
  member     = "serviceAccount:${google_service_account.sa[each.key].email}"
}

# NOTA: run.invoker NO se concede aqui. Scheduler -> job y Pub/Sub -> worker se
# vinculan sobre el recurso concreto en los modulos async/cloud_run_job, para no
# dar un invoker amplio a nivel de proyecto.

# Permite que CI/CD despliegue revisiones ejecutandose "como" las SA de runtime
# sin tener sus permisos: es el patron de impersonacion acotada.
resource "google_service_account_iam_member" "deployer_act_as" {
  for_each = toset(["api", "worker", "batch"])

  service_account_id = google_service_account.sa[each.key].name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${google_service_account.sa["deployer"].email}"
}

# Quien puede impersonar la SA de deployer desde CI/CD. Sin este binding el paso
# `auth` de los workflows de GitHub falla con 403: federar identidad no basta,
# hace falta que el principal federado tenga workloadIdentityUser SOBRE la SA
# que pretende usar.
#
# Se concede solo sobre la SA de despliegue, nunca sobre las de runtime: esas se
# usan por impersonacion acotada (deployer_act_as, arriba), que permite
# desplegar "como" ellas sin heredar sus permisos.
resource "google_service_account_iam_member" "deployer_wif" {
  count = var.deployer_wif_principal == "" ? 0 : 1

  service_account_id = google_service_account.sa["deployer"].name
  role               = "roles/iam.workloadIdentityUser"
  member             = var.deployer_wif_principal
}
