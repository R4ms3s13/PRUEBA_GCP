# Decisiones técnicas y sus implicaciones

Cada decisión recoge la alternativa descartada y **qué se pierde** al elegir
como se eligió. Un registro que solo justifica no sirve para revisar.

---

## D1 — Cloud Run como runtime, no GKE

**Decisión.** API, worker y procesos batch sobre Cloud Run (servicios y jobs).

**Por qué.** La carga declarada (2.000 concurrentes, 500.000 operaciones/día)
la cubre un autoescalado por petición sin gestionar nodos. El tráfico de una
plataforma B2B es diurno y de días hábiles: con GKE se paga el valle nocturno;
con Cloud Run, no. Y un clúster añade un plano de control que hay que parchear
y vigilar en tres ambientes sin aportar nada que aquí se necesite.

**Alternativa descartada.** GKE Autopilot. Habría tenido sentido con cargas con
estado, sidecars complejos (service mesh), DaemonSets o necesidad de GPU.

**Qué se pierde.**
- Techo de 60 minutos por petición y de 24 h por ejecución de job.
- Menos control sobre la topología de red del pod y sobre la afinidad.
- Dependencia de un servicio gestionado concreto: migrar a Kubernetes más
  adelante exige rehacer el despliegue, aunque **no** la aplicación (los
  contenedores son los mismos).

**Cuándo reconsiderarlo.** Si aparecen conexiones persistentes de larga
duración (WebSockets masivos), procesos de más de 24 h, o si el gasto en
instancias mínimas supera el coste de un clúster.

---

## D2 — Frontend en Cloud Storage + CDN, no en un contenedor

**Decisión.** El build de React se publica en un bucket servido por un backend
bucket del balanceador con Cloud CDN delante.

> **Desviación explícita del enunciado.** El enunciado pide, bajo *Aplicación*,
> «un runtime para: frontend; backend/API». Un bucket con CDN **no es un
> runtime**, y por tanto esto es una desviación consciente de la letra del
> requisito, no un descuido. El motivo es que el requisito de fondo —servir el
> frontend React— se cumple mejor así, y el enunciado también pide decisiones
> documentadas con sus implicaciones. Si el ejercicio exigiera literalmente un
> runtime, el cambio es pequeño y está acotado: un tercer servicio de Cloud Run
> sirviendo los estáticos y un backend service en lugar del backend bucket en
> `modules/frontend_lb`. Coste de ese cambio: entre 15 y 25 $/mes por ambiente
> en CPU que hoy no se paga, latencia peor para el usuario lejano, y un servicio
> más que escalar, versionar y vigilar. **Recomendación: mantener el bucket.**

**Por qué.** Un SPA compilado es un conjunto de ficheros estáticos. Servirlo
desde un contenedor significa pagar CPU por devolver bytes que el CDN entrega
desde el borde, y añade un servicio más que escalar y vigilar.

**Implicación operativa.** El `index.html` se publica con `no-cache` y los
assets con hash en el nombre con caché de un año. Si se invierte, un despliegue
tarda horas en verse o el navegador pide los assets en cada carga.

**Qué se pierde.** No hay renderizado en servidor. Si en el futuro se necesita
SSR por SEO o por tiempo de primera pintura, el frontend tendría que pasar a
Cloud Run.

---

## D3 — Un dominio para frontend y API

**Decisión.** El mismo balanceador sirve `/` desde el bucket y `/api/*` desde
Cloud Run, bajo un único host.

**Por qué.** Elimina CORS en el navegador, permite cookies de sesión del mismo
sitio (`SameSite=Strict`), y da **un solo punto de entrada** que proteger con
Cloud Armor. Con dominios separados habría dos superficies y dos políticas.

**Qué se pierde.** El `url_map` acopla ambos componentes: un cambio de rutas se
toca en infraestructura, no solo en la aplicación.

---

## D4 — Cloud SQL con IP privada, sin IP pública

**Decisión.** `ipv4_enabled = false` sobre Private Service Access; acceso desde
Cloud Run por Direct VPC egress.

Es la respuesta al requisito explícito *"la base de datos no deberá estar
expuesta directamente a Internet. Deberás decidir cómo resolver la
conectividad."*

**Alternativas descartadas.**

| Opción | Por qué no |
|---|---|
| IP pública + redes autorizadas | La instancia conserva superficie en Internet, y una allowlist no cubre las IPs efímeras de un runtime serverless |
| Cloud SQL Auth Proxy como sidecar | Válido, pero con IP privada y Direct VPC egress no aporta ruta nueva y sí un componente que operar |
| Private Service Connect | Más aislamiento, más piezas. PSA cubre el requisito para este tamaño |

