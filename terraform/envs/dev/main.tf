# ---------------------------------------------------------------------------
# Ambiente DEV.
#
# Este fichero es intencionadamente IDENTICO en los tres ambientes salvo el
# valor de "env": toda la diferencia vive en terraform.tfvars. Asi la
# definicion de infraestructura es demostrablemente la misma.
# ---------------------------------------------------------------------------

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }

  # Backend remoto: el state es compartido, versionado y bloqueado. Los valores
  # concretos se pasan con -backend-config desde el pipeline (ver backend.hcl).
  backend "gcs" {}
}

provider "google" {
  project = var.project_id
  region  = var.region

  default_labels = {
    gestion  = "terraform"
    ambiente = "dev"
  }
}

module "plataforma" {
  source = "../../platform"

  project_id = var.project_id
  env        = "dev"
  region     = var.region

  subnet_app_cidr      = var.subnet_app_cidr
  subnet_internal_cidr = var.subnet_internal_cidr
  psa_cidr             = var.psa_cidr
  enable_nat           = var.enable_nat

  api_image    = var.api_image
  worker_image = var.worker_image
  batch_image  = var.batch_image

  api_cpu             = var.api_cpu
  api_memory          = var.api_memory
  api_min_instances   = var.api_min_instances
  api_max_instances   = var.api_max_instances
  api_max_concurrency = var.api_max_concurrency

  worker_ingress       = var.worker_ingress
  worker_cpu           = var.worker_cpu
  worker_memory        = var.worker_memory
  worker_min_instances = var.worker_min_instances
  worker_max_instances = var.worker_max_instances

  db_tier                           = var.db_tier
  db_highly_available               = var.db_highly_available
  db_disk_size_gb                   = var.db_disk_size_gb
  db_max_connections                = var.db_max_connections
  db_point_in_time_recovery         = var.db_point_in_time_recovery
  db_retained_backups               = var.db_retained_backups
  db_transaction_log_retention_days = var.db_transaction_log_retention_days
  db_deletion_protection            = var.db_deletion_protection
  db_backup_location                = var.db_backup_location

  storage_location        = var.storage_location
  storage_backup_location = var.storage_backup_location
  uploads_retention_days  = var.uploads_retention_days
  force_destroy_buckets   = var.force_destroy_buckets

  domains             = var.domains
  enable_https        = var.enable_https
  enable_cloud_armor  = var.enable_cloud_armor
  waf_preview_mode    = var.waf_preview_mode
  rate_limit_requests = var.rate_limit_requests

  alert_emails             = var.alert_emails
  log_retention_days       = var.log_retention_days
  enable_bigquery_sink     = var.enable_bigquery_sink
  latency_p95_threshold_ms = var.latency_p95_threshold_ms
  error_rate_threshold     = var.error_rate_threshold

  # Estandar de la organizacion ajustado por ambiente.
  vpc_flow_sampling             = var.vpc_flow_sampling
  runtime_deletion_protection   = var.runtime_deletion_protection
  registry_immutable_tags       = var.registry_immutable_tags
  registry_keep_recent_versions = var.registry_keep_recent_versions
  registry_cleanup_dry_run      = var.registry_cleanup_dry_run
  exports_retention_days        = var.exports_retention_days
  db_backup_retention_days      = var.db_backup_retention_days
  frontend_keep_versions        = var.frontend_keep_versions
  db_version                    = var.db_version
  db_edition                    = var.db_edition
  db_cpu_alert_threshold        = var.db_cpu_alert_threshold
  db_disk_alert_threshold       = var.db_disk_alert_threshold
  enable_adaptive_protection    = var.enable_adaptive_protection
  rate_limit_interval_sec       = var.rate_limit_interval_sec
  uptime_check_regions          = var.uptime_check_regions
  app_health_path               = var.app_health_path
  app_container_port            = var.app_container_port
  secret_version                = var.secret_version

  batch_jobs    = var.batch_jobs
  pubsub_topics = var.pubsub_topics
  time_zone     = var.time_zone

  # CI/CD: federacion de identidad para la SA de despliegue.
  wif_pool_name     = var.wif_pool_name
  github_repository = var.github_repository
  protected_branch  = var.protected_branch
}
