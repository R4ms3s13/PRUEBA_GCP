# ---------------------------------------------------------------------------
# Contrato unico de la plataforma.
#
# Los tres ambientes instancian ESTE modulo. La definicion de infraestructura es
# por tanto identica, y lo unico que cambia es el valor de estas variables,
# fijado en el tfvars de cada ambiente. Es la respuesta directa al requisito:
# "Los tres ambientes deberan utilizar la misma definicion de infraestructura,
# pero con configuraciones diferentes."
# ---------------------------------------------------------------------------

variable "project_id" {
  description = "Proyecto GCP del ambiente. Un proyecto por ambiente."
  type        = string
}

variable "env" {
  description = "Identificador del ambiente."
  type        = string

  validation {
    condition     = contains(["dev", "qa", "prod"], var.env)
    error_message = "env debe ser dev, qa o prod."
  }
}

variable "region" {
  description = "Region principal."
  type        = string
  default     = "europe-west1"
}

variable "name_prefix" {
  description = "Prefijo de todos los nombres de recurso."
  type        = string
  default     = null
}

# --- Red ---

variable "subnet_app_cidr" {
  description = <<-EOT
    CIDR de la subnet del API, el componente expuesto a traves del balanceador.
    Queda FUERA de Cloud NAT a proposito: sin ruta a Internet.
    No debe solaparse entre ambientes.
  EOT
  type        = string
}

variable "subnet_internal_cidr" {
  description = <<-EOT
    CIDR de la subnet de los componentes internos (worker y jobs batch), la
    unica traducida por Cloud NAT: de ahi sale el intercambio con aplicaciones
    de terceros por una IP fija.
  EOT
  type        = string
}

variable "psa_cidr" {
  description = "Direccion base del rango de Private Service Access."
  type        = string
}

variable "psa_prefix_length" {
  description = "Longitud del prefijo del rango de Private Service Access. /20 da holgura para la instancia de Cloud SQL y sus replicas."
  type        = number
  default     = 20
}

variable "enable_nat" {
  description = "Crea Cloud NAT para la subred interna. false deja al worker y a los jobs sin poder llamar a sistemas de terceros."
  type        = bool
  default     = true
}

# --- Runtime ---

variable "api_image" {
  description = <<-EOT
    Imagen del API. En el primer apply el repositorio esta vacio, asi que el
    valor por defecto es la imagen publica de ejemplo de Cloud Run: la
    infraestructura queda desplegada y verificable antes de que exista la
    aplicacion. A partir de ahi la sustituye el pipeline, y el modulo ignora los
    cambios de imagen para no revertir despliegues.
  EOT
  type        = string
  default     = "us-docker.pkg.dev/cloudrun/container/hello"
}

variable "worker_image" {
  description = "Imagen del worker. La gobierna el pipeline de aplicacion; el modulo ignora sus cambios para no revertir despliegues."
  type        = string
  default     = "us-docker.pkg.dev/cloudrun/container/hello"
}

variable "batch_image" {
  description = "Imagen de los procesos batch. La gobierna el pipeline de aplicacion."
  type        = string
  default     = "us-docker.pkg.dev/cloudrun/container/hello"
}

variable "api_cpu" {
  description = "vCPU por instancia del API."
  type        = string
  default     = "1"
}

variable "api_memory" {
  description = "Memoria por instancia del API. El volumen temporal cuenta contra este limite."
  type        = string
  default     = "512Mi"
}

variable "api_min_instances" {
  description = "> 0 elimina el arranque en frio. Imprescindible en prod."
  type        = number
  default     = 0
}

variable "api_max_instances" {
  description = "Techo de escalado del API. Se fija junto a db_max_connections: es lo que impide agotar las conexiones de PostgreSQL."
  type        = number
  default     = 10
}

variable "api_max_concurrency" {
  description = "Peticiones simultaneas por instancia del API."
  type        = number
  default     = 80
}

variable "worker_cpu" {
  description = "vCPU por instancia del worker."
  type        = string
  default     = "1"
}

variable "worker_memory" {
  description = "Memoria por instancia del worker."
  type        = string
  default     = "512Mi"
}

