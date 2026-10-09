# Trazabilidad: enunciado → implementación → verificación

Cada exigencia literal de la prueba técnica, dónde se cumple y cómo se comprobó.
Las comprobaciones marcadas **(automática)** se ejecutaron sobre el código, no
son afirmaciones.

**54 de 54 requisitos con implementación verificada.**

---

## 1 · Lo que la infraestructura debe soportar

| Requisito | Implementación | Verificación |
|---|---|---|
| Frontend React | Cloud Storage + backend bucket + Cloud CDN | (automática) `google_storage_bucket.frontend` + `google_compute_backend_bucket` |
| API backend Node.js | Cloud Run, ingress solo balanceador | (automática) `module.api` sobre `cloud_run_service` |
| Base de datos relacional | Cloud SQL PostgreSQL 16 | (automática) `google_sql_database_instance` |
| Almacenamiento de archivos | 4 buckets separados por responsabilidad | (automática) uploads, exports, db_backups, frontend |
| **Procesos asíncronos para intercambio con otras aplicaciones** | Pub/Sub + worker; topic `integracion-salida` y job `intercambio-terceros` con IP fija | (automática) `dead_letter_policy` + [D7b](decisiones.md) |
| Procesos batch | Cloud Run Jobs + Cloud Scheduler | (automática) `google_cloud_run_v2_job` |

---

## 2 · Ambientes

| Requisito | Implementación | Verificación |
|---|---|---|
| 3 ambientes DEV, QA, PROD | Un proyecto GCP por ambiente | (automática) `terraform/envs/{dev,qa,prod}` |
| **Misma definición, configuraciones diferentes** | Los tres instancian `terraform/platform` | (automática) `diff` de los `main.tf` sin diferencias tras normalizar el nombre; `variables.tf` y `outputs.tf` con **un solo hash** entre los tres |

---

## 3 · Lo que hay que entregar además del código

| Requisito | Implementación | Verificación |
|---|---|---|
| Definir los servicios GCP **explicando la selección de cada uno** | README §2 + 21 decisiones con alternativa descartada y coste | (automática) `docs/decisiones.md` |
| **Crear un diagrama** para compartir con el equipo | 6 diagramas | (automática) 6 SVG renderizados con `mermaid-cli` |
| Presupuesto dev/qa/prod para años 1, 2 y 3 | Modelo con supuestos declarados | [`presupuesto.md`](presupuesto.md) |

---

## 4 · Lo que hay que preparar en Terraform

| Requisito | Implementación | Verificación |
|---|---|---|
| Runtime para frontend | GCS + CDN — **desviación consciente**, ver [D2](decisiones.md) | (automática) `google_compute_backend_bucket` |
| Runtime para backend/API | Cloud Run | (automática) `google_cloud_run_v2_service` |
| Base de datos relacional administrada | Cloud SQL | (automática) |
| Almacenamiento de objetos | Cloud Storage | (automática) |
| Mecanismo para publicar eventos procesados posteriormente | Pub/Sub push + DLQ | (automática) |
| Ejecutar procesos **programados o bajo demanda** | Jobs con `schedule` y con `schedule = null` | (automática) ambos presentes |
| Registro privado de imágenes Docker | Artifact Registry | (automática) |

---

## 5 · Red

| Requisito | Implementación | Verificación |
|---|---|---|
| VPC | Modo custom | (automática) `google_compute_network` |
| **Subnets** (plural) | `snet-app` y `snet-internal` | (automática) 2 recursos `google_compute_subnetwork` |
| Comunicación entre servicios | Firewall entre las dos subredes en los puertos usados | (automática) regla `allow-internal` |
| Acceso privado a la base de datos | Private Service Access | (automática) `google_service_networking_connection` |
| **Separación entre componentes públicos y privados** | NAT solo en la subred interna: el API no tiene salida a Internet | (automática) `LIST_OF_SUBNETWORKS` — ver [D5b](decisiones.md) |
| Conectividad runtime → servicios internos | Direct VPC egress | (automática) `network_interfaces` |
| **BBDD no expuesta a Internet** | `ipv4_enabled = false` + firewall de egress + auth IAM | (automática) — ver [D4](decisiones.md) |

---

## 6 · Seguridad

| Requisito | Implementación | Verificación |
|---|---|---|
| Definiciones IAM | `modules/iam` | (automática) |
| Service Accounts | 6, una por componente | (automática) |
| **Privilegios mínimos** | Ningún rol básico; permisos a nivel de recurso | (automática) `grep roles/owner\|editor\|viewer` → **sin resultados** |
| Gestión de secretos | Secret Manager + `random_password` | (automática) |
| Separación de permisos entre componentes | Bindings distintos por identidad y por bucket | (automática) |
| Acceso seguro a la base de datos | Autenticación IAM + TLS obligatorio | (automática) `cloudsql.iam_authentication` |
| Separación entre ambientes | Proyecto por ambiente, rangos disjuntos | (automática) sin solape dentro ni entre ambientes |
| **Sin credenciales en código duro** | Se generan, van a Secret Manager, y los runtimes usan IAM | (automática) `grep` de credenciales → **sin resultados** |

