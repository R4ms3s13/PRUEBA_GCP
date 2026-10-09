# `database`

Cloud SQL PostgreSQL con IP privada unica y autenticacion IAM.

## Proposito

La base de datos relacional de la plataforma, resolviendo el requisito de que
**no este expuesta a Internet**.

## Como se resuelve la no exposicion

Tres capas independientes. La clave no es ninguna por separado, sino que
comprometer una no basta:

| Capa | Mecanismo | Que impide |
|---|---|---|
| Red | `ipv4_enabled = false` sobre Private Service Access | No existe IP publica que alcanzar |
| Ruta | Direct VPC egress + firewall de egress al 5432 | Solo las subredes de la plataforma llegan |
| Identidad | `cloudsql.iam_authentication` + usuarios service account | Hace falta identidad IAM autorizada |

**Alternativas descartadas:** IP publica con redes autorizadas (la allowlist no
cubre IPs efimeras de serverless); Cloud SQL Auth Proxy como sidecar (no aporta
ruta nueva y si un componente que operar); Private Service Connect (mas
aislamiento, mas piezas de las necesarias a esta escala).

## Credenciales

1. La contrasena se **genera** con `random_password`: no se escribe en ningun
   sitio.
2. Se guarda en Secret Manager, con lectura concedida por secreto y por
   identidad.
3. Los runtimes **no la usan**: se conectan con autenticacion IAM.

> **Limitacion declarada:** con la forma estable de los argumentos, el valor
> generado queda en el state de Terraform. Mitigacion: bucket de state cifrado,
> versionado y con acceso restringido al pipeline. Endurecimiento disponible con
> Terraform >= 1.11: `password_wo` y `secret_data_wo` (write-only), que no
> persisten en el state. No se usa por defecto para no acoplar el repositorio a
> versiones muy recientes.

## Dependencia de orden

La instancia **no puede crearse antes** del peering de Private Service Access.
El modulo raiz lo declara con `depends_on = [module.network]`, porque
`depends_on` no admite valores de variable.

## Recuperacion

Tres mecanismos, porque cada uno cubre un fallo distinto: backups automaticos
(corrupcion), PITR (error humano a una hora conocida) y volcado logico a Cloud
Storage (**borrado de la propia instancia**, que se llevaria sus backups).

El nombre lleva un sufijo aleatorio porque el de una instancia borrada queda
reservado unos dias, lo que bloquearia una reconstruccion inmediata.

---

## Referencia

