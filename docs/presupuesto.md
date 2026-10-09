# Presupuesto — años 1, 2 y 3

## Cómo leer este documento

Las cifras son **estimaciones con precios de lista** de `europe-west1`, en USD
al mes, sin IVA, sin plan de soporte y sin descuentos por compromiso de uso.
No son una oferta: son un presupuesto defendible con el modelo de cálculo a la
vista, para que cualquier supuesto se pueda discutir y rehacer.

Antes de aprobar un gasto real conviene validar los dos o tres conceptos
dominantes (Cloud SQL y Cloud Run) en la calculadora oficial, porque los
precios de lista cambian y porque el dimensionado definitivo sale de medir, no
de estimar.

---

## 1. Supuestos de carga

Del enunciado:

| Dato | Valor |
|---|---|
| Usuarios registrados | 20.000 |
| Usuarios concurrentes | 2.000 |
| Operaciones diarias | 100.000 – 500.000 |
| Crecimiento anual | 30 % |

Supuestos propios, necesarios para convertir eso en consumo. Se declaran porque
son el punto más frágil de cualquier estimación:

| Supuesto | Valor | Razonamiento |
|---|---|---|
| Operaciones/día en año 1 | 500.000 | Se presupuesta el extremo alto del rango: un presupuesto que se queda corto es peor que uno holgado |
| Distribución horaria | 10 h laborables | Plataforma B2B de proveedores: el tráfico es diurno y de días hábiles |
| Tasa media | ~14 req/s | 500.000 / (10 × 3.600) |
| Tasa de pico | ~50 req/s | Factor 3–4× sobre la media |
| Latencia media del API | 150 ms | Operaciones CRUD con una o dos consultas |
| Tamaño medio de respuesta | 15 KB | JSON de listados y detalle de pedidos |
| Mensajes asíncronos | 1,5 por operación | Evento de dominio + notificación |
| Egress mensual año 1 | ~300 GB | API 225 GB + assets no cacheados |
| Crecimiento del almacenamiento | 40 %/año | Más que el tráfico: los archivos se acumulan, no se reemplazan |

**Nota sobre el dimensionado:** con 80 peticiones concurrentes por instancia y
150 ms de respuesta, una sola instancia de Cloud Run absorbe del orden de
cientos de req/s. El pico de 50 req/s no es, por tanto, lo que fija el tamaño
del cómputo: lo que lo fija es el **mínimo de instancias calientes** (2, para
eliminar arranques en frío y repartir entre zonas) y el **pool de conexiones a
PostgreSQL**. De ahí que el gasto en Cloud Run sea casi un coste fijo y no
proporcional a las operaciones.

---

## 2. Año 1 — detalle por servicio

### PROD

| Servicio | Configuración | $/mes | Comentario |
|---|---|---:|---|
| Cloud SQL PostgreSQL | 4 vCPU / 15 GB, **HA regional**, 100 GB SSD | **450** | Cómputo y memoria duplicados por el standby síncrono |
| Cloud Run — API | 2 vCPU / 2 GiB, min 2, media ~2,2 instancias | 230 | Coste dominado por las instancias siempre activas |
| Cloud Run — worker | 1 vCPU / 2 GiB, min 1, media ~1,5 | 87 | `cpu_idle = false`: trabaja tras el ack |
| Cloud Logging | ~150 GiB/mes, retención 90 días | 55 | Con la exclusión de health checks ya aplicada |
| Load Balancer + egress | 2 reglas de reenvío + ~300 GB | 70 | Las reglas son fijas (~$36); el resto es tráfico |
| Cloud NAT | 1 gateway, solo la subred interna | 30 | Casi todo coste fijo del gateway. Acotarlo a una subred no cambia el precio, cambia la seguridad |
| Cloud Armor | 1 política, 4 reglas, 15 M req | 20 | |
| Cloud Storage | ~550 GB entre los 4 buckets (EU multi-región) | 16 | |
| Cloud Run Jobs (batch) | 4 procesos programados | 11 | ~90 h de ejecución/mes |
| Cloud Build | ~2 despliegues/día | 10 | |
| Artifact Registry | ~60 GB de imágenes | 6 | Las políticas de limpieza lo mantienen plano |
| Cloud CDN | caché y cache-fill | 5 | |
| Cloud Monitoring | métricas y uptime checks | 5 | Las métricas de GCP no se facturan |
| BigQuery (analítica de logs) | 50 GB + consultas | 2 | 1 TB/mes de consulta es gratuito |
| Pub/Sub | ~22 M mensajes/mes | 2 | 45 GB sobre 10 GiB gratuitos |
| Secret Manager | 2 secretos | 1 | |
| **Total PROD** | | **1.000** | **$12.000/año** |

### QA