---

## 7 · Observabilidad

| Requisito | Implementación | Verificación |
|---|---|---|
| Centralizar logs | Bucket central + sink + `logging.bucketWriter` | (automática) |
| Recopilar métricas | 3 métricas basadas en log + las nativas | (automática) |
| Monitorear los servicios | Dashboard de 4 planos + uptime check desde 3 continentes | (automática) |
| Detectar errores | Error Reporting + Cloud Trace | (automática) |
| Generar alertas básicas | 8 políticas, cada una con acción asociada | (automática) |
| **Explicar el propósito de cada componente** | README §10 con el porqué de cada pieza | README |

---

## 8 · Plataforma productiva

| Requisito | Implementación | Verificación |
|---|---|---|
| Eliminar SPOF **cuando sea razonable** | HA regional de Cloud SQL, `min_instances = 2`, LB anycast. **La caída de región no se cubre, y está justificado** | [D14](decisiones.md) |
| Capacidad de escalar | Autoescalado + `disk_autoresize` con techo | (automática) |
| Recuperación ante fallos | Failover automático + PITR + DLQ + rollback de revisión | (automática) |
| Backups de la información | Gestionados + volcado lógico + versionado de buckets | (automática) |
| Mecanismos de recuperación de la BBDD | 3 mecanismos con procedimiento escrito | README §11 |
| **Documentar decisiones y sus implicaciones** | 21 decisiones, cada una con «qué se pierde» | (automática) |

---

## 9 · Calidad exigida al código

| Requisito | Implementación | Verificación |
|---|---|---|
| Parametrizable | 502 variables en 3 niveles; ningún valor de configuración dentro de un recurso | (automática) — ver [D7c](decisiones.md) |
| Reutilizable | 10 módulos con interfaz propia | (automática) |
| Reproducible | `.terraform.lock.hcl` versionado, provider fijado a **6.50.0** | (automática) |
| Versionable | Todo en Git; el `plan` se publica en el PR | — |

---

## 10 · CI/CD y entregables

| Requisito | Implementación | Verificación |
|---|---|---|
| Pipeline **con servicios de GCP** | Cloud Build → Artifact Registry → Artifact Analysis → Cloud Run, con Cloud Deploy | (automática) |
| 1. Código Terraform completo | 58 ficheros `.tf` y 3 `.tfvars`, 100 bloques `resource`, 10 módulos | (automática) |
| 2. Diagrama de la arquitectura | 6, renderizados a SVG | (automática) |
| 3. README con 13 apartados | 13/13 cubiertos, 15 apartados en total | (automática) |
| 4. Configuración del pipeline | 3 pipelines de Cloud Build (infra, backend, frontend) y sus 3 equivalentes en GitHub Actions | (automática) |

---

## Estado de verificación del código

| Comprobación | Resultado |
|---|---|
| `terraform fmt -check -recursive` | Limpio |
| `terraform validate` × 4 (dev, QA, prod, bootstrap) | **Success** — con el esquema real del provider 6.50.0 |
| Estructura de los 61 ficheros HCL | 61/61 sin incidencias |
| Coherencia referencial | Sin incidencias |
| Credenciales literales | Ninguna |
| Roles básicos de IAM | Ninguno |
| `main.tf` de los 3 ambientes | Idénticos |
| `variables.tf` de los 3 ambientes | Un solo hash |
| Rangos de red | Sin solape, dentro y entre ambientes |
| Enlaces de la documentación | 42/42 |
| Diagramas renderizados | 10/10 |

---

## Lo que NO está verificado

Dicho aquí para que nadie tenga que buscarlo:

| | |
|---|---|
| **`terraform plan` y `apply`** | No se han ejecutado: no hay credenciales ni proyecto GCP disponibles. `validate` comprueba esquema y tipos, **no valores**: un enum inválido, una cuota agotada o una política de organización solo aparecen en el `plan` |
| **Las cifras del presupuesto** | Son un modelo con precios de lista y supuestos declarados, no una cotización |
| **Los tiempos de operación** | Estimaciones del comportamiento típico de los servicios, no medidas de este despliegue |

**Las dos primeras comprobaciones a hacer en un despliegue real:**

1. Que el worker reciba las entregas push de Pub/Sub con `ingress = INTERNAL_ONLY`. Si no, la variable `worker_ingress` lo resuelve sin debilitar la autorización.
2. Que el certificado gestionado pase a `ACTIVE` tras apuntar el DNS.

Y un riesgo que depende de algo fuera de este repositorio: el bucket del frontend
necesita acceso público. Si la organización aplica una política que fuerza
`public_access_prevention = enforced`, el `apply` falla ahí.
