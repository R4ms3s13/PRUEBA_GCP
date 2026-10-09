# ---------------------------------------------------------------------------
# Modulo raiz de la plataforma. Cablea los modulos y concentra las decisiones
# que dependen del ambiente.
# ---------------------------------------------------------------------------

data "google_project" "this" {
  project_id = var.project_id
}

locals {
  name_prefix = coalesce(var.name_prefix, "prov-${var.env}")

  labels = merge(
    {
      aplicacion = var.app_name
      ambiente   = var.env
      gestion    = "terraform"
    },
    var.extra_labels
  )

  # Etiquetas de red derivadas del prefijo, no escritas a mano: asi no pueden
  # divergir del nombre de los recursos a los que acompanan.
  network_tags = {
    api    = ["${local.name_prefix}-api"]
    worker = ["${local.name_prefix}-worker"]
    batch  = ["${local.name_prefix}-batch"]
  }

  # Principal de CI/CD autorizado a impersonar la SA de despliegue. Mismo
  # criterio que el bootstrap aplica a la SA de Terraform: en prod se exige
  # ademas que el workflow venga de la rama protegida, porque ahi el alcance de
  # un despliegue indebido no se puede deshacer con un `terraform destroy`.
  #
  # Vacio si no se pasa el pool: entonces no se crea el binding y solo se puede
  # desplegar con Cloud Build, que usa la SA directamente sin federar.
  deployer_wif_principal = var.wif_pool_name == "" ? "" : (
    var.env == "prod"
    ? "principalSet://iam.googleapis.com/${var.wif_pool_name}/attribute.ref/refs/heads/${var.protected_branch}"
    : "principalSet://iam.googleapis.com/${var.wif_pool_name}/attribute.repository/${var.github_repository}"
  )
}

# NOTA: image_base NO se define aqui. Se expone a traves de module.registry,
# que es quien conoce el nombre real del repositorio. Tenerlo en dos sitios
# significaba que cambiar repository_id dejaba la otra copia obsoleta sin que
# nada fallara.

# ---------------------------------------------------------------------------
# APIs necesarias. Se habilitan desde Terraform para que un proyecto nuevo sea
# reproducible sin pasos manuales.
# ---------------------------------------------------------------------------
resource "google_project_service" "apis" {
  for_each = toset(var.project_services)

  project = var.project_id
  service = each.value

  # No se deshabilitan al destruir: otro recurso del proyecto podria usarlas.
  disable_on_destroy         = false
  disable_dependent_services = false
}

# ---------------------------------------------------------------------------
# Red
# ---------------------------------------------------------------------------
module "network" {
  source = "../modules/network"

  project_id           = var.project_id
  env                  = var.env
  region               = var.region
  name_prefix          = local.name_prefix
  subnet_app_cidr      = var.subnet_app_cidr
  subnet_internal_cidr = var.subnet_internal_cidr
  psa_cidr             = var.psa_cidr
  psa_prefix_length    = var.psa_prefix_length
  enable_nat           = var.enable_nat
  nat_min_ports_per_vm = var.nat_min_ports_per_vm
  flow_sampling        = var.vpc_flow_sampling

  depends_on = [google_project_service.apis]
}

# ---------------------------------------------------------------------------
# Registro de imagenes
# ---------------------------------------------------------------------------
module "registry" {
  source = "../modules/registry"

  project_id           = var.project_id
  env                  = var.env
  region               = var.region
  repository_id        = var.registry_repository_id
  immutable_tags       = var.registry_immutable_tags
  keep_recent_versions = var.registry_keep_recent_versions
  tracked_images       = var.registry_tracked_images
  untagged_ttl_days    = var.registry_untagged_ttl_days
  cleanup_dry_run      = var.registry_cleanup_dry_run

  depends_on = [google_project_service.apis]
}

# ---------------------------------------------------------------------------
# Almacenamiento de objetos
# ---------------------------------------------------------------------------
module "storage" {
  source = "../modules/storage"

  project_id                        = var.project_id
  project_number                    = data.google_project.this.number
  env                               = var.env
  name_prefix                       = local.name_prefix
  location                          = var.storage_location
  backup_location                   = var.storage_backup_location
  cors_origins                      = length(var.domains) > 0 ? [for d in var.domains : "https://${d}"] : ["*"]
  uploads_retention_days            = var.uploads_retention_days
  uploads_storage_class_transitions = var.uploads_storage_class_transitions
  exports_retention_days            = var.exports_retention_days
  db_backup_retention_days          = var.db_backup_retention_days
  frontend_keep_versions            = var.frontend_keep_versions
  force_destroy                     = var.force_destroy_buckets