variable "worker_ingress" {
  description = <<-EOT
    Ingress del worker. INGRESS_TRAFFIC_INTERNAL_ONLY es lo mas restrictivo y
    es el valor por defecto. Si las entregas push de Pub/Sub no llegasen a
    considerarse trafico interno en esta configuracion, el ajuste es
    INGRESS_TRAFFIC_ALL: la autorizacion no se debilita, porque el worker sigue
    exigiendo token OIDC y solo la service account de Pub/Sub tiene
    roles/run.invoker sobre el. Es el primer punto a verificar en un apply real.
  EOT
  type        = string
  default     = "INGRESS_TRAFFIC_INTERNAL_ONLY"

  validation {
    condition = contains(
      ["INGRESS_TRAFFIC_INTERNAL_ONLY", "INGRESS_TRAFFIC_ALL"],
      var.worker_ingress
    )
    error_message = "worker_ingress debe ser INGRESS_TRAFFIC_INTERNAL_ONLY o INGRESS_TRAFFIC_ALL."
  }
}

variable "worker_min_instances" {
  description = "Instancias del worker siempre activas. Mayor que 0 evita latencia en el primer evento tras un periodo sin trafico."
  type        = number
  default     = 0
}

variable "worker_max_instances" {
  description = "Techo de escalado del worker. Cuenta, junto al del API, para el reparto del pool de conexiones."
  type        = number
  default     = 5
}

# --- Base de datos ---

variable "db_tier" {
  description = "Tipo de maquina de Cloud SQL. Es el parametro que mas pesa en el coste total de la plataforma."
  type        = string
  default     = "db-custom-1-3840"
}

variable "db_highly_available" {
  description = "Activa el standby sincrono en otra zona con failover automatico. Duplica el coste de computo de la instancia y elimina el punto unico de falla del plano de datos."
  type        = bool
  default     = false
}

variable "db_disk_size_gb" {
  description = "Tamano inicial del disco de la base de datos. Crece solo con autoresize."
  type        = number
  default     = 20
}

variable "db_max_connections" {
  description = "Conexiones simultaneas que admite el motor. Se fija junto a los maximos de instancias de Cloud Run."
  type        = number
  default     = 100
}

variable "db_point_in_time_recovery" {
  description = "Habilita la recuperacion a un instante concreto mediante registros WAL."
  type        = bool
  default     = false
}

variable "db_retained_backups" {
  description = "Numero de backups automaticos conservados."
  type        = number
  default     = 7
}

variable "db_transaction_log_retention_days" {
  description = "Ventana en dias dentro de la cual se puede recuperar a un punto en el tiempo."
  type        = number
  default     = 7
}

variable "db_deletion_protection" {
  description = "Impide destruir la instancia desde Terraform y desde la consola. Debe estar activo en produccion."
  type        = bool
  default     = true
}

variable "db_backup_location" {
  description = "Region de los backups. Distinta de la principal en prod."
  type        = string
  default     = null
}

# --- Almacenamiento ---

variable "storage_location" {
  description = "Ubicacion de los buckets operativos. Una multi-region sobrevive a la perdida de una region."
  type        = string
  default     = "EU"
}

variable "storage_backup_location" {
  description = "Ubicacion del bucket de backups. En produccion, distinta de la region principal."
  type        = string
  default     = "EUROPE-WEST4"
}

variable "uploads_retention_days" {
  description = "Retencion inmutable de los archivos subidos, en dias. 0 la desactiva."
  type        = number
  default     = 0
}

variable "force_destroy_buckets" {
  description = "true solo en dev/qa: permite un destroy limpio."
  type        = bool
  default     = false
}

# --- Punto de entrada publico ---

variable "domains" {
  description = "Dominios del certificado gestionado."
  type        = list(string)
  default     = []
}

variable "enable_https" {
  description = "Crea el certificado gestionado y la redireccion a HTTPS. false permite probar en dev sin DNS delegado."
  type        = bool
  default     = true
}

variable "enable_cloud_armor" {
  description = "Activa el WAF y la limitacion de tasa delante del punto de entrada publico."
  type        = bool
  default     = true
}

variable "waf_preview_mode" {
  description = "Deja las reglas del WAF en observacion: registran lo que bloquearian sin bloquear. Es como deben estrenarse, para detectar falsos positivos."
  type        = bool
  default     = true
}

variable "rate_limit_requests" {
  description = "Peticiones por IP e intervalo antes del baneo temporal."
  type        = number
  default     = 300
}

