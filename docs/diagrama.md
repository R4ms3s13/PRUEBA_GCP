# Diagrama de arquitectura

Documento para compartir con el equipo.

La **fuente de verdad es el código Mermaid**, plegado bajo cada imagen: vive en
el repositorio y se revisa en el mismo *pull request* que el Terraform que
describe, de modo que no puede quedarse desactualizado sin que alguien lo vea.
Los **SVG de `img/`** son una salida, para que el documento se lea igual en
GitHub, en un editor o en un PDF.

Tras tocar cualquier diagrama, regenerar con:

```bash
./docs/render-diagramas.sh
```

El script falla si algún diagrama no renderiza, así que un error de sintaxis se
detecta antes de entregar y no al abrirlo delante de quien lo revisa.

**Los seis diagramas están renderizados y verificados** con `mermaid-cli`.

---

## 1. Vista general

![1. Vista general](img/01-1-vista-general.svg)

<details>
<summary>Codigo fuente del diagrama (Mermaid)</summary>

```mermaid
flowchart TB
    subgraph internet["Internet"]
        usuario["Usuarios<br/>20.000 registrados<br/>2.000 concurrentes"]
        terceros["Aplicaciones<br/>de terceros"]
    end

    subgraph gcp["Proyecto GCP (uno por ambiente)"]
        subgraph publico["Perímetro público"]
            armor["Cloud Armor<br/>WAF + rate limit"]
            lb["Application Load Balancer<br/>externo global + Cloud CDN"]
        end

        subgraph privado["VPC — sin IPs públicas"]
            subgraph snetapp["snet-app 10.x.0.0/22 — SIN Cloud NAT"]
                api["Cloud Run: API<br/>Node.js<br/>ingress solo LB<br/><b>sin ruta a Internet</b>"]
            end

            subgraph snetint["snet-internal 10.x.4.0/22 — CON Cloud NAT"]
                worker["Cloud Run: worker<br/>ingress interno"]
                jobs["Cloud Run Jobs<br/>procesos batch"]
            end

            nat["Cloud NAT<br/>IP de salida fija"]
        end

        subgraph psa["Private Service Access"]
            sql[("Cloud SQL PostgreSQL<br/>IP privada · HA regional")]
        end

        subgraph datos["Servicios gestionados"]
            gcsfront[("GCS: frontend<br/>build de React")]
            gcsup[("GCS: uploads")]
            gcsexp[("GCS: exports")]
            gcsbk[("GCS: backups")]
            ar["Artifact Registry"]
            sm["Secret Manager"]
        end

        subgraph async["Asíncrono"]
            topics["Pub/Sub<br/>topics por dominio"]
            dlq["Pub/Sub DLQ"]
        end

        sched["Cloud Scheduler"]

        subgraph obs["Observabilidad"]
            logging["Cloud Logging<br/>bucket central"]
            monitoring["Cloud Monitoring<br/>alertas + dashboard"]
            errors["Error Reporting<br/>+ Cloud Trace"]
        end
    end

    usuario -->|HTTPS| armor
    armor --> lb
    lb -->|"/"| gcsfront
    lb -->|"/api/*"| api

    api -->|SQL privado| sql
    api -->|publica| topics
    api -->|URL firmada| gcsup
    api -->|lee secreto| sm

    topics -->|push OIDC| worker
    topics -.->|agota reintentos| dlq
    worker --> sql
    worker --> gcsup

    sched -->|OAuth| jobs
    jobs --> sql
    jobs --> gcsexp
    jobs --> gcsbk
    jobs -->|ficheros de intercambio| nat
    worker -->|llamadas a sistemas ajenos| nat
    nat -->|IP fija para su allowlist| terceros

    ar -.->|imagenes| privado
    privado -.->|logs y metricas| logging
    sql -.-> logging
    lb -.-> logging
    logging --> monitoring
    logging --> errors
```

</details>

---

## 2. Flujo de una petición de usuario

![2. Flujo de una petición de usuario](img/02-2-flujo-de-una-peticion-de-usuario.svg)

<details>
<summary>Codigo fuente del diagrama (Mermaid)</summary>

