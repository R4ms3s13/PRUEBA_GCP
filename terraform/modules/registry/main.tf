# ---------------------------------------------------------------------------
# Artifact Registry: registro privado de imagenes Docker.
#
# Decision: un unico repositorio por ambiente. La alternativa (un repositorio
# compartido para los tres) ahorra almacenamiento y permite promocionar la MISMA
# imagen de dev a prod por digest, pero obliga a que el runtime de prod tenga
# lectura sobre un recurso que tambien escribe el CI de dev. Con proyectos
# separados por ambiente, mantener el registro de cada uno es mas limpio; el
# flujo de promocion se resuelve copiando por digest en el pipeline.
# ---------------------------------------------------------------------------
resource "google_artifact_registry_repository" "docker" {
  project       = var.project_id
  location      = var.region
  repository_id = var.repository_id
  format        = "DOCKER"
  description   = "Imagenes de la plataforma de proveedores (${var.env})"

  docker_config {
    # Una etiqueta ya publicada no puede reescribirse: garantiza que el digest
    # desplegado es el que se construyo y testeo.
    immutable_tags = var.immutable_tags
  }

  # El analisis de vulnerabilidades de las imagenes NO se configura aqui: lo
  # gobierna Artifact Analysis a nivel de proyecto, habilitando la API
  # containerscanning.googleapis.com (ver google_project_service en el modulo
  # raiz). Declararlo tambien en el repositorio seria redundante y acoplaria el
  # codigo a un atributo reciente del provider.

  # Limpieza automatica: sin esto el registro crece sin limite y el coste con el.
  cleanup_policies {
    id     = "mantener-releases-recientes"
    action = "KEEP"
    most_recent_versions {
      package_name_prefixes = var.tracked_images
      keep_count            = var.keep_recent_versions
    }
  }

  cleanup_policies {
    id     = "borrar-untagged-antiguas"
    action = "DELETE"
    condition {
      tag_state  = "UNTAGGED"
      older_than = "${var.untagged_ttl_days * 86400}s"
    }
  }

  # En dev/qa no se conserva historico largo; en prod si (var.keep_recent_versions).
  cleanup_policy_dry_run = var.cleanup_dry_run
}