# --- Observabilidad ---

variable "alert_emails" {
  description = "Mapa etiqueta a email de los destinatarios de las alertas. Mapa y no lista para que renombrar uno no recree los demas."
  type        = map(string)
  default     = {}
}

variable "log_retention_days" {
  description = "Dias que se conservan los logs en el bucket central."
  type        = number
  default     = 30
}

variable "enable_bigquery_sink" {
  description = "Exporta los logs a BigQuery para analitica con SQL. Solo se justifica en produccion."
  type        = bool
  default     = false
}

variable "latency_p95_threshold_ms" {
  description = "Latencia p95 en milisegundos que dispara la alerta de degradacion."
  type        = number
  default     = 2000
}

variable "error_rate_threshold" {
  description = "Peticiones 5xx por segundo que disparan la alerta de errores."
  type        = number
  default     = 1
}

# --- Batch y asincrono ---

variable "batch_jobs" {
  description = "Procesos batch del ambiente. Ver modulo cloud_run_job."
  type = map(object({
    description     = string
    command         = optional(list(string))
    args            = optional(list(string))
    schedule        = optional(string)
    cpu             = optional(string, "1")
    memory          = optional(string, "1Gi")
    task_count      = optional(number, 1)
    parallelism     = optional(number, 1)
    max_retries     = optional(number, 2)
    timeout_seconds = optional(number, 3600)
    vpc_egress      = optional(string, "ALL_TRAFFIC")
    env_vars = optional(map(string), {
    })
  }))
  default = {}
}

variable "pubsub_topics" {
  description = "Topics de eventos asincronos y la ruta del worker que los procesa."
  type = map(object({
    path                  = string
    ack_deadline_seconds  = optional(number, 60)
    retention_duration    = optional(string, "604800s")
    max_delivery_attempts = optional(number, 5)
    ordered               = optional(bool, false)
    schema_id             = optional(string)
  }))
  default = {}
}

variable "time_zone" {
  description = "Zona horaria en la que se interpretan las expresiones cron de los procesos batch."
  type        = string
  default     = "Europe/Madrid"
}

# --- Metadatos ---

variable "extra_labels" {
  description = "Etiquetas adicionales que se anaden a las de la plataforma."
  type        = map(string)
  default     = {}
}

# ===========================================================================
# ESTANDAR DE LA ORGANIZACION
#
# Dos niveles de parametrizacion, a proposito:
#
#   - Variables de ESTE fichero con default: el estandar de la plataforma. Se
#     cambian en un solo sitio y aplican a los tres ambientes. Siguen siendo
#     parametros (tipados, documentados, en un unico lugar), no literales
#     enterrados dentro de un recurso.
#   - Variables que los envs/*/terraform.tfvars pasan explicitamente: lo que
#     DIFIERE entre ambientes.
#
# Ningun modulo contiene un valor escrito a mano que no sea una constante del
# propio proveedor (rangos de health check de Google, issuer OIDC de GitHub,
# puertos 80 y 443).
# ===========================================================================

variable "app_name" {
  description = "Nombre de la aplicacion. Va a las etiquetas de todos los recursos."
  type        = string
  default     = "plataforma-proveedores"
}

# --- Contrato con el equipo de desarrollo -----------------------------------
#
# Estos cuatro valores los consume la infraestructura en varios sitios a la vez
# (runtimes, balanceador, uptime check, exclusion de logs). Viven aqui, en una
# sola fuente, precisamente para que cambiar la ruta de salud sea un cambio de
# una linea y no una caceria por cuatro ficheros.

variable "app_health_path" {
  description = "Ruta de salud que expone la aplicacion."
  type        = string
  default     = "/healthz"
}

variable "app_container_port" {
  description = "Puerto en el que escucha el contenedor."
  type        = number
  default     = 8080
}

variable "app_api_path_patterns" {
  description = "Rutas que el balanceador enruta al API en lugar del frontend."
  type        = list(string)
  default     = ["/api", "/api/*"]
}

variable "app_tmp_mount_path" {
  description = "Punto de montaje del volumen temporal en memoria."
  type        = string
  default     = "/tmp"
}

# --- Servicios del proyecto -------------------------------------------------

