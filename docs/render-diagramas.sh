#!/usr/bin/env bash
#
# Regenera los SVG de docs/img a partir de los bloques Mermaid de diagrama.md.
#
# La fuente de verdad es SIEMPRE el codigo Mermaid del documento: los SVG son
# una salida, no un original. Ejecutar esto tras cualquier cambio en un
# diagrama, o los SVG quedan obsoletos sin que nada avise.
#
# Uso:   ./docs/render-diagramas.sh
# Pide:  node >= 18 y npx (descarga mermaid-cli la primera vez)

set -euo pipefail

DOCS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$DOCS/diagrama.md"
IMG="$DOCS/img"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$IMG"

cat > "$TMP/config.json" <<'JSON'
{
  "theme": "neutral",
  "themeVariables": { "fontFamily": "Segoe UI, Helvetica, Arial, sans-serif", "fontSize": "14px" },
  "flowchart": { "htmlLabels": true, "curve": "basis", "padding": 12 }
}
JSON

# Trocea el markdown: un .mmd por bloque, nombrado por la seccion que lo contiene.
python - "$SRC" "$TMP" <<'PY'
import io, re, sys, unicodedata, os
src, tmp = sys.argv[1], sys.argv[2]

def slug(t):
    t = unicodedata.normalize("NFD", t)
    t = "".join(c for c in t if unicodedata.category(c) != "Mn")
    return re.sub(r"[^A-Za-z0-9]+", "-", t).strip("-").lower()

titulo, dentro, buf, n = "diagrama", False, [], 0
for l in io.open(src, encoding="utf-8").read().splitlines():
    if l.startswith("## "):
        titulo = l[3:].strip()
    if l.strip() == "```mermaid":
        dentro, buf = True, []
        continue
    if dentro and l.strip() == "```":
        dentro = False
        n += 1
        nombre = "%02d-%s" % (n, slug(titulo))
        io.open(os.path.join(tmp, nombre + ".mmd"), "w",
                encoding="utf-8", newline="\n").write("\n".join(buf) + "\n")
        continue
    if dentro:
        buf.append(l)
print("bloques extraidos: %d" % n)
PY

fallos=0
for f in "$TMP"/*.mmd; do
  b="$(basename "$f" .mmd)"
  printf '  %-56s ' "$b"
  if npx -y @mermaid-js/mermaid-cli -i "$f" -o "$IMG/$b.svg" \
       -c "$TMP/config.json" -b transparent >/dev/null 2>&1; then
    echo "OK"
  else
    echo "FALLA"
    fallos=$((fallos + 1))
  fi
done

if [ "$fallos" -gt 0 ]; then
  echo "ERROR: $fallos diagrama(s) no renderizan. Revisa la sintaxis Mermaid." >&2
  exit 1
fi

echo "Todos los diagramas renderizados en docs/img/"
