# ---------------------------------------------------------------------------
# VPC en modo custom: ninguna subnet se crea automaticamente, de forma que el
# direccionamiento es explicito, documentado y reproducible en los 3 ambientes.
# ---------------------------------------------------------------------------
resource "google_compute_network" "vpc" {
  project                 = var.project_id
  name                    = "${var.name_prefix}-vpc"
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
  description             = "VPC de la plataforma de proveedores (${var.env})"
}

# ---------------------------------------------------------------------------
# DOS subnets, y la separacion es funcional, no cosmetica:
#
#   snet-app      -> el API, que es el unico componente alcanzable desde fuera
#                    (a traves del balanceador). NO lo cubre Cloud NAT, asi que
#                    no tiene ninguna ruta a Internet.
#   snet-internal -> worker y jobs batch, que no son alcanzables desde fuera
#                    pero si necesitan llamar a aplicaciones de terceros. Es la
#                    unica subnet que Cloud NAT traduce.
#
# De ahi sale la "separacion entre componentes publicos y privados" que pide el
# enunciado a nivel de RED y no solo de IAM: el componente expuesto a Internet
# es precisamente el que no puede iniciar conexiones hacia Internet. Si alguien
# logra ejecutar codigo en el API, no tiene por donde sacar datos ni por donde
# descargar una segunda etapa.
#
# Ambas conservan Private Google Access, de modo que llegan a las APIs de Google
# (Secret Manager, Pub/Sub, Cloud Storage) sin pasar por Internet ni por el NAT.
# ---------------------------------------------------------------------------
resource "google_compute_subnetwork" "app" {
  project                  = var.project_id
  name                     = "${var.name_prefix}-snet-app"
  region                   = var.region
  network                  = google_compute_network.vpc.id
  ip_cidr_range            = var.subnet_app_cidr
  private_ip_google_access = true

  log_config {
    aggregation_interval = "INTERVAL_10_MIN"
    flow_sampling        = var.flow_sampling
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

resource "google_compute_subnetwork" "internal" {
  project                  = var.project_id
  name                     = "${var.name_prefix}-snet-internal"
  region                   = var.region
  network                  = google_compute_network.vpc.id
  ip_cidr_range            = var.subnet_internal_cidr
  private_ip_google_access = true

  log_config {
    aggregation_interval = "INTERVAL_10_MIN"
    flow_sampling        = var.flow_sampling
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

# ---------------------------------------------------------------------------
# Private Service Access: rango donde Google despliega la instancia de Cloud SQL
# al otro lado de un VPC peering. Es el mecanismo que permite que la base de
# datos tenga unicamente IP privada.
# ---------------------------------------------------------------------------
resource "google_compute_global_address" "psa_range" {
  project       = var.project_id
  name          = "${var.name_prefix}-psa-range"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  address       = var.psa_cidr
  prefix_length = var.psa_prefix_length
  network       = google_compute_network.vpc.id
}

resource "google_service_networking_connection" "psa" {
  network                 = google_compute_network.vpc.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.psa_range.name]

  # ABANDON evita que un destroy se quede bloqueado por el peering.
  deletion_policy = "ABANDON"
}

resource "google_compute_network_peering_routes_config" "psa_routes" {
  project              = var.project_id
  peering              = google_service_networking_connection.psa.peering
  network              = google_compute_network.vpc.name
  import_custom_routes = true
  export_custom_routes = true
}

# ---------------------------------------------------------------------------
# Salida a Internet, SOLO para la subnet interna.
#
# El worker y los jobs batch intercambian informacion con aplicaciones de
# terceros, y con Cloud NAT ese trafico sale por una IP estable y auditable que
# el tercero puede poner en su allowlist.
#
# El API queda fuera a proposito: es la mitad del control descrito arriba. No es
# una regla de firewall que se pueda relajar por error, es la ausencia de una
# ruta.
# ---------------------------------------------------------------------------
resource "google_compute_router" "router" {
  count   = var.enable_nat ? 1 : 0
  project = var.project_id
  name    = "${var.name_prefix}-router"
  region  = var.region
  network = google_compute_network.vpc.id
}

resource "google_compute_address" "nat" {
  count        = var.enable_nat ? 1 : 0
  project      = var.project_id
  name         = "${var.name_prefix}-nat-ip"
  region       = var.region
  address_type = "EXTERNAL"
}

resource "google_compute_router_nat" "nat" {
  count                  = var.enable_nat ? 1 : 0
  project                = var.project_id
  name                   = "${var.name_prefix}-nat"
  region                 = var.region
  router                 = google_compute_router.router[0].name
  nat_ip_allocate_option = "MANUAL_ONLY"
  nat_ips                = [google_compute_address.nat[0].self_link]
  min_ports_per_vm       = var.nat_min_ports_per_vm

  # LIST_OF_SUBNETWORKS y no ALL_SUBNETWORKS: enumerar explicitamente es lo que
  # deja al API sin ruta a Internet. Con ALL_SUBNETWORKS el control se perderia
  # en silencio al crear cualquier subnet nueva.
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"

  subnetwork {
    name                    = google_compute_subnetwork.internal.id
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# ---------------------------------------------------------------------------
# Firewall. Deny-by-default en ingress: solo se abre lo imprescindible.
# ---------------------------------------------------------------------------
resource "google_compute_firewall" "deny_all_ingress" {
  project       = var.project_id
  name          = "${var.name_prefix}-deny-all-ingress"
  network       = google_compute_network.vpc.name
  direction     = "INGRESS"
  priority      = 65534
  source_ranges = ["0.0.0.0/0"]

  deny { protocol = "all" }

  log_config { metadata = "INCLUDE_ALL_METADATA" }
}

# Rangos fijos y documentados de los health checks y del Google Front End.
resource "google_compute_firewall" "allow_health_checks" {
  project       = var.project_id
  name          = "${var.name_prefix}-allow-health-checks"
  network       = google_compute_network.vpc.name
  direction     = "INGRESS"
  priority      = 1000
  source_ranges = ["35.191.0.0/16", "130.211.0.0/22"]

  allow {
    protocol = "tcp"
    ports    = ["8080"]
  }

  log_config { metadata = "EXCLUDE_ALL_METADATA" }
}

# Comunicacion entre servicios: las dos subnets de la plataforma pueden hablar
# entre si en los puertos que se usan, y nada mas.
resource "google_compute_firewall" "allow_internal" {
  project   = var.project_id
  name      = "${var.name_prefix}-allow-internal"
  network   = google_compute_network.vpc.name
  direction = "INGRESS"
  priority  = 1100

  source_ranges = [
    var.subnet_app_cidr,
    var.subnet_internal_cidr,
  ]

  allow {
    protocol = "tcp"
    ports    = ["443", "5432", "8080"]
  }
}

# Egress explicito hacia el rango privado de Cloud SQL, desde ambas subnets.
resource "google_compute_firewall" "allow_egress_sql" {
  project            = var.project_id
  name               = "${var.name_prefix}-allow-egress-sql"
  network            = google_compute_network.vpc.name
  direction          = "EGRESS"
  priority           = 1000
  destination_ranges = ["${var.psa_cidr}/${var.psa_prefix_length}"]

  allow {
    protocol = "tcp"
    ports    = ["5432"]
  }
}

# ---------------------------------------------------------------------------
# Nota deliberada: NO hay una regla de egress que deniegue 0.0.0.0/0 al API.
#
# Seria tentador anadirla como segunda capa, pero el trafico hacia las APIs de
# Google via Private Google Access sigue teniendo como destino direcciones
# PUBLICAS de Google: una denegacion general a 0.0.0.0/0 cortaria tambien
# Secret Manager, Pub/Sub y Cloud Storage. Hacerlo bien exigiria forzar
# restricted.googleapis.com con zonas privadas de Cloud DNS, que es el patron
# de VPC Service Controls y aporta mas fragilidad que seguridad a esta escala.
#
# El control efectivo es el de arriba: el API no esta en la lista del NAT, asi
# que no existe ruta. Una ausencia de ruta es mas robusta que una regla que
# alguien puede relajar.
# ---------------------------------------------------------------------------
