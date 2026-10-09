# `storage`

Cuatro buckets con responsabilidades, permisos y ciclos de vida separados.

## Proposito

| Bucket | Contenido | Acceso publico |
|---|---|---|
| `frontend` | Build estatico del SPA, servido por el balanceador | Si, por diseno |
| `uploads` | Archivos de proveedores y pedidos | **Bloqueado** |
| `exports` | Salidas de los procesos batch | **Bloqueado** |
| `db-backups` | Volcados logicos de la base de datos | **Bloqueado** |

Son cuatro y no uno porque sus permisos y sus politicas de retencion no se
parecen en nada, y mezclarlos obligaria a conceder mas de lo necesario.

## Decisiones

- **`uniform_bucket_level_access` en todos.** Las ACL por objeto son una fuente
  clasica de fugas y ademas impiden razonar sobre los permisos desde IAM.
- **`public_access_prevention = enforced`** en los tres que contienen datos.
- **CORS en `uploads`** para subida directa desde el navegador con URL firmada:
  el fichero no atraviesa Cloud Run, lo que evita el limite de tamano de
  peticion y ahorra CPU.
- **Retencion inmutable opcional** en `uploads`, para documentacion mercantil.

> **Interaccion a tener presente:** si `uploads_retention_days > 0` hay una
> politica de retencion, y GCS **no** borra un objeto todavia bajo retencion.
> La regla de ciclo de vida que limpia versiones antiguas solo surte efecto una
> vez vencida. Es intencionado: la retencion manda sobre el ahorro.

## Dependencia externa

El bucket de frontend necesita lectura publica. **Si la organizacion aplica una
politica que fuerza `public_access_prevention = enforced`, el apply falla aqui.**
Es el unico punto del repositorio que depende de una politica externa.

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
| [google_storage_bucket.db_backups](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/storage_bucket) | resource |
| [google_storage_bucket.exports](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/storage_bucket) | resource |
| [google_storage_bucket.frontend](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/storage_bucket) | resource |
| [google_storage_bucket.uploads](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/storage_bucket) | resource |
| [google_storage_bucket_iam_member.frontend_public](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/storage_bucket_iam_member) | resource |

### Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_backup_location"></a> [backup\_location](#input\_backup\_location) | Ubicacion de los backups. En prod, distinta de la region principal. | `string` | n/a | yes |
| <a name="input_env"></a> [env](#input\_env) | Identificador del ambiente (dev, qa o prod). Se usa en nombres, etiquetas y decisiones condicionales. | `string` | n/a | yes |
| <a name="input_location"></a> [location](#input\_location) | Ubicacion de los buckets operativos (region o multi-region). | `string` | n/a | yes |
| <a name="input_name_prefix"></a> [name\_prefix](#input\_name\_prefix) | Prefijo comun de todos los nombres de recurso del modulo. Hace que los recursos de un ambiente se reconozcan de un vistazo. | `string` | n/a | yes |
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | ID del proyecto de GCP donde se crean los recursos. | `string` | n/a | yes |
| <a name="input_project_number"></a> [project\_number](#input\_project\_number) | Se usa como sufijo para que los nombres de bucket sean globalmente unicos. | `string` | n/a | yes |
| <a name="input_cors_max_age_seconds"></a> [cors\_max\_age\_seconds](#input\_cors\_max\_age\_seconds) | Tiempo que el navegador cachea la respuesta preflight de CORS, evitando una peticion OPTIONS por cada subida. | `number` | `3600` | no |
| <a name="input_cors_methods"></a> [cors\_methods](#input\_cors\_methods) | Metodos HTTP permitidos en las peticiones CORS al bucket de subidas. PUT y POST son los que usa la subida directa con URL firmada. | `list(string)` | <pre>[<br/>  "GET",<br/>  "PUT",<br/>  "POST",<br/>  "HEAD"<br/>]</pre> | no |
| <a name="input_cors_origins"></a> [cors\_origins](#input\_cors\_origins) | Origenes permitidos para subida directa con URL firmada. | `list(string)` | `[]` | no |
| <a name="input_cors_response_headers"></a> [cors\_response\_headers](#input\_cors\_response\_headers) | Cabeceras que el navegador puede leer en la respuesta del bucket. Content-MD5 permite al cliente verificar la integridad de lo subido. | `list(string)` | <pre>[<br/>  "Content-Type",<br/>  "Content-MD5",<br/>  "x-goog-resumable"<br/>]</pre> | no |
| <a name="input_db_backup_retention_days"></a> [db\_backup\_retention\_days](#input\_db\_backup\_retention\_days) | Dias que se conservan los volcados logicos de la base de datos. | `number` | `30` | no |
| <a name="input_exports_retention_days"></a> [exports\_retention\_days](#input\_exports\_retention\_days) | Dias que se conservan las salidas de los procesos batch. Son regenerables, de modo que no se guardan indefinidamente. | `number` | `30` | no |
| <a name="input_force_destroy"></a> [force\_destroy](#input\_force\_destroy) | Permite destruir buckets con contenido. Debe ser false en prod. | `bool` | `false` | no |
| <a name="input_frontend_keep_versions"></a> [frontend\_keep\_versions](#input\_frontend\_keep\_versions) | Versiones del build estatico que se conservan para poder revertir. | `number` | `5` | no |
| <a name="input_uploads_keep_versions"></a> [uploads\_keep\_versions](#input\_uploads\_keep\_versions) | Versiones archivadas que se conservan de cada objeto. | `number` | `3` | no |
| <a name="input_uploads_retention_days"></a> [uploads\_retention\_days](#input\_uploads\_retention\_days) | Retencion inmutable de los archivos subidos. 0 la desactiva (dev/qa). | `number` | `0` | no |
| <a name="input_uploads_storage_class_transitions"></a> [uploads\_storage\_class\_transitions](#input\_uploads\_storage\_class\_transitions) | Transiciones de clase de almacenamiento por edad. El acceso a documentos de<br/>pedidos cae con el tiempo, asi que bajarlos de clase es ahorro directo sin<br/>perder disponibilidad. | <pre>list(object({<br/>    age_days      = number<br/>    storage_class = string<br/>  }))</pre> | <pre>[<br/>  {<br/>    "age_days": 90,<br/>    "storage_class": "NEARLINE"<br/>  },<br/>  {<br/>    "age_days": 365,<br/>    "storage_class": "COLDLINE"<br/>  }<br/>]</pre> | no |

### Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_db_backups_bucket_name"></a> [db\_backups\_bucket\_name](#output\_db\_backups\_bucket\_name) | Bucket de volcados logicos de la base de datos. |
| <a name="output_exports_bucket_name"></a> [exports\_bucket\_name](#output\_exports\_bucket\_name) | Bucket de salidas de los procesos batch. |
| <a name="output_frontend_bucket_name"></a> [frontend\_bucket\_name](#output\_frontend\_bucket\_name) | Bucket del build estatico del SPA. |
| <a name="output_frontend_bucket_self_link"></a> [frontend\_bucket\_self\_link](#output\_frontend\_bucket\_self\_link) | Enlace propio del bucket de frontend. |
| <a name="output_uploads_bucket_name"></a> [uploads\_bucket\_name](#output\_uploads\_bucket\_name) | Bucket de archivos subidos por los usuarios. |
<!-- END_TF_DOCS -->
