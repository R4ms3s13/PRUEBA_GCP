# `registry`

Registro privado de imagenes con limpieza automatica.

## Proposito

Un repositorio Docker de Artifact Registry por ambiente, con politicas de
limpieza para que el coste no crezca sin limite.

## Decisiones

- **Un repositorio por ambiente**, no uno compartido. Un repositorio comun
  ahorraria almacenamiento y permitiria promocionar la misma imagen por digest,
  pero obligaria a que el runtime de produccion tuviera lectura sobre un recurso
  que tambien escribe el CI de dev. La promocion se resuelve copiando por digest
  en el pipeline.
- **`immutable_tags` en produccion.** Una etiqueta publicada no puede
  reescribirse: garantiza que el digest desplegado es el que se construyo.
- **Limpieza automatica.** Sin ella el registro crece sin limite y el coste con
  el. Las imagenes sin etiqueta de builds fallidos son la principal fuente.

El analisis de vulnerabilidades **no** se configura aqui: lo gobierna Artifact
Analysis a nivel de proyecto, habilitando `containerscanning.googleapis.com`.

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
| [google_artifact_registry_repository.docker](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/artifact_registry_repository) | resource |

### Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_env"></a> [env](#input\_env) | Identificador del ambiente (dev, qa o prod). Se usa en nombres, etiquetas y decisiones condicionales. | `string` | n/a | yes |
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | ID del proyecto de GCP donde se crean los recursos. | `string` | n/a | yes |
| <a name="input_region"></a> [region](#input\_region) | Region de GCP donde se despliegan los recursos regionales. | `string` | n/a | yes |
| <a name="input_cleanup_dry_run"></a> [cleanup\_dry\_run](#input\_cleanup\_dry\_run) | true evalua las politicas sin borrar nada. Util al estrenarlas. | `bool` | `false` | no |
| <a name="input_immutable_tags"></a> [immutable\_tags](#input\_immutable\_tags) | Impide reescribir una etiqueta ya publicada. Garantiza que el digest desplegado es exactamente el que se construyo y se probo. | `bool` | `false` | no |
| <a name="input_keep_recent_versions"></a> [keep\_recent\_versions](#input\_keep\_recent\_versions) | Numero de versiones recientes que la politica de limpieza conserva de cada imagen seguida. Es lo que permite revertir a un release anterior. | `number` | `10` | no |
| <a name="input_repository_id"></a> [repository\_id](#input\_repository\_id) | Identificador del repositorio de Artifact Registry. Las referencias de imagen del pipeline se derivan de el, de modo que cambiarlo exige republicar. | `string` | `"plataforma"` | no |
| <a name="input_tracked_images"></a> [tracked\_images](#input\_tracked\_images) | Nombres de imagen cuyo historico se conserva. | `list(string)` | <pre>[<br/>  "api",<br/>  "worker",<br/>  "batch"<br/>]</pre> | no |
| <a name="input_untagged_ttl_days"></a> [untagged\_ttl\_days](#input\_untagged\_ttl\_days) | Dias que sobrevive una imagen sin etiqueta antes de borrarse. Las imagenes huerfanas de builds fallidos son la principal fuente de crecimiento del registro. | `number` | `7` | no |

### Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_image_base"></a> [image\_base](#output\_image\_base) | Prefijo completo: <base>/<imagen>:<tag> |
| <a name="output_registry_host"></a> [registry\_host](#output\_registry\_host) | Host Docker al que etiquetar y empujar las imagenes. |
| <a name="output_repository_id"></a> [repository\_id](#output\_repository\_id) | Identificador del repositorio de imagenes. |
| <a name="output_repository_name"></a> [repository\_name](#output\_repository\_name) | Nombre completo del recurso de Artifact Registry. |
<!-- END_TF_DOCS -->
