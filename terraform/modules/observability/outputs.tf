output "log_bucket_id" {
  description = "Bucket central de logs del ambiente."
  value       = google_logging_project_bucket_config.central.bucket_id
}

output "notification_channel_ids" {
  description = "Canales a los que se envian las alertas."
  value       = local.notification_channels
}

output "dashboard_id" {
  description = "Dashboard de estado de los cuatro planos de la plataforma."
  value       = google_monitoring_dashboard.main.id
}

output "bigquery_logs_dataset" {
  description = "Dataset de analitica de logs. null si el sink a BigQuery esta desactivado."
  value       = var.enable_bigquery_sink ? google_bigquery_dataset.logs[0].dataset_id : null
}

output "uptime_check_id" {
  description = "Identificador del uptime check, necesario para filtrar su metrica en la alerta. null si no hay dominio."
  value       = var.uptime_check_host == null ? null : google_monitoring_uptime_check_config.public[0].uptime_check_id
}
