output "network_id" {
  description = "Identificador de la VPC, para conectar runtimes y publicar la IP privada de Cloud SQL."
  value       = google_compute_network.vpc.id
}
output "network_name" {
  description = "Nombre de la VPC."
  value       = google_compute_network.vpc.name
}
output "network_self_link" {
  description = "Enlace propio de la VPC, requerido por recursos que no aceptan el id."
  value       = google_compute_network.vpc.self_link
}
output "subnet_app_id" {
  description = "Subnet del API. Sin Cloud NAT: no tiene salida a Internet."
  value       = google_compute_subnetwork.app.id
}

output "subnet_app_name" {
  description = "Nombre de la subred del componente expuesto."
  value       = google_compute_subnetwork.app.name
}

output "subnet_internal_id" {
  description = "Subnet de worker y jobs. Unica traducida por Cloud NAT."
  value       = google_compute_subnetwork.internal.id
}

output "subnet_internal_name" {
  description = "Nombre de la subred de los componentes internos."
  value       = google_compute_subnetwork.internal.name
}

output "psa_connection_id" {
  description = "Dependencia explicita: Cloud SQL no puede crearse antes que el peering."
  value       = google_service_networking_connection.psa.id
}

output "nat_ip" {
  description = "IP de salida estable para allowlists de terceros."
  value       = var.enable_nat ? google_compute_address.nat[0].address : null
}
