# ---------------------------------------------------------------------------
# Cloud SQL para PostgreSQL.
#
# Requisito: "La base de datos no debera estar expuesta directamente a Internet.
# Deberas decidir como resolver la conectividad."
#
# Decision: IP privada unica (ipv4_enabled = false) sobre Private Service
# Access, y conexion desde Cloud Run mediante Direct VPC egress. Alternativas
# descartadas y por que:
#   - IP publica + redes autorizadas: la instancia sigue teniendo superficie en
#     Internet y la allowlist no cubre IPs efimeras de serverless.
#   - Cloud SQL Auth Proxy como sidecar: valido, pero con IP privada + Direct
#     VPC egress el proxy no aporta ruta y si anade un componente que operar.
#     Se mantiene el rol cloudsql.client para poder usar el conector de la
#     libreria de Node.js, que ademas da TLS y autenticacion IAM.
#   - Private Service Connect: mas aislamiento aun, pero PSA cubre el requisito
#     con menos piezas moviles para este tamano de plataforma.
# ---------------------------------------------------------------------------

resource "google_sql_database_instance" "main" {
  project          = var.project_id
  name             = "${var.name_prefix}-pg-${random_id.instance_suffix.hex}"
  database_version = var.database_version
  region           = var.region

  # El orden importa: sin el peering de Private Service Access creado, una
  # instancia con IP privada falla al crearse. La dependencia se declara en el
  # modulo raiz (depends_on = [module.network]) porque depends_on no admite
  # valores de variable, solo referencias a recursos o modulos.

  settings {
    tier              = var.tier
    edition           = var.edition
    availability_type = var.highly_available ? "REGIONAL" : "ZONAL"
    disk_type         = "PD_SSD"
    disk_size         = var.disk_size_gb
    disk_autoresize   = true

    # Techo al autocrecimiento: evita que una fuga de datos silenciosa se
    # convierta en una factura silenciosa.
    disk_autoresize_limit = var.disk_autoresize_limit_gb

    user_labels = var.labels

    ip_configuration {
      # El punto central del requisito: ninguna IP publica.
      ipv4_enabled    = false
      private_network = var.network_id
      ssl_mode        = var.ssl_mode

      # Permite que servicios gestionados de Google (p. ej. Datastream o
      # exportaciones) lleguen por la ruta privada en lugar de abrir IP publica.
      enable_private_path_for_google_cloud_services = true
    }

    backup_configuration {
      enabled                        = true
      start_time                     = var.backup_start_time
      location                       = var.backup_location
      point_in_time_recovery_enabled = var.point_in_time_recovery
      transaction_log_retention_days = var.transaction_log_retention_days

      backup_retention_settings {
        retained_backups = var.retained_backups
        retention_unit   = "COUNT"
      }
    }

    maintenance_window {
      day          = var.maintenance_day
      hour         = var.maintenance_hour
      update_track = var.env == "prod" ? "stable" : "canary"
    }

    # Query Insights: diagnostico de rendimiento sin instalar nada en la BBDD.
    insights_config {
      query_insights_enabled  = true
      query_string_length     = var.query_insights_string_length
      record_application_tags = true
      record_client_address   = false # evita guardar IPs de cliente
    }

    dynamic "database_flags" {
      for_each = local.database_flags
      content {
        name  = database_flags.key
        value = database_flags.value
      }
    }
  }

  # En prod la instancia no puede destruirse por accidente desde Terraform
  # ni desde la consola.
  deletion_protection = var.deletion_protection
}

locals {
  database_flags = merge(
    {
      # Autenticacion IAM: permite que las service accounts se conecten sin
      # contrasena. Es lo que hace posible "cero credenciales en codigo".
      "cloudsql.iam_authentication" = "on"

      # Registro de conexiones y DDL para auditoria.
      "log_connections"    = "on"
      "log_disconnections" = "on"
      "log_statement"      = "ddl"

      # Consultas lentas a Cloud Logging, base de la alerta de latencia de BBDD.
      "log_min_duration_statement" = tostring(var.log_min_duration_ms)

      # Conexiones maximas acorde al tier y al pool de la aplicacion.
      "max_connections" = tostring(var.max_connections)
    },
    var.extra_database_flags
  )
}

