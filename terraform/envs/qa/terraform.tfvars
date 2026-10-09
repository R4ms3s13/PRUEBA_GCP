# ===========================================================================
# QA - configuracion del ambiente
#
# Criterio: replica fiel de prod en TOPOLOGIA, reducida en capacidad. Es el
# ambiente donde una prueba de carga o un ensayo de recuperacion tienen que
# comportarse como produccion, asi que aqui si hay PITR, Cloud Armor y TLS.
# Lo que no hay es alta disponibilidad ni sobredimensionado.
# ===========================================================================

project_id = "proveedores-qa"
region     = "europe-west1"

subnet_app_cidr      = "10.20.0.0/22" # API: sin Cloud NAT, sin salida a Internet
subnet_internal_cidr = "10.20.4.0/22" # worker y jobs: salida por NAT con IP fija
psa_cidr             = "10.20.16.0"
enable_nat           = true

api_image    = "us-docker.pkg.dev/cloudrun/container/hello"
worker_image = "us-docker.pkg.dev/cloudrun/container/hello"
batch_image  = "us-docker.pkg.dev/cloudrun/container/hello"

# --- Runtime. 1 instancia caliente para que las medidas de latencia en las
#     pruebas de carga no esten contaminadas por arranques en frio.
api_cpu             = "1"
api_memory          = "1Gi"
api_min_instances   = 1
api_max_instances   = 10
api_max_concurrency = 80

# Ingress del worker. Si las entregas push de Pub/Sub no contasen como
# trafico interno, pasar a INGRESS_TRAFFIC_ALL: la autorizacion no se
# debilita (sigue exigiendo OIDC y run.invoker de la SA de Pub/Sub).
worker_ingress       = "INGRESS_TRAFFIC_INTERNAL_ONLY"
worker_cpu           = "1"
worker_memory        = "1Gi"
worker_min_instances = 0
worker_max_instances = 5

# --- Base de datos. Sin HA (es el ahorro grande), pero con PITR para poder
#     ensayar el procedimiento de recuperacion antes de necesitarlo en prod.
db_tier                           = "db-custom-2-7680"
db_highly_available               = false
db_disk_size_gb                   = 50
db_max_connections                = 150
db_point_in_time_recovery         = true
db_retained_backups               = 7
db_transaction_log_retention_days = 3
db_deletion_protection            = false

storage_location        = "europe-west1"
storage_backup_location = "europe-west4"
uploads_retention_days  = 0
force_destroy_buckets   = true

# --- Entrada publica. Con dominio y TLS: valida la cadena completa antes de prod.
domains             = ["qa.proveedores.example.com"]
enable_https        = true
enable_cloud_armor  = true
waf_preview_mode    = false # aqui SI se bloquea: es donde se detectan los falsos positivos
rate_limit_requests = 600

alert_emails = {
  qa = "qa-alertas@example.com"
}
log_retention_days       = 14
enable_bigquery_sink     = false
latency_p95_threshold_ms = 3000
error_rate_threshold     = 2

pubsub_topics = {
  pedidos-eventos = {
    path                  = "/events/pedidos"
    ack_deadline_seconds  = 60
    max_delivery_attempts = 5
    ordered               = true
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

# --- Batch. Programados con la misma cadencia que prod, para que un fallo de
#     planificacion aparezca aqui primero.
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
    schedule        = "30 2 * * *"
    cpu             = "1"
    memory          = "1Gi"
    timeout_seconds = 1800
  }
  export-proveedores = {
    description     = "Exportacion de catalogo de proveedores a fichero"
    args            = ["node", "jobs/export-proveedores.js"]
    schedule        = "0 4 * * 1"
    timeout_seconds = 900
  }
  backup-logico-bbdd = {
    description     = "pg_dump a Cloud Storage, complementario a los backups gestionados"
    args            = ["node", "jobs/backup-logico.js"]
    schedule        = "0 3 * * *"
    memory          = "2Gi"
    timeout_seconds = 3600
  }
}

time_zone = "Europe/Madrid"

# --- Estandar de la organizacion ajustado para este ambiente -------------
# Los cuatro primeros valores vivian como condicionales sobre el nombre del
# ambiente dentro del codigo; aqui son explicitos y auditables.
vpc_flow_sampling             = 0.1
runtime_deletion_protection   = false
registry_immutable_tags       = false
registry_keep_recent_versions = 10 # historico suficiente para reproducir un bug
registry_cleanup_dry_run      = false
exports_retention_days        = 14
db_backup_retention_days      = 14
frontend_keep_versions        = 5
db_version                    = "POSTGRES_16"
db_edition                    = "ENTERPRISE"
db_cpu_alert_threshold        = 0.85
db_disk_alert_threshold       = 0.85
enable_adaptive_protection    = false
rate_limit_interval_sec       = 60
uptime_check_regions          = ["EUROPE"]
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