variable "project_services" {
  description = "APIs de GCP que la plataforma necesita habilitadas."
  type        = list(string)
  default = [
    "compute.googleapis.com",
    "run.googleapis.com",
    "sqladmin.googleapis.com",
    "servicenetworking.googleapis.com",
    "secretmanager.googleapis.com",
    "artifactregistry.googleapis.com",
    "pubsub.googleapis.com",
    "cloudscheduler.googleapis.com",
    "cloudbuild.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "cloudtrace.googleapis.com",
    "clouderrorreporting.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "storage.googleapis.com",
    "bigquery.googleapis.com",
    "containerscanning.googleapis.com",
  ]
}

# --- Red --------------------------------------------------------------------

variable "nat_min_ports_per_vm" {
  description = "Puertos de origen que Cloud NAT reserva por instancia. Si se agotan, las conexiones salientes fallan de forma intermitente."
  type        = number
  default     = 64
}

variable "vpc_flow_sampling" {
  description = "Fraccion de flujos VPC registrados. Mas alto en prod."
  type        = number
  default     = 0.1

  validation {
    condition     = var.vpc_flow_sampling >= 0 && var.vpc_flow_sampling <= 1
    error_message = "vpc_flow_sampling es una fraccion entre 0 y 1."
  }
}

variable "runtime_vpc_egress" {
  description = <<-EOT
    ALL_TRAFFIC envia toda la salida por la VPC, y es lo que hace que la
    topologia de subredes sea un control real de seguridad (ver D5b).
    Cambiarlo a PRIVATE_RANGES_ONLY desactiva ese control.
  EOT
  type        = string
  default     = "ALL_TRAFFIC"

  validation {
    condition     = contains(["ALL_TRAFFIC", "PRIVATE_RANGES_ONLY"], var.runtime_vpc_egress)
    error_message = "runtime_vpc_egress debe ser ALL_TRAFFIC o PRIVATE_RANGES_ONLY. Con PRIVATE_RANGES_ONLY se desactiva el control de salida basado en subredes (ver D5b)."
  }
}

# --- Runtime ----------------------------------------------------------------

variable "api_ingress" {
  description = "Quien puede llegar al API. Por defecto, solo el balanceador."
  type        = string
  default     = "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER"

  validation {
    condition     = contains(["INGRESS_TRAFFIC_ALL", "INGRESS_TRAFFIC_INTERNAL_ONLY", "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER"], var.api_ingress)
    error_message = "api_ingress debe ser uno de los tres valores admitidos por Cloud Run."
  }
}

variable "api_request_timeout_seconds" {
  description = "Un API de pedidos no deberia necesitar mas: libera instancias antes."
  type        = number
  default     = 60
}

variable "api_tmp_size_limit" {
  description = "Volumen temporal del API. CUENTA contra api_memory."
  type        = string
  default     = "64Mi"
}

variable "worker_max_concurrency" {
  description = "Mensajes simultaneos por instancia del worker."
  type        = number
  default     = 10
}

variable "worker_cpu_idle" {
  description = "false mantiene CPU tras el ack: el worker sigue trabajando."
  type        = bool
  default     = false
}

variable "worker_request_timeout_seconds" {
  description = "Un intercambio con un tercero puede tardar mas que una request de usuario."
  type        = number
  default     = 300
}

variable "worker_tmp_size_limit" {
  description = "Tamano del volumen temporal del worker. Cuenta contra worker_memory."
  type        = string
  default     = "64Mi"
}

variable "startup_probe_delay" {
  description = "Segundos de espera antes de la primera sonda de arranque de los runtimes."
  type        = number
  default     = 5
}

variable "startup_probe_failures" {
  description = "Intentos antes de declarar fallido el arranque."
  type        = number
  default     = 12
}

variable "runtime_deletion_protection" {
  description = "Impide borrar los servicios de Cloud Run. true en prod."
  type        = bool
  default     = false
}

variable "secret_version" {
  description = <<-EOT
    Version de los secretos que montan los runtimes. "latest" hace que una
    rotacion se recoja en el siguiente despliegue; fijar un numero da control
    total a costa de tener que actualizarlo a mano al rotar.
  EOT
  type        = string
  default     = "latest"
}

# --- Registro de imagenes ---------------------------------------------------

variable "registry_repository_id" {
  description = "Nombre del repositorio de Artifact Registry. Fuente unica: el output image_base se deriva de el."
  type        = string
  default     = "plataforma"
}

