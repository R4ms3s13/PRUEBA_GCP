# ---------------------------------------------------------------------------
# Punto de entrada publico: Application Load Balancer externo global.
#
# Un unico dominio sirve las dos cosas y evita CORS en el navegador:
#   /            -> backend bucket con el build de React, cacheado en Cloud CDN
#   /api/*       -> serverless NEG hacia el servicio Cloud Run del API
#
# Por que el frontend en Cloud Storage y no en Cloud Run: un SPA compilado es
# un conjunto de ficheros estaticos. Servirlo desde un contenedor significa
# pagar CPU por devolver bytes que el CDN puede servir desde el borde.
# ---------------------------------------------------------------------------

# --- IP publica estable (anclaje del registro DNS) -------------------------
resource "google_compute_global_address" "lb" {
  project = var.project_id
  name    = "${var.name_prefix}-lb-ip"
}

# --- Certificado TLS gestionado por Google ---------------------------------
# Google emite y renueva. Requiere que el DNS apunte ya a la IP de arriba,
# por lo que el primer apply deja el certificado en PROVISIONING.
resource "google_compute_managed_ssl_certificate" "cert" {
  count   = var.enable_https ? 1 : 0
  project = var.project_id
  name    = "${var.name_prefix}-cert"

  managed {
    domains = var.domains
  }

  lifecycle {
    create_before_destroy = true
  }
}

# --- Backend estatico: bucket + CDN ---------------------------------------
resource "google_compute_backend_bucket" "frontend" {
  project     = var.project_id
  name        = "${var.name_prefix}-be-frontend"
  bucket_name = var.frontend_bucket_name
  enable_cdn  = true
  description = "Build estatico del SPA de React"

  cdn_policy {
    cache_mode = var.cdn_cache_mode

    # El SPA se publica con hash en el nombre de los ficheros, asi que los
    # assets pueden cachearse mucho tiempo. index.html lo controla el
    # Cache-Control del objeto al subirlo (no-cache), para que un despliegue
    # sea visible de inmediato.
    client_ttl  = var.cdn_client_ttl
    default_ttl = var.cdn_default_ttl
    max_ttl     = var.cdn_max_ttl

    # Sirve contenido caducado mientras revalida en segundo plano: un fallo
    # momentaneo del origen no se traduce en error para el usuario.
    serve_while_stale = var.cdn_serve_while_stale

    negative_caching = true
    negative_caching_policy {
      code = 404
      ttl  = var.cdn_negative_ttl
    }
  }

  # Compresion en el borde.
  compression_mode = "AUTOMATIC"
}

# --- Backend dinamico: Cloud Run via serverless NEG ------------------------
resource "google_compute_region_network_endpoint_group" "api" {
  project               = var.project_id
  name                  = "${var.name_prefix}-neg-api"
  region                = var.region
  network_endpoint_type = "SERVERLESS"

  cloud_run {
    service = var.api_service_name
  }
}

resource "google_compute_backend_service" "api" {
  project     = var.project_id
  name        = "${var.name_prefix}-be-api"
  protocol    = "HTTPS"
  port_name   = "http"
  timeout_sec = var.api_timeout_sec
  description = "API backend Node.js sobre Cloud Run"

  load_balancing_scheme = "EXTERNAL_MANAGED"

  backend {
    group = google_compute_region_network_endpoint_group.api.id
  }

  # Las respuestas del API no se cachean: son datos de pedidos por usuario.
  enable_cdn = false

  security_policy = var.enable_cloud_armor ? google_compute_security_policy.armor[0].id : null

  log_config {
    enable      = true
    sample_rate = var.env == "prod" ? 1.0 : 0.5
  }

  # Contexto que el API recibe sin tener que deducirlo del request.
  custom_request_headers = [
    "X-Client-Geo-Region:{client_region}",
    "X-Client-TLS-Version:{tls_version}",
  ]
}

