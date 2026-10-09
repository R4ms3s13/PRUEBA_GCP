# Configuracion de tflint.
#
# Sin este fichero, `tflint` solo aplica sus reglas basicas de Terraform y el
# paso del pipeline pasa casi siempre: da una falsa sensacion de cobertura.
# Lo que de verdad aporta valor es el plugin de Google, que valida tipos de
# maquina inexistentes, nombres de recurso mal formados y argumentos invalidos
# ANTES de llamar a la API.
#
# Uso:
#   tflint --init              # descarga los plugins (una vez)
#   tflint --recursive         # analiza todos los modulos

plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

plugin "google" {
  enabled = true
  version = "0.34.0"
  source  = "github.com/terraform-linters/tflint-ruleset-google"
}

config {
  call_module_type = "local"
}

# --- Convenciones del repositorio -------------------------------------------

# Toda variable y todo output con description. Ya se cumple al 100 %, y esta
# regla impide que se degrade.
rule "terraform_documented_variables" {
  enabled = true
}

rule "terraform_documented_outputs" {
  enabled = true
}

# Tipo explicito en cada variable: sin el, Terraform acepta cualquier cosa y
# el error aparece tarde y lejos de su causa.
rule "terraform_typed_variables" {
  enabled = true
}

# Nombres en snake_case, como el resto del ecosistema.
rule "terraform_naming_convention" {
  enabled = true
  format  = "snake_case"
}

# Cada modulo declara required_version y required_providers.
rule "terraform_required_version" {
  enabled = true
}

rule "terraform_required_providers" {
  enabled = true
}

# Avisa de declaraciones que ya no se usan: variables que sobraron de un
# refactor y que nadie se atreve a borrar porque no sabe si hacen algo.
rule "terraform_unused_declarations" {
  enabled = true
}

# Bloques siempre en el mismo orden, para que los diffs sean legibles.
rule "terraform_module_version" {
  enabled = false # los modulos son locales, no versionados en un registro
}
