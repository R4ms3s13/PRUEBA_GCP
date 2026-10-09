# ---------------------------------------------------------------------------
# Buckets de la plataforma. Tres responsabilidades separadas para que los
# permisos y las politicas de ciclo de vida no se mezclen:
#   - frontend : build estatico de React, servido por el balanceador + CDN
#   - uploads  : archivos de proveedores/pedidos subidos por los usuarios
#   - exports  : salidas de los procesos batch (informes, ficheros de intercambio)
#
# Todos con uniform_bucket_level_access: las ACL por objeto son una fuente
# clasica de fugas y ademas impiden razonar sobre los permisos desde IAM.
# ---------------------------------------------------------------------------

resource "google_storage_bucket" "frontend" {
  project  = var.project_id
  name     = "${var.name_prefix}-frontend-${var.project_number}"
  location = var.location

  uniform_bucket_level_access = true
  public_access_prevention    = "inherited" # lo sirve el LB via backend bucket

  # El SPA se sirve desde el balanceador; estas claves cubren el acceso directo.
  website {
    main_page_suffix = "index.html"
    not_found_page   = "index.html" # routing client-side de React
  }

  versioning { enabled = true }

  lifecycle_rule {
    condition {
      num_newer_versions = var.frontend_keep_versions
    }
    action { type = "Delete" }
  }

  force_destroy = var.force_destroy
}

# El build estatico es publico por diseno: es el frontend de una web.
# Se expone via backend bucket del LB, y aqui se permite la lectura del objeto.
resource "google_storage_bucket_iam_member" "frontend_public" {
  bucket = google_storage_bucket.frontend.name
  role   = "roles/storage.objectViewer"
  member = "allUsers"
}

resource "google_storage_bucket" "uploads" {
  project  = var.project_id
  name     = "${var.name_prefix}-uploads-${var.project_number}"
  location = var.location

  uniform_bucket_level_access = true
  public_access_prevention    = "enforced" # nunca accesible desde Internet

  versioning { enabled = true }

  # Transicion por coste: el acceso a documentos de pedidos cae con la edad.
  dynamic "lifecycle_rule" {
    for_each = var.uploads_storage_class_transitions
    content {
      condition { age = lifecycle_rule.value.age_days }
      action {
        type          = "SetStorageClass"
        storage_class = lifecycle_rule.value.storage_class
      }
    }
  }

  # Las versiones antiguas no se guardan indefinidamente.
  #
  # OJO con la interaccion: si uploads_retention_days > 0 hay una retention
  # policy, y GCS NO borra un objeto todavia bajo retencion. Esta regla solo
  # surte efecto una vez vencida la retencion. Es intencionado: la retencion
  # manda sobre el ahorro.
  lifecycle_rule {
    condition {
      num_newer_versions = var.uploads_keep_versions
      with_state         = "ARCHIVED"
    }
    action { type = "Delete" }
  }

  # CORS para subida directa desde el navegador con URL firmada: el fichero no
  # atraviesa Cloud Run, lo que evita el limite de tamano de request y ahorra CPU.
  cors {
    origin          = var.cors_origins
    method          = var.cors_methods
    response_header = var.cors_response_headers
    max_age_seconds = var.cors_max_age_seconds
  }

  dynamic "retention_policy" {
    for_each = var.uploads_retention_days > 0 ? [1] : []
    content {
      retention_period = var.uploads_retention_days * 86400
    }
  }

  force_destroy = var.force_destroy
}

resource "google_storage_bucket" "exports" {
  project  = var.project_id
  name     = "${var.name_prefix}-exports-${var.project_number}"
  location = var.location

  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  # Las exportaciones son regenerables: no se versionan y caducan.
  lifecycle_rule {
    condition { age = var.exports_retention_days }
    action { type = "Delete" }
  }

  force_destroy = var.force_destroy
}

# ---------------------------------------------------------------------------
# Bucket de backups logicos de la base de datos (pg_dump del job batch).
# Complementa a los backups gestionados de Cloud SQL: protege frente al borrado
# accidental de la propia instancia, que se llevaria sus backups con ella.
# ---------------------------------------------------------------------------
resource "google_storage_bucket" "db_backups" {
  project  = var.project_id
  name     = "${var.name_prefix}-db-backups-${var.project_number}"
  location = var.backup_location

  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  versioning { enabled = true }

  lifecycle_rule {
    condition { age = var.db_backup_retention_days }
    action { type = "Delete" }
  }

  force_destroy = var.force_destroy
}