# Sufijo aleatorio: el nombre de una instancia de Cloud SQL borrada queda
# reservado unos dias, lo que bloquearia un reconstruir inmediato.
resource "random_id" "instance_suffix" {
  byte_length = 2
}

resource "google_sql_database" "app" {
  project  = var.project_id
  name     = var.database_name
  instance = google_sql_database_instance.main.name

  # Collation y charset explicitos para que los 3 ambientes sean identicos.
  charset   = var.charset
  collation = var.collation

  deletion_policy = var.env == "prod" ? "ABANDON" : "DELETE"
}

# ---------------------------------------------------------------------------
# Credenciales.
#
# Requisito: "No deberan existir credenciales en codigo duro en Terraform o en
# codigo de configuracion."
#
# Como se cumple:
#   1. La contrasena se GENERA (random_password), no se escribe en ningun sitio.
#   2. Se guarda en Secret Manager; la aplicacion la lee de ahi en arranque.
#   3. Los runtimes prefieren autenticacion IAM (usuarios de tipo
#      CLOUD_IAM_SERVICE_ACCOUNT) y no usan contrasena en absoluto.
#
# La contrasena del usuario administrativo existe solo para migraciones y
# operaciones de mantenimiento.
#
# Limitacion honesta: con esta forma el valor generado queda en el state de
# Terraform. Mitigacion aplicada: el bucket de state esta cifrado, versionado y
# con acceso restringido al pipeline. Endurecimiento posible con Terraform
# >= 1.11 y provider >= 6.20: sustituir "password" por "password_wo" y
# "secret_data" por "secret_data_wo" (write-only), con lo que el valor no se
# persiste en el state. Se deja la forma estable para no acoplar el repositorio
# a versiones muy recientes.
# ---------------------------------------------------------------------------
resource "random_password" "app_user" {
  length           = var.password_length
  special          = true
  override_special = var.password_special_chars

  # Rota al cambiar este valor, sin tocar el codigo.
  keepers = {
    rotation = var.password_rotation_token
  }
}

resource "google_sql_user" "app" {
  project  = var.project_id
  name     = var.app_db_user
  instance = google_sql_database_instance.main.name
  password = random_password.app_user.result
  type     = "BUILT_IN"
}

# Usuarios IAM: cada runtime se autentica con su propia identidad. Nada que
# rotar, nada que filtrar.
resource "google_sql_user" "iam_service_accounts" {
  for_each = var.iam_db_users

  project  = var.project_id
  instance = google_sql_database_instance.main.name

  # Para SA el nombre es el email SIN el sufijo .gserviceaccount.com.
  name = trimsuffix(each.value, ".gserviceaccount.com")
  type = "CLOUD_IAM_SERVICE_ACCOUNT"
}

resource "google_secret_manager_secret" "db_password" {
  project   = var.project_id
  secret_id = "${var.name_prefix}-db-password"

  labels = var.labels

  replication {
    user_managed {
      replicas {
        location = var.region
      }
    }
  }
}

resource "google_secret_manager_secret_version" "db_password" {
  secret      = google_secret_manager_secret.db_password.id
  secret_data = random_password.app_user.result
}

# Cadena de conexion completa, para que la aplicacion no tenga que componerla
# a partir de media docena de variables de entorno.
resource "google_secret_manager_secret" "db_url" {
  project   = var.project_id
  secret_id = "${var.name_prefix}-db-url"

  labels = var.labels

  replication {
    user_managed {
      replicas {
        location = var.region
      }
    }
  }
}

resource "google_secret_manager_secret_version" "db_url" {
  secret = google_secret_manager_secret.db_url.id
  secret_data = format(
    "postgresql://%s:%s@%s:5432/%s?sslmode=require",
    var.app_db_user,
    urlencode(random_password.app_user.result),
    google_sql_database_instance.main.private_ip_address,
    var.database_name,
  )
}

# Lectura del secreto acotada a las identidades que lo necesitan.
resource "google_secret_manager_secret_iam_member" "db_password_accessors" {
  for_each = var.secret_accessor_members

  project   = var.project_id
  secret_id = google_secret_manager_secret.db_password.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${each.value}"
}

resource "google_secret_manager_secret_iam_member" "db_url_accessors" {
  for_each = var.secret_accessor_members

  project   = var.project_id
  secret_id = google_secret_manager_secret.db_url.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${each.value}"
}