```mermaid
sequenceDiagram
    autonumber
    participant U as Navegador
    participant A as Cloud Armor
    participant L as Load Balancer
    participant C as Cloud CDN
    participant S as GCS frontend
    participant R as Cloud Run API
    participant D as Cloud SQL
    participant P as Pub/Sub
    participant W as Worker

    U->>A: GET /
    A->>A: WAF + rate limit por IP
    A->>L: permitido
    L->>C: ¿está en caché?
    C-->>U: index.html + assets (desde el borde)

    U->>L: POST /api/pedidos
    L->>R: enruta a serverless NEG
    Note over R: autenticación IAM<br/>sin contraseña
    R->>D: INSERT por IP privada
    D-->>R: ok
    R->>P: publica pedido.creado
    R-->>U: 201 Created

    Note over P,W: el usuario ya tiene respuesta<br/>y el trabajo pesado sigue aparte
    P->>W: push con token OIDC
    W->>W: valida token y audiencia
    W->>D: actualiza estado
    W-->>P: ack
```

</details>

---

## 3. Por qué la base de datos no está expuesta

Es el requisito con nombre propio del enunciado, y se resuelve con tres capas:

![3. Por qué la base de datos no está expuesta](img/03-3-por-que-la-base-de-datos-no-esta-expuesta.svg)

<details>
<summary>Codigo fuente del diagrama (Mermaid)</summary>

```mermaid
flowchart LR
    subgraph fuera["Internet"]
        atacante["Cualquier origen"]
    end

    subgraph vpc["VPC del proyecto"]
        cr["Cloud Run<br/>Direct VPC egress<br/>IP de la subnet"]
    end

    subgraph peering["Red de servicios de Google<br/>(VPC peering)"]
        db[("Cloud SQL<br/>ipv4_enabled = false")]
    end

    atacante -.->|"❌ sin IP pública<br/>que alcanzar"| db
    cr -->|"✅ ruta privada<br/>TLS + auth IAM"| db
```

</details>

| Capa | Mecanismo | Qué impide |
|---|---|---|
| Red | `ipv4_enabled = false` sobre Private Service Access | No existe ninguna dirección pública hacia la que dirigir una conexión |
| Ruta | Direct VPC egress en Cloud Run + firewall de egress al 5432 | Solo las dos subredes de la plataforma alcanzan la instancia, y solo por ese puerto |
| Identidad | `cloudsql.iam_authentication` + usuarios de tipo service account | Aun con ruta, hace falta una identidad IAM autorizada; no hay contraseña que robar |

---

## 4. Separación entre componentes públicos y privados

El requisito pide esta separación y aquí se cumple en **tres planos a la vez**.
El plano de red es el que suele faltar, y es el que invierte la intuición:

![4. Separación entre componentes públicos y privados](img/04-4-separacion-entre-componentes-publicos-y-privados.svg)

<details>
<summary>Codigo fuente del diagrama (Mermaid)</summary>

```mermaid
flowchart LR
    internet(["Internet"])

    subgraph app["snet-app · 10.x.0.0/22"]
        api["Cloud Run: API<br/>expuesto vía balanceador"]
    end

    subgraph interna["snet-internal · 10.x.4.0/22"]
        wk["worker"]
        jb["jobs batch"]
    end

    nat["Cloud NAT<br/>IP estática"]
    goog[["APIs de Google<br/>vía Private Google Access"]]

    internet -->|"✅ entra (LB + Cloud Armor)"| api
    api -.->|"❌ NO puede salir<br/>(fuera de la lista del NAT)"| internet
    api --> goog

    wk --> nat
    jb --> nat
    nat -->|"✅ sale con IP fija"| internet
    internet -.->|"❌ NO puede entrar<br/>(ingress interno)"| wk
    wk --> goog
    jb --> goog
```

</details>

| Plano | Mecanismo | Resultado |
|---|---|---|
| Red | `snet-app` fuera de `LIST_OF_SUBNETWORKS` en Cloud NAT | El componente expuesto no puede iniciar conexiones a Internet |
| Egress | `vpc_egress = ALL_TRAFFIC` en los runtimes | Todo el tráfico de salida pasa por la VPC, así que la topología manda |
| Ingress | `INTERNAL_LOAD_BALANCER` en el API, interno en el worker | Nada se alcanza por su URL `run.app` |
| Identidad | Una service account por componente | Comprometer uno no da los permisos de los demás |

**Lo relevante:** si alguien lograra ejecutar código en el API —el único
componente que recibe tráfico de Internet— no tendría por dónde exfiltrar datos
ni por dónde descargar una segunda etapa. El control es la **ausencia de una
ruta**, no una regla de firewall que pueda relajarse. Ver
[decisiones.md, D5b](decisiones.md).

