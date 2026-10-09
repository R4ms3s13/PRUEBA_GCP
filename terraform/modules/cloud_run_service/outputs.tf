output "name" {
  description = "Nombre del servicio desplegado."
  value       = google_cloud_run_v2_service.this.name
}
output "id" {
  description = "Identificador completo del servicio."
  value       = google_cloud_run_v2_service.this.id
}

output "uri" {
  description = "URL run.app. Con ingress restringido no es accesible desde Internet."
  value       = google_cloud_run_v2_service.this.uri
}

output "location" {
  description = "Region en la que se ha desplegado el servicio."
  value       = google_cloud_run_v2_service.this.location
}
