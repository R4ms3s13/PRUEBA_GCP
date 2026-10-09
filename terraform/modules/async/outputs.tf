output "topic_names" {
  description = "Nombre de cada topic de eventos, indexado por dominio."
  value       = { for k, t in google_pubsub_topic.topics : k => t.name }
}

output "topic_ids" {
  description = "Identificador completo de cada topic."
  value       = { for k, t in google_pubsub_topic.topics : k => t.id }
}

output "subscription_names" {
  description = "Nombre de cada suscripcion push al worker."
  value       = { for k, s in google_pubsub_subscription.push : k => s.name }
}

output "dlq_topic_name" {
  description = "Topic de la cola de mensajes fallidos."
  value       = google_pubsub_topic.dlq.name
}
output "dlq_subscription_name" {
  description = "Suscripcion de la cola de fallidos, la que vigila la alerta."
  value       = google_pubsub_subscription.dlq.name
}
