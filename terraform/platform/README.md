# `platform`

Modulo raiz: cablea los diez modulos y concentra el estandar de la organizacion.

## Proposito

**Este es el modulo que instancian los tres ambientes.** Es la respuesta al
requisito de que dev, QA y produccion usen la misma definicion de
infraestructura con configuraciones diferentes.

Los ficheros `envs/*/main.tf` son identicos salvo el valor de `env`; toda la
diferencia vive en `terraform.tfvars`. Es verificable:

```bash
diff <(sed 's/\bdev\b/ENV/g'  ../envs/dev/main.tf) \
     <(sed 's/\bprod\b/ENV/g' ../envs/prod/main.tf)
# sin diferencias
```

## Orden de dependencias

Terraform lo resuelve solo, pero conviene conocerlo porque explica los errores
del primer intento:

1. APIs del proyecto. Todo lo demas falla sin ellas.
2. VPC, subredes y **peering de Private Service Access**.
3. Cloud SQL, que **no puede crearse antes del peering**.
4. Buckets y Artifact Registry.
5. Service accounts y permisos, que necesitan los recursos a los que se conceden.
6. Servicios de Cloud Run.
7. Pub/Sub, que necesita la URL del worker ya creado.
8. Balanceador, que necesita el servicio del API para el serverless NEG.
9. Observabilidad, que necesita los nombres de todo lo anterior.

## Niveles de parametrizacion

| Nivel | Donde | Que contiene |
|---|---|---|
| Ambiente | `envs/*/terraform.tfvars` | Lo que difiere entre dev, QA y prod |
| Organizacion | **este modulo** | El estandar: contrato con la aplicacion, APIs, nombre del registro, politica de egress |
| Diseno del modulo | `modules/*/variables.tf` | Valores con default razonable |

## El contrato con el equipo de desarrollo

Cuatro variables que la infraestructura consume en varios sitios a la vez, y que
por eso viven en **una sola** fuente:

| Variable | Donde se usa |
|---|---|
| `app_health_path` | Sondas de los runtimes, enrutado del balanceador, uptime check y exclusion de logs |
| `app_container_port` | Puerto de los runtimes y de la regla de firewall de health checks |
| `app_api_path_patterns` | Rutas que el balanceador envia al API |
| `secret_version` | Version de los secretos que montan los runtimes |

## Primer apply

Los tres servicios arrancan con la imagen publica de ejemplo de Cloud Run,
porque el repositorio esta vacio. **Es intencionado:** la infraestructura queda
desplegada y verificable antes de que exista la aplicacion. A partir de ahi la
imagen la gobierna el pipeline, y los modulos ignoran sus cambios.

---

## Referencia

