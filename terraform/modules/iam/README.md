# `iam`

Una service account por componente, con permisos disjuntos.

## Proposito

Crea las seis identidades de la plataforma y les concede **solo** lo que cada
una necesita. El objetivo es que comprometer un componente no otorgue nada de
lo que necesitan los demas.

| Identidad | Para que | Lo que NO puede |
|---|---|---|
| `api` | Runtime del API backend | Escribir en exports, leer suscripciones |
| `worker` | Consumidor de Pub/Sub | Publicar eventos, escribir archivos |
| `batch` | Ejecuciones batch | Publicar eventos, tocar el frontend |
| `scheduler` | Invocar los jobs | Invocar servicios, leer datos |
| `pubsub` | Firmar el OIDC hacia el worker | Cualquier otra cosa |
| `deployer` | CI/CD | Tocar red, IAM o base de datos |

## Reglas aplicadas sin excepcion

- **Ningun rol basico.** Ni `owner`, ni `editor`, ni `viewer`, en ningun sitio.
- **Permiso a nivel de recurso siempre que exista.** `run.invoker` se concede
  sobre el job o el servicio concreto, nunca sobre el proyecto: por eso este
  modulo **no** lo concede, lo hacen `async` y `cloud_run_job` sobre su recurso.
- **Impersonacion acotada.** El pipeline despliega *como* las service accounts
  de runtime via `serviceAccountUser`, sin tener sus permisos.

## Uso

```hcl
module "iam" {
  source = "../modules/iam"

  project_id             = "mi-proyecto"
  env                    = "prod"
  region                 = "europe-west1"
  name_prefix            = "prov-prod"
  uploads_bucket_name    = module.storage.uploads_bucket_name
  exports_bucket_name    = module.storage.exports_bucket_name
  db_backups_bucket_name = module.storage.db_backups_bucket_name
  frontend_bucket_name   = module.storage.frontend_bucket_name
  registry_repository_id = module.registry.repository_id
}
```

---

## Referencia

<!-- BEGIN_TF_DOCS -->
### Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.6.0 |
| <a name="requirement_google"></a> [google](#requirement\_google) | >= 6.0, < 7.0 |

### Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_google"></a> [google](#provider\_google) | >= 6.0, < 7.0 |

### Resources

| Name | Type |
| ---- | ---- |
| [google_artifact_registry_repository_iam_member.readers](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/artifact_registry_repository_iam_member) | resource |
| [google_project_iam_member.bindings](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/project_iam_member) | resource |
| [google_project_iam_member.deployer_cdn_invalidate](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/project_iam_member) | resource |
| [google_service_account.sa](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/service_account) | resource |
| [google_service_account_iam_member.deployer_act_as](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/service_account_iam_member) | resource |
| [google_service_account_iam_member.deployer_wif](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/service_account_iam_member) | resource |
| [google_storage_bucket_iam_member.db_backups_batch](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/storage_bucket_iam_member) | resource |
| [google_storage_bucket_iam_member.exports_batch](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/storage_bucket_iam_member) | resource |
| [google_storage_bucket_iam_member.frontend_deployer](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/storage_bucket_iam_member) | resource |
| [google_storage_bucket_iam_member.uploads_api](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/storage_bucket_iam_member) | resource |
| [google_storage_bucket_iam_member.uploads_batch](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/storage_bucket_iam_member) | resource |
| [google_storage_bucket_iam_member.uploads_worker](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/storage_bucket_iam_member) | resource |

### Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_db_backups_bucket_name"></a> [db\_backups\_bucket\_name](#input\_db\_backups\_bucket\_name) | Bucket de volcados logicos de la base de datos. | `string` | n/a | yes |
| <a name="input_env"></a> [env](#input\_env) | Identificador del ambiente (dev, qa o prod). Se usa en nombres, etiquetas y decisiones condicionales. | `string` | n/a | yes |
| <a name="input_exports_bucket_name"></a> [exports\_bucket\_name](#input\_exports\_bucket\_name) | Bucket de salidas de los procesos batch. | `string` | n/a | yes |
| <a name="input_frontend_bucket_name"></a> [frontend\_bucket\_name](#input\_frontend\_bucket\_name) | Bucket del build estatico. Solo CI/CD escribe en el. | `string` | n/a | yes |
| <a name="input_name_prefix"></a> [name\_prefix](#input\_name\_prefix) | Prefijo comun de los nombres de recurso del modulo. | `string` | n/a | yes |
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | ID del proyecto de GCP donde se crean los recursos. | `string` | n/a | yes |
| <a name="input_region"></a> [region](#input\_region) | Region de GCP donde se despliegan los recursos regionales. | `string` | n/a | yes |
| <a name="input_registry_repository_id"></a> [registry\_repository\_id](#input\_registry\_repository\_id) | ID del repositorio de Artifact Registry con las imagenes. | `string` | n/a | yes |
| <a name="input_uploads_bucket_name"></a> [uploads\_bucket\_name](#input\_uploads\_bucket\_name) | Bucket de archivos subidos por los usuarios. | `string` | n/a | yes |
| <a name="input_deployer_wif_principal"></a> [deployer\_wif\_principal](#input\_deployer\_wif\_principal) | Principal de Workload Identity Federation autorizado a impersonar la SA<br/>deployer, en formato principalSet://... Lo construye el modulo raiz a partir<br/>del pool que crea el bootstrap.<br/><br/>Si queda vacio no se crea el binding, y entonces el pipeline de GitHub<br/>Actions NO puede autenticarse: ese es el caso de quien despliega solo con<br/>Cloud Build, que usa la SA directamente y no federa identidad. | `string` | `""` | no |

### Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_api_sa_email"></a> [api\_sa\_email](#output\_api\_sa\_email) | Identidad del API backend. |
| <a name="output_batch_sa_email"></a> [batch\_sa\_email](#output\_batch\_sa\_email) | Identidad de las ejecuciones batch. |
| <a name="output_deployer_sa_email"></a> [deployer\_sa\_email](#output\_deployer\_sa\_email) | Identidad que debe impersonar el pipeline de CI/CD. |
| <a name="output_pubsub_sa_email"></a> [pubsub\_sa\_email](#output\_pubsub\_sa\_email) | Identidad con la que Pub/Sub firma el token OIDC hacia el worker. |
| <a name="output_pubsub_sa_id"></a> [pubsub\_sa\_id](#output\_pubsub\_sa\_id) | Identificador completo de la service account de Pub/Sub, para el binding de tokenCreator. |
| <a name="output_scheduler_sa_email"></a> [scheduler\_sa\_email](#output\_scheduler\_sa\_email) | Identidad con la que Cloud Scheduler invoca los jobs. |
| <a name="output_service_account_emails"></a> [service\_account\_emails](#output\_service\_account\_emails) | Email de cada service account, indexado por componente. |
| <a name="output_service_account_ids"></a> [service\_account\_ids](#output\_service\_account\_ids) | Identificador completo de cada service account, indexado por componente. |
| <a name="output_worker_sa_email"></a> [worker\_sa\_email](#output\_worker\_sa\_email) | Identidad del worker de procesos asincronos. |
<!-- END_TF_DOCS -->
