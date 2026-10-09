# `network`

VPC, subredes, Private Service Access y salida a Internet controlada.

## Proposito

Crea la red del ambiente: una VPC en modo custom, **dos subredes**, el peering
de Private Service Access que da IP privada a Cloud SQL y un Cloud NAT acotado.

## La decision de diseno que importa

Las dos subredes no son una division cosmetica: sostienen un control de
seguridad real.

| Subred | Quien vive ahi | Cloud NAT | Consecuencia |
|---|---|---|---|
| `snet-app` | El componente expuesto (el API) | **No** | Sin ruta a Internet |
| `snet-internal` | Worker y jobs batch | **Si** | Salida por IP fija y auditable |

**El componente que recibe trafico de Internet es precisamente el que no puede
iniciar conexiones hacia Internet.** Si alguien ejecuta codigo en el API, no
tiene por donde exfiltrar datos ni por donde descargar una segunda etapa.

Dos detalles sin los cuales el control no existiria:

- Cloud NAT se declara con `LIST_OF_SUBNETWORKS` enumerando **solo** la subred
  interna. Con `ALL_SUBNETWORKS` el control se perderia en silencio al crear
  cualquier subred nueva.
- Los runtimes deben usar `vpc_egress = ALL_TRAFFIC`. Con `PRIVATE_RANGES_ONLY`
  el trafico publico saldria por la ruta gestionada de Google, **esquivando la
  VPC**, y la topologia no controlaria nada.

## Lo que NO hace, a proposito

No hay regla de firewall que deniegue `0.0.0.0/0` al API. El trafico hacia las
APIs de Google via Private Google Access tiene destino en IPs **publicas**: una
denegacion general cortaria Secret Manager, Pub/Sub y Cloud Storage. El control
efectivo es la **ausencia de ruta**, que es mas robusta que una regla que
alguien puede relajar.

## Uso

```hcl
module "network" {
  source = "../modules/network"

  project_id           = "mi-proyecto"
  env                  = "prod"
  region               = "europe-west1"
  name_prefix          = "prov-prod"
  subnet_app_cidr      = "10.30.0.0/22"
  subnet_internal_cidr = "10.30.4.0/22"
  psa_cidr             = "10.30.16.0"
}
```

> El rango de PSA no debe solaparse con las subredes. Conviene reservar
> rangos disjuntos entre ambientes aunque hoy no haya peering: cuesta nada
> ahora y evita renumerar si manana se conectan.

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
| [google_compute_address.nat](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_address) | resource |
| [google_compute_firewall.allow_egress_sql](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_firewall) | resource |
| [google_compute_firewall.allow_health_checks](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_firewall) | resource |
| [google_compute_firewall.allow_internal](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_firewall) | resource |
| [google_compute_firewall.deny_all_ingress](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_firewall) | resource |
| [google_compute_global_address.psa_range](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_global_address) | resource |
| [google_compute_network.vpc](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_network) | resource |
| [google_compute_network_peering_routes_config.psa_routes](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_network_peering_routes_config) | resource |
| [google_compute_router.router](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_router) | resource |
| [google_compute_router_nat.nat](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_router_nat) | resource |
| [google_compute_subnetwork.app](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_subnetwork) | resource |
| [google_compute_subnetwork.internal](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_subnetwork) | resource |
| [google_service_networking_connection.psa](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/service_networking_connection) | resource |

### Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_env"></a> [env](#input\_env) | Identificador del ambiente (dev, qa o prod). Se usa en nombres, etiquetas y decisiones condicionales. | `string` | n/a | yes |
| <a name="input_name_prefix"></a> [name\_prefix](#input\_name\_prefix) | Prefijo comun de los nombres de recurso de red. | `string` | n/a | yes |
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | ID del proyecto de GCP donde se crea la VPC. | `string` | n/a | yes |
| <a name="input_psa_cidr"></a> [psa\_cidr](#input\_psa\_cidr) | Direccion base del rango reservado para Private Service Access (Cloud SQL). | `string` | n/a | yes |
| <a name="input_region"></a> [region](#input\_region) | Region donde se crean las subredes, el router y el NAT. | `string` | n/a | yes |
| <a name="input_subnet_app_cidr"></a> [subnet\_app\_cidr](#input\_subnet\_app\_cidr) | Subnet del componente EXPUESTO (el API, alcanzable desde el balanceador).<br/>Deliberadamente SIN Cloud NAT: sin ruta a Internet. | `string` | n/a | yes |
| <a name="input_subnet_internal_cidr"></a> [subnet\_internal\_cidr](#input\_subnet\_internal\_cidr) | Subnet de los componentes INTERNOS (worker y jobs batch), que si necesitan<br/>salir a Internet para el intercambio con aplicaciones de terceros. Es la<br/>unica subnet que Cloud NAT traduce. | `string` | n/a | yes |
| <a name="input_enable_nat"></a> [enable\_nat](#input\_enable\_nat) | Cloud NAT para salida a Internet desde recursos sin IP publica. | `bool` | `true` | no |
| <a name="input_flow_sampling"></a> [flow\_sampling](#input\_flow\_sampling) | Fraccion de flujos VPC registrados. Mas alto en prod, mas bajo en dev por coste. | `number` | `0.1` | no |
| <a name="input_nat_min_ports_per_vm"></a> [nat\_min\_ports\_per\_vm](#input\_nat\_min\_ports\_per\_vm) | Puertos de origen que Cloud NAT reserva por instancia. Si se agotan, las conexiones salientes fallan de forma intermitente y dificil de diagnosticar. | `number` | `64` | no |
| <a name="input_psa_prefix_length"></a> [psa\_prefix\_length](#input\_psa\_prefix\_length) | Longitud del prefijo del rango de Private Service Access. /20 da holgura para que Google despliegue la instancia de Cloud SQL y sus replicas. | `number` | `20` | no |

### Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_nat_ip"></a> [nat\_ip](#output\_nat\_ip) | IP de salida estable para allowlists de terceros. |
| <a name="output_network_id"></a> [network\_id](#output\_network\_id) | Identificador de la VPC, para conectar runtimes y publicar la IP privada de Cloud SQL. |
| <a name="output_network_name"></a> [network\_name](#output\_network\_name) | Nombre de la VPC. |
| <a name="output_network_self_link"></a> [network\_self\_link](#output\_network\_self\_link) | Enlace propio de la VPC, requerido por recursos que no aceptan el id. |
| <a name="output_psa_connection_id"></a> [psa\_connection\_id](#output\_psa\_connection\_id) | Dependencia explicita: Cloud SQL no puede crearse antes que el peering. |
| <a name="output_subnet_app_id"></a> [subnet\_app\_id](#output\_subnet\_app\_id) | Subnet del API. Sin Cloud NAT: no tiene salida a Internet. |
| <a name="output_subnet_app_name"></a> [subnet\_app\_name](#output\_subnet\_app\_name) | Nombre de la subred del componente expuesto. |
| <a name="output_subnet_internal_id"></a> [subnet\_internal\_id](#output\_subnet\_internal\_id) | Subnet de worker y jobs. Unica traducida por Cloud NAT. |
| <a name="output_subnet_internal_name"></a> [subnet\_internal\_name](#output\_subnet\_internal\_name) | Nombre de la subred de los componentes internos. |
<!-- END_TF_DOCS -->
