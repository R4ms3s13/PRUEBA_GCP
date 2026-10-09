# `cloud_run_service`

Modulo generico de servicio Cloud Run. Lo instancian el API y el worker.

## Proposito

Un contrato unico para los dos servicios de larga vida de la plataforma. Mismo
modulo, configuracion distinta.

## Por que Cloud Run y no GKE

- 2.000 usuarios concurrentes y 500.000 operaciones diarias es carga que un
  autoescalado por peticion cubre sin gestionar nodos.
- El trafico de una plataforma B2B es diurno: con GKE se paga el valle.
- Un cluster anade un plano de control que parchear y vigilar en tres
  ambientes, sin aportar nada que aqui se necesite.

**Cuando reconsiderarlo:** cargas con estado, sidecars complejos, procesos de
mas de 24 h o necesidad de GPU. GKE Autopilot seria la via natural, y la
migracion no toca la aplicacion: los contenedores son los mismos.

## Parametros que no se tocan por separado

- **`max_instances` y el pool de conexiones.** El techo de escalado no es solo
  un limite de coste: es lo que impide que el autoescalado agote las conexiones
  de PostgreSQL. Se fija junto a `db_max_connections`.
- **`tmp_size_limit` y `memory`.** El volumen temporal es tmpfs y **cuenta
  contra el limite de memoria**: 256Mi en una instancia de 512Mi deja la mitad
  de la RAM al proceso y puede provocar OOM.
- **`vpc_egress` y la subred.** `ALL_TRAFFIC` es lo que hace que la presencia o
  ausencia de Cloud NAT en la subred determine si hay Internet.

## Lo que el modulo deja fuera a proposito

`ignore_changes` sobre la imagen del contenedor y sobre `traffic`. La imagen la
gobierna el pipeline de **aplicacion**, no el de infraestructura; sin esto, cada
`terraform apply` revertiria el ultimo despliegue. Y el reparto de trafico de un
canary necesita el id de la revision estable, que cambia en cada despliegue: es
estado de release, no de infraestructura.

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
| [google_cloud_run_v2_service.this](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/cloud_run_v2_service) | resource |
| [google_cloud_run_v2_service_iam_member.invokers](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/cloud_run_v2_service_iam_member) | resource |

### Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_image"></a> [image](#input\_image) | Imagen completa. El pipeline la sustituye por digest en cada release. | `string` | n/a | yes |
| <a name="input_network_id"></a> [network\_id](#input\_network\_id) | VPC a la que se conectan las instancias mediante Direct VPC egress. | `string` | n/a | yes |
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | ID del proyecto de GCP donde se crean los recursos. | `string` | n/a | yes |
| <a name="input_region"></a> [region](#input\_region) | Region de GCP donde se despliegan los recursos regionales. | `string` | n/a | yes |
| <a name="input_service_account_email"></a> [service\_account\_email](#input\_service\_account\_email) | Identidad con la que se ejecuta el servicio. Determina a que puede acceder y es la base del privilegio minimo. | `string` | n/a | yes |
| <a name="input_service_name"></a> [service\_name](#input\_service\_name) | Nombre del servicio de Cloud Run. Es tambien el identificador por el que se filtran sus metricas y sus logs. | `string` | n/a | yes |
| <a name="input_subnet_id"></a> [subnet\_id](#input\_subnet\_id) | Subred de la que las instancias toman IP. Determina si tienen salida a Internet, segun este o no cubierta por Cloud NAT. | `string` | n/a | yes |
| <a name="input_container_port"></a> [container\_port](#input\_container\_port) | Puerto en el que escucha el contenedor. Contrato con el equipo de desarrollo. | `number` | `8080` | no |
| <a name="input_cpu"></a> [cpu](#input\_cpu) | vCPU por instancia. | `string` | `"1"` | no |
| <a name="input_cpu_idle"></a> [cpu\_idle](#input\_cpu\_idle) | true = CPU solo durante la request. false para trabajo en background. | `bool` | `true` | no |
| <a name="input_deletion_protection"></a> [deletion\_protection](#input\_deletion\_protection) | Impide destruir el servicio desde Terraform. Debe estar activo en produccion. | `bool` | `false` | no |
| <a name="input_env_vars"></a> [env\_vars](#input\_env\_vars) | Variables de entorno NO sensibles. | `map(string)` | `{}` | no |
| <a name="input_execution_environment"></a> [execution\_environment](#input\_execution\_environment) | Generacion del entorno de ejecucion. GEN2 da soporte completo de sistema de ficheros y mejor rendimiento de red. | `string` | `"EXECUTION_ENVIRONMENT_GEN2"` | no |
| <a name="input_health_path"></a> [health\_path](#input\_health\_path) | Ruta de salud que expone la aplicacion, usada por las sondas de arranque y vivacidad. Contrato con el equipo de desarrollo. | `string` | `"/healthz"` | no |
| <a name="input_ingress"></a> [ingress](#input\_ingress) | INGRESS\_TRAFFIC\_INTERNAL\_LOAD\_BALANCER: solo balanceador y fuentes internas.<br/>INGRESS\_TRAFFIC\_INTERNAL\_ONLY: solo fuentes internas (worker).<br/>INGRESS\_TRAFFIC\_ALL: expuesto en su URL run.app (no usar en prod). | `string` | `"INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER"` | no |
| <a name="input_invoker_members"></a> [invoker\_members](#input\_invoker\_members) | Miembros IAM con roles/run.invoker sobre este servicio. | `map(string)` | `{}` | no |
| <a name="input_labels"></a> [labels](#input\_labels) | Etiquetas aplicadas a los recursos que las admiten, para repartir costes y filtrar en facturacion. | `map(string)` | `{}` | no |
| <a name="input_max_concurrency"></a> [max\_concurrency](#input\_max\_concurrency) | Peticiones simultaneas que atiende una instancia. Node.js aprovecha valores altos por su E/S asincrona. | `number` | `80` | no |
| <a name="input_max_instances"></a> [max\_instances](#input\_max\_instances) | Techo de escalado. Protege a la BBDD de un exceso de conexiones. | `number` | `10` | no |
| <a name="input_memory"></a> [memory](#input\_memory) | Memoria por instancia. El volumen temporal en memoria cuenta contra este limite. | `string` | `"512Mi"` | no |
| <a name="input_min_instances"></a> [min\_instances](#input\_min\_instances) | Instancias siempre activas. > 0 en prod para eliminar arranques en frio. | `number` | `0` | no |
| <a name="input_network_tags"></a> [network\_tags](#input\_network\_tags) | Etiquetas de red de las instancias, para reglas de firewall dirigidas. | `list(string)` | `[]` | no |
| <a name="input_request_timeout_seconds"></a> [request\_timeout\_seconds](#input\_request\_timeout\_seconds) | Tiempo maximo de una peticion. Un valor bajo libera instancias antes y acota el dano de una consulta colgada. | `number` | `60` | no |
| <a name="input_secret_env_vars"></a> [secret\_env\_vars](#input\_secret\_env\_vars) | Variables cuyo valor se resuelve desde Secret Manager. | <pre>map(object({<br/>    secret_id = string<br/>    version   = string<br/>  }))</pre> | `{}` | no |
| <a name="input_startup_cpu_boost"></a> [startup\_cpu\_boost](#input\_startup\_cpu\_boost) | Asigna CPU adicional durante el arranque, lo que acorta el tiempo hasta la primera peticion servida. | `bool` | `true` | no |
| <a name="input_startup_probe_delay"></a> [startup\_probe\_delay](#input\_startup\_probe\_delay) | Segundos de espera antes de la primera sonda de arranque. | `number` | `5` | no |
| <a name="input_startup_probe_failures"></a> [startup\_probe\_failures](#input\_startup\_probe\_failures) | Fallos consecutivos de la sonda de arranque antes de dar la instancia por fallida. | `number` | `12` | no |
| <a name="input_tmp_size_limit"></a> [tmp\_size\_limit](#input\_tmp\_size\_limit) | Tamano del volumen temporal en memoria. CUENTA CONTRA var.memory: un tmpfs<br/>de 256Mi en una instancia de 512Mi deja la mitad de la RAM para el proceso<br/>y puede provocar OOM. Por eso el valor por defecto es conservador; subirlo<br/>solo cuando memory lo permita. | `string` | `"64Mi"` | no |
| <a name="input_volume_mounts"></a> [volume\_mounts](#input\_volume\_mounts) | Mapa nombre\_volumen => ruta de montaje (scratch en memoria). | `map(string)` | `{}` | no |
| <a name="input_vpc_egress"></a> [vpc\_egress](#input\_vpc\_egress) | ALL\_TRAFFIC envia toda la salida por la VPC, de forma que la presencia o<br/>ausencia de Cloud NAT en la subnet determina si hay Internet. Es lo que se<br/>usa aqui. PRIVATE\_RANGES\_ONLY dejaria el trafico publico por la ruta<br/>gestionada de Google, esquivando ese control. | `string` | `"ALL_TRAFFIC"` | no |

### Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_id"></a> [id](#output\_id) | Identificador completo del servicio. |
| <a name="output_location"></a> [location](#output\_location) | Region en la que se ha desplegado el servicio. |
| <a name="output_name"></a> [name](#output\_name) | Nombre del servicio desplegado. |
| <a name="output_uri"></a> [uri](#output\_uri) | URL run.app. Con ingress restringido no es accesible desde Internet. |
<!-- END_TF_DOCS -->