<!-- BEGIN_TF_DOCS -->
### Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.6.0 |
| <a name="requirement_google"></a> [google](#requirement\_google) | >= 6.0, < 7.0 |
| <a name="requirement_random"></a> [random](#requirement\_random) | >= 3.6, < 4.0 |

### Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_google"></a> [google](#provider\_google) | >= 6.0, < 7.0 |
| <a name="provider_random"></a> [random](#provider\_random) | >= 3.6, < 4.0 |

### Resources

| Name | Type |
| ---- | ---- |
| [google_secret_manager_secret.db_password](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/secret_manager_secret) | resource |
| [google_secret_manager_secret.db_url](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/secret_manager_secret) | resource |
| [google_secret_manager_secret_iam_member.db_password_accessors](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/secret_manager_secret_iam_member) | resource |
| [google_secret_manager_secret_iam_member.db_url_accessors](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/secret_manager_secret_iam_member) | resource |
| [google_secret_manager_secret_version.db_password](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/secret_manager_secret_version) | resource |
| [google_secret_manager_secret_version.db_url](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/secret_manager_secret_version) | resource |
| [google_sql_database.app](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/sql_database) | resource |
| [google_sql_database_instance.main](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/sql_database_instance) | resource |
| [google_sql_user.app](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/sql_user) | resource |
| [google_sql_user.iam_service_accounts](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/sql_user) | resource |
| [random_id.instance_suffix](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/id) | resource |
| [random_password.app_user](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/password) | resource |

### Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_env"></a> [env](#input\_env) | Identificador del ambiente (dev, qa o prod). Se usa en nombres, etiquetas y decisiones condicionales. | `string` | n/a | yes |
| <a name="input_name_prefix"></a> [name\_prefix](#input\_name\_prefix) | Prefijo comun de todos los nombres de recurso del modulo. Hace que los recursos de un ambiente se reconozcan de un vistazo. | `string` | n/a | yes |
| <a name="input_network_id"></a> [network\_id](#input\_network\_id) | VPC donde se publica la IP privada de la instancia. | `string` | n/a | yes |
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | ID del proyecto de GCP donde se crean los recursos. | `string` | n/a | yes |
| <a name="input_region"></a> [region](#input\_region) | Region de GCP donde se despliegan los recursos regionales. | `string` | n/a | yes |
| <a name="input_tier"></a> [tier](#input\_tier) | Tipo de maquina. Dimensionado por ambiente desde el tfvars. | `string` | n/a | yes |
| <a name="input_app_db_user"></a> [app\_db\_user](#input\_app\_db\_user) | Usuario administrativo con contrasena, reservado a migraciones y mantenimiento. Los runtimes no lo usan: se conectan con autenticacion IAM. | `string` | `"app"` | no |
| <a name="input_backup_location"></a> [backup\_location](#input\_backup\_location) | Region o multi-region donde se guardan los backups. | `string` | `null` | no |
| <a name="input_backup_start_time"></a> [backup\_start\_time](#input\_backup\_start\_time) | Hora UTC de inicio de la ventana de backup. | `string` | `"02:00"` | no |
| <a name="input_charset"></a> [charset](#input\_charset) | Juego de caracteres de la base de datos. | `string` | `"UTF8"` | no |
| <a name="input_collation"></a> [collation](#input\_collation) | Collation de la base de datos. Afecta al ORDER BY de los textos, asi que<br/>conviene elegirla segun el idioma de los datos y NO cambiarla despues:<br/>hacerlo obliga a reconstruir indices. | `string` | `"en_US.UTF8"` | no |
| <a name="input_database_name"></a> [database\_name](#input\_database\_name) | Nombre de la base de datos logica que usa la aplicacion. | `string` | `"proveedores"` | no |
| <a name="input_database_version"></a> [database\_version](#input\_database\_version) | Version del motor de PostgreSQL. Subirla es una operacion con reinicio, asi que se fija explicitamente en lugar de dejar el valor por defecto del provider. | `string` | `"POSTGRES_16"` | no |
| <a name="input_deletion_protection"></a> [deletion\_protection](#input\_deletion\_protection) | Impide destruir la instancia desde Terraform y desde la consola. Debe estar activo en produccion. | `bool` | `true` | no |
| <a name="input_disk_autoresize_limit_gb"></a> [disk\_autoresize\_limit\_gb](#input\_disk\_autoresize\_limit\_gb) | Techo del crecimiento automatico de disco. 0 = sin limite. | `number` | `100` | no |
| <a name="input_disk_size_gb"></a> [disk\_size\_gb](#input\_disk\_size\_gb) | Tamano inicial del disco. Crece solo con disk\_autoresize, de modo que este valor es el punto de partida y no un limite. | `number` | `20` | no |
| <a name="input_edition"></a> [edition](#input\_edition) | Edicion de Cloud SQL. ENTERPRISE\_PLUS admite mas conexiones y mejor cache por vCPU, a mayor precio unitario. | `string` | `"ENTERPRISE"` | no |
| <a name="input_extra_database_flags"></a> [extra\_database\_flags](#input\_extra\_database\_flags) | Flags adicionales del motor, para que un ambiente pueda afinar sin modificar el modulo. | `map(string)` | `{}` | no |
| <a name="input_highly_available"></a> [highly\_available](#input\_highly\_available) | REGIONAL (standby sincrono en otra zona) frente a ZONAL. | `bool` | `false` | no |
| <a name="input_iam_db_users"></a> [iam\_db\_users](#input\_iam\_db\_users) | Emails de service account que se conectan con autenticacion IAM. | `map(string)` | `{}` | no |
| <a name="input_labels"></a> [labels](#input\_labels) | Etiquetas aplicadas a los recursos que las admiten, para repartir costes y filtrar en los informes de facturacion. | `map(string)` | `{}` | no |
| <a name="input_log_min_duration_ms"></a> [log\_min\_duration\_ms](#input\_log\_min\_duration\_ms) | Umbral de consulta lenta registrada en Cloud Logging. | `number` | `1000` | no |
| <a name="input_maintenance_day"></a> [maintenance\_day](#input\_maintenance\_day) | 1 = lunes ... 7 = domingo. | `number` | `7` | no |
| <a name="input_maintenance_hour"></a> [maintenance\_hour](#input\_maintenance\_hour) | Hora UTC de inicio de la ventana de mantenimiento. | `number` | `3` | no |
| <a name="input_max_connections"></a> [max\_connections](#input\_max\_connections) | Limite de conexiones simultaneas del motor. Se fija junto al maximo de instancias de Cloud Run: es lo que impide que el autoescalado agote la base de datos. | `number` | `100` | no |
| <a name="input_password_length"></a> [password\_length](#input\_password\_length) | Longitud de la contrasena generada para el usuario administrativo. | `number` | `32` | no |
| <a name="input_password_rotation_token"></a> [password\_rotation\_token](#input\_password\_rotation\_token) | Cambiar este valor fuerza la regeneracion de la contrasena. | `string` | `"v1"` | no |
| <a name="input_password_special_chars"></a> [password\_special\_chars](#input\_password\_special\_chars) | Conjunto de caracteres especiales permitidos por PostgreSQL en una contrasena. | `string` | `"!#%*()-_=+[]{}<>:?"` | no |
| <a name="input_point_in_time_recovery"></a> [point\_in\_time\_recovery](#input\_point\_in\_time\_recovery) | PITR via WAL. Imprescindible en prod. | `bool` | `false` | no |
| <a name="input_query_insights_string_length"></a> [query\_insights\_string\_length](#input\_query\_insights\_string\_length) | Longitud maxima de la consulta capturada por Query Insights. Mas largo da mas contexto para diagnosticar; tambien mas volumen. | `number` | `1024` | no |
| <a name="input_retained_backups"></a> [retained\_backups](#input\_retained\_backups) | Numero de backups automaticos que se conservan. | `number` | `7` | no |
| <a name="input_secret_accessor_members"></a> [secret\_accessor\_members](#input\_secret\_accessor\_members) | Service accounts que pueden leer los secretos de la BBDD. | `map(string)` | `{}` | no |
| <a name="input_ssl_mode"></a> [ssl\_mode](#input\_ssl\_mode) | ENCRYPTED\_ONLY exige TLS en toda conexion. | `string` | `"ENCRYPTED_ONLY"` | no |
| <a name="input_transaction_log_retention_days"></a> [transaction\_log\_retention\_days](#input\_transaction\_log\_retention\_days) | Ventana de PITR en dias (1-35). | `number` | `7` | no |

### Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_app_db_user"></a> [app\_db\_user](#output\_app\_db\_user) | Usuario administrativo, reservado a migraciones y mantenimiento. |
| <a name="output_connection_name"></a> [connection\_name](#output\_connection\_name) | Formato proyecto:region:instancia, que consume el conector de Node.js. |
| <a name="output_database_name"></a> [database\_name](#output\_database\_name) | Nombre de la base de datos logica de la aplicacion. |
| <a name="output_db_password_secret_id"></a> [db\_password\_secret\_id](#output\_db\_password\_secret\_id) | Identificador del secreto que guarda la contrasena administrativa. |
| <a name="output_db_url_secret_id"></a> [db\_url\_secret\_id](#output\_db\_url\_secret\_id) | Identificador del secreto que guarda la cadena de conexion completa. |
| <a name="output_db_url_secret_name"></a> [db\_url\_secret\_name](#output\_db\_url\_secret\_name) | Nombre completo del secreto, para montarlo en Cloud Run. |
| <a name="output_instance_name"></a> [instance\_name](#output\_instance\_name) | Nombre de la instancia de Cloud SQL. |
| <a name="output_private_ip_address"></a> [private\_ip\_address](#output\_private\_ip\_address) | IP privada de la instancia. No existe equivalente publica: es el nucleo del requisito de no exposicion. |
| <a name="output_self_link"></a> [self\_link](#output\_self\_link) | Enlace propio de la instancia. |
<!-- END_TF_DOCS -->