# ---------------------------------------------------------------------------
# Cloud Armor: WAF y limitacion de tasa delante del API.
#
# Cubre el requisito implicito de "componentes publicos" protegidos: la unica
# superficie expuesta es este balanceador, y aqui se filtra.
# ---------------------------------------------------------------------------
resource "google_compute_security_policy" "armor" {
  count   = var.enable_cloud_armor ? 1 : 0
  project = var.project_id
  name    = "${var.name_prefix}-armor"

  description = "WAF y rate limiting del punto de entrada publico"

  # Regla 1000: limitacion de tasa por IP. Protege login y endpoints de
  # escritura de fuerza bruta y de un cliente mal programado.
  rule {
    action      = "rate_based_ban"
    priority    = 1000
    description = "Rate limit por IP"

    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }

    rate_limit_options {
      conform_action = "allow"
      exceed_action  = "deny(429)"

      enforce_on_key = "IP"

      rate_limit_threshold {
        count        = var.rate_limit_requests
        interval_sec = var.rate_limit_interval_sec
      }

      ban_duration_sec = var.rate_limit_ban_seconds
    }
  }

  # Reglas preconfiguradas del WAF. sensitivity 1 reduce falsos positivos:
  # conviene estrenarlas en modo preview y subir sensibilidad con datos.
  rule {
    action      = var.waf_preview_mode ? "allow" : "deny(403)"
    priority    = 2000
    description = "SQL injection (OWASP CRS)"
    preview     = var.waf_preview_mode

    match {
      expr {
        expression = "evaluatePreconfiguredWaf('sqli-v33-stable', {'sensitivity': 1})"
      }
    }
  }

  rule {
    action      = var.waf_preview_mode ? "allow" : "deny(403)"
    priority    = 2001
    description = "Cross-site scripting (OWASP CRS)"
    preview     = var.waf_preview_mode

    match {
      expr {
        expression = "evaluatePreconfiguredWaf('xss-v33-stable', {'sensitivity': 1})"
      }
    }
  }

  rule {
    action      = var.waf_preview_mode ? "allow" : "deny(403)"
    priority    = 2002
    description = "Local file inclusion"
    preview     = var.waf_preview_mode

    match {
      expr {
        expression = "evaluatePreconfiguredWaf('lfi-v33-stable', {'sensitivity': 1})"
      }
    }
  }

  # Regla por defecto obligatoria.
  rule {
    action      = "allow"
    priority    = 2147483647
    description = "Permitir el resto"

    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
  }

  # Adaptive Protection (deteccion de DDoS de capa 7 por aprendizaje) requiere
  # suscripcion a **Cloud Armor Enterprise**. Activarlo sin ella hace fallar el
  # apply, asi que va tras un flag desactivado por defecto: es una decision de
  # contratacion, no tecnica. El coste no esta en el presupuesto.
  dynamic "adaptive_protection_config" {
    for_each = var.enable_adaptive_protection ? [1] : []
    content {
      layer_7_ddos_defense_config {
        enable = true
      }
    }
  }
}

# ---------------------------------------------------------------------------
# Enrutado
# ---------------------------------------------------------------------------
resource "google_compute_url_map" "main" {
  project         = var.project_id
  name            = "${var.name_prefix}-urlmap"
  default_service = google_compute_backend_bucket.frontend.id

  host_rule {
    hosts        = var.enable_https ? var.domains : ["*"]
    path_matcher = "principal"
  }

  path_matcher {
    name            = "principal"
    default_service = google_compute_backend_bucket.frontend.id

    path_rule {
      paths   = var.api_path_patterns
      service = google_compute_backend_service.api.id
    }

    # Healthcheck externo del API, para la comprobacion de uptime. La ruta es
    # contrato con la aplicacion y llega como variable, no escrita a mano.
    path_rule {
      paths   = [var.health_path]
      service = google_compute_backend_service.api.id
    }
  }
}

# Redireccion 301 de HTTP a HTTPS: nada viaja en claro.
resource "google_compute_url_map" "redirect" {
  count   = var.enable_https ? 1 : 0
  project = var.project_id
  name    = "${var.name_prefix}-urlmap-redirect"

  default_url_redirect {
    https_redirect         = true
    redirect_response_code = "MOVED_PERMANENTLY_DEFAULT"
    strip_query            = false
  }
}

# ---------------------------------------------------------------------------
# Proxies y reglas de reenvio
# ---------------------------------------------------------------------------
resource "google_compute_target_https_proxy" "https" {
  count            = var.enable_https ? 1 : 0
  project          = var.project_id
  name             = "${var.name_prefix}-https-proxy"
  url_map          = google_compute_url_map.main.id
  ssl_certificates = [google_compute_managed_ssl_certificate.cert[0].id]

  # Rechaza suites obsoletas.
  ssl_policy = google_compute_ssl_policy.modern.id

  quic_override = "ENABLE"
}

resource "google_compute_ssl_policy" "modern" {
  project         = var.project_id
  name            = "${var.name_prefix}-ssl-policy"
  profile         = var.ssl_profile
  min_tls_version = var.min_tls_version
}

resource "google_compute_target_http_proxy" "http" {
  project = var.project_id
  name    = "${var.name_prefix}-http-proxy"
  url_map = var.enable_https ? google_compute_url_map.redirect[0].id : google_compute_url_map.main.id
}

resource "google_compute_global_forwarding_rule" "https" {
  count      = var.enable_https ? 1 : 0
  project    = var.project_id
  name       = "${var.name_prefix}-fr-https"
  target     = google_compute_target_https_proxy.https[0].id
  port_range = "443"
  ip_address = google_compute_global_address.lb.id

  load_balancing_scheme = "EXTERNAL_MANAGED"
}

resource "google_compute_global_forwarding_rule" "http" {
  project    = var.project_id
  name       = "${var.name_prefix}-fr-http"
  target     = google_compute_target_http_proxy.http.id
  port_range = "80"
  ip_address = google_compute_global_address.lb.id

  load_balancing_scheme = "EXTERNAL_MANAGED"
}