  depends_on = [google_project_service.apis]
}

# ---------------------------------------------------------------------------
# Identidades y permisos
# ---------------------------------------------------------------------------
module "iam" {
  source = "../modules/iam"

  project_id             = var.project_id
  env                    = var.env
  region                 = var.region
  name_prefix            = local.name_prefix
  uploads_bucket_name    = module.storage.uploads_bucket_name
  exports_bucket_name    = module.storage.exports_bucket_name
  db_backups_bucket_name = module.storage.db_backups_bucket_name
  frontend_bucket_name   = module.storage.frontend_bucket_name
  registry_repository_id = module.registry.repository_id
  deployer_wif_principal = local.deployer_wif_principal
}

# ---------------------------------------------------------------------------
# Base de datos relacional
# ---------------------------------------------------------------------------
module "database" {
  source = "../modules/database"

  project_id  = var.project_id
  env         = var.env
  region      = var.region
  name_prefix = local.name_prefix
  network_id  = module.network.network_id

  database_version         = var.db_version
  edition                  = var.db_edition
  tier                     = var.db_tier
  highly_available         = var.db_highly_available
  disk_size_gb             = var.db_disk_size_gb
  disk_autoresize_limit_gb = var.db_disk_autoresize_limit_gb
  max_connections          = var.db_max_connections
  database_name            = var.db_name
  app_db_user              = var.db_app_user
  collation                = var.db_collation
  log_min_duration_ms      = var.db_log_min_duration_ms
  extra_database_flags     = var.db_extra_flags
  password_rotation_token  = var.db_password_rotation_token

  point_in_time_recovery         = var.db_point_in_time_recovery
  retained_backups               = var.db_retained_backups
  transaction_log_retention_days = var.db_transaction_log_retention_days
  backup_location                = coalesce(var.db_backup_location, var.region)
  backup_start_time              = var.db_backup_start_time
  maintenance_day                = var.db_maintenance_day
  maintenance_hour               = var.db_maintenance_hour
  deletion_protection            = var.db_deletion_protection

  # Autenticacion IAM: los runtimes se conectan con su identidad, sin contrasena.
  iam_db_users = {
    api    = module.iam.api_sa_email
    worker = module.iam.worker_sa_email
    batch  = module.iam.batch_sa_email
  }

  # Solo estas identidades pueden leer los secretos de la BBDD.
  secret_accessor_members = {
    api    = module.iam.api_sa_email
    worker = module.iam.worker_sa_email
    batch  = module.iam.batch_sa_email
  }

  labels = local.labels

  # El peering de Private Service Access debe existir antes que una instancia
  # con IP privada.
  depends_on = [module.network]
}

# ---------------------------------------------------------------------------
# Runtime: API backend
# ---------------------------------------------------------------------------
module "api" {
  source = "../modules/cloud_run_service"

  project_id            = var.project_id
  region                = var.region
  service_name          = "${local.name_prefix}-api"
  image                 = var.api_image
  service_account_email = module.iam.api_sa_email

  # Subnet del componente expuesto: la que NO tiene Cloud NAT. El API atiende
  # peticiones de Internet y, a cambio, no puede iniciar conexiones hacia
  # Internet. Las llamadas a terceros son trabajo del worker y de los jobs.
  network_id   = module.network.network_id
  subnet_id    = module.network.subnet_app_id
  network_tags = local.network_tags.api
  vpc_egress   = var.runtime_vpc_egress

  # Solo alcanzable a traves del balanceador.
  ingress = var.api_ingress

  cpu                     = var.api_cpu
  memory                  = var.api_memory
  min_instances           = var.api_min_instances
  max_instances           = var.api_max_instances
  max_concurrency         = var.api_max_concurrency
  request_timeout_seconds = var.api_request_timeout_seconds

  # Contrato con el equipo de desarrollo: puerto y ruta de salud.
  container_port         = var.app_container_port
  health_path            = var.app_health_path
  startup_probe_delay    = var.startup_probe_delay
  startup_probe_failures = var.startup_probe_failures
  tmp_size_limit         = var.api_tmp_size_limit

