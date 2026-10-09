# ---------------------------------------------------------------------------
# Modulo generico de servicio Cloud Run. Lo instancian el API backend y el
# worker de procesos asincronos: mismo contrato, configuracion distinta.
#
# Por que Cloud Run y no GKE para este caso:
#   - 2.000 usuarios concurrentes y 100k-500k operaciones/dia es carga que un
#     autoescalado por request cubre sin gestionar nodos.
#   - El trafico de una plataforma B2B de pedidos es marcadamente diurno; con
#     GKE se paga el valle, con Cloud Run no.
#   - Un cluster anade un plano de control que operar y parchear en tres
#     ambientes, sin aportar nada que aqui se necesite.
# Si mas adelante aparecen cargas con estado, sidecars complejos o necesidad de
# GPUs, GKE Autopilot es la via de migracion natural.
# ---------------------------------------------------------------------------

resource "google_cloud_run_v2_service" "this" {
  project  = var.project_id
  name     = var.service_name
  location = var.region

  # INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER: el servicio solo acepta trafico del
  # balanceador, no de su propia URL *.run.app. Es lo que hace que el unico
  # punto de entrada publico sea el LB (con Cloud Armor delante).
  ingress = var.ingress

  deletion_protection = var.deletion_protection

  labels = var.labels

  template {
    service_account = var.service_account_email

    # Timeout de request. Un API de pedidos no deberia necesitar 60s; un valor
    # bajo libera instancias antes y acota el dano de una consulta colgada.
    timeout = "${var.request_timeout_seconds}s"

    # Concurrencia por instancia. Node.js es monohilo pero con E/S asincrona
    # aprovecha bien valores altos; el limite real suele ser el pool de la BBDD.
    max_instance_request_concurrency = var.max_concurrency

    execution_environment = var.execution_environment

    scaling {
      min_instance_count = var.min_instances
      max_instance_count = var.max_instances
    }

    # Direct VPC egress: la instancia recibe una IP de la subnet y alcanza la IP
    # privada de Cloud SQL sin conector serverless. Frente al conector VPC
    # Access: sin VMs intermedias que dimensionar ni pagar, y mejor latencia.
    vpc_access {
      network_interfaces {
        network    = var.network_id
        subnetwork = var.subnet_id
        # Etiquetas de red de la instancia: permiten escribir reglas de firewall
        # dirigidas a este servicio concreto.
        tags = var.network_tags
      }

      # ALL_TRAFFIC hace que TODO el trafico de salida pase por la VPC, y es lo
      # que convierte la topologia de subnets en un control real: en la subnet
      # sin Cloud NAT, el servicio queda sin ruta a Internet.
      # Con PRIVATE_RANGES_ONLY el trafico publico saldria por la ruta
      # gestionada de Google, saltandose la VPC y el control.
      egress = var.vpc_egress
    }

    containers {
      image = var.image

      ports {
        name           = "http1"
        container_port = var.container_port
      }

      resources {
        limits = {
          cpu    = var.cpu
          memory = var.memory
        }
        # CPU solo durante la request: con min_instances > 0 se mantiene una
        # instancia caliente pero sin pagar CPU en reposo. Se desactiva cuando
        # el servicio necesita trabajo en background (el worker).
        cpu_idle          = var.cpu_idle
        startup_cpu_boost = var.startup_cpu_boost
      }

      # Variables de entorno no sensibles.
      dynamic "env" {
        for_each = var.env_vars
        content {
          name  = env.key
          value = env.value
        }
      }

      # Secretos: se inyectan por referencia a Secret Manager. Cloud Run los
      # resuelve en arranque; el valor nunca pasa por el codigo ni por el estado
      # de despliegue.
      dynamic "env" {
        for_each = var.secret_env_vars
        content {
          name = env.key
          value_source {
            secret_key_ref {
              secret  = env.value.secret_id
              version = env.value.version
            }
          }
        }
      }

      # Sonda de arranque: evita que el LB envie trafico a una instancia que
      # todavia no ha abierto el pool de conexiones.
      startup_probe {
        initial_delay_seconds = var.startup_probe_delay
        timeout_seconds       = 3
        period_seconds        = 5
        failure_threshold     = var.startup_probe_failures
        http_get {
          path = var.health_path
          port = var.container_port
        }
      }

      # Sonda de vivacidad: reinicia instancias que han degradado.
      liveness_probe {
        initial_delay_seconds = 10
        timeout_seconds       = 3
        period_seconds        = 30
        failure_threshold     = 3
        http_get {
          path = var.health_path
          port = var.container_port
        }
      }

      dynamic "volume_mounts" {
        for_each = var.volume_mounts
        content {
          name       = volume_mounts.key
          mount_path = volume_mounts.value
        }
      }
    }

    # Volumen efimero en memoria para ficheros temporales: el sistema de
    # ficheros del contenedor es de solo lectura en la practica.
    dynamic "volumes" {
      for_each = var.volume_mounts
      content {
        name = volumes.key
        empty_dir {
          medium     = "MEMORY"
          size_limit = var.tmp_size_limit
        }
      }
    }
  }

  # Terraform deja el 100% del trafico en la ultima revision. El despliegue
  # gradual es responsabilidad del pipeline de APLICACION, que publica la
  # revision con --no-traffic y luego mueve porcentajes con
  # "gcloud run services update-traffic". Modelarlo aqui obligaria a que
  # Terraform conociera el id de la revision estable, que cambia en cada
  # despliegue: es estado de release, no de infraestructura.
  traffic {
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
    percent = 100
  }

  lifecycle {
    # La imagen la actualiza el pipeline de aplicacion, no el de infraestructura.
    # Sin esto, cada terraform apply revertiria el ultimo despliegue.
    ignore_changes = [
      template[0].containers[0].image,
      client,
      client_version,
      traffic,
    ]
  }
}

# ---------------------------------------------------------------------------
# Quien puede invocar el servicio. Nunca allUsers en el API: el acceso publico
# llega por el balanceador, que si esta expuesto y filtrado por Cloud Armor.
# ---------------------------------------------------------------------------
resource "google_cloud_run_v2_service_iam_member" "invokers" {
  for_each = var.invoker_members

  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.this.name
  role     = "roles/run.invoker"
  member   = each.value
}
