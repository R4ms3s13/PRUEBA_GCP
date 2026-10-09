# `frontend_lb`

Punto de entrada publico: balanceador global, CDN y Cloud Armor.

## Proposito

Un **unico** dominio sirve las dos cosas y evita CORS en el navegador:

| Ruta | Destino |
|---|---|
| `/` | Backend bucket con el build de React, cacheado en Cloud CDN |
| `/api/*` | Serverless NEG hacia el servicio Cloud Run del API |

## Decisiones

- **El frontend en un bucket y no en un contenedor.** Un SPA compilado es un
  conjunto de ficheros estaticos; servirlo desde Cloud Run es pagar CPU por
  devolver bytes que el CDN entrega desde el borde.
- **Un solo punto de entrada publico.** Es lo unico expuesto, y por tanto lo
  unico que hay que proteger: Cloud Armor va delante.
- **El API no cachea.** Son datos de pedidos por usuario.

## Cache del CDN

Los assets del SPA llevan hash en el nombre, de modo que pueden cachearse mucho
tiempo. **`index.html` se publica con `no-cache` desde el pipeline**, para que un
despliegue sea visible de inmediato. Invertir esto hace que un despliegue tarde
horas en verse, o que el navegador pida los assets en cada carga.

## Cloud Armor

`waf_preview_mode = true` por defecto. Las reglas preconfiguradas de OWASP
generan falsos positivos sobre aplicaciones reales (un campo de texto con
comillas puede parecer SQLi). Se estrenan en observacion, se revisa en los logs
que habrian bloqueado, y solo entonces se pasa a bloqueo.

`enable_adaptive_protection` requiere suscripcion a **Cloud Armor Enterprise**.
Activarlo sin ella hace fallar el apply, de ahi que venga desactivado: es una
decision de contratacion, no tecnica.

## Primer apply

El certificado gestionado requiere que el DNS **ya apunte** a la IP del
balanceador, asi que el primer apply lo deja en `PROVISIONING`. Pasa a `ACTIVE`
entre 15 y 60 minutos despues de crear el registro A.

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
| [google_compute_backend_bucket.frontend](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_backend_bucket) | resource |
| [google_compute_backend_service.api](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_backend_service) | resource |
| [google_compute_global_address.lb](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_global_address) | resource |
| [google_compute_global_forwarding_rule.http](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_global_forwarding_rule) | resource |
| [google_compute_global_forwarding_rule.https](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_global_forwarding_rule) | resource |
| [google_compute_managed_ssl_certificate.cert](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_managed_ssl_certificate) | resource |
| [google_compute_region_network_endpoint_group.api](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_region_network_endpoint_group) | resource |
| [google_compute_security_policy.armor](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_security_policy) | resource |
| [google_compute_ssl_policy.modern](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_ssl_policy) | resource |
| [google_compute_target_http_proxy.http](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_target_http_proxy) | resource |
| [google_compute_target_https_proxy.https](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_target_https_proxy) | resource |
| [google_compute_url_map.main](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_url_map) | resource |
| [google_compute_url_map.redirect](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_url_map) | resource |

### Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_api_service_name"></a> [api\_service\_name](#input\_api\_service\_name) | Nombre del servicio Cloud Run del API al que apunta el NEG. | `string` | n/a | yes |
| <a name="input_env"></a> [env](#input\_env) | Identificador del ambiente (dev, qa o prod). Se usa en nombres, etiquetas y decisiones condicionales. | `string` | n/a | yes |
| <a name="input_frontend_bucket_name"></a> [frontend\_bucket\_name](#input\_frontend\_bucket\_name) | Bucket con el build estatico del SPA. | `string` | n/a | yes |
| <a name="input_name_prefix"></a> [name\_prefix](#input\_name\_prefix) | Prefijo comun de los nombres de recurso del modulo. | `string` | n/a | yes |
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | ID del proyecto de GCP donde se crean los recursos. | `string` | n/a | yes |
| <a name="input_region"></a> [region](#input\_region) | Region de GCP donde se despliegan los recursos regionales. | `string` | n/a | yes |
| <a name="input_api_path_patterns"></a> [api\_path\_patterns](#input\_api\_path\_patterns) | Rutas que el balanceador enruta al API en lugar del bucket. | `list(string)` | <pre>[<br/>  "/api",<br/>  "/api/*"<br/>]</pre> | no |
| <a name="input_api_timeout_sec"></a> [api\_timeout\_sec](#input\_api\_timeout\_sec) | Tiempo que el balanceador espera la respuesta del API antes de cortar la conexion. | `number` | `60` | no |
| <a name="input_cdn_cache_mode"></a> [cdn\_cache\_mode](#input\_cdn\_cache\_mode) | Politica de cache del CDN. CACHE\_ALL\_STATIC cachea el contenido estatico detectado automaticamente. | `string` | `"CACHE_ALL_STATIC"` | no |
| <a name="input_cdn_client_ttl"></a> [cdn\_client\_ttl](#input\_cdn\_client\_ttl) | Tiempo que el navegador conserva el recurso en su cache local. | `number` | `3600` | no |
| <a name="input_cdn_default_ttl"></a> [cdn\_default\_ttl](#input\_cdn\_default\_ttl) | Tiempo por defecto que el CDN conserva un recurso sin cabecera de cache explicita. | `number` | `3600` | no |
| <a name="input_cdn_max_ttl"></a> [cdn\_max\_ttl](#input\_cdn\_max\_ttl) | Techo del tiempo de cache, aunque el origen pida mas. | `number` | `86400` | no |
| <a name="input_cdn_negative_ttl"></a> [cdn\_negative\_ttl](#input\_cdn\_negative\_ttl) | Cache de respuestas 404. | `number` | `60` | no |
| <a name="input_cdn_serve_while_stale"></a> [cdn\_serve\_while\_stale](#input\_cdn\_serve\_while\_stale) | Segundos que se sirve contenido caducado mientras revalida. | `number` | `86400` | no |
| <a name="input_domains"></a> [domains](#input\_domains) | Dominios del certificado gestionado. Vacio en dev (solo HTTP). | `list(string)` | `[]` | no |
| <a name="input_enable_adaptive_protection"></a> [enable\_adaptive\_protection](#input\_enable\_adaptive\_protection) | Deteccion adaptativa de DDoS de capa 7. Requiere suscripcion a Cloud Armor<br/>Enterprise; sin ella el apply falla. Desactivado por defecto a proposito. | `bool` | `false` | no |
| <a name="input_enable_cloud_armor"></a> [enable\_cloud\_armor](#input\_enable\_cloud\_armor) | Activa el WAF y la limitacion de tasa delante del punto de entrada publico. | `bool` | `true` | no |
| <a name="input_enable_https"></a> [enable\_https](#input\_enable\_https) | false permite probar en dev sin tener DNS delegado todavia. | `bool` | `true` | no |
| <a name="input_health_path"></a> [health\_path](#input\_health\_path) | Ruta de salud que expone el API. Contrato con desarrollo. | `string` | `"/healthz"` | no |
| <a name="input_min_tls_version"></a> [min\_tls\_version](#input\_min\_tls\_version) | Version minima de TLS aceptada. | `string` | `"TLS_1_2"` | no |
| <a name="input_rate_limit_ban_seconds"></a> [rate\_limit\_ban\_seconds](#input\_rate\_limit\_ban\_seconds) | Duracion del baneo temporal tras superar el limite de tasa. | `number` | `300` | no |
| <a name="input_rate_limit_interval_sec"></a> [rate\_limit\_interval\_sec](#input\_rate\_limit\_interval\_sec) | Ventana en segundos sobre la que se cuenta el limite de tasa. | `number` | `60` | no |
| <a name="input_rate_limit_requests"></a> [rate\_limit\_requests](#input\_rate\_limit\_requests) | Peticiones por IP y por intervalo antes de aplicar el baneo temporal. | `number` | `300` | no |
| <a name="input_ssl_profile"></a> [ssl\_profile](#input\_ssl\_profile) | Perfil de suites criptograficas. MODERN rechaza las obsoletas. | `string` | `"MODERN"` | no |
| <a name="input_waf_preview_mode"></a> [waf\_preview\_mode](#input\_waf\_preview\_mode) | true deja las reglas del WAF en modo observacion: registran lo que<br/>bloquearian sin bloquear. Es como deben estrenarse en prod, revisando<br/>falsos positivos antes de aplicar. | `bool` | `true` | no |

### Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_api_backend_service_id"></a> [api\_backend\_service\_id](#output\_api\_backend\_service\_id) | Backend service que apunta al API mediante serverless NEG. |
| <a name="output_frontend_backend_bucket_id"></a> [frontend\_backend\_bucket\_id](#output\_frontend\_backend\_bucket\_id) | Backend bucket que sirve el build estatico. |
| <a name="output_lb_ip_address"></a> [lb\_ip\_address](#output\_lb\_ip\_address) | IP global a la que debe apuntar el registro A del dominio. |
| <a name="output_public_url"></a> [public\_url](#output\_public\_url) | URL publica de entrada. Con HTTPS desactivado devuelve la IP del balanceador. |
| <a name="output_security_policy_id"></a> [security\_policy\_id](#output\_security\_policy\_id) | Politica de Cloud Armor asociada al backend del API. null si el WAF esta desactivado. |
| <a name="output_url_map_id"></a> [url\_map\_id](#output\_url\_map\_id) | Identificador del mapa de URL, necesario para invalidar la cache del CDN. |
<!-- END_TF_DOCS -->