**Defensa en profundidad aplicada.** Tres capas independientes: sin IP pública
(red), firewall de egress al 5432 solo desde la subnet de aplicación (ruta), y
autenticación IAM con usuarios de tipo service account (identidad). Comprometer
una no basta.

**Qué se pierde.** No se puede conectar desde un portátil sin más: hace falta
un bastión, Cloud SQL Studio o el proxy con un túnel IAP. Es un coste real de
operación y es intencionado.

---

## D4b — Por qué Cloud SQL y no Spanner

El enunciado pide «una base de datos relacional administrada», y Spanner lo es.
Merece respuesta explícita, porque es la pregunta natural de un revisor.

**El coste es la tercera razón, no la primera.** Las dos primeras pesan más.

### 1. Spanner no es PostgreSQL

Spanner ofrece un dialecto PostgreSQL y PGAdapter, pero eso es una **interfaz de
compatibilidad, no PostgreSQL**:

- Sin extensiones, sin `pg_trgm`, sin PostGIS.
- Sin triggers ni procedimientos almacenados.
- DDL limitado y asíncrono.
- Semántica transaccional distinta: la aplicación **debe** manejar transacciones
  abortadas y reintentarlas; no es un detalle, es un patrón obligatorio.
- Los ORM del ecosistema Node.js (Prisma, TypeORM, Sequelize) **no funcionan sin
  adaptación**, y las herramientas de migración habituales tampoco.

El enunciado dice que la aplicación «está en proceso de desarrollo». Elegir
Spanner ahora obliga a reescribir la capa de datos de un equipo que ya está
escribiendo contra SQL relacional. **Ese coste supera de largo cualquier
diferencia en la factura de infraestructura.**

### 2. El diseño de claves es una trampa justo en este dominio

Spanner distribuye por rango de clave primaria, así que una clave
**monótonamente creciente concentra toda la escritura en un split**: el
*hotspot* clásico. Una plataforma de pedidos quiere, de forma natural, números
de pedido secuenciales. Con Spanner habría que usar UUID o secuencias con bits
invertidos, y tablas intercaladas para conservar localidad.

Lo peligroso es *cuándo* se nota: en dev, con cien filas, todo va bien. El
precipicio aparece en producción con volumen real.

### 3. La carga no tiene el problema que Spanner resuelve

| | Lo que ofrece Spanner | Lo que necesita esta plataforma |
|---|---|---|
| Escalado de escritura | Horizontal, sin sharding, ilimitado | ~6 req/s de media, ~50 de pico |
| Consistencia | Fuerte y global entre regiones | Una sola región |
| Disponibilidad | 99,999 % multirregión | 99,95 % de Cloud SQL HA es suficiente |

Una instancia de 4 vCPU de PostgreSQL absorbe esta carga con muchísimo margen, y
con el 30 % de crecimiento anual **sigue dentro de una sola instancia durante
todo el horizonte de 3 años**. No hay problema de sharding que resolver.

