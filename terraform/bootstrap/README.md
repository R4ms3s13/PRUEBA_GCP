# `bootstrap`

Se aplica UNA vez por ambiente, antes que la plataforma, con state local.

## Proposito

Crea lo que el resto del repositorio da por existente:

1. El **bucket del state remoto** de Terraform.
2. La **federacion de identidad** (Workload Identity Federation) para que el
   CI/CD se autentique sin claves de service account descargadas.

Se ejecuta con **state local**: no puede guardar su propio state en un bucket
que el mismo esta creando.

## El control mas importante

```hcl
attribute_condition = "assertion.repository == \"owner/repo\""
```

**Sin esta condicion, cualquier repositorio de GitHub podria obtener un token
para este proyecto.** En produccion se restringe ademas a la rama protegida.

Es lo que permite cumplir "sin credenciales en codigo duro" tambien en el
pipeline: GitHub presenta su token OIDC y GCP lo intercambia por un token de
acceso de minutos.

## Despues de aplicarlo

```bash
terraform output tfstate_bucket              # -> envs/<env>/backend.hcl
terraform output workload_identity_provider  # -> variable WIF_PROVIDER_<env>
terraform output terraform_service_account   # -> variable TF_SA_<env>
```

> El state local del bootstrap contiene configuracion de IAM. Guardarlo en un
> sitio controlado, o migrarlo al bucket que acaba de crear.

## Permisos de la service account de Terraform

Son amplios por necesidad: gestiona red, IAM y bases de datos. Aun asi **no
incluyen ningun rol basico**, y se protegen con la condicion de repositorio y
rama de arriba.

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
| [google_iam_workload_identity_pool.github](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/iam_workload_identity_pool) | resource |
| [google_iam_workload_identity_pool_provider.github](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/iam_workload_identity_pool_provider) | resource |
| [google_project_iam_member.terraform_roles](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/project_iam_member) | resource |
| [google_service_account.terraform](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/service_account) | resource |
| [google_service_account_iam_member.terraform_wif](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/service_account_iam_member) | resource |
| [google_storage_bucket.tfstate](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/storage_bucket) | resource |
| [google_storage_bucket_iam_member.terraform_state](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/storage_bucket_iam_member) | resource |
| [google_storage_bucket_iam_member.tfstate_admin](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/storage_bucket_iam_member) | resource |

### Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_env"></a> [env](#input\_env) | Identificador del ambiente (dev, qa o prod). | `string` | n/a | yes |
| <a name="input_github_repository"></a> [github\_repository](#input\_github\_repository) | owner/repo exacto. Acota quien puede federar identidad. | `string` | n/a | yes |
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | ID del proyecto de GCP del ambiente sobre el que se ejecuta el bootstrap. | `string` | n/a | yes |
| <a name="input_allowed_workflows"></a> [allowed\_workflows](#input\_allowed\_workflows) | Ficheros de .github/workflows/ autorizados a federar identidad. Es una lista<br/>blanca: un workflow que no este aqui no obtiene token, aunque viva en el<br/>repositorio autorizado.<br/><br/>Es la defensa contra un repositorio comprometido en el que el atacante anade<br/>un workflow propio. No defiende de que modifique uno de estos tres: para eso<br/>hace falta proteccion de rama con revision obligatoria (D16). | `list(string)` | <pre>[<br/>  "infra.yml",<br/>  "backend.yml",<br/>  "frontend.yml"<br/>]</pre> | no |
| <a name="input_kms_key_name"></a> [kms\_key\_name](#input\_kms\_key\_name) | Clave CMEK para el bucket de state. null usa la clave de Google. | `string` | `null` | no |
| <a name="input_name_prefix"></a> [name\_prefix](#input\_name\_prefix) | Prefijo de la organizacion. Debe coincidir con el bucket del backend.hcl. | `string` | `"proveedores"` | no |
| <a name="input_protected_branch"></a> [protected\_branch](#input\_protected\_branch) | Rama desde la que se permite desplegar en prod. | `string` | `"main"` | no |
| <a name="input_region"></a> [region](#input\_region) | Region donde se crea el bucket de state. | `string` | `"europe-west1"` | no |
| <a name="input_state_admin_members"></a> [state\_admin\_members](#input\_state\_admin\_members) | Personas o grupos con acceso al state, ademas del pipeline. | `map(string)` | `{}` | no |
| <a name="input_state_keep_versions"></a> [state\_keep\_versions](#input\_state\_keep\_versions) | Versiones archivadas del state que se conservan. | `number` | `20` | no |
| <a name="input_terraform_sa_roles"></a> [terraform\_sa\_roles](#input\_terraform\_sa\_roles) | Roles de la SA de Terraform. Son amplios porque gestiona red, IAM y datos,<br/>pero siguen sin incluir roles basicos: ni owner ni editor. | `list(string)` | <pre>[<br/>  "roles/compute.networkAdmin",<br/>  "roles/compute.securityAdmin",<br/>  "roles/compute.loadBalancerAdmin",<br/>  "roles/run.admin",<br/>  "roles/cloudsql.admin",<br/>  "roles/storage.admin",<br/>  "roles/artifactregistry.admin",<br/>  "roles/pubsub.admin",<br/>  "roles/cloudscheduler.admin",<br/>  "roles/secretmanager.admin",<br/>  "roles/iam.serviceAccountAdmin",<br/>  "roles/resourcemanager.projectIamAdmin",<br/>  "roles/logging.admin",<br/>  "roles/monitoring.admin",<br/>  "roles/serviceusage.serviceUsageAdmin",<br/>  "roles/bigquery.admin",<br/>  "roles/iam.serviceAccountUser"<br/>]</pre> | no |
| <a name="input_tf_sa_prefix"></a> [tf\_sa\_prefix](#input\_tf\_sa\_prefix) | Prefijo de la service account que ejecuta Terraform. | `string` | `"tf-infra"` | no |
| <a name="input_wif_pool_prefix"></a> [wif\_pool\_prefix](#input\_wif\_pool\_prefix) | Prefijo del pool de Workload Identity Federation. | `string` | `"github"` | no |

### Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_terraform_service_account"></a> [terraform\_service\_account](#output\_terraform\_service\_account) | Valor de service\_account en el workflow de GitHub. |
| <a name="output_tfstate_bucket"></a> [tfstate\_bucket](#output\_tfstate\_bucket) | Valor de 'bucket' en el backend.hcl del ambiente. |
| <a name="output_workload_identity_pool"></a> [workload\_identity\_pool](#output\_workload\_identity\_pool) | Valor de wif\_pool\_name en el terraform.tfvars del ambiente. Lo necesita el<br/>modulo raiz para autorizar a CI/CD a impersonar la SA de despliegue. |
| <a name="output_workload_identity_provider"></a> [workload\_identity\_provider](#output\_workload\_identity\_provider) | Valor de workload\_identity\_provider en el workflow de GitHub. |
<!-- END_TF_DOCS -->
