#!/usr/bin/env bash
# Crea (o sincroniza) los roles checkinobra_app, checkinobra_migrador y
# checkinobra_plataforma, y la base de catálogo checkinobra_catalogo. Ver roles.sql.
#
# Se usa de tres maneras:
#   1. Base nueva: docker-compose lo monta en /docker-entrypoint-initdb.d y el
#      entrypoint de Postgres lo corre una sola vez, al crear el volumen.
#   2. Base existente (volumen anterior a esto):
#        docker compose exec -T db /docker-entrypoint-initdb.d/01-roles.sh
#      scripts/levantar.sh lo hace solo.
#   3. Fuera de Docker o en CI: con PGHOST, PGUSER, PGPASSWORD y PGDATABASE del
#      superusuario, y CHECKINOBRA_APP_PASSWORD / CHECKINOBRA_MIGRADOR_PASSWORD /
#      CHECKINOBRA_PLATAFORMA_PASSWORD.
#
# No imprime las contraseñas y se niega a seguir si falta alguna.
set -euo pipefail

: "${CHECKINOBRA_APP_PASSWORD:?Falta CHECKINOBRA_APP_PASSWORD (DB_APP_PASSWORD en el .env)}"
: "${CHECKINOBRA_MIGRADOR_PASSWORD:?Falta CHECKINOBRA_MIGRADOR_PASSWORD (DB_MIGRADOR_PASSWORD en el .env)}"
: "${CHECKINOBRA_PLATAFORMA_PASSWORD:?Falta CHECKINOBRA_PLATAFORMA_PASSWORD (DB_PLATAFORMA_PASSWORD en el .env)}"

sql="${ROLES_SQL:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/roles.sql}"
[[ -f "$sql" ]] || { echo "No encuentro $sql (defina ROLES_SQL)" >&2; exit 1; }

# Dentro del contenedor el superusuario viene en POSTGRES_USER / POSTGRES_DB.
export PGUSER="${PGUSER:-${POSTGRES_USER:-postgres}}"
export PGDATABASE="${PGDATABASE:-${POSTGRES_DB:-checkinobra}}"

# CHECKINOBRA_APROVISIONADOR_PASSWORD es opcional: con ella se crea el rol que da de alta bases de
# empresa desde la API (MT7); sin ella el alta por API no está disponible.
extra=()
if [[ -n "${CHECKINOBRA_APROVISIONADOR_PASSWORD:-}" ]]; then
  extra=(-v aprovisionador_password="$CHECKINOBRA_APROVISIONADOR_PASSWORD")
fi
psql -X -q -v ON_ERROR_STOP=1 \
  -v app_password="$CHECKINOBRA_APP_PASSWORD" \
  -v migrador_password="$CHECKINOBRA_MIGRADOR_PASSWORD" \
  -v plataforma_password="$CHECKINOBRA_PLATAFORMA_PASSWORD" \
  "${extra[@]}" \
  -f "$sql"
echo "Roles y base de catálogo listos."

# Bases de empresa adicionales, vacías, para las pruebas de aislamiento (MT5): una lista de
# nombres separados por coma en CHECKINOBRA_BASES_EXTRA. No hace falta en un despliegue.
if [[ -n "${CHECKINOBRA_BASES_EXTRA:-}" ]]; then
  base_sql="${BASE_SQL:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/crear-base-de-empresa.sql}"
  [[ -f "$base_sql" ]] || { echo "No encuentro $base_sql (defina BASE_SQL)" >&2; exit 1; }
  IFS=',' read -ra extras <<< "$CHECKINOBRA_BASES_EXTRA"
  for extra in "${extras[@]}"; do
    psql -X -q -v ON_ERROR_STOP=1 -v base="$extra" -f "$base_sql"
    echo "Base de empresa $extra lista."
  done
fi