  env_vars = {
    NODE_ENV            = var.env == "prod" ? "production" : var.env
    APP_ENV             = var.env
    GCP_PROJECT_ID      = var.project_id
    DB_SOCKET_PATH      = "/cloudsql/${module.database.connection_name}"
    DB_HOST             = module.database.private_ip_address
    DB_NAME             = module.database.database_name
    DB_IAM_USER         = trimsuffix(module.iam.api_sa_email, ".gserviceaccount.com")
    DB_MAX_POOL         = tostring(floor(var.db_max_connections / (var.api_max_instances + var.worker_max_instances)))
    UPLOADS_BUCKET      = module.storage.uploads_bucket_name
    EXPORTS_BUCKET      = module.storage.exports_bucket_name
    PUBSUB_TOPIC_PREFIX = "${local.name_prefix}-"
    LOG_LEVEL           = var.env == "prod" ? "info" : "debug"
  }

  # La cadena de conexion completa solo para migraciones o fallback; la ruta
  # normal es autenticacion IAM.
  secret_env_vars = {
    DATABASE_URL = {
      secret_id = module.database.db_url_secret_id
      version   = var.secret_version
    }
  }

  volume_mounts = { tmp = var.app_tmp_mount_path }

  labels              = local.labels
  deletion_protection = var.runtime_deletion_protection
}

# ---------------------------------------------------------------------------
# Runtime: worker de procesos asincronos
# ---------------------------------------------------------------------------
module "worker" {
  source = "../modules/cloud_run_service"

  project_id            = var.project_id
  region                = var.region
  service_name          = "${local.name_prefix}-worker"
  image                 = var.worker_image
  service_account_email = module.iam.worker_sa_email

  # Subnet interna: el worker intercambia informacion con aplicaciones de
  # terceros, asi que necesita la salida por Cloud NAT con IP fija.
  network_id   = module.network.network_id
  subnet_id    = module.network.subnet_internal_id
  network_tags = local.network_tags.worker
  vpc_egress   = var.runtime_vpc_egress

  # El worker no se publica en el balanceador: su unico invocador autorizado es
  # la identidad con la que Pub/Sub firma el push (ver invoker_members abajo).
  # El valor es configurable porque, si las peticiones de push de Pub/Sub no
  # llegasen a contar como trafico interno en esta configuracion, el ajuste es
  # pasar a INGRESS_TRAFFIC_ALL: la autorizacion no se debilita, porque sigue
  # exigiendo el token OIDC y el binding run.invoker.
  ingress = var.worker_ingress

  cpu             = var.worker_cpu
  memory          = var.worker_memory
  min_instances   = var.worker_min_instances
  max_instances   = var.worker_max_instances
  max_concurrency = var.worker_max_concurrency

  # Procesar un mensaje puede requerir trabajo despues de responder el ack, de
  # modo que la CPU no se libera al terminar la request.
  cpu_idle = var.worker_cpu_idle

  # Un evento de intercambio con terceros puede tardar: mas margen que el API.
  request_timeout_seconds = var.worker_request_timeout_seconds

  container_port         = var.app_container_port
  health_path            = var.app_health_path
  startup_probe_delay    = var.startup_probe_delay
  startup_probe_failures = var.startup_probe_failures
  tmp_size_limit         = var.worker_tmp_size_limit

  env_vars = {
    NODE_ENV       = var.env == "prod" ? "production" : var.env
    APP_ENV        = var.env
    GCP_PROJECT_ID = var.project_id
    DB_HOST        = module.database.private_ip_address
    DB_NAME        = module.database.database_name
    DB_IAM_USER    = trimsuffix(module.iam.worker_sa_email, ".gserviceaccount.com")
    UPLOADS_BUCKET = module.storage.uploads_bucket_name
    LOG_LEVEL      = var.env == "prod" ? "info" : "debug"
  }

  secret_env_vars = {
    DATABASE_URL = {
      secret_id = module.database.db_url_secret_id
      version   = var.secret_version
    }
  }

  # Unico invocador autorizado: la identidad con la que Pub/Sub firma el push.
  invoker_members = {
    pubsub = "serviceAccount:${module.iam.pubsub_sa_email}"
  }

  volume_mounts = { tmp = var.app_tmp_mount_path }

  labels = local.labels

  # Misma proteccion que el API. Era una inconsistencia que en prod el worker
  # se pudiera borrar desde Terraform y el API no.
  deletion_protection = var.runtime_deletion_protection
}

# ---------------------------------------------------------------------------
# Mensajeria asincrona
# ---------------------------------------------------------------------------
module "async" {
  source = "../modules/async"

  project_id     = var.project_id
  project_number = data.google_project.this.number
  env            = var.env
  name_prefix    = local.name_prefix

