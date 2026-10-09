output "repository_id" {
  description = "Identificador del repositorio de imagenes."
  value       = google_artifact_registry_repository.docker.repository_id
}
output "repository_name" {
  description = "Nombre completo del recurso de Artifact Registry."
  value       = google_artifact_registry_repository.docker.name
}

output "registry_host" {
  description = "Host Docker al que etiquetar y empujar las imagenes."
  value       = "${var.region}-docker.pkg.dev"
}

output "image_base" {
  description = "Prefijo completo: <base>/<imagen>:<tag>"
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.docker.repository_id}"
}
