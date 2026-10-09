# Plataforma de administración de proveedores — Infraestructura GCP

Resolución de la prueba técnica: diseño y preparación de la infraestructura en
Google Cloud Platform para una plataforma web de administración de proveedores,
pedidos y entregas.

## Los cuatro entregables

| # | Entregable pedido | Dónde está |
|---|---|---|
| **1** | Código Terraform completo | [`terraform/`](terraform/) — 10 módulos reutilizables, módulo raíz, 3 ambientes y bootstrap. 100 recursos |
| **2** | Diagrama de la arquitectura | [`docs/diagrama.md`](docs/diagrama.md) — 6 diagramas renderizados a SVG en [`docs/img/`](docs/img/) |
| **3** | README con sus 13 apartados | Este documento, [índice abajo](#índice) |
| **4** | Configuración del pipeline de CI/CD | [`cicd/`](cicd/) con servicios nativos de GCP, y [`.github/workflows/`](.github/workflows/) como equivalente. Tres pipelines independientes: infraestructura, backend y frontend ([D9b](docs/decisiones.md)) |

Además, lo que el enunciado pide en el cuerpo aunque no liste como entregable:

| Pedido | Dónde está |
|---|---|
| «Calcula el presupuesto … año 1, año 2 y año 3» | [`docs/presupuesto.md`](docs/presupuesto.md) |
| «Documentar las decisiones tomadas y sus implicaciones» | [`docs/decisiones.md`](docs/decisiones.md) — 21 decisiones, cada una con su alternativa descartada y qué se pierde |
| «Explicando la selección de cada [servicio]» | [Apartado 2](#2-servicios-gcp-utilizados) |

Y para facilitar la revisión: [`docs/trazabilidad.md`](docs/trazabilidad.md) traza
los **54 requisitos literales** del enunciado hasta su implementación, indicando
cómo se verificó cada uno.

---

## Índice

1. [Arquitectura](#1-arquitectura)
2. [Servicios GCP utilizados](#2-servicios-gcp-utilizados)
3. [Decisiones técnicas](#3-decisiones-técnicas)
4. [Prerrequisitos](#4-prerrequisitos)
5. [Configuración](#5-configuración)
6. [Despliegue](#6-despliegue)
7. [Variables](#7-variables)
8. [Ambientes](#8-ambientes)
9. [Seguridad](#9-seguridad)
10. [Observabilidad](#10-observabilidad)
11. [Recuperación](#11-recuperación)
12. [Destrucción](#12-destrucción)
13. [Reconstrucción](#13-reconstrucción)
14. [CI/CD](#14-cicd)
15. [Estado de la entrega](#15-estado-de-la-entrega)

---

## 1. Arquitectura

```
                    Internet
                        │
                ┌───────▼────────┐
                │  Cloud Armor   │  WAF + rate limit por IP
                └───────┬────────┘
                ┌───────▼────────┐
                │ Load Balancer  │  externo global + Cloud CDN
                │   global       │  un solo dominio, un solo punto de entrada
                └───┬────────┬───┘
            "/"     │        │  "/api/*"
        ┌───────────▼─┐   ┌──▼──────────────────────────────┐
        │ GCS frontend│   │ snet-app   (SIN Cloud NAT)      │
        │ build React │   │ ┌─────────────────────────────┐ │
        └─────────────┘   │ │ Cloud Run: API  Node.js     │ │
                          │ │ ingress = solo LB           │ │
                          │ │ → sin ruta a Internet       │ │
                          │ └──┬───────────────────┬──────┘ │
                          └────┼───────────────────┼────────┘
                               │                   │ publica
        ┌──────────────────────▼┐ ┌────────────────▼─────────┐
        │ Cloud SQL PostgreSQL  │ │        Pub/Sub           │
        │ IP PRIVADA · HA       │ │     topics + DLQ         │
        └───────────▲───────────┘ └────────────┬─────────────┘
                    │                          │ push OIDC
                    │  ┌───────────────────────▼──────────────────┐
                    │  │ snet-internal   (CON Cloud NAT, IP fija) │
                    ├──┤ ┌──────────────────────────────────────┐ │
                    │  │ │ Cloud Run: worker (ingress interno)  │ │
                    │  │ └──────────────────────────────────────┘ │
                    │  │ ┌──────────────────────────────────────┐ │
                    └──┤ │ Cloud Run Jobs: batch                │◄┼── Cloud Scheduler
                       │ └───────────────┬──────────────────────┘ │
                       └─────────────────┼────────────────────────┘
                                         ▼
                              Aplicaciones de terceros
```

**El detalle que no es decorativo:** el API, que es el único componente
alcanzable desde Internet, es precisamente el que **no puede iniciar**
conexiones hacia Internet — su subred queda fuera de Cloud NAT. El worker y los
jobs, que no son alcanzables desde fuera, sí salen, por una IP fija y auditable.
Ver [D5b](docs/decisiones.md).

Los seis diagramas completos están en [`docs/diagrama.md`](docs/diagrama.md),
renderizados a SVG y con el código Mermaid como fuente:

| # | Diagrama | Qué muestra |
|---|---|---|
| 1 | [Vista general](docs/img/01-1-vista-general.svg) | La arquitectura propuesta completa |
| 2 | [Flujo de una petición](docs/img/02-2-flujo-de-una-peticion-de-usuario.svg) | De navegador a base de datos, y el trabajo asíncrono que sigue |
| 3 | [Aislamiento de la BBDD](docs/img/03-3-por-que-la-base-de-datos-no-esta-expuesta.svg) | Las tres capas que la dejan sin exposición |
| 4 | [Separación público/privado](docs/img/04-4-separacion-entre-componentes-publicos-y-privados.svg) | Quién puede entrar y quién puede salir |
| 5 | [Separación entre ambientes](docs/img/05-5-separacion-entre-ambientes.svg) | Una definición, tres configuraciones, tres proyectos |
| 6 | [Pipeline de CI/CD](docs/img/06-6-pipeline-de-ci-cd.svg) | De *pull request* a producción con canary |

### Correspondencia con lo pedido

| Requisito del enunciado | Solución |
|---|---|
| Frontend React | Cloud Storage + backend bucket del LB + Cloud CDN |
| API backend Node.js | Cloud Run (servicio), ingress restringido al balanceador |
| Base de datos relacional | Cloud SQL para PostgreSQL 16, IP privada, HA regional en prod |
| Almacenamiento de archivos | Cloud Storage: buckets separados para uploads, exports y backups |
| Procesos asíncronos **para intercambio con otras aplicaciones** | Pub/Sub (topic por dominio) + worker con push OIDC + DLQ. El intercambio con terceros sale por Cloud NAT con **IP fija** para su allowlist, y el topic `integracion-salida` lleva más reintentos y más `ack_deadline` que los internos, porque la caída es ajena. Ver [D7b](docs/decisiones.md) |
| Procesos batch | Cloud Run Jobs, programados con Cloud Scheduler y disponibles bajo demanda |
| Registro privado de imágenes | Artifact Registry con análisis de vulnerabilidades y limpieza automática |
| VPC y **subnets** | Dos subredes con separación funcional: `snet-app` (expuesta, sin salida) y `snet-internal` (interna, con salida por NAT). Ver [D5b](docs/decisiones.md) |
| Separación público / privado | A nivel de red (subredes y NAT), de ingress (LB / interno) y de IAM (una service account por componente) |
| 3 ambientes, misma definición | Un módulo `platform`, tres `terraform.tfvars` |

---

## 2. Servicios GCP utilizados

Cada servicio con el motivo concreto por el que está, no solo lo que hace.

### Cómputo

| Servicio | Para qué | Por qué este y no otro |
|---|---|---|
| **Cloud Run** (servicios) | API y worker | Autoescalado por petición, escala a cero en dev, sin nodos que operar. La carga declarada no justifica un clúster |
| **Cloud Run Jobs** | Procesos batch y migraciones | Semántica de tarea: termina, da código de salida, reintenta. Un servicio HTTP no expresa eso |

### Datos

| Servicio | Para qué | Por qué |
|---|---|---|
| **Cloud SQL (PostgreSQL)** | Base de datos relacional | Gestionado, con HA regional, PITR y autenticación IAM. **Por qué no Spanner**, que también es relacional y administrado: no es PostgreSQL de verdad y obligaría a reescribir la capa de datos de una aplicación que ya se está desarrollando; además la carga no tiene el problema de escalado que Spanner resuelve, y sale más caro en los tres ambientes. Desarrollado en [D4b](docs/decisiones.md) |
| **Cloud Storage** | Archivos, estáticos, exportaciones, backups | Cuatro buckets separados: responsabilidades, permisos y ciclos de vida distintos |
| **Secret Manager** | Credenciales | Versionado, auditado y con permiso de lectura por identidad |
| **BigQuery** | Analítica de logs (solo prod) | SQL sobre el histórico de peticiones y errores |

### Red y entrada

| Servicio | Para qué | Por qué |
|---|---|---|
| **VPC + 2 subnets** | Aislamiento y separación público/privado | Modo custom, direccionamiento disjunto entre ambientes. El reparto en dos subredes es por **dirección del tráfico**, no por capas: es lo que deja al API sin salida a Internet |
| **Private Service Access** | Conectividad privada a Cloud SQL | Es lo que permite que la base de datos no tenga IP pública |
| **Application Load Balancer** (externo global) | Punto de entrada único | Anycast, TLS gestionado, y un solo sitio que proteger |
| **Cloud CDN** | Caché de estáticos | Los assets se sirven desde el borde, no desde el origen |
| **Cloud Armor** | WAF y rate limiting | Protección en el perímetro, antes de consumir cómputo |
| **Cloud NAT** | Salida a Internet **solo de la subred interna** | IP estable para allowlists de terceros, y a la vez el mecanismo que deja al API sin ruta de salida |

### Mensajería y orquestación

| Servicio | Para qué |
|---|---|
| **Pub/Sub** | Desacoplar el API del procesamiento pesado; DLQ para no perder mensajes |
| **Cloud Scheduler** | Disparar los jobs batch con token OAuth, sin webhooks compartidos |

### Entrega y seguridad

| Servicio | Para qué |
|---|---|
| **Artifact Registry** | Registro privado de imágenes, con escaneo y políticas de limpieza |
| **Cloud Build** | Pipelines nativos de infraestructura y aplicación |
| **IAM + Workload Identity Federation** | Identidad por componente; CI/CD sin claves descargadas |

### Observabilidad

| Servicio | Para qué |
|---|---|
| **Cloud Logging** | Bucket central con retención propia, índices y exclusión de ruido |
| **Cloud Monitoring** | 8 alertas accionables, dashboard de 4 planos, uptime check externo |
| **Error Reporting** | Agrupación de excepciones por causa raíz |
| **Cloud Trace** | Latencia por tramo dentro de una petición |

---

## 3. Decisiones técnicas

Las 21 decisiones con su alternativa descartada y lo que se pierde al elegir
están en [`docs/decisiones.md`](docs/decisiones.md). Las cuatro que más
condicionan el resto:

- **D4 — La base de datos sin IP pública.** Tres capas independientes: sin IP
  pública (red), firewall de egress solo desde la subnet de aplicación (ruta),
  autenticación IAM (identidad). Comprometer una no basta.
- **D5 — Cero credenciales.** Los runtimes se conectan con su identidad IAM: no
  hay contraseña de aplicación. La del usuario administrativo se **genera**,
  nunca se escribe, y vive en Secret Manager. La limitación del state de
  Terraform se documenta y se mitiga, no se oculta.
- **D9 / D9b — Tres pipelines independientes.** Terraform gobierna la
  infraestructura y los pipelines de aplicación gobiernan el release, de ahí el
  `ignore_changes` sobre la imagen del contenedor. Backend y frontend van
  separados porque son artefactos distintos con destinos distintos, y el
  contrato de compatibilidad N-1 que el canary ya exige hace que ningún orden de
  publicación entre ellos rompa.
- **D14 — Puntos únicos de falla.** Se eliminan los razonables (zona, instancia,
  entrada) y se dice explícitamente que la **caída de una región entera no está
  cubierta**, con el motivo y el coste de cubrirla.

---

## 4. Prerrequisitos

### Herramientas

| Herramienta | Versión | Para qué |
|---|---|---|
| Terraform | ≥ 1.6 (validado con **1.16.5**) | `optional()` en tipos de objeto |
| Provider `hashicorp/google` | `~> 6.0` (fijado a **6.50.0** en los lock files) | Toda la infraestructura |
| Google Cloud SDK | ≥ 470 | `gcloud`, `gcloud storage` |
| Un usuario con permisos | — | Ver abajo |

### En GCP

1. **Tres proyectos**, uno por ambiente, con **facturación activa**:
   `proveedores-dev`, `proveedores-qa`, `proveedores-prod`.
2. **Permisos** del usuario que ejecuta el bootstrap, sobre cada proyecto:
   `roles/owner` o, de forma más acotada, `resourcemanager.projectIamAdmin` +
   `serviceusage.serviceUsageAdmin` + `storage.admin` +
   `iam.serviceAccountAdmin`.
3. **Cuotas.** Las de un proyecto nuevo bastan para dev y QA. Para producción,
   revisar el límite de instancias de Cloud Run en la región antes de una
   prueba de carga.
4. **Dominio.** Necesario en QA y producción: el certificado gestionado solo se
   emite cuando el DNS ya apunta a la IP del balanceador. Dev funciona sin
   dominio (`enable_https = false`).

### Autenticación local

```bash
gcloud auth login
gcloud auth application-default login
gcloud config set project proveedores-dev
```

---

## 5. Configuración

### Paso 1 — Bootstrap (una vez por ambiente)

Crea el bucket del state remoto y la federación de identidad para CI/CD. Se
ejecuta con **state local**, porque no puede guardar su propio state en un
bucket que todavía no existe.

```bash
cd terraform/bootstrap

terraform init

terraform apply \
  -var="project_id=proveedores-dev" \
  -var="env=dev" \
  -var="github_repository=mi-organizacion/plataforma-proveedores"
```

Repetir con `env=qa` y `env=prod` cambiando `project_id`.

Los outputs dan los tres valores que necesitan el backend y el pipeline:

```bash
terraform output tfstate_bucket              # -> backend.hcl
terraform output workload_identity_provider  # -> variable WIF_PROVIDER_<env>
terraform output terraform_service_account   # -> variable TF_SA_<env>
terraform output workload_identity_pool      # -> wif_pool_name en el tfvars
```

> **`allowed_workflows`** es la lista blanca de ficheros de `.github/workflows/`
> autorizados a federar identidad ([D16](docs/decisiones.md)). Por defecto son
> `infra.yml`, `backend.yml` y `frontend.yml`. **Si se renombra un workflow hay
> que actualizarla**, o ese pipeline deja de poder autenticarse con un error de
> federación que no dice que la causa sea un nombre de fichero.

> El state local del bootstrap (`terraform.tfstate`) contiene configuración de
> IAM. Guardarlo en un sitio controlado o migrarlo al bucket que acaba de crear.

### Paso 2 — Ajustar el ambiente

Editar `terraform/envs/<env>/terraform.tfvars`. Lo que hay que cambiar sí o sí:

| Variable | Qué poner |
|---|---|
| `project_id` | El ID real del proyecto |
| `domains` | Los dominios reales (los de ejemplo son `example.com`) |
| `alert_emails` | Buzones que reciben las alertas |
| `wif_pool_name` | La salida `workload_identity_pool` del bootstrap de **ese** ambiente. Sin ella, GitHub Actions no puede impersonar la service account de despliegue y solo queda operativo el pipeline de Cloud Build |
| `github_repository` | `owner/repo`. Acota qué workloads pueden desplegar en dev y qa |
| `subnet_app_cidr` / `psa_cidr` | Solo si chocan con el direccionamiento corporativo |

Y en `terraform/envs/<env>/backend.hcl`, el nombre del bucket del paso 1.

---

## 6. Despliegue

### Orden y por qué es ese

```bash
cd terraform/envs/dev

terraform init -backend-config=backend.hcl
terraform plan -out=tfplan      # revisar SIEMPRE antes de aplicar
terraform apply tfplan
```

El primer `apply` tarda **15–25 minutos**. Lo que domina es Cloud SQL (de 10 a
15 minutos, y más si es HA) y la propagación del balanceador global.

### Qué se crea

Recursos que genera un `apply` desde cero, expandiendo los `for_each` y `count`
con los valores de cada `terraform.tfvars`:

| Área | DEV | QA | PROD | Qué explica la diferencia |
|---|---:|---:|---:|---|
| APIs y bindings IAM de proyecto | 42 | 42 | 42 | Idéntico: la postura de seguridad no se recorta por ambiente |
| Red y balanceador (`compute`) | 20 | 25 | 25 | Dev no tiene HTTPS gestionado ni Cloud Armor |
| Cloud Run (servicios y jobs) | 14 | 17 | 21 | Prod añade el job de intercambio con terceros y más programaciones |
| Pub/Sub | 15 | 15 | 15 | Mismos 3 topics con su DLQ en los tres |
| Service accounts | 11 | 11 | 11 | Seis identidades y sus vínculos, igual en todos |
| Cloud Storage | 11 | 11 | 11 | Los cuatro buckets con sus políticas |
| Secret Manager | 10 | 10 | 10 | |
| Observabilidad | 8 | 11 | 12 | Dev no tiene uptime check (sin dominio) ni canales de alerta |
| Cloud SQL | 6 | 6 | 6 | La diferencia está en la *configuración*, no en el número |
| Logging | 6 | 6 | 7 | Prod añade el sink analítico |
| Artifact Registry | 4 | 4 | 4 | |
| BigQuery | — | — | 2 | Dataset analítico, solo prod |
| **Total** | **~149** | **~160** | **~168** | |

Que los tres números sean tan parecidos es el punto: **la topología es la misma
y lo que cambia es el dimensionado**. Dev no es una versión recortada de la
arquitectura, es la misma arquitectura más pequeña.

Terraform resuelve el orden por las dependencias declaradas, pero conviene
conocerlas porque explican los errores del primer intento:

1. APIs del proyecto — todo lo demás falla sin ellas.
2. VPC, subnet y **peering de Private Service Access**.
3. Cloud SQL — *no puede crearse antes del peering*. Es el `depends_on` del
   módulo `database`.
4. Buckets y Artifact Registry.
5. Service accounts y permisos (necesitan los recursos a los que se conceden).
6. Servicios de Cloud Run.
7. Pub/Sub — necesita la URL del worker ya creado.
8. Balanceador — necesita el servicio del API para el serverless NEG.
9. Observabilidad — necesita los nombres de todo lo anterior.

### Primer despliegue: imágenes

El repositorio de imágenes está vacío en el primer `apply`, así que los tres
servicios arrancan con la imagen pública de ejemplo de Cloud Run
(`us-docker.pkg.dev/cloudrun/container/hello`). **Es intencionado**: la
infraestructura queda desplegada y verificable antes de que exista la
aplicación. A partir de ahí la imagen la gobierna el pipeline, y el módulo
ignora sus cambios para no revertir despliegues.

### Después del apply

```bash
terraform output lb_ip_address   # crear el registro A del dominio
```

Con el DNS apuntando, el certificado gestionado pasa de `PROVISIONING` a
`ACTIVE` en 15–60 minutos:

```bash
gcloud compute ssl-certificates describe prov-prod-cert \
  --global --format="value(managed.status)"
```

### Verificación

```bash
# El API responde a través del balanceador
curl -fsS https://$(terraform output -raw lb_ip_address)/healthz

# La URL run.app NO debe ser accesible: el ingress está restringido
curl -s -o /dev/null -w '%{http_code}\n' "$(terraform output -raw api_internal_uri)/healthz"
# esperado: 403

# La base de datos no tiene IP pública
gcloud sql instances describe $(terraform output -raw db_instance_name) \
  --format="value(settings.ipConfiguration.ipv4Enabled)"
# esperado: False

# Un job batch bajo demanda
gcloud run jobs execute prov-dev-conciliacion-pedidos --region=europe-west1 --wait
```

---

## 7. Variables

### Estándar de documentación del código

El código sigue la convención del Terraform Registry, que es lo que permite
consumir un módulo sin leer su implementación:

| Elemento | Estado |
|---|---|
| `README.md` por módulo, con propósito, decisiones de diseño y ejemplo de uso | **12/12** |
| Tablas de *Requirements, Providers, Resources, Inputs y Outputs* generadas con [`terraform-docs`](https://terraform-docs.io) | **12/12** |
| `versions.tf` por módulo, con `required_version` y `required_providers` | **12/12** |
| `description` en toda variable | **304/304** |
| `description` en todo output | **86/86** |
| `validation` donde el valor admite un conjunto cerrado | **20 bloques** |

Las tablas de referencia se **generan**, no se escriben a mano: viven entre los
marcadores `BEGIN_TF_DOCS` / `END_TF_DOCS` y la parte redactada queda intacta.
Regenerarlas tras cambiar variables, outputs o recursos:

```bash
terraform-docs .   # usa .terraform-docs.yml, recorre todos los módulos
```

Por qué `validation` importa: un valor inválido falla en el `plan`, con un
mensaje que dice exactamente qué se esperaba. Sin él falla en el `apply`, a
mitad de despliegue y con un error del API de Google mucho menos claro.

### Tres niveles, por orden de volatilidad

| Nivel | Dónde | Qué contiene |
|---|---|---|
| **Ambiente** | `envs/*/terraform.tfvars` | Lo que difiere entre dev, QA y prod: tamaños, HA, retenciones, dominios, umbrales, protecciones |
| **Organización** | `platform/variables.tf` | El estándar de la plataforma: contrato con la aplicación, APIs del proyecto, nombre del registro, política de egress. Un sitio, aplica a los tres |
| **Diseño del módulo** | `modules/*/variables.tf` | Valores con default razonable: TTL de CDN, backoff de reintentos, perfil TLS. Ajustables, pero nadie los toca para desplegar |

**Ningún módulo contiene un valor de configuración escrito dentro de un
recurso.** Lo que sigue siendo literal son constantes del proveedor (rangos de
health check de Google, issuer OIDC de GitHub, puertos 80 y 443, enums del
provider), textos legibles de `description`, y la definición interna de las
alertas y del dashboard. El criterio completo está en
[D7c](docs/decisiones.md).

### El contrato con el equipo de desarrollo

Cuatro valores que la infraestructura consume en varios sitios a la vez y que
por eso viven en **una sola** variable, no repetidos:

| Variable | Dónde se usa |
|---|---|
| `app_health_path` | Sonda de arranque y de vivacidad de los runtimes, enrutado del balanceador, uptime check y exclusión de logs |
| `app_container_port` | Puerto de los runtimes y de la regla de firewall de health checks |
| `app_api_path_patterns` | Rutas que el balanceador envía al API en lugar del frontend |
| `secret_version` | Versión de los secretos que montan los runtimes |

Cambiar la ruta de salud es editar una línea, no buscar `/healthz` por cuatro
ficheros.

### Las que más cambian el comportamiento

El contrato completo está documentado en
[`terraform/platform/variables.tf`](terraform/platform/variables.tf).

### Red

| Variable | Tipo | Efecto |
|---|---|---|
| `subnet_app_cidr` | string | Subred del API. **Queda fuera de Cloud NAT**: sin salida a Internet. Disjunta entre ambientes |
| `subnet_internal_cidr` | string | Subred de worker y jobs. La única traducida por NAT |
| `psa_cidr` | string | Base del rango de Private Service Access |
| `enable_nat` | bool | `false` ahorra ~$30/mes, pero **deja a worker y jobs sin salida**: solo en dev si no hay intercambio con terceros |
| `worker_ingress` | string | `INTERNAL_ONLY` por defecto. Pasar a `ALL` si las entregas push de Pub/Sub no se consideran internas; la autorización no se debilita (sigue exigiendo OIDC + `run.invoker`) |

### Cómputo

| Variable | Efecto |
|---|---|
| `api_min_instances` | `> 0` elimina el arranque en frío y es el mayor coste fijo |
| `api_max_instances` | Techo de escalado. **Se fija junto a `db_max_connections`**: es lo que protege a PostgreSQL de agotar conexiones |
| `api_max_concurrency` | Peticiones simultáneas por instancia |
| `api_cpu` / `api_memory` | Dimensionado por instancia |

### Base de datos

| Variable | Efecto |
|---|---|
| `db_tier` | Tamaño de la instancia |
| `db_highly_available` | `true` = standby síncrono en otra zona con failover. Duplica el cómputo |
| `db_point_in_time_recovery` | Habilita recuperación al segundo dentro de la ventana de WAL |
| `db_deletion_protection` | **`true` en prod.** Impide el borrado desde Terraform y desde la consola |

### Seguridad

| Variable | Efecto |
|---|---|
| `enable_cloud_armor` | Activa WAF y rate limiting |
| `waf_preview_mode` | `true` = las reglas registran lo que bloquearían sin bloquear. Así deben estrenarse |
| `rate_limit_requests` | Peticiones por IP y minuto antes del baneo temporal |
| `force_destroy_buckets` | **`false` en prod.** Evita borrar buckets con contenido |

### Observabilidad

| Variable | Efecto |
|---|---|
| `alert_emails` | Mapa etiqueta → email. Mapa y no lista para que renombrar uno no recree los demás |
| `log_retention_days` | Retención del bucket central |
| `enable_bigquery_sink` | Sink analítico. Solo prod: en dev/qa no se justifica el coste |
| `latency_p95_threshold_ms` | Umbral de la alerta de latencia |

---

## 8. Ambientes

### Cómo se cumple "misma definición, configuraciones diferentes"

Los tres ambientes instancian **el mismo** módulo `terraform/platform`. Los
ficheros `envs/*/main.tf` y `envs/*/variables.tf` son idénticos salvo el valor
de `env`. Toda la diferencia vive en `terraform.tfvars`, y es verificable:

```bash
# main.tf: idénticos salvo el nombre del ambiente
diff <(sed 's/\bdev\b/ENV/g;s/DEV/ENVU/g'   terraform/envs/dev/main.tf) \
     <(sed 's/\bprod\b/ENV/g;s/PROD/ENVU/g' terraform/envs/prod/main.tf)

# variables.tf y outputs.tf: byte a byte iguales
md5sum terraform/envs/*/variables.tf terraform/envs/*/outputs.tf
```

Ambas comprobaciones están ejecutadas: los `main.tf` no presentan ninguna
diferencia tras normalizar el nombre del ambiente, y los `variables.tf` y
`outputs.tf` de los tres ambientes tienen el mismo hash.

### Qué cambia entre ambientes

| | DEV | QA | PROD |
|---|---|---|---|
| Proyecto | `proveedores-dev` | `proveedores-qa` | `proveedores-prod` |
| Subred del API | 10.10.0.0/22 | 10.20.0.0/22 | 10.30.0.0/22 |
| Subred interna | 10.10.4.0/22 | 10.20.4.0/22 | 10.30.4.0/22 |
| Rango PSA (Cloud SQL) | 10.10.16.0/20 | 10.20.16.0/20 | 10.30.16.0/20 |
| API: min / max | 0 / 3 | 1 / 10 | **2 / 30** |
| CPU del API | 1 vCPU | 1 vCPU | 2 vCPU |
| Cloud SQL | 1 vCPU, 3,75 GB | 2 vCPU, 7,5 GB | **4 vCPU, 15 GB** |
| Alta disponibilidad | no | no | **sí (regional)** |
| PITR | no | **sí** | **sí** |
| Backups retenidos | 3 | 7 | 30 |
| HTTPS y dominio | no | sí | sí |
| Cloud Armor | no | sí (bloqueando) | sí (bloqueando) |
| Storage | regional | regional | **multi-región `eu`** |
| Retención de logs | 7 días | 14 días | 90 días |
| Sink a BigQuery | no | no | sí |
| Batch programado | solo bajo demanda | sí | sí (+ intercambio) |
| Protección de borrado | no | no | **sí** |

**El criterio de cada ambiente:**

- **DEV** — lo más barato que siga siendo representativo. Escala a cero, se
  destruye y se reconstruye a voluntad. Nada se dispara solo.
- **QA** — replica fiel de prod en **topología**, reducida en capacidad. Aquí sí
  hay PITR, TLS y Cloud Armor bloqueando: es donde deben aparecer los falsos
  positivos del WAF y donde se ensaya la recuperación. Lo que no hay es HA.
- **PROD** — alta disponibilidad, retenciones largas, protección de borrado.

---

## 9. Seguridad

### Identidades y privilegio mínimo

Seis service accounts, una por componente, para que el compromiso de una no
otorgue lo que necesitan las demás:

| Identidad | Permisos | No puede |
|---|---|---|
| `api` | Cliente y usuario IAM de Cloud SQL, publicar en Pub/Sub, `objectAdmin` en uploads, lector del registro, telemetría | Leer suscripciones, escribir en exports, administrar nada |
| `worker` | Cloud SQL, `objectViewer` en uploads, telemetría | Publicar en Pub/Sub, escribir archivos |
| `batch` | Cloud SQL, `objectViewer` en uploads, `objectAdmin` en exports y backups | Publicar eventos, tocar el frontend |
| `scheduler` | `run.invoker` **solo sobre los jobs concretos** | Invocar servicios, leer datos |
| `pubsub` | `run.invoker` **solo sobre el worker** | Nada más |
| `deployer` | `run.developer`, escritura en el registro, `serviceAccountUser` sobre las tres de runtime | Tocar red, IAM o base de datos |

Reglas aplicadas sin excepción:

- **Ningún rol básico.** Ni `owner`, ni `editor`, ni `viewer`, en ningún sitio.
- **Permiso a nivel de recurso siempre que exista.** `run.invoker` se concede
  sobre el job o el servicio concreto, nunca sobre el proyecto.
- **Impersonación acotada.** El pipeline despliega *como* las SA de runtime vía
  `serviceAccountUser`, sin tener sus permisos.

### Gestión de secretos

```
random_password (generado, nunca escrito)
   └─> Secret Manager (replicación gestionada, versionado)
          └─> Cloud Run (env var por referencia, resuelta en arranque)
```

- **No hay ninguna credencial en el código.** Verificable:
  `grep -rniE '(password|secret|api[_-]?key)\s*=\s*"[^"$]' terraform/` no
  devuelve ningún valor literal.
- La ruta normal de conexión es **autenticación IAM**: sin contraseña.
- `secretAccessor` se concede por secreto y por identidad, no a nivel de
  proyecto.
- **Limitación declarada:** el valor generado queda en el state. Mitigación:
  bucket cifrado, versionado, `public_access_prevention` y acceso restringido al
  pipeline. Endurecimiento disponible con argumentos *write-only* de Terraform
  ≥ 1.11, documentado en el módulo.

### Red

- **Separación público/privado en tres planos a la vez**, no solo en IAM:
  - *Red:* el API vive en `snet-app`, que no está en la lista de Cloud NAT, así
    que **no tiene ruta a Internet**. El worker y los jobs viven en
    `snet-internal`, la única traducida por el NAT.
  - *Ingress:* el API solo acepta tráfico del balanceador
    (`INTERNAL_LOAD_BALANCER`); el worker, solo interno.
  - *Identidad:* una service account por componente, con permisos disjuntos.
- Firewall **deny-by-default** en ingress; se abre solo health checks (rangos
  documentados de Google) y tráfico entre las dos subredes en los puertos usados.
- La base de datos **sin IP pública**, con egress explícito al 5432.
- Ningún componente tiene IP pública. La salida de worker y jobs va por Cloud
  NAT con IP fija, lo que además da al tercero una IP para su allowlist.
- `vpc_egress = ALL_TRAFFIC` en todos los runtimes: es lo que hace que la
  topología de subredes controle de verdad la salida. Con `PRIVATE_RANGES_ONLY`
  el tráfico público esquivaría la VPC y el control no existiría.
- TLS 1.2 mínimo con perfil `MODERN`, y redirección 301 de HTTP a HTTPS.

### Separación entre ambientes

Aislamiento por **proyecto**, no por etiquetas: el límite de IAM, de cuota y de
facturación coincide con el límite del ambiente. Rangos de red disjuntos.

### Comprobaciones automáticas

Cada pipeline comprueba lo suyo: el de **infraestructura** pasa Trivy y tflint
sobre la IaC (`HIGH,CRITICAL` corta el build); el de **backend** pasa Trivy sobre
las tres imágenes construidas y consulta Artifact Analysis antes de desplegar;
el de **frontend** corre `npm audit`. Artifact Registry escanea además todo lo
que se sube, y en prod las vulnerabilidades críticas bloquean el despliegue.

### Si el repositorio se compromete

El pipeline despliega con permisos amplios, así que la pregunta «¿y si alguien
consigue escribir en el repositorio?» tiene respuesta propia en
[D16](docs/decisiones.md). Resumen de las capas:

| Control | Qué para |
|---|---|
| **Sin claves de service account** (WIF) | No hay secreto que robar: lo que se obtiene no es reutilizable fuera de una ejecución de Actions |
| **Condición de repositorio** en el proveedor OIDC | Ningún otro repositorio puede federar identidad contra el proyecto |
| **Lista blanca de workflows** sobre `job_workflow_ref` | Un workflow **nuevo**, inyectado por quien tenga escritura, no obtiene token: solo los tres autorizados federan |
| **Prod solo desde la rama protegida** | `principalSet` con `attribute.ref`, no con el repositorio |
| **Aprobación humana** en el *environment* `prod` | Un push no llega solo a producción |
| **Acciones fijadas por SHA de commit** | Una etiqueta móvil como `@master` ejecuta en el *runner*, con el token OIDC delante, el código que su autor decida hoy |
| **Dependabot** | Un pin que nadie actualiza se queda con los fallos del día que se puso |

**Y lo que NO cubre, dicho explícitamente:** modificar uno de los tres workflows
ya autorizados. Eso solo lo para la **protección de rama con revisión
obligatoria**, que es un control de GitHub y no de Terraform — este repositorio
no gestiona la configuración de GitHub. Es un requisito a exigir fuera del
código, y está enunciado en D16 junto con los dos endurecimientos que siguen
abiertos: quitar `projectIamAdmin` a la SA de Terraform y aplicar Binary
Authorization.

---

## 10. Observabilidad

### Logs

| Pieza | Propósito |
|---|---|
| Bucket central de logs | Retención propia (7/14/90 días) con índices sobre `orderId` y `supplierId` |
| Sink a BigQuery (solo prod) | Analítica con SQL sobre peticiones y errores |
| **Exclusión de health checks** | El 99 % del volumen no informa de nada. Es la medida de ahorro más directa |

### Métricas basadas en log

Convierten patrones de log en series alertables sin instrumentar la aplicación:
`app_errors` (por servicio), `auth_failures` (picos de 401 = ataque de
credenciales), `slow_queries`.

### Alertas

Ocho políticas, cada una con una acción clara. Las críticas llevan el
procedimiento escrito en el propio recurso (`documentation`), que es donde se
lee a las tres de la mañana:

| # | Alerta | Severidad | Por qué |
|---|---|---|---|
| 1 | Uptime check externo fallando | CRITICAL | La única señal que detecta una caída del LB o del DNS |
| 2 | Tasa de 5xx elevada | ERROR | Mide lo que sufre el usuario |
| 3 | Latencia **p95** degradada | WARNING | La media esconde la cola |
| 4 | Mensajes en el DLQ | ERROR | Trabajo asíncrono perdido |
| 5 | CPU de Cloud SQL > 80 % | WARNING | Antecede a la degradación general |
| 6 | Disco de Cloud SQL > 85 % | CRITICAL | Un disco lleno es una caída total |
| 7 | Cloud Run al 80 % del techo | WARNING | Saturación o `max_instances` corto |
| 8 | Fallo de proceso batch | ERROR | Un batch que falla en silencio es peor que uno que no corre |

El uptime check se evalúa desde **tres continentes**: así un problema de red
local no se declara caída.

### Dashboard

Una pantalla con los cuatro planos —entrada, cómputo, datos y asíncrono— para
saber *en qué plano* está el problema sin navegar entre consolas.

### Detección de errores y trazas

Error Reporting agrupa excepciones por causa raíz; Cloud Trace da la latencia
por tramo. Ambos se alimentan de los roles `errorreporting.writer` y
`cloudtrace.agent` de cada runtime.

---

## 11. Recuperación

### Base de datos: tres mecanismos, tres fallos distintos

| Mecanismo | Cubre | Ventana |
|---|---|---|
| Backups automáticos (30 en prod, multi-región `eu`) | Corrupción o pérdida de datos | Diaria |
| Point-in-time recovery (7 días de WAL) | Error humano con hora conocida | Al segundo |
| `pg_dump` lógico a GCS (job nocturno) | **Borrado de la propia instancia** | Diaria |

El tercero es el que suele faltar: los backups gestionados viven con la
instancia y desaparecen con ella.

#### Restaurar a un punto en el tiempo

```bash
gcloud sql instances clone prov-prod-pg-ab12 prov-prod-pg-restore \
  --point-in-time="2026-10-09T14:30:00Z"
```

Clona, **no sobrescribe**: se valida la copia antes de repuntar la aplicación.

#### Restaurar un backup concreto

```bash
gcloud sql backups list --instance=prov-prod-pg-ab12
gcloud sql backups restore <BACKUP_ID> \
  --restore-instance=prov-prod-pg-restore \
  --backup-instance=prov-prod-pg-ab12
```

#### Restaurar desde el volcado lógico

```bash
gcloud storage cp gs://prov-prod-db-backups-<n>/dump-2026-10-09.sql.gz .
gunzip -c dump-2026-10-09.sql.gz | psql "$DATABASE_URL"
```

### Archivos

Los buckets de uploads y frontend tienen **versionado**: un objeto borrado o
sobrescrito se recupera por generación.

```bash
gcloud storage ls --all-versions gs://prov-prod-uploads-<n>/ruta/fichero.pdf
gcloud storage cp gs://prov-prod-uploads-<n>/ruta/fichero.pdf#<generacion> ./recuperado.pdf
```

En producción el bucket de uploads tiene además **retención de 7 años** (2555
días), por el carácter mercantil de los documentos de pedidos.

### Mensajes asíncronos

Un mensaje que agota los reintentos va al DLQ y la alerta 4 salta. Se inspecciona
y se reinyecta:

```bash
gcloud pubsub subscriptions pull prov-prod-dlq-sub --limit=10 --auto-ack=false
```

### Revisión de aplicación

Rollback inmediato sin reconstruir nada:

```bash
gcloud run services update-traffic prov-prod-api \
  --region=europe-west1 --to-revisions=prov-prod-api-00042-abc=100
```

### Caída de una región

**No está cubierta de forma automática, y es una decisión consciente**
([D14](docs/decisiones.md)). Un activo-activo multirregión multiplicaría coste y
complejidad para un RTO que una plataforma de gestión de proveedores suele
admitir en horas. El plan es: backups en multi-región e infraestructura
reproducible con un `apply` apuntando a otra región. **Debe validarse con el
negocio**: si el RTO exigido fuera de minutos, hay que replantearlo.

---

## 12. Destrucción

### Dev y QA

```bash
cd terraform/envs/dev
terraform destroy
```

Funciona directamente porque esos ambientes llevan `force_destroy_buckets = true`
y `db_deletion_protection = false`.

### Producción

**Está protegida a propósito y no se destruye sin pasos deliberados.** Hay tres
barreras, y es correcto que existan:

```bash
# 1. Quitar la protección de la instancia de base de datos
#    (en terraform.tfvars: db_deletion_protection = false)
terraform apply

# 2. Permitir el borrado de buckets con contenido
#    (en terraform.tfvars: force_destroy_buckets = false -> true)
terraform apply

# 3. Ahora sí
terraform destroy
```

Lo que **no** desaparece con el destroy, por diseño:

| Recurso | Motivo |
|---|---|
| Backups de Cloud SQL | Sobreviven para poder restaurar tras un borrado accidental |
| La base de datos lógica (`deletion_policy = ABANDON` en prod) | Evita perder el esquema por un cambio de nombre en Terraform |
| El peering de PSA (`deletion_policy = ABANDON`) | Un peering huérfano bloquearía el destroy |
| APIs habilitadas (`disable_on_destroy = false`) | Otro recurso del proyecto podría usarlas |
| Bucket del state | Lo gestiona el bootstrap, no la plataforma |

El nombre de una instancia de Cloud SQL borrada queda **reservado unos días**.
Por eso el módulo le añade un sufijo aleatorio: permite reconstruir de inmediato.

---

## 13. Reconstrucción

La infraestructura es reproducible: desde cero, sin ningún paso manual en la
consola.

```bash
# 1. Bootstrap (si también se perdió el proyecto)
cd terraform/bootstrap
terraform apply -var="project_id=..." -var="env=prod" -var="github_repository=..."

# 2. Plataforma completa
cd ../envs/prod
terraform init -backend-config=backend.hcl
terraform apply

# 3. Restaurar los datos
gcloud sql backups restore <BACKUP_ID> --restore-instance=<nueva>
#    o desde el volcado lógico del bucket de backups

# 4. Desplegar la aplicación: lanzar el pipeline, que publica por digest
```

### Reconstruir en otra región

Es el procedimiento de recuperación ante un incidente regional. Como la región
es una variable y nada está escrito a mano, basta:

```hcl
region                  = "europe-west4"
storage_backup_location = "europe-west1"
```

Y aplicar. Lo que hay que hacer a mano es repuntar el DNS a la nueva IP del
balanceador y restaurar los datos desde los backups multi-región.

### Las cuatro propiedades exigidas

| Propiedad | Cómo se consigue |
|---|---|
| **Parametrizable** | Todo el comportamiento por variables; cero valores escritos a mano en los módulos |
| **Reutilizable** | 10 módulos con interfaz propia. `cloud_run_service` lo instancian API y worker sin cambios |
| **Reproducible** | Restricción `~> 6.0` más `.terraform.lock.hcl` **versionado**, que fija el provider al 6.50.0 exacto con su checksum; state remoto bloqueado; APIs habilitadas desde el código |
| **Versionable** | Todo en Git. El `plan` se publica en el PR; cada cambio de infraestructura queda revisado y trazado |

---

## 14. CI/CD

Tres pipelines independientes ([D9](docs/decisiones.md), [D9b](docs/decisiones.md))
porque cambian a ritmos distintos, producen artefactos distintos y tienen
riesgos distintos.

**Implementación nativa de GCP** — la que pide el enunciado:

| Fichero | Se dispara con | Qué hace |
|---|---|---|
| [`cicd/cloudbuild-infra.yaml`](cicd/cloudbuild-infra.yaml) | `terraform/**` | `fmt` → `init` → `validate` → `tflint` → Trivy → doc al día → `plan` → `apply` del plan guardado |
| [`cicd/cloudbuild-backend.yaml`](cicd/cloudbuild-backend.yaml) | `app/api/**`, `app/worker/**`, `app/batch/**` | test → build de las 3 imágenes → push → puerta de vulnerabilidades → migraciones → deploy → smoke test |
| [`cicd/cloudbuild-frontend.yaml`](cicd/cloudbuild-frontend.yaml) | `app/frontend/**` | test → build de Vite → assets → `index.html` → invalidar CDN → verificar |

Cadena completa del backend: **Cloud Build** → **Artifact Registry** →
**Artifact Analysis** (escaneo) → **Binary Authorization** (atestación) →
**Cloud Run**, con **Cloud Deploy** para la promoción entre ambientes. El
frontend va a **Cloud Storage** y termina invalidando **Cloud CDN**.

**Por qué el frontend no comparte pipeline con el backend** ([D9b](docs/decisiones.md)):
son artefactos distintos con destinos distintos, y acoplarlos haría que un
cambio de CSS pagase el build de tres imágenes y las migraciones (~15 min frente
a ~2), además de que un test del backend en rojo bloquearía un arreglo de
frontend. El orden de publicación no es una restricción porque el API ya debe
ser compatible con la versión N-1: el canary hace convivir dos revisiones
sirviendo tráfico.

**Implementación equivalente en GitHub Actions**, por si el repositorio vive
allí: [`.github/workflows/`](.github/workflows/).

### Flujo

**Infraestructura:**

```
Pull request   → fmt, validate, tflint, Trivy, plan de los 3 ambientes comentado en el PR
Merge a main   → apply dev → apply qa  (secuencial: si dev rompe, qa no se toca)
Producción     → aprobación humana → apply prod
```

**Backend:**

```
Pull request   → test, build de las 3 imágenes, Trivy sobre la imagen (sin desplegar)
Merge a main   → migraciones + deploy dev → smoke test → promoción por digest a qa → integración
Producción     → aprobación humana → canary 10% → verificación 5 min → 100%
```

**Frontend:**

```
Pull request   → lint, test, build (sin publicar)
Merge a main   → publicar dev → verificar → publicar qa → verificar
Producción     → aprobación humana → assets → index.html → invalidar CDN → verificar
```

### Cinco detalles que importan

1. **Sin claves de service account.** Workload Identity Federation, con
   `attribute_condition` restringido al repositorio exacto. Sin esa condición,
   cualquier repositorio de GitHub podría pedir un token.
2. **`apply` del plan guardado**, no de uno nuevo: lo aplicado es exactamente
   lo revisado.
3. **Migraciones como job de Cloud Run**, dentro de la VPC. Ejecutarlas desde el
   runner de CI exigiría abrir la base de datos al exterior, que es justo lo que
   el diseño evita.
4. **Promoción por digest** ([D11](docs/decisiones.md)): el binario validado en
   QA es bit a bit el que entra en producción. El digest se resuelve **por
   componente**, porque API, worker y batch son imágenes distintas. El frontend
   sigue el mismo principio: se construye un artefacto y se publica tal cual en
   los tres ambientes.
5. **En el frontend, los assets antes que `index.html`.** Los assets llevan hash
   en el nombre, así que publicar los nuevos no invalida los que el `index.html`
   antiguo sigue pidiendo. Al revés habría una ventana de segundos pidiendo
   assets inexistentes. La invalidación de CDN es solo de `/index.html`:
   invalidar los assets sería tirar una caché que sigue siendo válida.

### Variables que espera el pipeline

Por ambiente: `WIF_PROVIDER_<env>`, `TF_SA_<env>`, `DEPLOYER_SA_<env>`,
`PROJECT_<env>`, `FRONTEND_BUCKET_<env>`, `URL_<env>`. Todas son
identificadores, **ninguna es un secreto**.

---

## 15. Estado de la entrega

### Completo

- Terraform: 10 módulos reutilizables, módulo raíz, 3 ambientes y bootstrap.
- Diagrama de arquitectura, flujo de petición, aislamiento de la BBDD,
  separación de ambientes y pipeline.
- Presupuesto de los 3 años con el modelo de cálculo y los supuestos a la vista.
- 21 decisiones técnicas con alternativa descartada y coste de la elección.
- Resistencia del pipeline a un repositorio comprometido: lista blanca de
  workflows en el proveedor OIDC, acciones fijadas por SHA y Dependabot (D16).
- CI/CD nativo de GCP y equivalente en GitHub Actions: tres pipelines
  independientes (infraestructura, backend y frontend).
- README con los 13 apartados pedidos, más arquitectura y estado de la entrega:
  15 en total.

### Revisión posterior y correcciones aplicadas

Tras una auditoría del propio entregable contra el enunciado se corrigieron
**once** defectos reales en la infraestructura. Se dejan listados porque dos de
ellos habrían roto el primer despliegue y porque el enunciado pide documentar
decisiones, lo que incluye las que corrigen un error propio:

| Defecto | Consecuencia que tenía |
|---|---|
| `deployer` sin escritura en el bucket del frontend | El paso «publicar frontend» fallaba con 403 en las dos implementaciones |
| `batch` sin permiso en el bucket de backups | El job de backup lógico no podía escribir: rompía el mecanismo de recuperación |
| Sink de logs sin `logging.bucketWriter` para su `writer_identity` | **Fallo silencioso:** el sink se creaba sin error y no entregaba nada |
| tmpfs de 256 Mi sobre instancias de 512 Mi | El tmpfs cuenta contra el límite de memoria: riesgo de OOM en dev. Bajado a 64 Mi |
| Adaptive Protection de Cloud Armor activo en prod | Requiere Cloud Armor Enterprise: el apply fallaba. Ahora tras un flag desactivado |
| `misconfiguration-ignore` no es clave válida de Trivy | La excepción se ignoraba. Movida a `.trivyignore` |
| `.gitignore` excluía `.terraform.lock.hcl` | Contradecía la reproducibilidad que promete este README: sin lock file cada `init` puede traer un provider distinto. Ahora **sí** se versiona |
| El nombre del repositorio de imágenes estaba escrito **dos veces** (`repository_id` y `local.image_base`) | Cambiar uno dejaba el otro obsoleto **sin que nada fallara**: el pipeline habría empujado la imagen a un repositorio y Cloud Run habría buscado en otro. Ahora `image_base` se deriva de la salida del módulo: una sola fuente |
| El worker no tenía `deletion_protection` y el API sí | En prod el worker se podía borrar desde Terraform y el API no. Inconsistencia silenciosa |
| `/healthz` escrito a mano en 4 sitios | Cambiar la ruta de salud exigía encontrarlos todos. Ahora es una variable del contrato con la aplicación |
| Cuatro valores eran condicionales `var.env == "prod"` dentro del código | Al extraerlos a variables se detectó el riesgo de que prod perdiera protecciones si quedaban en el default. Se cablearon explícitamente en los tres tfvars |

### Segunda auditoría: los pipelines

Una revisión posterior centrada en CI/CD encontró que el pipeline de aplicación
mezclaba backend y frontend, y que ese acoplamiento escondía defectos que lo
habrían hecho fallar en la primera ejecución —el primero de la tabla rompía los
tres ambientes, no solo uno. La separación en tres pipelines está razonada en
[D9b](docs/decisiones.md); estos son los defectos:

| Defecto | Consecuencia que tenía |
|---|---|
| **La service account `deployer` no tenía ningún binding de `workloadIdentityUser`.** Los tres workflows se autentican con ella, pero solo la SA de Terraform tenía el binding | **El paso `auth` de los pipelines de aplicación fallaba con 403 en los tres ambientes.** Federar identidad no basta: el principal federado necesita `workloadIdentityUser` **sobre la SA concreta** que pretende usar. Corregido con `deployer_wif_principal`, que el módulo raíz construye a partir del pool del bootstrap |
| **El frontend nunca se construía en GitHub Actions.** Los jobs `deploy_dev` y `deploy_prod` publicaban `app/frontend/dist`, pero ningún job ejecutaba `npm run build` y esos jobs ni siquiera hacían `checkout` | **Ambos jobs fallaban**: el directorio no existía. El pipeline de Cloud Build sí construía el frontend, así que las dos implementaciones no eran equivalentes, que es justo lo que este README prometía |
| **QA no recibía el frontend.** Solo dev y prod lo publicaban | QA servía un bundle obsoleto: las pruebas de integración validaban una combinación de frontend y API distinta de la que iría a producción |
| **Promoción a prod con un único digest para tres imágenes.** El paso recorría `api`, `worker` y `batch` aplicando el digest de entrada a los tres | Un digest identifica **una** imagen concreta y no existe en los otros dos repositorios: el paso fallaba. Ahora el digest se **resuelve por componente** antes de promocionar |
| La puerta de vulnerabilidades solo inspeccionaba la imagen del API | El worker y el batch entraban sin revisar, y ambos tienen acceso a la base de datos. Ahora se revisan las tres y se suman las críticas |
| `outputs.digest_api` declarado en un job con matriz y nunca consumido | Código muerto, y en una matriz el valor lo sobrescribe la última tarea que termine: habría dado un digest impredecible si alguien lo hubiera usado |

Y tres defectos de la propia documentación, que es parte del entregable:

| Defecto | Consecuencia que tenía |
|---|---|
| El apartado 15 tenía **dos** encabezados «No verificado», el primero vacío | Un hueco visible en el documento, justo en la sección que sostiene la credibilidad del resto |
| El recuento de decisiones no coincidía consigo mismo: «15 decisiones» en el apartado 3, «19» en la tabla de entregables | Dos cifras distintas para lo mismo en el mismo documento |
| `docs/trazabilidad.md` decía «47 ficheros» cuando hay 58 `.tf` y 3 `.tfvars` | Una cifra comprobable y equivocada: el revisor que la cuente encuentra otra |

### Tercera auditoría: ¿y si el repositorio se compromete?

El diseño protegía bien la identidad frente a **un tercero** —federación sin
claves, condición de repositorio— pero no frente al **propio repositorio**. Se
añadieron tres controles y se documentó el límite que queda:

| Añadido | Qué cierra |
|---|---|
| **Lista blanca de workflows** en el `attribute_condition` del proveedor OIDC, sobre el claim `job_workflow_ref` | Antes, cualquier workflow del repositorio autorizado podía federar identidad: quien lograse escribir añadía un fichero propio y obtenía el mismo token. Ahora solo los tres autorizados |
| **Las 42 referencias a acciones de GitHub fijadas por SHA de commit** (antes etiquetas móviles, y `trivy-action@master`) | Una etiqueta móvil ejecuta en el *runner*, con el token OIDC delante, el código que su autor decida hoy. Dos de los SHA exigían desreferenciar un tag anotado: el SHA de la *ref* no sirve para fijar una acción |
| **`.github/dependabot.yml`** | Un pin por SHA que nadie actualiza se queda con los fallos de seguridad del día que se puso. Esto lo convierte en un PR revisado |

**El límite, dicho sin adornos:** nada de esto impide modificar uno de los tres
workflows ya autorizados. Eso lo para la protección de rama con revisión
obligatoria, que es un control de GitHub y **no de Terraform**. Está enunciado
en [D16](docs/decisiones.md) junto con los dos endurecimientos que siguen
abiertos: quitarle `projectIamAdmin` a la service account de Terraform —que hoy
**puede concederse a sí misma cualquier rol**— y aplicar Binary Authorization.

Y tres desviaciones de la letra del enunciado, ahora resueltas o documentadas:

- **«Subnets», en plural.** Había una sola subred. Ahora hay dos, con separación
  funcional que sostiene un control de seguridad real ([D5b](docs/decisiones.md)).
- **«Un runtime para: frontend».** Se mantiene el bucket + CDN, pero D2 ahora
  confronta la desviación de forma explícita, con el coste de revertirla.
- **«Intercambio de información con otras aplicaciones».** Estaba cubierto pero
  implícito; ahora tiene respuesta nombrada en [D7b](docs/decisiones.md).

### Deliberadamente fuera de alcance

- **El código de la aplicación.** La prueba pide la infraestructura. Los
  `Dockerfile.*` y las rutas (`/healthz`, `/events/*`) son el **contrato** que
  la infraestructura espera del equipo de desarrollo.
- **Multirregión activo-activo.** Justificado en [D14](docs/decisiones.md), con
  el coste de cubrirlo y la recomendación de validar el RTO con el negocio.
- **Binary Authorization aplicado.** Está en el diseño del pipeline; la política
  en Terraform tiene sentido cuando existan imágenes reales que atestar.

### Verificado

Con **Terraform 1.16.5** y **provider `hashicorp/google` 6.50.0**, versión que
queda fijada en los `.terraform.lock.hcl` del repositorio:

| Comprobación | Resultado |
|---|---|
| `terraform fmt -check -recursive` | Limpio |
| `terraform validate` en `envs/dev` | **Success! The configuration is valid.** |
| `terraform validate` en `envs/qa` | **Success! The configuration is valid.** |
| `terraform validate` en `envs/prod` | **Success! The configuration is valid.** |
| `terraform validate` en `bootstrap` | **Success! The configuration is valid.** |
| YAML de los 6 pipelines y de `trivy.yaml` | Válidos, con los grafos `waitFor` y `needs` sin referencias a pasos inexistentes |
| Documentación de los 12 módulos al día respecto al código | **12/12 al día** con `terraform-docs v0.24.0 --output-check`: 304 variables y 87 salidas |
| Los 6 diagramas Mermaid renderizan a SVG | Confirmado con `mermaid-cli`: el script falla si alguno no parsea |
| Ausencia de credenciales literales | Ninguna |
| Los tres `main.tf` idénticos salvo el ambiente; `variables.tf` y `outputs.tf` con el mismo hash | Confirmado |
| Rangos de red sin solape, dentro de cada ambiente y entre ambientes | Confirmado |
| Enlaces internos de la documentación | 498/498 resuelven, anclas incluidas |

`validate` carga el esquema real del provider, así que esto confirma que los 100
recursos y todos sus argumentos existen y tienen el tipo correcto en el provider
6.50.0 — no solo que el HCL esté bien escrito.

Para reproducirlo:

```bash
terraform fmt -check -recursive terraform/
for e in dev qa prod; do
  terraform -chdir=terraform/envs/$e init -backend=false
  terraform -chdir=terraform/envs/$e validate
done
```

> **Si el `validate` falla con «plugin did not respond» o
> «certificate signed by unknown authority»**: no es el código. Es un antivirus
> con inspección TLS activa (Avast, Kaspersky y similares) interceptando el mTLS
> que Terraform usa entre su proceso y los plugins por *loopback*. Se resuelve
> excluyendo `terraform.exe` del escaneo HTTPS, o para una validación local con
> `TF_DISABLE_PLUGIN_TLS=1`.

### No verificado

El código **no se ha aplicado contra un proyecto GCP real**: no había
credenciales ni proyecto disponible. `validate` comprueba esquema y tipos, pero
no valores: un enum inválido, una cuota, una política de organización o un
permiso insuficiente solo aparecen en el `plan` o en el `apply`.

Las dos primeras comprobaciones funcionales a hacer en un apply real:

1. Que el worker reciba las entregas push de Pub/Sub con
   `ingress = INTERNAL_ONLY`. Si no, la variable `worker_ingress` lo resuelve
   sin debilitar la autorización ([D6](docs/decisiones.md)).
2. Que el certificado gestionado pase a `ACTIVE`, lo que depende de que el DNS
   apunte ya a la IP del balanceador.
