output "tfstate_bucket" {
  description = "Valor de 'bucket' en el backend.hcl del ambiente."
  value       = google_storage_bucket.tfstate.name
}

output "workload_identity_provider" {
  description = "Valor de workload_identity_provider en el workflow de GitHub."
  value       = google_iam_workload_identity_pool_provider.github.name
}

output "terraform_service_account" {
  description = "Valor de service_account en el workflow de GitHub."
  value       = google_service_account.terraform.email
}

output "workload_identity_pool" {
  description = <<-EOT
    Valor de wif_pool_name en el terraform.tfvars del ambiente. Lo necesita el
    modulo raiz para autorizar a CI/CD a impersonar la SA de despliegue.
  EOT
  value       = google_iam_workload_identity_pool.github.name
}