  worker_url             = module.worker.uri
  topics                 = var.pubsub_topics
  dlq_retention_duration = var.dlq_retention_duration

  publisher_service_account_email      = module.iam.api_sa_email
  pubsub_invoker_service_account_email = module.iam.pubsub_sa_email
  pubsub_invoker_service_account_id    = module.iam.pubsub_sa_id

  labels = local.labels
}

# ---------------------------------------------------------------------------
# Procesamiento batch
# ---------------------------------------------------------------------------
module "batch" {
  source = "../modules/cloud_run_job"

  project_id  = var.project_id
  region      = var.region
  name_prefix = local.name_prefix
  image       = var.batch_image

  service_account_email           = module.iam.batch_sa_email
  scheduler_service_account_email = module.iam.scheduler_sa_email
  api_service_account_email       = module.iam.api_sa_email

  # Subnet interna: los jobs de intercambio salen por Cloud NAT.
  network_id   = module.network.network_id
  subnet_id    = module.network.subnet_internal_id
  network_tags = local.network_tags.batch

  jobs      = var.batch_jobs
  time_zone = var.time_zone

  common_env_vars = {
    APP_ENV          = var.env
    GCP_PROJECT_ID   = var.project_id
    DB_HOST          = module.database.private_ip_address
    DB_NAME          = module.database.database_name
    DB_IAM_USER      = trimsuffix(module.iam.batch_sa_email, ".gserviceaccount.com")
    EXPORTS_BUCKET   = module.storage.exports_bucket_name
    UPLOADS_BUCKET   = module.storage.uploads_bucket_name
    DB_BACKUP_BUCKET = module.storage.db_backups_bucket_name
  }

  secret_env_vars = {
    DATABASE_URL = {
      secret_id = module.database.db_url_secret_id
      version   = var.secret_version
    }
  }

  labels = local.labels
}

# ---------------------------------------------------------------------------
# Punto de entrada publico
# ---------------------------------------------------------------------------
module "frontend_lb" {
  source = "../modules/frontend_lb"

  project_id  = var.project_id
  env         = var.env
  region      = var.region
  name_prefix = local.name_prefix

  frontend_bucket_name = module.storage.frontend_bucket_name
  api_service_name     = module.api.name

  domains      = var.domains
  enable_https = var.enable_https

  # Contrato con la aplicacion: que rutas van al API y cual es la de salud.
  health_path       = var.app_health_path
  api_path_patterns = var.app_api_path_patterns
  api_timeout_sec   = var.api_request_timeout_seconds

  cdn_client_ttl        = var.cdn_ttls.client
  cdn_default_ttl       = var.cdn_ttls.default
  cdn_max_ttl           = var.cdn_ttls.max
  cdn_serve_while_stale = var.cdn_ttls.stale
  cdn_negative_ttl      = var.cdn_ttls.negative

  enable_cloud_armor         = var.enable_cloud_armor
  waf_preview_mode           = var.waf_preview_mode
  rate_limit_requests        = var.rate_limit_requests
  rate_limit_interval_sec    = var.rate_limit_interval_sec
  enable_adaptive_protection = var.enable_adaptive_protection
}

# ---------------------------------------------------------------------------
# Observabilidad
# ---------------------------------------------------------------------------
module "observability" {
  source = "../modules/observability"

  project_id  = var.project_id
  env         = var.env
  region      = var.region
  name_prefix = local.name_prefix

  api_service_name      = module.api.name
  api_max_instances     = var.api_max_instances
  db_instance_name      = module.database.instance_name
  dlq_subscription_name = module.async.dlq_subscription_name

  # La ruta de salud se usa en el uptime check y en la exclusion de logs: una
  # sola fuente, compartida con el balanceador y con los runtimes.
  health_path = var.app_health_path

  alert_emails         = var.alert_emails
  uptime_check_host    = length(var.domains) > 0 ? var.domains[0] : null
  uptime_check_regions = var.uptime_check_regions

  log_retention_days             = var.log_retention_days
  log_index_fields               = var.log_index_fields
  enable_bigquery_sink           = var.enable_bigquery_sink
  bigquery_location              = var.bigquery_location
  bigquery_table_expiration_days = var.bigquery_table_expiration_days
  latency_p95_threshold_ms       = var.latency_p95_threshold_ms
  error_rate_threshold           = var.error_rate_threshold
  db_cpu_threshold               = var.db_cpu_alert_threshold
  db_disk_threshold              = var.db_disk_alert_threshold

  labels = local.labels
}
