output "lb_ip_address" {
  description = "IP global a la que debe apuntar el registro A del dominio."
  value       = google_compute_global_address.lb.address
}

output "url_map_id" {
  description = "Identificador del mapa de URL, necesario para invalidar la cache del CDN."
  value       = google_compute_url_map.main.id
}
output "api_backend_service_id" {
  description = "Backend service que apunta al API mediante serverless NEG."
  value       = google_compute_backend_service.api.id
}
output "frontend_backend_bucket_id" {
  description = "Backend bucket que sirve el build estatico."
  value       = google_compute_backend_bucket.frontend.id
}

output "security_policy_id" {
  description = "Politica de Cloud Armor asociada al backend del API. null si el WAF esta desactivado."
  value       = var.enable_cloud_armor ? google_compute_security_policy.armor[0].id : null
}

output "public_url" {
  description = "URL publica de entrada. Con HTTPS desactivado devuelve la IP del balanceador."
  value       = var.enable_https && length(var.domains) > 0 ? "https://${var.domains[0]}" : "http://${google_compute_global_address.lb.address}"
}
