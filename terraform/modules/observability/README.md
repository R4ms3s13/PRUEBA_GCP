# `observability`

Logs centralizados, metricas, dashboard y ocho alertas accionables.

## Proposito

Que un incidente se detecte desde fuera, se localice en el plano correcto y
tenga procedimiento escrito.

## Que aporta cada pieza

| Pieza | Por que esta |
|---|---|
| Bucket de logs dedicado | Retencion propia y consultas sobre el historico, sin depender de los 30 dias por defecto |
| Sink a BigQuery | Solo en produccion. Analitica de negocio sobre los logs con SQL |
| Metricas basadas en log | Convierten patrones de log en series alertables **sin instrumentar la aplicacion** |
| Uptime check | Vigila desde fuera. Es la unica senal que detecta una caida del propio balanceador o del DNS |
| Alertas | El minimo accionable |
| Dashboard | Una pantalla con los cuatro planos: entrada, computo, datos y asincrono |

## Criterio de las alertas

**Cada alerta debe tener una accion clara asociada.** Mas alertas que capacidad
de respuesta producen ruido, se silencian, y entonces no sirve ninguna.

Las criticas llevan el procedimiento escrito en el propio recurso
(`documentation`), que es donde se lee a las tres de la manana.

Se alerta sobre **p95** de latencia, no sobre la media: la media esconde la
cola, y la cola es lo que sufre el usuario.

**Lo que deliberadamente no se alerta:** metricas sin accion asociada. Van al
dashboard, que es donde se mira cuando ya hay un incidente.

## Coste

La exclusion de health checks es la medida de ahorro mas directa: son el ~99 %
del volumen de logs del balanceador y no informan de nada.

> El sink al bucket central usa `unique_writer_identity`, lo que exige concederle
> `roles/logging.bucketWriter`. Sin ese binding **el sink se crea sin error y no
> entrega nada**: un fallo silencioso. El modulo lo incluye.

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
| [google_bigquery_dataset.logs](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/bigquery_dataset) | resource |
| [google_bigquery_dataset_iam_member.sink_writer](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/bigquery_dataset_iam_member) | resource |
| [google_logging_metric.app_errors](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/logging_metric) | resource |
| [google_logging_metric.auth_failures](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/logging_metric) | resource |
| [google_logging_metric.slow_queries](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/logging_metric) | resource |
| [google_logging_project_bucket_config.central](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/logging_project_bucket_config) | resource |
| [google_logging_project_exclusion.health_checks](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/logging_project_exclusion) | resource |
| [google_logging_project_sink.bigquery](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/logging_project_sink) | resource |
| [google_logging_project_sink.central](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/logging_project_sink) | resource |
| [google_monitoring_alert_policy.batch_failures](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/monitoring_alert_policy) | resource |
| [google_monitoring_alert_policy.db_cpu](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/monitoring_alert_policy) | resource |
| [google_monitoring_alert_policy.db_disk](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/monitoring_alert_policy) | resource |
| [google_monitoring_alert_policy.dlq_messages](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/monitoring_alert_policy) | resource |
| [google_monitoring_alert_policy.error_rate_5xx](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/monitoring_alert_policy) | resource |
| [google_monitoring_alert_policy.latency_p95](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/monitoring_alert_policy) | resource |
| [google_monitoring_alert_policy.run_saturation](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/monitoring_alert_policy) | resource |
| [google_monitoring_alert_policy.uptime](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/monitoring_alert_policy) | resource |
| [google_monitoring_dashboard.main](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/monitoring_dashboard) | resource |
| [google_monitoring_notification_channel.email](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/monitoring_notification_channel) | resource |
| [google_monitoring_uptime_check_config.public](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/monitoring_uptime_check_config) | resource |
| [google_project_iam_member.sink_bucket_writer](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/project_iam_member) | resource |

### Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_api_max_instances"></a> [api\_max\_instances](#input\_api\_max\_instances) | Techo de escalado del API. Se usa para calcular el umbral de la alerta de saturacion. | `number` | n/a | yes |
| <a name="input_api_service_name"></a> [api\_service\_name](#input\_api\_service\_name) | Nombre del servicio de Cloud Run del API, para filtrar sus metricas en las alertas y el dashboard. | `string` | n/a | yes |
| <a name="input_db_instance_name"></a> [db\_instance\_name](#input\_db\_instance\_name) | Nombre de la instancia de Cloud SQL, para filtrar sus metricas en las alertas. | `string` | n/a | yes |
| <a name="input_dlq_subscription_name"></a> [dlq\_subscription\_name](#input\_dlq\_subscription\_name) | Suscripcion de la cola de mensajes fallidos que vigila la alerta de DLQ. | `string` | n/a | yes |
| <a name="input_env"></a> [env](#input\_env) | Identificador del ambiente (dev, qa o prod). Se usa en nombres, etiquetas y decisiones condicionales. | `string` | n/a | yes |
| <a name="input_health_path"></a> [health\_path](#input\_health\_path) | Ruta de salud que expone la aplicacion. Es CONTRATO con el equipo de<br/>desarrollo y se usa en tres sitios (uptime check, exclusion de logs y<br/>enrutado del balanceador), asi que viaja como variable y no escrita a mano<br/>en cada uno. | `string` | n/a | yes |
| <a name="input_name_prefix"></a> [name\_prefix](#input\_name\_prefix) | Prefijo comun de los nombres de recurso del modulo. | `string` | n/a | yes |
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | ID del proyecto de GCP donde se crean los recursos. | `string` | n/a | yes |
| <a name="input_region"></a> [region](#input\_region) | Region de GCP donde se despliegan los recursos regionales. | `string` | n/a | yes |
| <a name="input_alert_emails"></a> [alert\_emails](#input\_alert\_emails) | Mapa etiqueta => email. Mapa y no lista para que renombrar uno no recree los demas. | `map(string)` | `{}` | no |
| <a name="input_bigquery_location"></a> [bigquery\_location](#input\_bigquery\_location) | Ubicacion del dataset de analitica de logs. | `string` | `"EU"` | no |
| <a name="input_bigquery_table_expiration_days"></a> [bigquery\_table\_expiration\_days](#input\_bigquery\_table\_expiration\_days) | Dias tras los que caducan las tablas particionadas de logs en BigQuery. | `number` | `90` | no |
| <a name="input_db_cpu_threshold"></a> [db\_cpu\_threshold](#input\_db\_cpu\_threshold) | Fraccion de CPU de Cloud SQL que dispara la alerta. | `number` | `0.8` | no |
| <a name="input_db_disk_threshold"></a> [db\_disk\_threshold](#input\_db\_disk\_threshold) | Fraccion de disco de Cloud SQL que dispara la alerta. | `number` | `0.85` | no |
| <a name="input_enable_bigquery_sink"></a> [enable\_bigquery\_sink](#input\_enable\_bigquery\_sink) | Exporta los logs a BigQuery para analitica con SQL. Solo se justifica en produccion. | `bool` | `false` | no |
| <a name="input_error_rate_threshold"></a> [error\_rate\_threshold](#input\_error\_rate\_threshold) | Peticiones 5xx por segundo que disparan la alerta. | `number` | `1` | no |
| <a name="input_labels"></a> [labels](#input\_labels) | Etiquetas aplicadas a los recursos que las admiten, para repartir costes y filtrar en facturacion. | `map(string)` | `{}` | no |
| <a name="input_latency_p95_threshold_ms"></a> [latency\_p95\_threshold\_ms](#input\_latency\_p95\_threshold\_ms) | Latencia p95 en milisegundos que dispara la alerta de degradacion. | `number` | `2000` | no |
| <a name="input_log_index_fields"></a> [log\_index\_fields](#input\_log\_index\_fields) | Campos del jsonPayload que se indexan en el bucket de logs. Son propios del<br/>dominio de la aplicacion (identificadores de pedido, de proveedor), no de la<br/>infraestructura, de modo que los decide quien conoce el modelo de datos. | `list(string)` | `[]` | no |
| <a name="input_log_retention_days"></a> [log\_retention\_days](#input\_log\_retention\_days) | Dias que se conservan los logs en el bucket central. | `number` | `30` | no |
| <a name="input_run_saturation_ratio"></a> [run\_saturation\_ratio](#input\_run\_saturation\_ratio) | Fraccion de max\_instances a partir de la cual se alerta. | `number` | `0.8` | no |
| <a name="input_uptime_check_host"></a> [uptime\_check\_host](#input\_uptime\_check\_host) | Host publico a comprobar. null desactiva el check (dev sin DNS). | `string` | `null` | no |
| <a name="input_uptime_check_regions"></a> [uptime\_check\_regions](#input\_uptime\_check\_regions) | Regiones desde las que se comprueba la disponibilidad. | `list(string)` | <pre>[<br/>  "EUROPE",<br/>  "USA",<br/>  "SOUTH_AMERICA"<br/>]</pre> | no |

### Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_bigquery_logs_dataset"></a> [bigquery\_logs\_dataset](#output\_bigquery\_logs\_dataset) | Dataset de analitica de logs. null si el sink a BigQuery esta desactivado. |
| <a name="output_dashboard_id"></a> [dashboard\_id](#output\_dashboard\_id) | Dashboard de estado de los cuatro planos de la plataforma. |
| <a name="output_log_bucket_id"></a> [log\_bucket\_id](#output\_log\_bucket\_id) | Bucket central de logs del ambiente. |
| <a name="output_notification_channel_ids"></a> [notification\_channel\_ids](#output\_notification\_channel\_ids) | Canales a los que se envian las alertas. |
| <a name="output_uptime_check_id"></a> [uptime\_check\_id](#output\_uptime\_check\_id) | Identificador del uptime check, necesario para filtrar su metrica en la alerta. null si no hay dominio. |
<!-- END_TF_DOCS -->
