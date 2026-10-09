# ===========================================================================
# DEV - configuracion del ambiente
#
# Criterio: lo mas barato que siga siendo representativo. Sin HA, sin min
# instances (se acepta arranque en frio), sin Cloud Armor, retenciones cortas y
# destruccion permitida para poder reconstruirlo a voluntad.
# ===========================================================================

project_id = "proveedores-dev"
region     = "europe-west1"

# --- Red. Rangos disjuntos entre ambientes: permite un peering futuro sin
#     renumerar, y hace imposible confundir una IP de dev con una de prod.
subnet_app_cidr      = "10.10.0.0/22" # API: sin Cloud NAT, sin salida a Internet
subnet_internal_cidr = "10.10.4.0/22" # worker y jobs: salida por NAT con IP fija
psa_cidr             = "10.10.16.0"
enable_nat           = true

# --- Imagenes. Placeholder publico hasta el primer despliegue del pipeline.
api_image    = "us-docker.pkg.dev/cloudrun/container/hello"
worker_image = "us-docker.pkg.dev/cloudrun/container/hello"
batch_image  = "us-docker.pkg.dev/cloudrun/container/hello"

# --- Runtime. Escala a cero: fuera de horario de trabajo dev no cuesta computo.
api_cpu             = "1"
api_memory          = "512Mi"
api_min_instances   = 0
api_max_instances   = 3
api_max_concurrency = 80

# Ingress del worker. Si las entregas push de Pub/Sub no contasen como
# trafico interno, pasar a INGRESS_TRAFFIC_ALL: la autorizacion no se
# debilita (sigue exigiendo OIDC y run.invoker de la SA de Pub/Sub).
worker_ingress       = "INGRESS_TRAFFIC_INTERNAL_ONLY"
worker_cpu           = "1"
worker_memory        = "512Mi"
worker_min_instances = 0
worker_max_instances = 2

# --- Base de datos. La instancia mas pequena util; sin HA ni PITR.
db_tier                           = "db-custom-1-3840"
db_highly_available               = false
db_disk_size_gb                   = 20
db_max_connections                = 50
db_point_in_time_recovery         = false
db_retained_backups               = 3
db_transaction_log_retention_days = 1
db_deletion_protection            = false

# --- Almacenamiento. Regional (mas barato que multi-region) y borrable.
storage_location        = "europe-west1"
storage_backup_location = "europe-west1"
uploads_retention_days  = 0
force_destroy_buckets   = true

# --- Entrada publica. Sin dominio ni TLS gestionado: se accede por IP.
domains             = []
enable_https        = false
enable_cloud_armor  = false
waf_preview_mode    = true
rate_limit_requests = 1000

# --- Observabilidad. Retencion minima y sin sink analitico.
alert_emails             = {}
log_retention_days       = 7
enable_bigquery_sink     = false
latency_p95_threshold_ms = 5000
error_rate_threshold     = 5

# --- Asincrono
pubsub_topics = {
  pedidos-eventos = {
    path                  = "/events/pedidos"
    ack_deadline_seconds  = 60
    max_delivery_attempts = 5
  }
  integracion-salida = {
    path                  = "/events/integracion"
    ack_deadline_seconds  = 120
    max_delivery_attempts = 5
  }
  notificaciones = {
    path                 = "/events/notificaciones"
    ack_deadline_seconds = 30
  }
}

# --- Batch. En dev solo bajo demanda (schedule = null): nada se dispara solo.
batch_jobs = {
  # Migraciones de esquema. Siempre bajo demanda (schedule = null): las ejecuta
  # el pipeline antes de desplegar una revision. Correrlas como job y no desde
  # el runner de CI es lo que permite que la BBDD siga sin acceso publico.
  migraciones = {
    description     = "Migraciones de esquema de la base de datos"
    args            = ["node", "jobs/migrate.js"]
    schedule        = null
    cpu             = "1"
    memory          = "1Gi"
    max_retries     = 0
    timeout_seconds = 1800
  }
  conciliacion-pedidos = {
    description     = "Conciliacion diaria de pedidos con proveedores"
    args            = ["node", "jobs/conciliacion.js"]
    schedule        = null
    cpu             = "1"
    memory          = "1Gi"
    timeout_seconds = 1800
  }
  export-proveedores = {
    description     = "Exportacion de catalogo de proveedores a fichero"
    args            = ["node", "jobs/export-proveedores.js"]
    schedule        = null
    timeout_seconds = 900
  }
  backup-logico-bbdd = {
    description     = "pg_dump a Cloud Storage, complementario a los backups gestionados"
    args            = ["node", "jobs/backup-logico.js"]
    schedule        = null
    memory          = "2Gi"
    timeout_seconds = 3600
  }
}

time_zone = "Europe/Madrid"

# --- Estandar de la organizacion ajustado para este ambiente -------------
# Los cuatro primeros valores vivian como condicionales sobre el nombre del
# ambiente dentro del codigo; aqui son explicitos y auditables.
vpc_flow_sampling             = 0.1
runtime_deletion_protection   = false # dev se destruye y reconstruye a voluntad
registry_immutable_tags       = false
registry_keep_recent_versions = 5
registry_cleanup_dry_run      = false
exports_retention_days        = 7
db_backup_retention_days      = 7
frontend_keep_versions        = 3
db_version                    = "POSTGRES_16"
db_edition                    = "ENTERPRISE"
db_cpu_alert_threshold        = 0.9 # umbral laxo: en dev un pico no es noticia
db_disk_alert_threshold       = 0.9
enable_adaptive_protection    = false
rate_limit_interval_sec       = 60
uptime_check_regions          = ["EUROPE"] # sin dominio no hay check; valor para cuando lo haya
app_health_path               = "/healthz"
app_container_port            = 8080
secret_version                = "latest"

# ---------------------------------------------------------------------------
# CI/CD: federacion de identidad
#
# wif_pool_name es la salida `workload_identity_pool` del bootstrap de ESTE
# ambiente. Sin el, GitHub Actions no puede impersonar la SA de despliegue y
# solo queda operativo el pipeline de Cloud Build.
# ---------------------------------------------------------------------------
wif_pool_name     = "" # SUSTITUIR por la salida del bootstrap
github_repository = "" # SUSTITUIR por owner/repo
protected_branch  = "main"
