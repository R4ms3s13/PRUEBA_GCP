# `async`

Pub/Sub con entrega push autenticada y cola de mensajes fallidos.

## Proposito

Desacopla el API del procesamiento pesado y resuelve el **intercambio de
informacion con otras aplicaciones** que pide el enunciado.

Un topic por dominio de evento, cada uno con una suscripcion **push** que
entrega al worker autenticando con OIDC.

## Push frente a pull

Con push, Pub/Sub provoca el escalado de Cloud Run por si solo. Un consumidor
pull necesitaria un proceso siempre vivo haciendo polling, lo que en Cloud Run
obliga a `min_instances > 0` pagando el valle.

> **Lo que esto exige de la aplicacion: el worker debe ser idempotente.**
> Pub/Sub garantiza entrega *al menos una vez*, no exactamente una. Procesar un
> mensaje dos veces no puede duplicar un pedido. Es un requisito de diseno que
> esta infraestructura impone y conviene decir en voz alta.

## Red de seguridad

- **Backoff exponencial** de 10 s a 600 s: ante un fallo transitorio no se
  reintenta en bucle cerrado.
- **Cola de fallidos** tras N intentos, con alerta en cuanto deja de estar
  vacia. Un mensaje nunca se pierde en silencio.
- Los topics de intercambio con terceros llevan **mas reintentos y mas
  `ack_deadline`** que los internos: la caida es ajena y hay que tolerarla.

## Punto a verificar en el primer apply

El worker se despliega con el ingress mas restrictivo. Si las entregas push de
Pub/Sub no llegaran a considerarse trafico interno, el ajuste es la variable
`worker_ingress` del modulo raiz, y **no debilita la autorizacion**: el worker
sigue exigiendo token OIDC y solo la service account de Pub/Sub tiene
`run.invoker` sobre el.

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
| [google_pubsub_subscription.dlq](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/pubsub_subscription) | resource |
| [google_pubsub_subscription.push](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/pubsub_subscription) | resource |
| [google_pubsub_subscription_iam_member.dlq_subscriber](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/pubsub_subscription_iam_member) | resource |
| [google_pubsub_topic.dlq](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/pubsub_topic) | resource |
| [google_pubsub_topic.topics](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/pubsub_topic) | resource |
| [google_pubsub_topic_iam_member.dlq_publisher](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/pubsub_topic_iam_member) | resource |
| [google_pubsub_topic_iam_member.publisher](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/pubsub_topic_iam_member) | resource |
| [google_service_account_iam_member.pubsub_token_creator](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/service_account_iam_member) | resource |

### Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_env"></a> [env](#input\_env) | Identificador del ambiente (dev, qa o prod). Se usa en nombres, etiquetas y decisiones condicionales. | `string` | n/a | yes |
| <a name="input_name_prefix"></a> [name\_prefix](#input\_name\_prefix) | Prefijo comun de los nombres de recurso del modulo. | `string` | n/a | yes |
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | ID del proyecto de GCP donde se crean los topics y las suscripciones. | `string` | n/a | yes |
| <a name="input_project_number"></a> [project\_number](#input\_project\_number) | Necesario para construir el email del agente de servicio de Pub/Sub. | `string` | n/a | yes |
| <a name="input_publisher_service_account_email"></a> [publisher\_service\_account\_email](#input\_publisher\_service\_account\_email) | Identidad del API backend, unica autorizada a publicar. | `string` | n/a | yes |
| <a name="input_pubsub_invoker_service_account_email"></a> [pubsub\_invoker\_service\_account\_email](#input\_pubsub\_invoker\_service\_account\_email) | SA con la que Pub/Sub firma el OIDC e invoca al worker. | `string` | n/a | yes |
| <a name="input_pubsub_invoker_service_account_id"></a> [pubsub\_invoker\_service\_account\_id](#input\_pubsub\_invoker\_service\_account\_id) | ID completo de esa SA, para el binding de tokenCreator. | `string` | n/a | yes |
| <a name="input_topics"></a> [topics](#input\_topics) | Un topic por dominio de evento, con su suscripcion push al worker.<br/>"path" es la ruta del worker que procesa ese evento. | <pre>map(object({<br/>    path                  = string<br/>    ack_deadline_seconds  = optional(number, 60)<br/>    retention_duration    = optional(string, "604800s")<br/>    max_delivery_attempts = optional(number, 5)<br/>    ordered               = optional(bool, false)<br/>    schema_id             = optional(string)<br/>  }))</pre> | n/a | yes |
| <a name="input_worker_url"></a> [worker\_url](#input\_worker\_url) | URL base del servicio worker de Cloud Run (destino del push). | `string` | n/a | yes |
| <a name="input_dlq_retention_duration"></a> [dlq\_retention\_duration](#input\_dlq\_retention\_duration) | Tiempo que un mensaje fallido se conserva para inspeccion y reinyeccion.<br/>Debe cubrir al menos un fin de semana largo: si el DLQ caduca antes de que<br/>alguien lo mire, el evento se pierde de verdad. | `string` | `"604800s"` | no |
| <a name="input_labels"></a> [labels](#input\_labels) | Etiquetas aplicadas a los recursos que las admiten, para repartir costes y filtrar en facturacion. | `map(string)` | `{}` | no |
| <a name="input_retry_maximum_backoff"></a> [retry\_maximum\_backoff](#input\_retry\_maximum\_backoff) | Espera maxima entre reintentos. Evita castigar a un sistema de terceros que ya esta caido. | `string` | `"600s"` | no |
| <a name="input_retry_minimum_backoff"></a> [retry\_minimum\_backoff](#input\_retry\_minimum\_backoff) | Espera minima antes de reintentar una entrega fallida. | `string` | `"10s"` | no |

### Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_dlq_subscription_name"></a> [dlq\_subscription\_name](#output\_dlq\_subscription\_name) | Suscripcion de la cola de fallidos, la que vigila la alerta. |
| <a name="output_dlq_topic_name"></a> [dlq\_topic\_name](#output\_dlq\_topic\_name) | Topic de la cola de mensajes fallidos. |
| <a name="output_subscription_names"></a> [subscription\_names](#output\_subscription\_names) | Nombre de cada suscripcion push al worker. |
| <a name="output_topic_ids"></a> [topic\_ids](#output\_topic\_ids) | Identificador completo de cada topic. |
| <a name="output_topic_names"></a> [topic\_names](#output\_topic\_names) | Nombre de cada topic de eventos, indexado por dominio. |
<!-- END_TF_DOCS -->
