# Requisitos de version del modulo.
#
# Se declaran por modulo, y no solo en la raiz, porque un modulo reutilizable
# debe ser autodescriptivo: quien lo consuma desde otro repositorio necesita
# saber que provider y que version espera sin leer su implementacion.

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 6.0, < 7.0"
    }
  }
}
