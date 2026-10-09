output "instance_name" {
  description = "Nombre de la instancia de Cloud SQL."
  value       = google_sql_database_instance.main.name
}

output "connection_name" {
  description = "Formato proyecto:region:instancia, que consume el conector de Node.js."
  value       = google_sql_database_instance.main.connection_name
}

output "private_ip_address" {
  description = "IP privada de la instancia. No existe equivalente publica: es el nucleo del requisito de no exposicion."
  value       = google_sql_database_instance.main.private_ip_address
}

output "database_name" {
  description = "Nombre de la base de datos logica de la aplicacion."
  value       = google_sql_database.app.name
}
output "app_db_user" {
  description = "Usuario administrativo, reservado a migraciones y mantenimiento."
  value       = google_sql_user.app.name
}

output "db_password_secret_id" {
  description = "Identificador del secreto que guarda la contrasena administrativa."
  value       = google_secret_manager_secret.db_password.secret_id
}

output "db_url_secret_id" {
  description = "Identificador del secreto que guarda la cadena de conexion completa."
  value       = google_secret_manager_secret.db_url.secret_id
}

output "db_url_secret_name" {
  description = "Nombre completo del secreto, para montarlo en Cloud Run."
  value       = google_secret_manager_secret.db_url.id
}

output "self_link" {
  description = "Enlace propio de la instancia."
  value       = google_sql_database_instance.main.self_link
}