---

## 5. Separación entre ambientes

![5. Separación entre ambientes](img/05-5-separacion-entre-ambientes.svg)

<details>
<summary>Codigo fuente del diagrama (Mermaid)</summary>

```mermaid
flowchart TB
    subgraph repo["Un repositorio · una definición"]
        plat["terraform/platform/<br/>módulo raíz"]
        mod["terraform/modules/<br/>10 módulos"]
    end

    subgraph envs["Tres configuraciones"]
        dev["dev.tfvars<br/>sin HA · escala a 0<br/>destruible"]
        qa["qa.tfvars<br/>topología de prod<br/>capacidad reducida"]
        prod["prod.tfvars<br/>HA · PITR · WAF<br/>protegido"]
    end

    subgraph proyectos["Tres proyectos GCP aislados"]
        pdev["proveedores-dev<br/>10.10.0.0/22 + 10.10.4.0/22"]
        pqa["proveedores-qa<br/>10.20.0.0/22 + 10.20.4.0/22"]
        pprod["proveedores-prod<br/>10.30.0.0/22 + 10.30.4.0/22"]
    end

    plat --> mod
    plat --> dev --> pdev
    plat --> qa --> pqa
    plat --> prod --> pprod
```

</details>

El aislamiento es por **proyecto**, no por etiquetas ni por prefijos de nombre:
el límite de IAM, de cuota y de facturación coincide con el límite del ambiente.
Un error de permisos en dev no puede alcanzar datos de producción.

---

## 6. Pipeline de CI/CD

![6. Pipeline de CI/CD](img/06-6-pipeline-de-ci-cd.svg)

<details>
<summary>Codigo fuente del diagrama (Mermaid)</summary>

```mermaid
flowchart LR
    subgraph infra["Infraestructura · dispara con terraform/**"]
        direction LR
        i1["fmt · validate<br/>tflint · trivy"] --> i2["terraform plan<br/>publicado en el PR"]
        i2 --> i3["apply del plan<br/>guardado"]
    end

    subgraph back["Backend · dispara con app/api, app/worker, app/batch"]
        direction LR
        b1["npm test<br/>+ audit"] --> b2["Build de las<br/>3 imágenes"]
        b2 --> b3["Artifact Registry"]
        b3 --> b4{"Artifact Analysis<br/>¿críticas?"}
        b4 -->|"sí, en prod"| bx["bloqueado"]
        b4 -->|no| b5["Migraciones<br/>expand/contract<br/>dentro de la VPC"]
        b5 --> b6["Deploy dev"] --> b7["Deploy qa<br/>por digest"]
        b7 --> b8{"Aprobación<br/>humana"}
        b8 --> b9["Canary 10%"] --> b10{"¿Errores<br/>en 5 min?"}
        b10 -->|sí| b11["Rollback a la<br/>revisión estable"]
        b10 -->|no| b12["100% del tráfico"]
    end

    subgraph front["Frontend · dispara con app/frontend/**"]
        direction LR
        f1["npm test<br/>+ audit"] --> f2["Build de Vite<br/>un solo artefacto"]
        f2 --> f3["Assets<br/>cache 1 año"]
        f3 --> f4["index.html<br/>sin cache"]
        f4 --> f5["Invalidar CDN<br/>solo /index.html"]
        f5 --> f6["dev · qa · prod"]
    end

    back -.->|"compatibilidad N-1<br/>ningún orden rompe"| front
```

</details>

**Tres pipelines, no uno.** Cada uno se dispara con sus propias rutas y no
espera a los demás ([D9](decisiones.md), [D9b](decisiones.md)): un cambio de CSS
no paga el build de tres imágenes ni las migraciones, y un test del backend en
rojo no bloquea un arreglo de frontend.

La flecha discontinua es el contrato que lo hace seguro: el API mantiene
compatibilidad con la versión N-1 del cliente —obligatorio de todas formas,
porque el canary hace convivir dos revisiones sirviendo tráfico— de modo que
**ningún orden de publicación entre backend y frontend produce una combinación
incompatible**.

La imagen se promociona **por digest**, nunca reconstruyendo: el binario que
pasó las pruebas en QA es bit a bit el que entra en producción. El frontend
sigue el mismo principio con su artefacto: se construye una vez y se publica
tal cual en los tres ambientes.