variable "registry_immutable_tags" {
  description = "Una etiqueta publicada no puede reescribirse. true en prod."
  type        = bool
  default     = false
}

variable "registry_keep_recent_versions" {
  description = "Versiones recientes que la limpieza conserva de cada imagen. Es lo que permite revertir a un release anterior."
  type        = number
  default     = 10
}

variable "registry_tracked_images" {
  description = "Imagenes cuyo historico se conserva."
  type        = list(string)
  default     = ["api", "worker", "batch"]
}

variable "registry_untagged_ttl_days" {
  description = "Dias que sobrevive una imagen sin etiqueta antes de borrarse. Las huerfanas de builds fallidos son la principal fuente de crecimiento del registro."
  type        = number
  default     = 7
}

variable "registry_cleanup_dry_run" {
  description = "true evalua las politicas de limpieza sin borrar nada."
  type        = bool
  default     = false
}

# --- Almacenamiento ---------------------------------------------------------

variable "exports_retention_days" {
  description = "Dias que se conservan las salidas de los procesos batch. Son regenerables."
  type        = number
  default     = 30
}

variable "db_backup_retention_days" {
  description = "Retencion de los volcados logicos de la BBDD en Cloud Storage."
  type        = number
  default     = 30
}

variable "frontend_keep_versions" {
  description = "Versiones del build estatico que permiten revertir un despliegue."
  type        = number
  default     = 5
}

# --- Base de datos ----------------------------------------------------------

variable "db_version" {
  description = "Version del motor de PostgreSQL. Subirla implica reinicio, asi que se fija explicitamente."
  type        = string
  default     = "POSTGRES_16"
}

variable "db_edition" {
  description = "Edicion de Cloud SQL. ENTERPRISE_PLUS admite mas conexiones y mejor cache por vCPU, a mayor precio unitario."
  type        = string
  default     = "ENTERPRISE"
}

variable "db_name" {
  description = "Nombre de la base de datos logica que usa la aplicacion."
  type        = string
  default     = "proveedores"
}

variable "db_app_user" {
  description = "Usuario administrativo, solo para migraciones y mantenimiento."
  type        = string
  default     = "app"
}

variable "db_collation" {
  description = "Afecta al ORDER BY de los textos. No cambiar tras el primer apply."
  type        = string
  default     = "en_US.UTF8"
}

variable "db_disk_autoresize_limit_gb" {
  description = "Techo del crecimiento automatico: evita una factura silenciosa."
  type        = number
  default     = 100
}

variable "db_log_min_duration_ms" {
  description = "Umbral de consulta lenta registrada en Cloud Logging."
  type        = number
  default     = 1000
}

variable "db_extra_flags" {
  description = "Flags adicionales del motor, por si un ambiente necesita afinar."
  type        = map(string)
  default = {
  }
}

variable "db_backup_start_time" {
  description = "Hora UTC de la ventana de backup."
  type        = string
  default     = "02:00"
}

variable "db_maintenance_day" {
  description = "1 = lunes ... 7 = domingo."
  type        = number
  default     = 7
}

variable "db_maintenance_hour" {
  description = "Hora UTC de inicio de la ventana de mantenimiento de Cloud SQL."
  type        = number
  default     = 3
}

variable "db_password_rotation_token" {
  description = "Cambiar este valor regenera la contrasena administrativa."
  type        = string
  default     = "v1"
}

# --- Perimetro publico ------------------------------------------------------

variable "rate_limit_interval_sec" {
  description = "Ventana en segundos sobre la que se cuenta el limite de tasa de Cloud Armor."
  type        = number
  default     = 60
}

variable "enable_adaptive_protection" {
  description = "Deteccion adaptativa de DDoS L7. Requiere Cloud Armor Enterprise."
  type        = bool
  default     = false
}

# --- Observabilidad ---------------------------------------------------------

variable "log_index_fields" {
  description = <<-EOT
    Campos del jsonPayload que se indexan en el bucket de logs. Son del dominio
    de la aplicacion, no de la infraestructura.
  EOT
  type        = list(string)
  default     = ["jsonPayload.orderId", "jsonPayload.supplierId"]
}

variable "uptime_check_regions" {
  description = "Regiones desde las que se comprueba la disponibilidad."
  type        = list(string)
  default     = ["EUROPE", "USA", "SOUTH_AMERICA"]
}