<!-- BEGIN_TF_DOCS -->
### Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.6.0 |
| <a name="requirement_google"></a> [google](#requirement\_google) | ~> 6.0 |
| <a name="requirement_random"></a> [random](#requirement\_random) | ~> 3.6 |

### Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_google"></a> [google](#provider\_google) | ~> 6.0 |

### Resources

| Name | Type |
| ---- | ---- |
| [google_project_service.apis](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/project_service) | resource |

### Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_env"></a> [env](#input\_env) | Identificador del ambiente. | `string` | n/a | yes |
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | Proyecto GCP del ambiente. Un proyecto por ambiente. | `string` | n/a | yes |
| <a name="input_psa_cidr"></a> [psa\_cidr](#input\_psa\_cidr) | Direccion base del rango de Private Service Access. | `string` | n/a | yes |
| <a name="input_subnet_app_cidr"></a> [subnet\_app\_cidr](#input\_subnet\_app\_cidr) | CIDR de la subnet del API, el componente expuesto a traves del balanceador.<br/>Queda FUERA de Cloud NAT a proposito: sin ruta a Internet.<br/>No debe solaparse entre ambientes. | `string` | n/a | yes |
| <a name="input_subnet_internal_cidr"></a> [subnet\_internal\_cidr](#input\_subnet\_internal\_cidr) | CIDR de la subnet de los componentes internos (worker y jobs batch), la<br/>unica traducida por Cloud NAT: de ahi sale el intercambio con aplicaciones<br/>de terceros por una IP fija. | `string` | n/a | yes |
| <a name="input_alert_emails"></a> [alert\_emails](#input\_alert\_emails) | Mapa etiqueta a email de los destinatarios de las alertas. Mapa y no lista para que renombrar uno no recree los demas. | `map(string)` | `{}` | no |
| <a name="input_api_cpu"></a> [api\_cpu](#input\_api\_cpu) | vCPU por instancia del API. | `string` | `"1"` | no |
| <a name="input_api_image"></a> [api\_image](#input\_api\_image) | Imagen del API. En el primer apply el repositorio esta vacio, asi que el<br/>valor por defecto es la imagen publica de ejemplo de Cloud Run: la<br/>infraestructura queda desplegada y verificable antes de que exista la<br/>aplicacion. A partir de ahi la sustituye el pipeline, y el modulo ignora los<br/>cambios de imagen para no revertir despliegues. | `string` | `"us-docker.pkg.dev/cloudrun/container/hello"` | no |
| <a name="input_api_ingress"></a> [api\_ingress](#input\_api\_ingress) | Quien puede llegar al API. Por defecto, solo el balanceador. | `string` | `"INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER"` | no |
| <a name="input_api_max_concurrency"></a> [api\_max\_concurrency](#input\_api\_max\_concurrency) | Peticiones simultaneas por instancia del API. | `number` | `80` | no |
| <a name="input_api_max_instances"></a> [api\_max\_instances](#input\_api\_max\_instances) | Techo de escalado del API. Se fija junto a db\_max\_connections: es lo que impide agotar las conexiones de PostgreSQL. | `number` | `10` | no |
| <a name="input_api_memory"></a> [api\_memory](#input\_api\_memory) | Memoria por instancia del API. El volumen temporal cuenta contra este limite. | `string` | `"512Mi"` | no |
| <a name="input_api_min_instances"></a> [api\_min\_instances](#input\_api\_min\_instances) | > 0 elimina el arranque en frio. Imprescindible en prod. | `number` | `0` | no |
| <a name="input_api_request_timeout_seconds"></a> [api\_request\_timeout\_seconds](#input\_api\_request\_timeout\_seconds) | Un API de pedidos no deberia necesitar mas: libera instancias antes. | `number` | `60` | no |
| <a name="input_api_tmp_size_limit"></a> [api\_tmp\_size\_limit](#input\_api\_tmp\_size\_limit) | Volumen temporal del API. CUENTA contra api\_memory. | `string` | `"64Mi"` | no |
| <a name="input_app_api_path_patterns"></a> [app\_api\_path\_patterns](#input\_app\_api\_path\_patterns) | Rutas que el balanceador enruta al API en lugar del frontend. | `list(string)` | <pre>[<br/>  "/api",<br/>  "/api/*"<br/>]</pre> | no |
| <a name="input_app_container_port"></a> [app\_container\_port](#input\_app\_container\_port) | Puerto en el que escucha el contenedor. | `number` | `8080` | no |
| <a name="input_app_health_path"></a> [app\_health\_path](#input\_app\_health\_path) | Ruta de salud que expone la aplicacion. | `string` | `"/healthz"` | no |
| <a name="input_app_name"></a> [app\_name](#input\_app\_name) | Nombre de la aplicacion. Va a las etiquetas de todos los recursos. | `string` | `"plataforma-proveedores"` | no |
| <a name="input_app_tmp_mount_path"></a> [app\_tmp\_mount\_path](#input\_app\_tmp\_mount\_path) | Punto de montaje del volumen temporal en memoria. | `string` | `"/tmp"` | no |
| <a name="input_batch_image"></a> [batch\_image](#input\_batch\_image) | Imagen de los procesos batch. La gobierna el pipeline de aplicacion. | `string` | `"us-docker.pkg.dev/cloudrun/container/hello"` | no |
| <a name="input_batch_jobs"></a> [batch\_jobs](#input\_batch\_jobs) | Procesos batch del ambiente. Ver modulo cloud\_run\_job. | <pre>map(object({<br/>    description     = string<br/>    command         = optional(list(string))<br/>    args            = optional(list(string))<br/>    schedule        = optional(string)<br/>    cpu             = optional(string, "1")<br/>    memory          = optional(string, "1Gi")<br/>    task_count      = optional(number, 1)<br/>    parallelism     = optional(number, 1)<br/>    max_retries     = optional(number, 2)<br/>    timeout_seconds = optional(number, 3600)<br/>    vpc_egress      = optional(string, "ALL_TRAFFIC")<br/>    env_vars = optional(map(string), {<br/>    })<br/>  }))</pre> | `{}` | no |
| <a name="input_bigquery_location"></a> [bigquery\_location](#input\_bigquery\_location) | Ubicacion del dataset de analitica de logs. | `string` | `"EU"` | no |
| <a name="input_bigquery_table_expiration_days"></a> [bigquery\_table\_expiration\_days](#input\_bigquery\_table\_expiration\_days) | Dias tras los que caducan las tablas particionadas de logs en BigQuery. | `number` | `90` | no |
| <a name="input_cdn_ttls"></a> [cdn\_ttls](#input\_cdn\_ttls) | TTL de la cache del CDN. Los assets del SPA llevan hash en el nombre, de<br/>modo que pueden cachearse mucho; index.html se publica con no-cache desde<br/>el pipeline para que un despliegue se vea de inmediato. | <pre>object({<br/>    client   = optional(number, 3600)<br/>    default  = optional(number, 3600)<br/>    max      = optional(number, 86400)<br/>    stale    = optional(number, 86400)<br/>    negative = optional(number, 60)<br/>  })</pre> | `{}` | no |
| <a name="input_db_app_user"></a> [db\_app\_user](#input\_db\_app\_user) | Usuario administrativo, solo para migraciones y mantenimiento. | `string` | `"app"` | no |
| <a name="input_db_backup_location"></a> [db\_backup\_location](#input\_db\_backup\_location) | Region de los backups. Distinta de la principal en prod. | `string` | `null` | no |
| <a name="input_db_backup_retention_days"></a> [db\_backup\_retention\_days](#input\_db\_backup\_retention\_days) | Retencion de los volcados logicos de la BBDD en Cloud Storage. | `number` | `30` | no |
| <a name="input_db_backup_start_time"></a> [db\_backup\_start\_time](#input\_db\_backup\_start\_time) | Hora UTC de la ventana de backup. | `string` | `"02:00"` | no |
| <a name="input_db_collation"></a> [db\_collation](#input\_db\_collation) | Afecta al ORDER BY de los textos. No cambiar tras el primer apply. | `string` | `"en_US.UTF8"` | no |
| <a name="input_db_cpu_alert_threshold"></a> [db\_cpu\_alert\_threshold](#input\_db\_cpu\_alert\_threshold) | Fraccion de CPU de Cloud SQL sostenida que dispara la alerta. Antecede a la degradacion general. | `number` | `0.8` | no |
| <a name="input_db_deletion_protection"></a> [db\_deletion\_protection](#input\_db\_deletion\_protection) | Impide destruir la instancia desde Terraform y desde la consola. Debe estar activo en produccion. | `bool` | `true` | no |
| <a name="input_db_disk_alert_threshold"></a> [db\_disk\_alert\_threshold](#input\_db\_disk\_alert\_threshold) | Fraccion de disco de Cloud SQL que dispara la alerta. Un disco lleno es una caida total. | `number` | `0.85` | no |
| <a name="input_db_disk_autoresize_limit_gb"></a> [db\_disk\_autoresize\_limit\_gb](#input\_db\_disk\_autoresize\_limit\_gb) | Techo del crecimiento automatico: evita una factura silenciosa. | `number` | `100` | no |
| <a name="input_db_disk_size_gb"></a> [db\_disk\_size\_gb](#input\_db\_disk\_size\_gb) | Tamano inicial del disco de la base de datos. Crece solo con autoresize. | `number` | `20` | no |
| <a name="input_db_edition"></a> [db\_edition](#input\_db\_edition) | Edicion de Cloud SQL. ENTERPRISE\_PLUS admite mas conexiones y mejor cache por vCPU, a mayor precio unitario. | `string` | `"ENTERPRISE"` | no |
| <a name="input_db_extra_flags"></a> [db\_extra\_flags](#input\_db\_extra\_flags) | Flags adicionales del motor, por si un ambiente necesita afinar. | `map(string)` | `{}` | no |
| <a name="input_db_highly_available"></a> [db\_highly\_available](#input\_db\_highly\_available) | Activa el standby sincrono en otra zona con failover automatico. Duplica el coste de computo de la instancia y elimina el punto unico de falla del plano de datos. | `bool` | `false` | no |
| <a name="input_db_log_min_duration_ms"></a> [db\_log\_min\_duration\_ms](#input\_db\_log\_min\_duration\_ms) | Umbral de consulta lenta registrada en Cloud Logging. | `number` | `1000` | no |
| <a name="input_db_maintenance_day"></a> [db\_maintenance\_day](#input\_db\_maintenance\_day) | 1 = lunes ... 7 = domingo. | `number` | `7` | no |
| <a name="input_db_maintenance_hour"></a> [db\_maintenance\_hour](#input\_db\_maintenance\_hour) | Hora UTC de inicio de la ventana de mantenimiento de Cloud SQL. | `number` | `3` | no |
| <a name="input_db_max_connections"></a> [db\_max\_connections](#input\_db\_max\_connections) | Conexiones simultaneas que admite el motor. Se fija junto a los maximos de instancias de Cloud Run. | `number` | `100` | no |
| <a name="input_db_name"></a> [db\_name](#input\_db\_name) | Nombre de la base de datos logica que usa la aplicacion. | `string` | `"proveedores"` | no |
| <a name="input_db_password_rotation_token"></a> [db\_password\_rotation\_token](#input\_db\_password\_rotation\_token) | Cambiar este valor regenera la contrasena administrativa. | `string` | `"v1"` | no |
| <a name="input_db_point_in_time_recovery"></a> [db\_point\_in\_time\_recovery](#input\_db\_point\_in\_time\_recovery) | Habilita la recuperacion a un instante concreto mediante registros WAL. | `bool` | `false` | no |
| <a name="input_db_retained_backups"></a> [db\_retained\_backups](#input\_db\_retained\_backups) | Numero de backups automaticos conservados. | `number` | `7` | no |
| <a name="input_db_tier"></a> [db\_tier](#input\_db\_tier) | Tipo de maquina de Cloud SQL. Es el parametro que mas pesa en el coste total de la plataforma. | `string` | `"db-custom-1-3840"` | no |
| <a name="input_db_transaction_log_retention_days"></a> [db\_transaction\_log\_retention\_days](#input\_db\_transaction\_log\_retention\_days) | Ventana en dias dentro de la cual se puede recuperar a un punto en el tiempo. | `number` | `7` | no |
| <a name="input_db_version"></a> [db\_version](#input\_db\_version) | Version del motor de PostgreSQL. Subirla implica reinicio, asi que se fija explicitamente. | `string` | `"POSTGRES_16"` | no |
| <a name="input_dlq_retention_duration"></a> [dlq\_retention\_duration](#input\_dlq\_retention\_duration) | Tiempo que un mensaje fallido espera en el DLQ a ser inspeccionado. | `string` | `"604800s"` | no |
| <a name="input_domains"></a> [domains](#input\_domains) | Dominios del certificado gestionado. | `list(string)` | `[]` | no |
| <a name="input_enable_adaptive_protection"></a> [enable\_adaptive\_protection](#input\_enable\_adaptive\_protection) | Deteccion adaptativa de DDoS L7. Requiere Cloud Armor Enterprise. | `bool` | `false` | no |
| <a name="input_enable_bigquery_sink"></a> [enable\_bigquery\_sink](#input\_enable\_bigquery\_sink) | Exporta los logs a BigQuery para analitica con SQL. Solo se justifica en produccion. | `bool` | `false` | no |
| <a name="input_enable_cloud_armor"></a> [enable\_cloud\_armor](#input\_enable\_cloud\_armor) | Activa el WAF y la limitacion de tasa delante del punto de entrada publico. | `bool` | `true` | no |
| <a name="input_enable_https"></a> [enable\_https](#input\_enable\_https) | Crea el certificado gestionado y la redireccion a HTTPS. false permite probar en dev sin DNS delegado. | `bool` | `true` | no |
| <a name="input_enable_nat"></a> [enable\_nat](#input\_enable\_nat) | Crea Cloud NAT para la subred interna. false deja al worker y a los jobs sin poder llamar a sistemas de terceros. | `bool` | `true` | no |
| <a name="input_error_rate_threshold"></a> [error\_rate\_threshold](#input\_error\_rate\_threshold) | Peticiones 5xx por segundo que disparan la alerta de errores. | `number` | `1` | no |
| <a name="input_exports_retention_days"></a> [exports\_retention\_days](#input\_exports\_retention\_days) | Dias que se conservan las salidas de los procesos batch. Son regenerables. | `number` | `30` | no |
| <a name="input_extra_labels"></a> [extra\_labels](#input\_extra\_labels) | Etiquetas adicionales que se anaden a las de la plataforma. | `map(string)` | `{}` | no |
| <a name="input_force_destroy_buckets"></a> [force\_destroy\_buckets](#input\_force\_destroy\_buckets) | true solo en dev/qa: permite un destroy limpio. | `bool` | `false` | no |
| <a name="input_frontend_keep_versions"></a> [frontend\_keep\_versions](#input\_frontend\_keep\_versions) | Versiones del build estatico que permiten revertir un despliegue. | `number` | `5` | no |
| <a name="input_github_repository"></a> [github\_repository](#input\_github\_repository) | Repositorio en formato owner/repo. Acota que workloads pueden impersonar la<br/>SA de despliegue en dev y qa. Obligatorio si se pasa wif\_pool\_name. | `string` | `""` | no |
| <a name="input_latency_p95_threshold_ms"></a> [latency\_p95\_threshold\_ms](#input\_latency\_p95\_threshold\_ms) | Latencia p95 en milisegundos que dispara la alerta de degradacion. | `number` | `2000` | no |
| <a name="input_log_index_fields"></a> [log\_index\_fields](#input\_log\_index\_fields) | Campos del jsonPayload que se indexan en el bucket de logs. Son del dominio<br/>de la aplicacion, no de la infraestructura. | `list(string)` | <pre>[<br/>  "jsonPayload.orderId",<br/>  "jsonPayload.supplierId"<br/>]</pre> | no |
| <a name="input_log_retention_days"></a> [log\_retention\_days](#input\_log\_retention\_days) | Dias que se conservan los logs en el bucket central. | `number` | `30` | no |
| <a name="input_name_prefix"></a> [name\_prefix](#input\_name\_prefix) | Prefijo de todos los nombres de recurso. | `string` | `null` | no |
| <a name="input_nat_min_ports_per_vm"></a> [nat\_min\_ports\_per\_vm](#input\_nat\_min\_ports\_per\_vm) | Puertos de origen que Cloud NAT reserva por instancia. Si se agotan, las conexiones salientes fallan de forma intermitente. | `number` | `64` | no |
| <a name="input_project_services"></a> [project\_services](#input\_project\_services) | APIs de GCP que la plataforma necesita habilitadas. | `list(string)` | <pre>[<br/>  "compute.googleapis.com",<br/>  "run.googleapis.com",<br/>  "sqladmin.googleapis.com",<br/>  "servicenetworking.googleapis.com",<br/>  "secretmanager.googleapis.com",<br/>  "artifactregistry.googleapis.com",<br/>  "pubsub.googleapis.com",<br/>  "cloudscheduler.googleapis.com",<br/>  "cloudbuild.googleapis.com",<br/>  "logging.googleapis.com",<br/>  "monitoring.googleapis.com",<br/>  "cloudtrace.googleapis.com",<br/>  "clouderrorreporting.googleapis.com",<br/>  "iam.googleapis.com",<br/>  "iamcredentials.googleapis.com",<br/>  "storage.googleapis.com",<br/>  "bigquery.googleapis.com",<br/>  "containerscanning.googleapis.com"<br/>]</pre> | no |
| <a name="input_protected_branch"></a> [protected\_branch](#input\_protected\_branch) | Rama desde la que se permite desplegar en prod. En prod el principal de CI/CD<br/>se acota a esta rama en lugar de al repositorio completo. | `string` | `"main"` | no |
| <a name="input_psa_prefix_length"></a> [psa\_prefix\_length](#input\_psa\_prefix\_length) | Longitud del prefijo del rango de Private Service Access. /20 da holgura para la instancia de Cloud SQL y sus replicas. | `number` | `20` | no |
| <a name="input_pubsub_topics"></a> [pubsub\_topics](#input\_pubsub\_topics) | Topics de eventos asincronos y la ruta del worker que los procesa. | <pre>map(object({<br/>    path                  = string<br/>    ack_deadline_seconds  = optional(number, 60)<br/>    retention_duration    = optional(string, "604800s")<br/>    max_delivery_attempts = optional(number, 5)<br/>    ordered               = optional(bool, false)<br/>    schema_id             = optional(string)<br/>  }))</pre> | `{}` | no |
| <a name="input_rate_limit_interval_sec"></a> [rate\_limit\_interval\_sec](#input\_rate\_limit\_interval\_sec) | Ventana en segundos sobre la que se cuenta el limite de tasa de Cloud Armor. | `number` | `60` | no |
| <a name="input_rate_limit_requests"></a> [rate\_limit\_requests](#input\_rate\_limit\_requests) | Peticiones por IP e intervalo antes del baneo temporal. | `number` | `300` | no |
| <a name="input_region"></a> [region](#input\_region) | Region principal. | `string` | `"europe-west1"` | no |
| <a name="input_registry_cleanup_dry_run"></a> [registry\_cleanup\_dry\_run](#input\_registry\_cleanup\_dry\_run) | true evalua las politicas de limpieza sin borrar nada. | `bool` | `false` | no |
| <a name="input_registry_immutable_tags"></a> [registry\_immutable\_tags](#input\_registry\_immutable\_tags) | Una etiqueta publicada no puede reescribirse. true en prod. | `bool` | `false` | no |
| <a name="input_registry_keep_recent_versions"></a> [registry\_keep\_recent\_versions](#input\_registry\_keep\_recent\_versions) | Versiones recientes que la limpieza conserva de cada imagen. Es lo que permite revertir a un release anterior. | `number` | `10` | no |
| <a name="input_registry_repository_id"></a> [registry\_repository\_id](#input\_registry\_repository\_id) | Nombre del repositorio de Artifact Registry. Fuente unica: el output image\_base se deriva de el. | `string` | `"plataforma"` | no |
| <a name="input_registry_tracked_images"></a> [registry\_tracked\_images](#input\_registry\_tracked\_images) | Imagenes cuyo historico se conserva. | `list(string)` | <pre>[<br/>  "api",<br/>  "worker",<br/>  "batch"<br/>]</pre> | no |
| <a name="input_registry_untagged_ttl_days"></a> [registry\_untagged\_ttl\_days](#input\_registry\_untagged\_ttl\_days) | Dias que sobrevive una imagen sin etiqueta antes de borrarse. Las huerfanas de builds fallidos son la principal fuente de crecimiento del registro. | `number` | `7` | no |
| <a name="input_runtime_deletion_protection"></a> [runtime\_deletion\_protection](#input\_runtime\_deletion\_protection) | Impide borrar los servicios de Cloud Run. true en prod. | `bool` | `false` | no |
| <a name="input_runtime_vpc_egress"></a> [runtime\_vpc\_egress](#input\_runtime\_vpc\_egress) | ALL\_TRAFFIC envia toda la salida por la VPC, y es lo que hace que la<br/>topologia de subredes sea un control real de seguridad (ver D5b).<br/>Cambiarlo a PRIVATE\_RANGES\_ONLY desactiva ese control. | `string` | `"ALL_TRAFFIC"` | no |
| <a name="input_secret_version"></a> [secret\_version](#input\_secret\_version) | Version de los secretos que montan los runtimes. "latest" hace que una<br/>rotacion se recoja en el siguiente despliegue; fijar un numero da control<br/>total a costa de tener que actualizarlo a mano al rotar. | `string` | `"latest"` | no |
| <a name="input_startup_probe_delay"></a> [startup\_probe\_delay](#input\_startup\_probe\_delay) | Segundos de espera antes de la primera sonda de arranque de los runtimes. | `number` | `5` | no |
| <a name="input_startup_probe_failures"></a> [startup\_probe\_failures](#input\_startup\_probe\_failures) | Intentos antes de declarar fallido el arranque. | `number` | `12` | no |
| <a name="input_storage_backup_location"></a> [storage\_backup\_location](#input\_storage\_backup\_location) | Ubicacion del bucket de backups. En produccion, distinta de la region principal. | `string` | `"EUROPE-WEST4"` | no |
| <a name="input_storage_location"></a> [storage\_location](#input\_storage\_location) | Ubicacion de los buckets operativos. Una multi-region sobrevive a la perdida de una region. | `string` | `"EU"` | no |
| <a name="input_time_zone"></a> [time\_zone](#input\_time\_zone) | Zona horaria en la que se interpretan las expresiones cron de los procesos batch. | `string` | `"Europe/Madrid"` | no |
| <a name="input_uploads_retention_days"></a> [uploads\_retention\_days](#input\_uploads\_retention\_days) | Retencion inmutable de los archivos subidos, en dias. 0 la desactiva. | `number` | `0` | no |
| <a name="input_uploads_storage_class_transitions"></a> [uploads\_storage\_class\_transitions](#input\_uploads\_storage\_class\_transitions) | Bajadas de clase de almacenamiento por edad de los archivos subidos. | <pre>list(object({<br/>    age_days      = number<br/>    storage_class = string<br/>  }))</pre> | <pre>[<br/>  {<br/>    "age_days": 90,<br/>    "storage_class": "NEARLINE"<br/>  },<br/>  {<br/>    "age_days": 365,<br/>    "storage_class": "COLDLINE"<br/>  }<br/>]</pre> | no |
| <a name="input_uptime_check_regions"></a> [uptime\_check\_regions](#input\_uptime\_check\_regions) | Regiones desde las que se comprueba la disponibilidad. | `list(string)` | <pre>[<br/>  "EUROPE",<br/>  "USA",<br/>  "SOUTH_AMERICA"<br/>]</pre> | no |
| <a name="input_vpc_flow_sampling"></a> [vpc\_flow\_sampling](#input\_vpc\_flow\_sampling) | Fraccion de flujos VPC registrados. Mas alto en prod. | `number` | `0.1` | no |
| <a name="input_waf_preview_mode"></a> [waf\_preview\_mode](#input\_waf\_preview\_mode) | Deja las reglas del WAF en observacion: registran lo que bloquearian sin bloquear. Es como deben estrenarse, para detectar falsos positivos. | `bool` | `true` | no |
| <a name="input_wif_pool_name"></a> [wif\_pool\_name](#input\_wif\_pool\_name) | Nombre completo del pool de Workload Identity Federation que crea el<br/>bootstrap, en formato<br/>projects/<numero>/locations/global/workloadIdentityPools/<id>.<br/><br/>Es la salida `workload_identity_pool` del bootstrap del ambiente. Vacio<br/>desactiva el binding que permite a GitHub Actions impersonar la SA de<br/>despliegue, lo que deja operativo solo el pipeline de Cloud Build. | `string` | `""` | no |
| <a name="input_worker_cpu"></a> [worker\_cpu](#input\_worker\_cpu) | vCPU por instancia del worker. | `string` | `"1"` | no |
| <a name="input_worker_cpu_idle"></a> [worker\_cpu\_idle](#input\_worker\_cpu\_idle) | false mantiene CPU tras el ack: el worker sigue trabajando. | `bool` | `false` | no |
| <a name="input_worker_image"></a> [worker\_image](#input\_worker\_image) | Imagen del worker. La gobierna el pipeline de aplicacion; el modulo ignora sus cambios para no revertir despliegues. | `string` | `"us-docker.pkg.dev/cloudrun/container/hello"` | no |
| <a name="input_worker_ingress"></a> [worker\_ingress](#input\_worker\_ingress) | Ingress del worker. INGRESS\_TRAFFIC\_INTERNAL\_ONLY es lo mas restrictivo y<br/>es el valor por defecto. Si las entregas push de Pub/Sub no llegasen a<br/>considerarse trafico interno en esta configuracion, el ajuste es<br/>INGRESS\_TRAFFIC\_ALL: la autorizacion no se debilita, porque el worker sigue<br/>exigiendo token OIDC y solo la service account de Pub/Sub tiene<br/>roles/run.invoker sobre el. Es el primer punto a verificar en un apply real. | `string` | `"INGRESS_TRAFFIC_INTERNAL_ONLY"` | no |
| <a name="input_worker_max_concurrency"></a> [worker\_max\_concurrency](#input\_worker\_max\_concurrency) | Mensajes simultaneos por instancia del worker. | `number` | `10` | no |
| <a name="input_worker_max_instances"></a> [worker\_max\_instances](#input\_worker\_max\_instances) | Techo de escalado del worker. Cuenta, junto al del API, para el reparto del pool de conexiones. | `number` | `5` | no |
| <a name="input_worker_memory"></a> [worker\_memory](#input\_worker\_memory) | Memoria por instancia del worker. | `string` | `"512Mi"` | no |
| <a name="input_worker_min_instances"></a> [worker\_min\_instances](#input\_worker\_min\_instances) | Instancias del worker siempre activas. Mayor que 0 evita latencia en el primer evento tras un periodo sin trafico. | `number` | `0` | no |
| <a name="input_worker_request_timeout_seconds"></a> [worker\_request\_timeout\_seconds](#input\_worker\_request\_timeout\_seconds) | Un intercambio con un tercero puede tardar mas que una request de usuario. | `number` | `300` | no |
| <a name="input_worker_tmp_size_limit"></a> [worker\_tmp\_size\_limit](#input\_worker\_tmp\_size\_limit) | Tamano del volumen temporal del worker. Cuenta contra worker\_memory. | `string` | `"64Mi"` | no |

### Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_ambiente"></a> [ambiente](#output\_ambiente) | Ambiente desplegado por esta instancia del modulo. |
| <a name="output_api_internal_uri"></a> [api\_internal\_uri](#output\_api\_internal\_uri) | URL run.app del API. Con el ingress restringido NO es accesible desde Internet. |
| <a name="output_api_service_name"></a> [api\_service\_name](#output\_api\_service\_name) | Nombre del servicio de Cloud Run del API. |
| <a name="output_batch_job_names"></a> [batch\_job\_names](#output\_batch\_job\_names) | Nombre de cada job batch creado. |
| <a name="output_buckets"></a> [buckets](#output\_buckets) | Nombre de los cuatro buckets de la plataforma, indexados por proposito. |
| <a name="output_dashboard_id"></a> [dashboard\_id](#output\_dashboard\_id) | Dashboard de estado de la plataforma. |
| <a name="output_db_connection_name"></a> [db\_connection\_name](#output\_db\_connection\_name) | Cadena proyecto:region:instancia que consume el conector de Node.js. |
| <a name="output_db_instance_name"></a> [db\_instance\_name](#output\_db\_instance\_name) | Nombre de la instancia de Cloud SQL. |
| <a name="output_db_private_ip"></a> [db\_private\_ip](#output\_db\_private\_ip) | IP privada de la instancia de Cloud SQL. Marcada como sensible porque revela el direccionamiento interno. |
| <a name="output_db_secret_ids"></a> [db\_secret\_ids](#output\_db\_secret\_ids) | Secretos en Secret Manager. Nunca el valor, solo la referencia. |
| <a name="output_deployer_service_account"></a> [deployer\_service\_account](#output\_deployer\_service\_account) | SA que debe impersonar el pipeline de CI/CD. |
| <a name="output_image_base"></a> [image\_base](#output\_image\_base) | Prefijo para etiquetar las imagenes del pipeline. |
| <a name="output_lb_ip_address"></a> [lb\_ip\_address](#output\_lb\_ip\_address) | IP global. Crear el registro A del dominio apuntando aqui. |
| <a name="output_log_bucket"></a> [log\_bucket](#output\_log\_bucket) | Bucket central de logs. |
| <a name="output_name_prefix"></a> [name\_prefix](#output\_name\_prefix) | Prefijo aplicado a los nombres de todos los recursos. |
| <a name="output_nat_ip"></a> [nat\_ip](#output\_nat\_ip) | IP de salida para allowlists de sistemas de terceros. |
| <a name="output_network_name"></a> [network\_name](#output\_network\_name) | Nombre de la VPC del ambiente. |
| <a name="output_public_url"></a> [public\_url](#output\_public\_url) | URL publica de la plataforma. Con HTTPS desactivado, la IP del balanceador. |
| <a name="output_pubsub_dlq"></a> [pubsub\_dlq](#output\_pubsub\_dlq) | Topic de la cola de mensajes fallidos. |
| <a name="output_pubsub_topics"></a> [pubsub\_topics](#output\_pubsub\_topics) | Topics de eventos creados, indexados por dominio. |
| <a name="output_region"></a> [region](#output\_region) | Region principal del despliegue. |
| <a name="output_service_accounts"></a> [service\_accounts](#output\_service\_accounts) | Identidad de cada componente, para auditoria de permisos. |
| <a name="output_subnet_app_name"></a> [subnet\_app\_name](#output\_subnet\_app\_name) | Subred del API, la que no tiene salida a Internet. |
| <a name="output_worker_service_name"></a> [worker\_service\_name](#output\_worker\_service\_name) | Nombre del servicio de Cloud Run del worker. |
<!-- END_TF_DOCS -->