Y hay una incoherencia que sería difícil de defender: en
[D14](#d14--cómo-se-eliminan-los-puntos-únicos-de-falla) se descarta
explícitamente el multirregión activo-activo. Spanner cuesta sus restricciones
precisamente para dar eso. Se pagaría la factura sin usar la función.

### 4. Y además es más caro, en los tres ambientes

Con precios de lista aproximados y a verificar —el modelo de ediciones de
Spanner cambió en 2025, así que estas cifras son orientativas:

| Ambiente | Cloud SQL (este diseño) | Spanner equivalente |
|---|---:|---:|
| PROD | ~450 $/mes (4 vCPU, HA regional) | ~690 $/mes (1.000 PU + almacenamiento) |
| QA | ~115 $/mes | ~100 $/mes (100 PU) |
| DEV | ~55 $/mes | ~75 $/mes (100 PU, el mínimo) |

En producción, dimensionar Spanner por debajo de 1.000 unidades de proceso deja
de ser una configuración que Google considere adecuada para carga productiva, y
ahí el precio se dispara. En dev ocurre lo contrario y resulta igual de
revelador: **Spanner no escala a cero ni a casi nada**, mientras Cloud SQL
permite una instancia diminuta. Lo que en Cloud Run es una ventaja —pagar el
valle a casi nada— con Spanner desaparece.

### Cuándo sí elegiría Spanner

Si el negocio exigiera **RTO de minutos con tolerancia a la caída de una región
entera**, o throughput de escritura por encima de una instancia, o consistencia
fuerte entre continentes. En ese caso el coste de la capa de datos está
justificado — y la decisión debe tomarse **antes** de escribir la aplicación, no
después.

### El escalón intermedio que sí recomendaría antes de Spanner

**AlloyDB for PostgreSQL**: compatibilidad real con PostgreSQL (no un dialecto),
entre 2 y 4 veces más rendimiento transaccional y motor columnar para analítica
sobre los mismos datos. Cuesta del orden del doble que Cloud SQL y tiene un
mínimo de infraestructura mayor, pero **no obliga a reescribir nada**. Es la vía
natural si PostgreSQL llega a ser el cuello de botella: primero AlloyDB, y solo
si el problema es de escalado horizontal de escritura, Spanner.

---

## D5 — Autenticación IAM en la base de datos

**Decisión.** `cloudsql.iam_authentication = on`, y cada runtime es un usuario
de PostgreSQL de tipo `CLOUD_IAM_SERVICE_ACCOUNT`.

**Por qué.** Es lo que permite cumplir *"no deberán existir credenciales en
código duro"* de verdad y no solo moviéndolas a otro sitio: el API se conecta
con su identidad y **no existe contraseña** que filtrar o rotar.

**Implicación.** Sigue habiendo una contraseña generada para el usuario
administrativo (migraciones y mantenimiento). Se genera con `random_password`,
nunca se escribe, y vive en Secret Manager.

**Limitación que se asume y se mitiga.** Ese valor queda en el state de
Terraform. Mitigación: bucket de state cifrado, versionado, con acceso
restringido al pipeline y con `public_access_prevention`. Endurecimiento
disponible con Terraform ≥ 1.11: argumentos *write-only* (`password_wo`,
`secret_data_wo`) que no persisten en el state. No se ha usado por defecto para
no acoplar el repositorio a versiones muy recientes, y está documentado en el
propio módulo.

---

## D5b — Dos subredes, y la separación hace trabajo real

**Decisión.** La VPC tiene dos subredes y el reparto no es por capas lógicas
sino **por dirección del tráfico**:

| Subred | Quién vive ahí | Cloud NAT | Consecuencia |
|---|---|---|---|
| `snet-app` | El API, único componente alcanzable desde fuera | **No** | No tiene ruta a Internet |
| `snet-internal` | Worker y jobs batch, no alcanzables desde fuera | **Sí** | Salida con IP fija y auditable |

**Por qué así.** El enunciado pide «subnets» y «separación entre componentes
públicos y privados». Partir la red en dos sin que cambie nada sería decorativo.
Esta partición invierte deliberadamente la intuición y produce un control:
**el componente expuesto a Internet es precisamente el que no puede iniciar
conexiones hacia Internet.** Si alguien consigue ejecutar código en el API, no
tiene por dónde exfiltrar datos ni por dónde descargar una segunda etapa.

**La pieza que lo hace funcionar.** Los servicios usan
`vpc_egress = ALL_TRAFFIC`, no `PRIVATE_RANGES_ONLY`. Con `PRIVATE_RANGES_ONLY`
el tráfico público sale por la ruta gestionada de Google **sin pasar por la
VPC**, de modo que la topología de subredes no controlaría nada. Y Cloud NAT se
declara con `LIST_OF_SUBNETWORKS` enumerando solo la subred interna: con
`ALL_SUBNETWORKS` el control se perdería en silencio al crear cualquier subred
nueva.

**Por qué no hay además una regla de firewall que deniegue 0.0.0.0/0 al API.**
Sería tentador como segunda capa, pero el tráfico hacia las APIs de Google vía
Private Google Access tiene como destino direcciones **públicas** de Google: una
denegación general cortaría también Secret Manager, Pub/Sub y Cloud Storage.
Hacerlo correctamente exigiría forzar `restricted.googleapis.com` con zonas
privadas de Cloud DNS —el patrón de VPC Service Controls—, que a esta escala
añade más fragilidad que seguridad. **Una ausencia de ruta es más robusta que una
regla que alguien puede relajar.**

**Qué se pierde.** El API no puede llamar directamente a APIs de terceros. Es
intencionado: ese trabajo pertenece al worker y a los jobs, que es donde el
enunciado lo sitúa. Si mañana el API necesitara una llamada sincrónica a un
tercero, la decisión a tomar es consciente: añadir la subred del API al NAT, o
—mejor— mover esa llamada a un evento asíncrono.

---

## D6 — Pub/Sub con entrega push, no pull

**Decisión.** Suscripciones push al worker de Cloud Run, autenticadas con OIDC.

**Por qué.** Con push, Pub/Sub provoca el escalado de Cloud Run por sí solo. Un
consumidor pull necesitaría un proceso siempre vivo haciendo polling, lo que en
Cloud Run obliga a `min_instances > 0` pagando el valle.

**Lo que esto exige de la aplicación.** El worker **debe ser idempotente**:
Pub/Sub garantiza entrega *al menos una vez*, no exactamente una. Procesar un
mensaje dos veces no puede duplicar un pedido. Es un requisito de diseño de la
aplicación que esta infraestructura impone y conviene decir en voz alta.

**Red de seguridad.** Backoff exponencial (10 s → 600 s) y cola de mensajes
fallidos tras N intentos, con alerta en cuanto el DLQ deja de estar vacío. Un
mensaje nunca se pierde en silencio ni se reintenta en bucle cerrado.

**Punto a verificar en el primer apply.** El worker se despliega con
`ingress = INGRESS_TRAFFIC_INTERNAL_ONLY`, lo más restrictivo. Si las entregas
push de Pub/Sub no llegaran a considerarse tráfico interno en esta
configuración, el worker rechazaría los eventos. El ajuste es una variable
(`worker_ingress = "INGRESS_TRAFFIC_ALL"`) y **no debilita la autorización**: el
worker sigue exigiendo el token OIDC y solo la service account de Pub/Sub tiene
`roles/run.invoker` sobre él. Se deja en el valor restrictivo por defecto y
documentado como primera comprobación, en lugar de relajarlo preventivamente.

---

## D7 — Cloud Run Jobs para el batch

**Decisión.** Procesos batch como jobs, disparados por Cloud Scheduler
(programados) o por el API (bajo demanda).

**Por qué.** Un job tiene ciclo de vida de tarea: termina, tiene código de
salida, reintentos propios y timeout de horas. Un servicio HTTP no expresa
"esto ha terminado bien o mal" y está limitado por el timeout de petición.

**Detalle deliberado.** El job de backup lógico tiene `max_retries = 0`. Si
falla, se quiere ver la alerta, no un segundo volcado compitiendo por E/S con
la base de datos.

**Cuándo no serviría.** Volúmenes que exijan paralelismo masivo o un DAG de
dependencias: ahí la respuesta es Cloud Batch o Dataflow.

---

## D7b — El intercambio con aplicaciones de terceros, en concreto

El enunciado no pide «procesos asíncronos» en abstracto: pide «procesos
asíncronos **para intercambio de información con otras aplicaciones**». Merece
una respuesta nombrada, porque es un requisito de integración y no solo de
desacoplamiento.

Se resuelve por dos caminos, según quién inicia:

| Dirección | Mecanismo | Por qué ese |
|---|---|---|
| **Salida en tiempo casi real** | El API publica en el topic `integracion-salida`; el worker consume y llama al sistema del tercero | El API responde al usuario sin esperar a un sistema externo del que no controlamos la disponibilidad |
| **Salida por lotes** | El job `intercambio-terceros`, cada 4 h, genera y envía los ficheros de intercambio | Muchos ERP y sistemas de proveedores solo aceptan ficheros por lotes, no API |
| **Entrada desde terceros** | El tercero llama a `/api/*` a través del balanceador, con Cloud Armor delante | Ya existe un único punto de entrada protegido; no hace falta otro |

Tres detalles que hacen que esto funcione de verdad contra sistemas ajenos:

1. **IP de salida fija.** Todo el tráfico saliente de worker y jobs pasa por
   Cloud NAT con una IP estática ([D5b](#d5b--dos-subredes-y-la-separación-hace-trabajo-real)).
   Es lo primero que pide un tercero para su allowlist, y con IPs efímeras de
   serverless no se podría dar.
2. **Más tolerancia a fallos ajenos.** El topic `integracion-salida` lleva
   `max_delivery_attempts = 10` y `ack_deadline = 300 s` en producción, frente a
   5 y 60 s de los topics internos: una caída del sistema del tercero no debe
   mandar el mensaje al DLQ en cuestión de minutos.
3. **Nada se pierde en silencio.** Si el tercero sigue caído tras los
   reintentos, el mensaje acaba en el DLQ y salta la alerta 4, que es la única
   señal de que un intercambio no se completó.

---

## D7c — Dónde vive cada valor: el modelo de parametrización

El enunciado exige que la infraestructura sea **parametrizable** y que **no haya
credenciales en código duro**. Conviene ser preciso sobre qué cuenta como
hardcode, porque la respuesta ingenua —convertir todo literal en variable—
produce un módulo con doscientas variables que nadie entiende ni ajusta.

**La distinción que se aplica aquí:**

| | Es parametrización | Es hardcode |
|---|---|---|
| Un `variable` con `default`, tipado y documentado, en un único sitio | ✅ | |
| Un literal dentro del cuerpo de un `resource` | | ❌ |

Un valor dentro de un `variable` ya es configuración: tiene tipo, descripción,
se cambia en un solo lugar y aparece en `terraform plan`. Un literal enterrado
en un recurso no se encuentra, no se documenta y se duplica.

**Tres niveles, por orden de volatilidad:**

1. **`envs/*/terraform.tfvars`** — lo que difiere entre ambientes: tamaños, HA,
   retenciones, dominios, umbrales de alerta, protecciones de borrado.
2. **`platform/variables.tf`** — el estándar de la organización: contrato con la
   aplicación (ruta de salud, puerto, rutas del API), APIs del proyecto, nombre
   del registro, política de egress. Se cambia en un sitio y aplica a los tres.
3. **`modules/*/variables.tf`** — valores de diseño del módulo con un default
   razonable: TTL de CDN, backoff de reintentos, caracteres de la contraseña,
   perfil TLS. Ajustables, pero nadie necesita tocarlos para desplegar.

**Lo que sigue siendo literal, a propósito:**

- **Constantes del proveedor.** Los rangos de health check de Google
  (`35.191.0.0/16`, `130.211.0.0/22`), el issuer OIDC de GitHub, los puertos 80
  y 443, los enums del provider (`COMPARISON_GT`, `ARCHIVED`, `SRC_IPS_V1`).
  Parametrizarlos permitiría configurarlos mal sin aportar nada.
- **Textos legibles.** `description`, `display_name`, títulos del dashboard. Son
  documentación, no configuración.
- **La definición interna de una alerta.** El umbral de CPU **es** variable,
  porque difiere por ambiente; que la ventana sea de 600 s y el agregador
  `ALIGN_MEAN` es *qué es* esa alerta, no cómo se configura.
- **Geometría del dashboard.** Es diseño visual.

**Y lo que no está en ninguna parte del código:** las credenciales. La
contraseña de la base de datos se **genera** (`random_password`), vive en Secret
Manager y los runtimes ni la usan, porque se autentican con IAM
([D5](#d5--autenticación-iam-en-la-base-de-datos)). El pipeline no tiene claves:
federa identidad ([D10](#d10--workload-identity-federation-sin-claves-de-service-account)).

Verificable:

```bash
grep -rniE '(password|secret|api[_-]?key|token)[[:space:]]*=[[:space:]]*"[^"$]' \
  --include='*.tf' --include='*.tfvars' terraform/
# sin resultados
```

---

## D8 — Un proyecto GCP por ambiente

**Decisión.** `proveedores-dev`, `proveedores-qa`, `proveedores-prod`, con
rangos de red disjuntos (10.10 / 10.20 / 10.30).

**Por qué.** El proyecto es el límite natural de IAM, cuota y facturación en
GCP. Con un solo proyecto y separación por etiquetas, un error de permisos
alcanza datos de producción y el coste por ambiente deja de ser medible.

**Cómo se cumple "misma definición, configuraciones diferentes".** Los tres
ambientes instancian el mismo módulo `terraform/platform`. Los ficheros
`envs/*/main.tf` son idénticos salvo el valor de `env`; **toda** la diferencia
vive en `terraform.tfvars`. Es verificable:

```bash
diff <(sed 's/dev/ENV/g' terraform/envs/dev/main.tf) \
     <(sed 's/prod/ENV/g' terraform/envs/prod/main.tf)
```

**Qué se pierde.** Más proyectos que administrar y APIs que habilitar tres
veces. Se compensa automatizando el bootstrap.

**Rangos disjuntos aunque hoy no haya peering.** Cuesta nada decidirlo ahora y
evita renumerar si mañana se conectan (VPN a la red corporativa, por ejemplo).

---

## D9 — Pipelines de infraestructura y de aplicación separados

**Decisión.** La infraestructura tiene su propio pipeline, separado de los de
aplicación, y el módulo de Cloud Run lleva `ignore_changes` sobre la imagen del
contenedor. Los de aplicación son dos —backend y frontend— por el motivo de
[D9b](#d9b--backend-y-frontend-se-despliegan-independientemente): tres en total.

**Por qué.** Cambian a ritmos distintos y tienen riesgos distintos: un
despliegue de aplicación es diario y reversible; un cambio de red o de IAM es
ocasional y puede cortar el servicio. Sin `ignore_changes`, cada
`terraform apply` revertiría el último despliegue a la imagen del tfvars.

**Consecuencia asumida.** El tfvars no refleja la imagen que corre de verdad en
producción. La fuente de verdad del release es Cloud Run, y se consulta con
`gcloud run services describe`. Es el precio de no tener los pipelines
peleándose, y es el reparto correcto: Terraform gobierna la infraestructura,
los pipelines de aplicación gobiernan el release.

**Por eso el reparto de tráfico tampoco está en Terraform.** El canary necesita
el identificador de la revisión estable, que cambia en cada despliegue: es
estado de release, no de infraestructura.

---

## D9b — Backend y frontend se despliegan independientemente

**Decisión.** Tres pipelines, no dos: infraestructura, backend y frontend. Cada
uno con sus propios filtros de ruta (`terraform/**`, `app/api|worker|batch/**`,
`app/frontend/**`) y sin esperar a los demás.

**Por qué.** Es el mismo razonamiento de [D9](#d9--pipelines-de-infraestructura-y-de-aplicación-separados)
aplicado un nivel más abajo. Son artefactos distintos con destinos distintos
—contenedores en Artifact Registry y Cloud Run frente a objetos estáticos en
Cloud Storage— y cadencias distintas: el frontend cambia a diario por motivos
cosméticos, el backend cambia con el modelo de datos.

Acoplarlos cuesta dos cosas medibles:

| | Acoplado | Independiente |
|---|---|---|
| Cambio de solo CSS | ~15 min: tests, 3 imágenes, puerta de vulnerabilidades, migraciones | ~2 min: build, `rsync`, invalidar CDN |
| Un test del backend en rojo | **bloquea un arreglo de frontend** | no lo bloquea |

**El argumento para acoplarlos no resiste.** Sería garantizar que el frontend no
se publique antes del API que lo sirve. Pero en producción el API se despliega
con `--no-traffic --tag=canary` y se promociona en dos tramos, de modo que **la
revisión antigua y la nueva sirven tráfico simultáneamente**. La compatibilidad
retroactiva del API ya es obligatoria, y las migraciones ya tienen que ser
expand/contract por la misma razón. Si el contrato de compatibilidad existe de
todas formas, el orden de publicación deja de ser una restricción: un pipeline
acoplado pagaría el coste sin cobrar el beneficio.

**El contrato, explícito**, porque es lo que sostiene la decisión:

1. El API es compatible con la versión N-1 del cliente. Lo exige el canary, no
   el frontend.
2. Las migraciones son expand/contract: añadir primero, retirar en un despliegue
   posterior.
3. El frontend llama a `/api` relativo ([D3](#d3--un-dominio-para-frontend-y-api)),
   así que el bundle no contiene el host del backend y el mismo artefacto sirve
   en los tres ambientes.

**Dentro del pipeline de frontend sí hay un orden, y es al contrario del
intuitivo:** primero los assets y después `index.html`. Los assets llevan hash
en el nombre, de modo que publicar los nuevos no invalida los que el
`index.html` antiguo sigue pidiendo. Al revés, habría una ventana de segundos en
la que `index.html` pediría assets que todavía no existen. Por eso el `rsync` de
assets excluye `index.html` y este se sube en un paso aparte.

**Consecuencia asumida.** Un cambio que necesite frontend y backend a la vez
—un campo nuevo en un formulario— se publica en dos despliegues, no en uno
atómico. El orden correcto es backend primero, y mientras no esté, el frontend
no debe exponer la función: eso es un *feature flag*, no un problema de
pipeline. Si el equipo creciera hasta necesitar releases coordinados frecuentes,
la respuesta sería versionar el API (`/api/v2`), no volver a acoplar los
pipelines.

**Lo que se pierde.** Un único *smoke test* que valide la pila completa después
de cada cambio. Cada pipeline verifica lo suyo: el backend su `/healthz`, el
frontend que el documento de entrada se sirve. La comprobación end-to-end queda
en el *uptime check* de Cloud Monitoring, que corre continuamente y no por
despliegue.

---

## D10 — Workload Identity Federation, sin claves de service account

**Decisión.** El CI/CD se autentica federando el token OIDC del proveedor; no
hay ninguna clave JSON descargada.

**Por qué.** Una clave de service account en los secretos del repositorio es
una credencial de larga duración que no caduca, no rota y se filtra en cuanto
alguien la copia a su máquina. La federación entrega tokens de minutos.

**El control que de verdad importa.** `attribute_condition` restringido al
repositorio exacto. Sin esa condición, **cualquier** repositorio de GitHub
podría pedir un token para este proyecto. En prod se restringe además a la rama
protegida.

---

## D11 — Promoción de imágenes por digest

**Decisión.** De QA a producción se copia la imagen por digest
(`...@sha256:...`), nunca se reconstruye.

**Por qué.** Una etiqueta puede reescribirse; un digest no. Reconstruir desde
el mismo commit puede producir una imagen distinta (dependencias transitivas,
imagen base actualizada, orden de ficheros). Promocionar por digest es lo que
hace que *el binario validado en QA sea bit a bit el que entra en producción*.

**Refuerzo.** `immutable_tags` activado en el registro de producción.

---

## D12 — WAF en modo observación al estrenarse

**Decisión.** `waf_preview_mode = true` por defecto; en QA se pone a `false`.

**Por qué.** Las reglas preconfiguradas de OWASP generan falsos positivos sobre
aplicaciones reales (un campo de texto con comillas puede parecer SQLi). Activar
el bloqueo a ciegas en producción provoca una incidencia el primer día.

**Procedimiento.** Estrenar en preview, revisar en los logs qué habría
bloqueado, ajustar, y solo entonces pasar a bloqueo. QA va con bloqueo activo
precisamente para que los falsos positivos aparezcan allí.

---

## D13 — Alertas mínimas y accionables

**Decisión.** Ocho políticas de alerta, cada una con una acción clara y las
críticas con procedimiento escrito en el campo `documentation`.

**Por qué.** Más alertas que capacidad de respuesta produce fatiga: se silencian
y entonces no sirve ninguna. Se alerta de disponibilidad externa, errores 5xx,
latencia p95, DLQ no vacío, CPU y disco de la base de datos, saturación de
Cloud Run y fallos de batch.

**Nota sobre la latencia.** Se alerta sobre **p95**, no sobre la media: la media
esconde la cola, y la cola es lo que sufre el usuario.

**Lo que deliberadamente no se alerta.** Métricas sin acción asociada (uso de
memoria sin umbral de impacto, número de peticiones). Van al dashboard, que es
donde se mira cuando ya hay un incidente.

---

## D14 — Cómo se eliminan los puntos únicos de falla

El requisito pide eliminarlos *"cuando sea razonable"*. Lo que se ha hecho y
lo que se ha dejado fuera a propósito:

| Componente | Punto único | Cómo se resuelve | Coste |
|---|---|---|---|
| Base de datos | Instancia en una zona | `availability_type = REGIONAL`: standby síncrono en otra zona con failover automático | ×2 el cómputo (~$225/mes) |
| Runtime | Instancia única | Cloud Run reparte entre zonas; `min_instances = 2` en prod garantiza capacidad en más de una | Incluido |
| Entrada | — | El balanceador global es anycast y redundante por diseño | Incluido |
| Estáticos y archivos | Pérdida de una región | Buckets multi-región (`eu`) | ~30 % más por GB |
| Backups | Perder origen y copia juntos | Backups de Cloud SQL en multi-región `eu`; bucket de backups en `europe-west4` | Marginal |
| **Región completa** | **Sí, queda** | **No resuelto a propósito** | Ver abajo |

**Lo que no se cubre: la caída de una región entera.** Un despliegue activo-activo
multirregión exigiría replicación de base de datos entre regiones, balanceo
global con failover y resolver la consistencia de escrituras. Multiplicaría el
coste y la complejidad operativa para un riesgo que, con el RTO que una
plataforma de gestión de proveedores suele admitir, se cubre con un plan de
recuperación: los backups están en multi-región y la infraestructura es
reproducible con un `terraform apply` apuntando a otra región.

Es una decisión que debe **validarse con el negocio**, no asumirse: si el RTO
exigido fuera de minutos y no de horas, habría que replantearla.

---

## D15 — Recuperación de la base de datos

Tres mecanismos complementarios, porque cada uno cubre un fallo distinto:

| Mecanismo | Cubre | Ventana |
|---|---|---|
| Backups automáticos (30 retenidos en prod) | Corrupción o pérdida de datos | Diaria |
| Point-in-time recovery (7 días de WAL) | Error humano con hora conocida: un `DELETE` sin `WHERE` | Al segundo |
| `pg_dump` lógico a Cloud Storage (job nocturno) | **Borrado de la propia instancia**, que se llevaría sus backups con ella | Diaria |

El tercero es el que suele faltar: los backups gestionados viven con la
instancia. Por eso existe el job `backup-logico-bbdd`, con su bucket versionado
en otra región.

**Protecciones contra el borrado accidental:** `deletion_protection` en la
instancia de prod, `deletion_policy = ABANDON` en la base de datos, y
`force_destroy = false` en los buckets de producción.

**Un procedimiento de recuperación no probado no es un procedimiento.** De ahí
que QA tenga PITR activado aunque no tenga HA: es el ambiente donde se ensaya
la restauración antes de necesitarla de verdad.

---

## D16 — Qué pasa si el repositorio se compromete

**La pregunta.** El pipeline despliega con permisos amplios. Si alguien consigue
escribir en el repositorio, ¿qué lo detiene?

**Decisión.** Defensa en capas, asumiendo explícitamente que **una de ellas no
vive en Terraform** y nombrándola igual.

### Lo que ya impide el daño

| Control | Dónde | Qué para |
|---|---|---|
| **Sin claves de service account** | WIF en `bootstrap/` ([D10](#d10--workload-identity-federation-sin-claves-de-service-account)) | No hay secreto que robar del repositorio. Lo que se filtra no es reutilizable fuera de una ejecución de GitHub Actions |
| **Condición de repositorio** | `attribute_condition` | Ningún *otro* repositorio puede federar identidad contra este proyecto |
| **Lista blanca de workflows** | `attribute_condition` sobre `job_workflow_ref` | Un workflow **nuevo**, inyectado por quien tenga escritura, no obtiene token: solo `infra.yml`, `backend.yml` y `frontend.yml` pueden federar |
| **Prod solo desde la rama protegida** | `principalSet` con `attribute.ref` | Una rama cualquiera no despliega en producción |
| **Aprobación humana en prod** | `environment: prod` | Un push no llega solo a producción |
| **Tres proyectos GCP** | [D8](#d8--un-proyecto-gcp-por-ambiente) | Comprometer dev no da acceso a prod: son límites de IAM distintos |
| **Etiquetas inmutables en prod** | `registry_immutable_tags = true` | No se puede reescribir por debajo una etiqueta ya publicada |
| **Promoción por digest** | [D11](#d11--promoción-de-imágenes-por-digest) | Producción recibe el binario exacto validado en QA |
| **Canary sin tráfico** | `--no-traffic --tag=canary` | Una revisión maliciosa no recibe el 100% del tráfico de inmediato |
| **Acciones fijadas por SHA** | los tres workflows | Una etiqueta móvil como `@master` ejecuta en el *runner*, con el token OIDC delante, el código que su autor decida hoy. Un SHA no cambia |
| **Dependabot** | `.github/dependabot.yml` | Un pin que nadie actualiza se queda con los fallos del día que se puso: esto lo convierte en un PR revisado |

### Lo que NO está cubierto, y es lo importante

**Modificar uno de los tres workflows ya autorizados.** Quien tenga escritura en
la rama protegida reescribe `backend.yml` y el pipeline hace lo que él quiera con
los permisos del *deployer*. Ninguno de los controles de arriba lo impide: la
identidad federa correctamente porque el repositorio y el workflow **sí** son los
autorizados.

Eso lo para **la protección de rama con revisión obligatoria**, que es un control
de GitHub y **no de Terraform**: este repositorio no gestiona la configuración de
GitHub. Es el requisito que hay que exigir fuera del código, y se enuncia aquí
para que no quede como un olvido:

- `main` protegida, sin `force push` y sin borrado.
- Revisión obligatoria de al menos una persona distinta del autor.
- `CODEOWNERS` sobre `.github/workflows/` y `terraform/`, para que un cambio en
  el pipeline exija aprobación de plataforma.
- Revisores obligatorios en el *environment* `prod`.

**Y dos más que siguen abiertos:**

1. **La SA de Terraform tiene `resourcemanager.projectIamAdmin` e
   `iam.serviceAccountAdmin`.** Un pipeline de infraestructura comprometido
   **se concede a sí mismo cualquier rol**, lo que vuelve teórico el «sin roles
   básicos». Quitarlo exige mover los cambios de IAM a un camino con aprobación
   aparte, y es el siguiente endurecimiento que haría.
2. **Binary Authorization no está aplicado** (ver el apartado 15 del README).
   Es el único control que impediría admitir una imagen que no pasó por el
   pipeline. Está en el diseño y no en el código.

### Lo que se pierde

La lista blanca de workflows **acopla el bootstrap a los nombres de los ficheros
de CI/CD**: renombrar `backend.yml` sin actualizar `allowed_workflows` deja el
pipeline sin poder autenticarse, con un error de federación que no dice
claramente que la causa es un nombre de fichero. Es un fallo molesto de
diagnosticar, y se acepta porque la alternativa —cualquier workflow del
repositorio puede desplegar— es exactamente el agujero que esta decisión cierra.

El pin por SHA cuesta legibilidad: `actions/checkout@11d5960...` no dice qué
versión es. De ahí el comentario `# v4` al lado de cada uno, que es
documentación y no control: quien quiera verificarlo tiene que resolver el SHA.
