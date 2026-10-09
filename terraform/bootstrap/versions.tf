# Requisitos de version del bootstrap.
#
# Se aplica con state LOCAL, antes que todo lo demas: no puede guardar su propio
# state en un bucket que el mismo esta creando.

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 6.0, < 7.0"
    }
  }
}
