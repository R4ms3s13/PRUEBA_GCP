# ===========================================================================
# PROD - configuracion del ambiente
#
# Dimensionado para la carga declarada en el enunciado:
#   20.000 usuarios registrados
#    2.000 usuarios concurrentes
#   100.000-500.000 operaciones/dia
#   crecimiento del 30% anual
#
# Como se traduce eso:
#   500.000 op/dia concentradas en ~10 h laborables => ~14 req/s de media y
#   picos estimados en 3-4x => ~50 req/s. Con 80 requests concurrentes por
#   instancia y respuestas de ~150 ms, una instancia absorbe del orden de
#   cientos de req/s, de modo que el techo de 30 instancias deja un margen
#   amplio; lo que realmente limita es el pool de conexiones a PostgreSQL, y de
#   ahi que max_instances y db_max_connections se fijen juntos.
#
# Decisiones propias de prod: alta disponibilidad regional, PITR, backups en
# otra region, retenciones largas, proteccion de borrado y WAF bloqueando.
# ===========================================================================

project_id = "proveedores-prod"
region     = "europe-west1"

subnet_app_cidr      = "10.30.0.0/22" # API: sin Cloud NAT, sin salida a Internet
subnet_internal_cidr = "10.30.4.0/22" # worker y jobs: salida por NAT con IP fija
psa_cidr             = "10.30.16.0"
enable_nat           = true

api_image    = "us-docker.pkg.dev/cloudrun/container/hello"
worker_image = "us-docker.pkg.dev/cloudrun/container/hello"
batch_image  = "us-docker.pkg.dev/cloudrun/container/hello"

# --- Runtime.
#     min_instances = 2 cumple dos cosas a la vez: elimina el arranque en frio
#     y reparte las instancias calientes entre zonas, de modo que la perdida de
#     una zona no deja al servicio sin capacidad inmediata.
api_cpu             = "2"
api_memory          = "2Gi"
api_min_instances   = 2
api_max_instances   = 30
api_max_concurrency = 80

# Ingress del worker. Si las entregas push de Pub/Sub no contasen como
# trafico interno, pasar a INGRESS_TRAFFIC_ALL: la autorizacion no se
# debilita (sigue exigiendo OIDC y run.invoker de la SA de Pub/Sub).
worker_ingress       = "INGRESS_TRAFFIC_INTERNAL_ONLY"
worker_cpu           = "1"
worker_memory        = "2Gi"
worker_min_instances = 1
worker_max_instances = 15

# --- Base de datos.
#     availability_type REGIONAL mantiene un standby sincrono en otra zona con
#     failover automatico: es la medida que elimina el punto unico de falla del
#     plano de datos. Duplica el coste de computo de la instancia, y es el
#     gasto que mejor se justifica de todo el presupuesto.
db_tier                           = "db-custom-4-15360"
db_highly_available               = true
db_disk_size_gb                   = 100
db_max_connections                = 400
db_point_in_time_recovery         = true
db_retained_backups               = 30
db_transaction_log_retention_days = 7
db_deletion_protection            = true
db_backup_location                = "eu" # multi-region: sobrevive a la perdida de europe-west1

# --- Almacenamiento. Multi-region para los datos de negocio; backups en otra
#     region para que un incidente regional no se lleve origen y copia.
storage_location        = "eu"
storage_backup_location = "europe-west4"
uploads_retention_days  = 2555 # 7 anos: documentos mercantiles de pedidos
force_destroy_buckets   = false

# --- Entrada publica.
domains             = ["proveedores.example.com", "www.proveedores.example.com"]
enable_https        = true
enable_cloud_armor  = true
waf_preview_mode    = false
rate_limit_requests = 300

# --- Observabilidad. Retencion larga y sink analitico activo.
alert_emails = {
  guardia = "guardia@example.com"
  equipo  = "plataforma@example.com"
}
log_retention_days       = 90
enable_bigquery_sink     = true
latency_p95_threshold_ms = 1500
error_rate_threshold     = 1

pubsub_topics = {
  pedidos-eventos = {
    path                  = "/events/pedidos"
    ack_deadline_seconds  = 60
    max_delivery_attempts = 5
    # Las transiciones de estado de un mismo pedido deben procesarse en orden.
    ordered = true
  }
  integracion-salida = {
    path                  = "/events/integracion"
    ack_deadline_seconds  = 300
    max_delivery_attempts = 10 # sistemas de terceros: mas tolerancia a caidas suyas
    retention_duration    = "604800s"
  }
  notificaciones = {
    path                  = "/events/notificaciones"
    ack_deadline_seconds  = 30
    max_delivery_attempts = 3 # una notificacion vieja ya no sirve: al DLQ antes
  }
}

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
    cpu             = "2"
    memory          = "4Gi"
    max_retries     = 2
    timeout_seconds = 3600
  }
  export-proveedores = {
    description     = "Exportacion de catalogo de proveedores a fichero"
    args            = ["node", "jobs/export-proveedores.js"]
    schedule        = "0 4 * * 1"
    cpu             = "1"
    memory          = "2Gi"
    timeout_seconds = 1800
  }
  backup-logico-bbdd = {
    description = "pg_dump a Cloud Storage, complementario a los backups gestionados"
    args        = ["node", "jobs/backup-logico.js"]
    schedule    = "0 3 * * *"
    cpu         = "2"
    memory      = "4Gi"
    # Sin reintentos: si falla, se quiere ver la alerta, no un segundo dump.
    max_retries     = 0
    timeout_seconds = 7200
  }
  intercambio-terceros = {
    description = "Envio de ficheros de intercambio a aplicaciones externas"
    args        = ["node", "jobs/intercambio.js"]
    schedule    = "0 */4 * * *"
    cpu         = "1"
    memory      = "1Gi"
    # Necesita salir a Internet: su trafico pasa por Cloud NAT con IP fija.
    vpc_egress      = "ALL_TRAFFIC"
    timeout_seconds = 1800
  }
}

time_zone = "Europe/Madrid"

# --- Estandar de la organizacion ajustado para este ambiente -------------
# Los cuatro primeros valores vivian como condicionales sobre el nombre del
# ambiente dentro del codigo; aqui son explicitos y auditables.
vpc_flow_sampling             = 0.5  # mas muestreo: hace falta para investigar un incidente
runtime_deletion_protection   = true # ningun servicio de prod se borra desde Terraform
registry_immutable_tags       = true # una etiqueta publicada no puede reescribirse
registry_keep_recent_versions = 20
registry_cleanup_dry_run      = false
exports_retention_days        = 90
db_backup_retention_days      = 90
frontend_keep_versions        = 10
db_version                    = "POSTGRES_16"
db_edition                    = "ENTERPRISE"
db_cpu_alert_threshold        = 0.8
db_disk_alert_threshold       = 0.85
enable_adaptive_protection    = false # requiere Cloud Armor Enterprise; no contratado
rate_limit_interval_sec       = 60
uptime_check_regions          = ["EUROPE", "USA", "SOUTH_AMERICA"] # tres continentes: un problema de red local no es una caida
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
