# Declaracion de las variables del ambiente. Identica en dev, qa y prod: los
# valores los aporta terraform.tfvars.

variable "project_id" { type = string }
variable "region" { type = string }

variable "subnet_app_cidr" { type = string }
variable "subnet_internal_cidr" { type = string }
variable "psa_cidr" { type = string }
variable "enable_nat" { type = bool }

variable "api_image" { type = string }
variable "worker_image" { type = string }
variable "batch_image" { type = string }

variable "api_cpu" { type = string }
variable "api_memory" { type = string }
variable "api_min_instances" { type = number }
variable "api_max_instances" { type = number }
variable "api_max_concurrency" { type = number }

variable "worker_ingress" { type = string }
variable "worker_cpu" { type = string }
variable "worker_memory" { type = string }
variable "worker_min_instances" { type = number }
variable "worker_max_instances" { type = number }

variable "db_tier" { type = string }
variable "db_highly_available" { type = bool }
variable "db_disk_size_gb" { type = number }
variable "db_max_connections" { type = number }
variable "db_point_in_time_recovery" { type = bool }
variable "db_retained_backups" { type = number }
variable "db_transaction_log_retention_days" { type = number }
variable "db_deletion_protection" { type = bool }

variable "db_backup_location" {
  type    = string
  default = null
}

variable "storage_location" { type = string }
variable "storage_backup_location" { type = string }
variable "uploads_retention_days" { type = number }
variable "force_destroy_buckets" { type = bool }

variable "domains" { type = list(string) }
variable "enable_https" { type = bool }
variable "enable_cloud_armor" { type = bool }
variable "waf_preview_mode" { type = bool }
variable "rate_limit_requests" { type = number }

variable "alert_emails" { type = map(string) }
variable "log_retention_days" { type = number }
variable "enable_bigquery_sink" { type = bool }
variable "latency_p95_threshold_ms" { type = number }
variable "error_rate_threshold" { type = number }

variable "batch_jobs" {
  type = map(object({
    description     = string
    command         = optional(list(string))
    args            = optional(list(string))
    schedule        = optional(string)
    cpu             = optional(string, "1")
    memory          = optional(string, "1Gi")
    task_count      = optional(number, 1)
    parallelism     = optional(number, 1)
    max_retries     = optional(number, 2)
    timeout_seconds = optional(number, 3600)
    vpc_egress      = optional(string, "ALL_TRAFFIC")
    env_vars        = optional(map(string), {})
  }))
}

variable "pubsub_topics" {
  type = map(object({
    path                  = string
    ack_deadline_seconds  = optional(number, 60)
    retention_duration    = optional(string, "604800s")
    max_delivery_attempts = optional(number, 5)
    ordered               = optional(bool, false)
    schema_id             = optional(string)
  }))
}

variable "time_zone" { type = string }

# Estandar de la organizacion que este ambiente ajusta explicitamente.
# Los cuatro primeros eran condicionales sobre el nombre del ambiente dentro
# del modulo raiz; ahora son configuracion, que es donde deben estar.
variable "vpc_flow_sampling" { type = number }
variable "runtime_deletion_protection" { type = bool }
variable "registry_immutable_tags" { type = bool }
variable "registry_keep_recent_versions" { type = number }
variable "registry_cleanup_dry_run" { type = bool }
variable "exports_retention_days" { type = number }
variable "db_backup_retention_days" { type = number }
variable "frontend_keep_versions" { type = number }
variable "db_version" { type = string }
variable "db_edition" { type = string }
variable "db_cpu_alert_threshold" { type = number }
variable "db_disk_alert_threshold" { type = number }
variable "enable_adaptive_protection" { type = bool }
variable "rate_limit_interval_sec" { type = number }
variable "uptime_check_regions" { type = list(string) }
variable "app_health_path" { type = string }
variable "app_container_port" { type = number }
variable "secret_version" { type = string }

variable "wif_pool_name" { type = string }
variable "github_repository" { type = string }
variable "protected_branch" { type = string }
