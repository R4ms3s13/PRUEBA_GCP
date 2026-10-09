output "ambiente" {
  description = "Ambiente desplegado por esta instancia del modulo."
  value       = var.env
}
output "region" {
  description = "Region principal del despliegue."
  value       = var.region
}
output "name_prefix" {
  description = "Prefijo aplicado a los nombres de todos los recursos."
  value       = local.name_prefix
}

# --- Punto de entrada ---

output "lb_ip_address" {
  description = "IP global. Crear el registro A del dominio apuntando aqui."
  value       = module.frontend_lb.lb_ip_address
}

output "public_url" {
  description = "URL publica de la plataforma. Con HTTPS desactivado, la IP del balanceador."
  value       = module.frontend_lb.public_url
}

# --- Runtime ---

output "api_service_name" {
  description = "Nombre del servicio de Cloud Run del API."
  value       = module.api.name
}
output "api_internal_uri" {
  description = "URL run.app del API. Con el ingress restringido NO es accesible desde Internet."
  value       = module.api.uri
}
output "worker_service_name" {
  description = "Nombre del servicio de Cloud Run del worker."
  value       = module.worker.name
}
output "batch_job_names" {
  description = "Nombre de cada job batch creado."
  value       = module.batch.job_names
}

# --- Datos ---

output "db_instance_name" {
  description = "Nombre de la instancia de Cloud SQL."
  value       = module.database.instance_name
}
output "db_connection_name" {
  description = "Cadena proyecto:region:instancia que consume el conector de Node.js."
  value       = module.database.connection_name
}

output "db_private_ip" {
  description = "IP privada de la instancia de Cloud SQL. Marcada como sensible porque revela el direccionamiento interno."
  value       = module.database.private_ip_address
  sensitive   = true
}

output "db_secret_ids" {
  description = "Secretos en Secret Manager. Nunca el valor, solo la referencia."
  value = {
    password = module.database.db_password_secret_id
    url      = module.database.db_url_secret_id
  }
}

# --- Almacenamiento ---

output "buckets" {
  description = "Nombre de los cuatro buckets de la plataforma, indexados por proposito."
  value = {
    frontend   = module.storage.frontend_bucket_name
    uploads    = module.storage.uploads_bucket_name
    exports    = module.storage.exports_bucket_name
    db_backups = module.storage.db_backups_bucket_name
  }
}

# --- Contenedores ---

output "image_base" {
  description = "Prefijo para etiquetar las imagenes del pipeline."
  value       = module.registry.image_base
}

# --- Mensajeria ---

output "pubsub_topics" {
  description = "Topics de eventos creados, indexados por dominio."
  value       = module.async.topic_names
}
output "pubsub_dlq" {
  description = "Topic de la cola de mensajes fallidos."
  value       = module.async.dlq_topic_name
}

# --- Identidades ---

output "service_accounts" {
  description = "Identidad de cada componente, para auditoria de permisos."
  value       = module.iam.service_account_emails
}

output "deployer_service_account" {
  description = "SA que debe impersonar el pipeline de CI/CD."
  value       = module.iam.deployer_sa_email
}

# --- Red ---

output "network_name" {
  description = "Nombre de la VPC del ambiente."
  value       = module.network.network_name
}
output "subnet_app_name" {
  description = "Subred del API, la que no tiene salida a Internet."
  value       = module.network.subnet_app_name
}

output "nat_ip" {
  description = "IP de salida para allowlists de sistemas de terceros."
  value       = module.network.nat_ip
}

# --- Observabilidad ---

output "log_bucket" {
  description = "Bucket central de logs."
  value       = module.observability.log_bucket_id
}
output "dashboard_id" {
  description = "Dashboard de estado de la plataforma."
  value       = module.observability.dashboard_id
}