| Servicio | Configuración | $/mes |
|---|---|---:|
| Cloud SQL | 2 vCPU / 7,5 GB, sin HA, con PITR | 115 |
| Cloud Run — API | 1 vCPU / 1 GiB, min 1 | 68 |
| Load Balancer + egress | 2 reglas, tráfico bajo | 38 |
| Cloud NAT | 1 gateway | 30 |
| Cloud Run — worker | min 0 | 10 |
| Cloud Armor | política activa, bloqueando | 10 |
| Cloud Run Jobs | mismos cron que prod | 6 |
| Cloud Logging | retención 14 días | 5 |
| Cloud Build | | 5 |
| Resto (storage, AR, Pub/Sub, monitoring, secretos) | | 10 |
| **Total QA** | | **297** → **$3.564/año** |

### DEV

| Servicio | Configuración | $/mes |
|---|---|---:|
| Cloud SQL | 1 vCPU / 3,75 GB, sin HA ni PITR | 55 |
| Cloud NAT | 1 gateway | 30 |
| Load Balancer | 1 regla (solo HTTP) | 19 |
| Cloud Run — API | escala a cero, media ~0,3 instancias | 15 |
| Cloud Run — worker | escala a cero | 5 |
| Cloud Build | | 5 |
| Resto | | 7 |
| **Total DEV** | | **136** → **$1.632/año** |

### Año 1 consolidado

| Ambiente | $/mes | $/año | Peso |
|---|---:|---:|---:|
| PROD | 1.000 | 12.000 | 70 % |
| QA | 297 | 3.564 | 21 % |
| DEV | 136 | 1.632 | 9 % |
| **Total** | **1.433** | **17.196** | |

---

## 3. Proyección a 3 años

El 30 % anual **no se aplica a todo**. Hay que separar tres comportamientos,
porque aplicar un 1,3× plano al total sobreestima el gasto:

| Comportamiento | Conceptos | Escala |
|---|---|---|
| Proporcional al tráfico | egress, datos del LB, Pub/Sub, logging, Cloud Armor, cómputo de los jobs | ×1,3 anual |
| Escalonado | Cloud SQL (salta al redimensionar), disco | por escalones |
| Prácticamente fijo | reglas de reenvío, gateway NAT, Artifact Registry, secretos, Cloud Build | ~plano |

El cómputo de Cloud Run crece menos que el tráfico (está dominado por las
instancias mínimas), pero se proyecta al 1,3× por prudencia.

### PROD

| Concepto | Año 1 | Año 2 | Año 3 |
|---|---:|---:|---:|
| Cloud SQL | 450 | 458 | **887** |
| Cloud Run (API + worker + jobs) | 328 | 426 | 555 |
| Logging y analítica | 57 | 75 | 97 |
| LB, CDN y egress | 75 | 97 | 126 |
| Cloud NAT | 30 | 33 | 36 |
| Cloud Armor | 20 | 26 | 34 |
| Storage | 16 | 22 | 30 |
| Resto | 24 | 25 | 28 |
| **Total PROD $/mes** | **1.000** | **1.162** | **1.793** |
| **Total PROD $/año** | **12.000** | **13.944** | **21.516** |

El salto del año 3 es casi todo Cloud SQL: con 1,69× la carga inicial, la
instancia de 4 vCPU pasa a 8 vCPU y, al ser HA, el incremento se duplica. **Es
el punto del presupuesto que conviene revisar antes de asumirlo**, porque hay
dos alternativas más baratas que un salto de tier:

1. **Réplica de lectura** (~$200/mes, sin HA) para informes y consultas de
   catálogo, dejando la primaria en 4 vCPU. Sale a cuenta si la carga de
   lectura domina, que es lo habitual en una plataforma de consulta de pedidos.
2. **Cloud SQL Enterprise Plus**, que admite más conexiones y mejor caché por
   vCPU: puede evitar el salto de tamaño a un precio unitario mayor.

Cuál de las dos se elige es una decisión que debe tomarse con las métricas del
año 2 delante, no ahora.

### Consolidado a 3 años

| Ambiente | Año 1 | Año 2 | Año 3 | Total |
|---|---:|---:|---:|---:|
| PROD | 12.000 | 13.944 | 21.516 | 47.460 |
| QA | 3.564 | 3.900 | 4.560 | 12.024 |
| DEV | 1.632 | 1.740 | 1.860 | 5.232 |
| **Total** | **17.196** | **19.584** | **27.936** | **64.716** |

DEV y QA crecen poco: su consumo depende del tamaño del equipo y del volumen de
pruebas, no del número de usuarios de producción.

---

## 4. Palancas de reducción

Ordenadas por ahorro frente a esfuerzo. Las tres primeras son las que
recomendaría aplicar desde el principio.

| # | Medida | Ahorro estimado | Coste de aplicarla |
|---|---|---:|---|
| 1 | **Committed Use Discounts a 1 año** sobre Cloud SQL y Cloud Run de prod | ~**$1.860/año** (~15 % de PROD) | Ninguno técnico; compromiso de gasto. **No se compra desde Terraform**, ver abajo |
| 2 | **Apagar DEV fuera de horario.** Cloud Scheduler detiene la instancia de Cloud SQL por la noche y fines de semana (~128 h/semana de 168) | ~$35/mes ≈ **$420/año** | Un job programado |
| 3 | **Desactivar Cloud NAT en DEV** (`enable_nat = false`). En dev los jobs de intercambio no se ejecutan de forma programada, así que nadie usa la salida | $30/mes ≈ **$360/año** | Un flag en el tfvars. Ojo: deja al worker y a los jobs de dev sin salida a Internet |
| 4 | Afinar la **retención de logs** y ampliar exclusiones una vez se sepa qué se consulta de verdad | $15–25/mes | Revisión de filtros |
| 5 | Bajar el API de prod a **1 vCPU** si las métricas confirman que 2 es holgado | ~$115/mes | Requiere medir antes |
| 6 | CUD a **3 años** en Cloud SQL en lugar de 1 año | ~$1.100/año adicionales | Compromiso largo; solo con la plataforma estabilizada |

