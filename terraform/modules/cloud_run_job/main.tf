# ---------------------------------------------------------------------------
# Procesamiento batch: Cloud Run Jobs + Cloud Scheduler.
#
# Requisito: "Infraestructura que permita ejecutar procesos programados o bajo
# demanda."
#   - Programados : Cloud Scheduler invoca la API de ejecucion del job.
#   - Bajo demanda: el mismo job se lanza con "gcloud run jobs execute" o desde
#     el API backend, que tiene run.invoker acotado sobre el job.
#
# Por que Cloud Run Jobs y no Cloud Scheduler -> Pub/Sub -> Cloud Run service:
# un job tiene ciclo de vida de tarea (termina, reintenta, tiene codigo de
# salida y timeout de horas), mientras que un servicio esta limitado por el
# timeout de request y no expresa "esto ha terminado bien o mal".
# Para volumenes mucho mayores el salto natural seria Cloud Batch o Dataflow.
# ---------------------------------------------------------------------------

resource "google_cloud_run_v2_job" "this" {
  for_each = var.jobs

  project  = var.project_id
  name     = "${var.name_prefix}-${each.key}"
  location = var.region

  deletion_protection = false
  labels              = var.labels

  template {
    # Reintentos y paralelismo a nivel de TAREA.
    task_count  = each.value.task_count
    parallelism = each.value.parallelism

    template {
      service_account = var.service_account_email
      max_retries     = each.value.max_retries
      timeout         = "${each.value.timeout_seconds}s"

      execution_environment = "EXECUTION_ENVIRONMENT_GEN2"

      vpc_access {
        network_interfaces {
          network    = var.network_id
          subnetwork = var.subnet_id
          tags       = var.network_tags
        }
        # Los jobs viven en la subnet interna, que si tiene Cloud NAT: de ahi
        # sale el intercambio de informacion con aplicaciones de terceros, por
        # una IP fija y auditable.
        egress = each.value.vpc_egress
      }

      containers {
        image   = var.image
        command = each.value.command
        args    = each.value.args

        resources {
          limits = {
            cpu    = each.value.cpu
            memory = each.value.memory
          }
        }

        dynamic "env" {
          for_each = merge(var.common_env_vars, each.value.env_vars)
          content {
            name  = env.key
            value = env.value
          }
        }

        dynamic "env" {
          for_each = var.secret_env_vars
          content {
            name = env.key
            value_source {
              secret_key_ref {
                secret  = env.value.secret_id
                version = env.value.version
              }
            }
          }
        }
      }
    }
  }

  lifecycle {
    ignore_changes = [
      template[0].template[0].containers[0].image,
      client,
      client_version,
    ]
  }
}

# ---------------------------------------------------------------------------
# run.invoker acotado al job concreto, no al proyecto: Scheduler puede lanzar
# estos jobs y nada mas.
# ---------------------------------------------------------------------------
resource "google_cloud_run_v2_job_iam_member" "scheduler_invoker" {
  for_each = var.jobs

  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_job.this[each.key].name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${var.scheduler_service_account_email}"
}

# Permite al API backend disparar ejecuciones bajo demanda.
resource "google_cloud_run_v2_job_iam_member" "api_invoker" {
  for_each = var.api_service_account_email == null ? {} : var.jobs

  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_job.this[each.key].name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${var.api_service_account_email}"
}

# ---------------------------------------------------------------------------
# Programacion. Cloud Scheduler llama a la API de Cloud Run Admin con un token
# OAuth de su propia service account (OAuth y no OIDC porque el destino es una
# API de Google, no un endpoint propio): no hay claves ni webhooks compartidos.
# ---------------------------------------------------------------------------
resource "google_cloud_scheduler_job" "schedule" {
  for_each = { for k, v in var.jobs : k => v if v.schedule != null }

  project     = var.project_id
  region      = var.region
  name        = "${var.name_prefix}-${each.key}-sched"
  description = each.value.description
  schedule    = each.value.schedule
  time_zone   = var.time_zone

  # Sin reintentos a nivel de Scheduler: los reintentos son del job
  # (max_retries), que es donde esta el contexto para decidir si tiene sentido.
  retry_config {
    retry_count = 0
  }

  attempt_deadline = "${min(each.value.timeout_seconds, 1800)}s"

  http_target {
    http_method = "POST"
    uri         = "https://${var.region}-run.googleapis.com/v2/projects/${var.project_id}/locations/${var.region}/jobs/${google_cloud_run_v2_job.this[each.key].name}:run"

    oauth_token {
      service_account_email = var.scheduler_service_account_email
      scope                 = "https://www.googleapis.com/auth/cloud-platform"
    }
  }
}