variable "bigquery_location" {
  description = "Ubicacion del dataset de analitica de logs."
  type        = string
  default     = "EU"
}

variable "bigquery_table_expiration_days" {
  description = "Dias tras los que caducan las tablas particionadas de logs en BigQuery."
  type        = number
  default     = 90
}

variable "db_cpu_alert_threshold" {
  description = "Fraccion de CPU de Cloud SQL sostenida que dispara la alerta. Antecede a la degradacion general."
  type        = number
  default     = 0.8

  validation {
    condition     = var.db_cpu_alert_threshold > 0 && var.db_cpu_alert_threshold <= 1
    error_message = "db_cpu_alert_threshold es una fraccion entre 0 y 1."
  }
}

variable "db_disk_alert_threshold" {
  description = "Fraccion de disco de Cloud SQL que dispara la alerta. Un disco lleno es una caida total."
  type        = number
  default     = 0.85

  validation {
    condition     = var.db_disk_alert_threshold > 0 && var.db_disk_alert_threshold <= 1
    error_message = "db_disk_alert_threshold es una fraccion entre 0 y 1."
  }
}

# --- Ultimas palancas con valor real por ambiente --------------------------

variable "cdn_ttls" {
  description = <<-EOT
    TTL de la cache del CDN. Los assets del SPA llevan hash en el nombre, de
    modo que pueden cachearse mucho; index.html se publica con no-cache desde
    el pipeline para que un despliegue se vea de inmediato.
  EOT
  type = object({
    client   = optional(number, 3600)
    default  = optional(number, 3600)
    max      = optional(number, 86400)
    stale    = optional(number, 86400)
    negative = optional(number, 60)
  })
  default = {}
}

variable "uploads_storage_class_transitions" {
  description = "Bajadas de clase de almacenamiento por edad de los archivos subidos."
  type = list(object({
    age_days      = number
    storage_class = string
  }))
  default = [
    { age_days = 90, storage_class = "NEARLINE" },
    { age_days = 365, storage_class = "COLDLINE" },
  ]
}

variable "dlq_retention_duration" {
  description = "Tiempo que un mensaje fallido espera en el DLQ a ser inspeccionado."
  type        = string
  default     = "604800s"
}

# ---------------------------------------------------------------------------
# CI/CD: federacion de identidad
# ---------------------------------------------------------------------------

variable "wif_pool_name" {
  description = <<-EOT
    Nombre completo del pool de Workload Identity Federation que crea el
    bootstrap, en formato
    projects/<numero>/locations/global/workloadIdentityPools/<id>.

    Es la salida `workload_identity_pool` del bootstrap del ambiente. Vacio
    desactiva el binding que permite a GitHub Actions impersonar la SA de
    despliegue, lo que deja operativo solo el pipeline de Cloud Build.
  EOT
  type        = string
  default     = ""
}

variable "github_repository" {
  description = <<-EOT
    Repositorio en formato owner/repo. Acota que workloads pueden impersonar la
    SA de despliegue en dev y qa. Obligatorio si se pasa wif_pool_name.
  EOT
  type        = string
  default     = ""

  validation {
    condition     = var.github_repository == "" || can(regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", var.github_repository))
    error_message = "github_repository debe tener el formato owner/repo."
  }
}

variable "protected_branch" {
  description = <<-EOT
    Rama desde la que se permite desplegar en prod. En prod el principal de CI/CD
    se acota a esta rama en lugar de al repositorio completo.
  EOT
  type        = string
  default     = "main"
}

# Comprobacion cruzada: en dev y qa el principal se construye con el
# repositorio, asi que pasar el pool sin el repositorio generaria un
# principalSet invalido que Terraform aceptaria y la API rechazaria.
#
# Va en un bloque `check` y no en un `validation` porque una validacion que
# referencia OTRA variable exige Terraform >= 1.9, y aqui se soporta >= 1.6.
# La contrapartida honesta: un `check` emite advertencia, no error, asi que
# avisa durante el plan pero no detiene el apply.
check "wif_coherente" {
  assert {
    condition     = var.wif_pool_name == "" || var.env == "prod" || var.github_repository != ""
    error_message = "Si se pasa wif_pool_name, github_repository es obligatorio en dev y qa."
  }
}
