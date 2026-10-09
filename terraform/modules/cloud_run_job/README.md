# `cloud_run_job`

Procesos batch programados y bajo demanda, con Cloud Scheduler.

## Proposito

Los procesos batch de la plataforma: conciliacion, exportaciones, backup logico,
intercambio con terceros y migraciones de esquema.

- **Programados:** Cloud Scheduler invoca la API de ejecucion con un token OAuth
  de su propia service account. No hay claves ni webhooks compartidos.
- **Bajo demanda:** el mismo job se lanza con `gcloud run jobs execute` o desde
  el API, que recibe `run.invoker` acotado sobre el job.

## Por que jobs y no un servicio con cron

Un job tiene ciclo de vida de **tarea**: termina, tiene codigo de salida,
reintentos propios y timeout de horas. Un servicio HTTP esta limitado por el
timeout de peticion y no expresa "esto ha terminado bien o mal".

Para volumenes que exijan paralelismo masivo o un DAG de dependencias, la
respuesta seria Cloud Batch o Dataflow.

## Detalle deliberado

El job de backup logico se configura con `max_retries = 0`. Si falla, se quiere
ver la alerta, no un segundo volcado compitiendo por E/S con la base de datos.

## Permisos

`run.invoker` se concede **sobre cada job concreto**, nunca a nivel de proyecto:
Scheduler puede lanzar estos jobs y nada mas.

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
| [google_cloud_run_v2_job.this](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/cloud_run_v2_job) | resource |
| [google_cloud_run_v2_job_iam_member.api_invoker](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/cloud_run_v2_job_iam_member) | resource |
| [google_cloud_run_v2_job_iam_member.scheduler_invoker](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/cloud_run_v2_job_iam_member) | resource |
| [google_cloud_scheduler_job.schedule](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/cloud_scheduler_job) | resource |

### Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_image"></a> [image](#input\_image) | Imagen de contenedor que ejecutan los jobs. La actualiza el pipeline de aplicacion, no el de infraestructura. | `string` | n/a | yes |
| <a name="input_jobs"></a> [jobs](#input\_jobs) | Definicion de cada proceso batch. schedule = null lo deja solo bajo demanda.<br/>El cron se interpreta en var.time\_zone. | <pre>map(object({<br/>    description     = string<br/>    command         = optional(list(string))<br/>    args            = optional(list(string))<br/>    schedule        = optional(string)<br/>    cpu             = optional(string, "1")<br/>    memory          = optional(string, "1Gi")<br/>    task_count      = optional(number, 1)<br/>    parallelism     = optional(number, 1)<br/>    max_retries     = optional(number, 2)<br/>    timeout_seconds = optional(number, 3600)<br/>    vpc_egress      = optional(string, "ALL_TRAFFIC")<br/>    env_vars        = optional(map(string), {})<br/>  }))</pre> | n/a | yes |
| <a name="input_name_prefix"></a> [name\_prefix](#input\_name\_prefix) | Prefijo comun de los nombres de recurso del modulo. | `string` | n/a | yes |
| <a name="input_network_id"></a> [network\_id](#input\_network\_id) | VPC a la que se conectan las ejecuciones. | `string` | n/a | yes |
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | ID del proyecto de GCP donde se crean los recursos. | `string` | n/a | yes |
| <a name="input_region"></a> [region](#input\_region) | Region de GCP donde se despliegan los recursos regionales. | `string` | n/a | yes |
| <a name="input_scheduler_service_account_email"></a> [scheduler\_service\_account\_email](#input\_scheduler\_service\_account\_email) | Identidad con la que Cloud Scheduler invoca los jobs. Recibe run.invoker sobre cada job concreto, no sobre el proyecto. | `string` | n/a | yes |
| <a name="input_service_account_email"></a> [service\_account\_email](#input\_service\_account\_email) | Identidad con la que se ejecutan los jobs. | `string` | n/a | yes |
| <a name="input_subnet_id"></a> [subnet\_id](#input\_subnet\_id) | Subred de la que toman IP las ejecuciones. La interna es la unica con salida a Internet. | `string` | n/a | yes |
| <a name="input_api_service_account_email"></a> [api\_service\_account\_email](#input\_api\_service\_account\_email) | Si se indica, el API puede lanzar ejecuciones bajo demanda. | `string` | `null` | no |
| <a name="input_common_env_vars"></a> [common\_env\_vars](#input\_common\_env\_vars) | Variables de entorno comunes a todos los jobs del ambiente. | `map(string)` | `{}` | no |
| <a name="input_labels"></a> [labels](#input\_labels) | Etiquetas aplicadas a los recursos que las admiten, para repartir costes y filtrar en facturacion. | `map(string)` | `{}` | no |
| <a name="input_network_tags"></a> [network\_tags](#input\_network\_tags) | Etiquetas de red de las instancias de los jobs. | `list(string)` | `[]` | no |
| <a name="input_secret_env_vars"></a> [secret\_env\_vars](#input\_secret\_env\_vars) | Variables cuyo valor se resuelve desde Secret Manager en el arranque de la ejecucion. | <pre>map(object({<br/>    secret_id = string<br/>    version   = string<br/>  }))</pre> | `{}` | no |
| <a name="input_time_zone"></a> [time\_zone](#input\_time\_zone) | Zona horaria en la que se interpretan las expresiones cron de Cloud Scheduler. | `string` | `"Europe/Madrid"` | no |

### Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_job_ids"></a> [job\_ids](#output\_job\_ids) | Identificador completo de cada job. |
| <a name="output_job_names"></a> [job\_names](#output\_job\_names) | Nombre de cada job creado, indexado por clave logica. |
| <a name="output_scheduled_jobs"></a> [scheduled\_jobs](#output\_scheduled\_jobs) | Expresion cron de cada job programado, para verificar la planificacion de un vistazo. |
<!-- END_TF_DOCS -->
