output "frontend_bucket_name" {
  description = "Bucket del build estatico del SPA."
  value       = google_storage_bucket.frontend.name
}
output "uploads_bucket_name" {
  description = "Bucket de archivos subidos por los usuarios."
  value       = google_storage_bucket.uploads.name
}
output "exports_bucket_name" {
  description = "Bucket de salidas de los procesos batch."
  value       = google_storage_bucket.exports.name
}
output "db_backups_bucket_name" {
  description = "Bucket de volcados logicos de la base de datos."
  value       = google_storage_bucket.db_backups.name
}

output "frontend_bucket_self_link" {
  description = "Enlace propio del bucket de frontend."
  value       = google_storage_bucket.frontend.self_link
}
