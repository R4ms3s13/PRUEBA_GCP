output "service_account_emails" {
  description = "Email de cada service account, indexado por componente."
  value       = { for k, sa in google_service_account.sa : k => sa.email }
}

output "service_account_ids" {
  description = "Identificador completo de cada service account, indexado por componente."
  value       = { for k, sa in google_service_account.sa : k => sa.name }
}

output "api_sa_email" {
  description = "Identidad del API backend."
  value       = google_service_account.sa["api"].email
}
output "worker_sa_email" {
  description = "Identidad del worker de procesos asincronos."
  value       = google_service_account.sa["worker"].email
}
output "batch_sa_email" {
  description = "Identidad de las ejecuciones batch."
  value       = google_service_account.sa["batch"].email
}
output "scheduler_sa_email" {
  description = "Identidad con la que Cloud Scheduler invoca los jobs."
  value       = google_service_account.sa["scheduler"].email
}
output "pubsub_sa_email" {
  description = "Identidad con la que Pub/Sub firma el token OIDC hacia el worker."
  value       = google_service_account.sa["pubsub"].email
}
output "pubsub_sa_id" {
  description = "Identificador completo de la service account de Pub/Sub, para el binding de tokenCreator."
  value       = google_service_account.sa["pubsub"].name
}
output "deployer_sa_email" {
  description = "Identidad que debe impersonar el pipeline de CI/CD."
  value       = google_service_account.sa["deployer"].email
}