Aplicando las medidas 1 a 3, el año 1 baja de **$17.196 a ~$14.600**.

### 4.1 · Los Committed Use Discounts, en detalle

Son la primera palanca y merecen precisión, porque es donde más se exagera.

**Qué servicios de esta plataforma admiten CUD:**

| Servicio | Tipo de compromiso | Descuento aprox. 1 año | Sobre qué parte de la factura |
|---|---|---:|---|
| **Cloud SQL** | Basado en gasto | ~25 % | **Solo vCPU y RAM.** El almacenamiento SSD y los backups **no** son elegibles |
| **Cloud Run** | Basado en gasto | ~17 % | vCPU y memoria del servicio |
| Cloud Storage, Pub/Sub, Logging, LB, NAT | — | **No aplica** | Estos no admiten CUD |

**El cálculo honesto, sobre las cifras de este presupuesto:**

```
Cloud SQL prod   450 $/mes
  − 34 almacenamiento − 20 backups  =  396 $/mes elegibles  × 25 %  =   99 $/mes
Cloud Run prod   328 $/mes (API + worker + jobs)             × 17 %  =   56 $/mes
                                                        ────────────────────────
                                                                       155 $/mes
                                                                     1.860 $/año
```

Eso es un **~15 % de producción**, no el 20 % que diría una estimación rápida.
La diferencia está en que **la mitad de la factura no es elegible**: el
balanceador, el NAT, Cloud Storage, Pub/Sub y Cloud Logging suman ~200 $/mes a
los que ningún compromiso llega.

> Los porcentajes son los habituales de los CUD basados en gasto y conviene
> confirmarlos en la consola de facturación antes de comprometerse: el modelo de
> descuentos de Google cambia, y un compromiso de un año no se deshace.

### 4.2 · Por qué los CUD no están en el código Terraform

**No es un olvido: no existe el recurso.** Verificado contra el esquema del
provider `hashicorp/google` 6.50.0, que declara 1.096 recursos:

| Lo que sí existe | Para qué sirve |
|---|---|
| `google_compute_region_commitment` | **Solo Compute Engine.** Sus valores de `type` son familias de máquina (`GENERAL_PURPOSE_N2`, `MEMORY_OPTIMIZED`…) y su `category` es `MACHINE` o `LICENSE`. No cubre Cloud Run ni Cloud SQL |
| `google_bigquery_capacity_commitment` | Slots de BigQuery |

No hay ningún recurso para los **CUD basados en gasto** de Cloud Run o Cloud SQL.

Y aunque lo hubiera, hay una razón estructural para que no viviera aquí:

| | |
|---|---|
| **Ámbito equivocado** | Un CUD basado en gasto se compra sobre la **cuenta de facturación**, no sobre el proyecto. Este Terraform es de ámbito proyecto, y la service account que lo ejecuta no tiene —ni debe tener— permisos sobre la facturación |
| **Decisión financiera, no técnica** | Comprometer gasto a un año es una decisión que firma quien administra el presupuesto, no un `terraform apply` |
| **Irreversible** | Un `destroy` borraría la infraestructura y dejaría el compromiso vivo, pagándose solo |

**Cómo se compran, entonces:** en la consola de facturación, en
*Committed use discounts → Purchase*, eligiendo servicio, región y gasto por
hora. Se aplican automáticamente al consumo del proyecto sin tocar nada del
despliegue.

**Lo que sí se podría añadir a Terraform y hoy no está:**
`google_billing_budget`, para que salte una alerta al superar un umbral de gasto.
No se incluyó porque requiere el ID de la cuenta de facturación y permisos a
ese nivel, fuera del alcance de la service account de este repositorio. Es una
decisión discutible: si se quiere, son ~15 líneas y una variable más.

---

## 5. Qué no está incluido

Dicho explícitamente para que nadie lo descubra en la primera factura:

- **Soporte de Google Cloud.** El plan Standard parte de ~$29/mes o el 3 % del
  gasto, el que sea mayor. Para producción es recomendable.
- **Impuestos.**
- **Transferencia entre regiones** si más adelante se añade DR en otra región.
- **Dominio y DNS.** Cloud DNS son ~$0,40/zona/mes más consultas; el registro
  del dominio es externo.
- **Herramientas de terceros** (gestión de errores, APM, CI externo) si se
  usaran en lugar de las nativas.
- **Coste de la primera migración de datos**, si hay un sistema anterior.
