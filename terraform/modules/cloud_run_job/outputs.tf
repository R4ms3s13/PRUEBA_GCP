output "job_names" {
  description = "Nombre de cada job creado, indexado por clave logica."
  value       = { for k, j in google_cloud_run_v2_job.this : k => j.name }
}

output "job_ids" {
  description = "Identificador completo de cada job."
  value       = { for k, j in google_cloud_run_v2_job.this : k => j.id }
}

output "scheduled_jobs" {
  description = "Expresion cron de cada job programado, para verificar la planificacion de un vistazo."
  value       = { for k, s in google_cloud_scheduler_job.schedule : k => s.schedule }
}
