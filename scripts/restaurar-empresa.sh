#!/usr/bin/env bash
# Restaura el respaldo de UNA empresa en una base nueva (MT8, #111).
#
# Crea la base (vacía, con el migrador como dueño), deja los permisos como los de una empresa dada
# de alta (solo el usuario de la empresa y el migrador se conectan; la API tiene DML y nada más) y
# carga el respaldo. NUNCA sobrescribe: si la base de destino ya existe, se detiene.
#
# Uso:     scripts/restaurar-empresa.sh <archivo.dump> <base_destino> <usuario_de_la_empresa>
# Ejemplo: scripts/restaurar-empresa.sh respaldos/checkinobra_e764123309-20261120.dump \
#            checkinobra_e764123309 app_e764123309
#
# El usuario de PostgreSQL de la empresa (app_e…) debe existir. Para recuperar una empresa cuya base se
# perdió, la restauración se hace con el MISMO nombre de base y de usuario que figuran en el catálogo;
# después, un operador reactiva la empresa (PUT /api/plataforma/empresas/{id}/estado con "ACTIVA")
# para que la API abra su pool.
#
# Variables: CHECKINOBRA_MIGRADOR_PASSWORD y CHECKINOBRA_APROVISIONADOR_PASSWORD (obligatorias),
#            PGHOST / PGPORT, PG_PREFIX (ver respaldar-empresa.sh).
set -Eeuo pipefail

archivo="${1:?Uso: restaurar-empresa.sh <archivo.dump> <base_destino> <usuario_de_la_empresa>}"
base="${2:?Falta la base de destino}"
usuario="${3:?Falta el usuario de la empresa}"
: "${CHECKINOBRA_MIGRADOR_PASSWORD:?Falta CHECKINOBRA_MIGRADOR_PASSWORD}"
: "${CHECKINOBRA_APROVISIONADOR_PASSWORD:?Falta CHECKINOBRA_APROVISIONADOR_PASSWORD}"

[[ -f "$archivo" ]] || { echo "No existe el archivo $archivo" >&2; exit 2; }
for nombre in "$base" "$usuario"; do
  [[ "$nombre" =~ ^[a-z][a-z0-9_]{2,40}$ ]] || { echo "Nombre no válido: $nombre" >&2; exit 2; }
done

host="${PGHOST:-localhost}"
puerto="${PGPORT:-5432}"
prefijo="${PG_PREFIX:-}"

# pg <contraseña> <herramienta> args…
pg() {
  local clave="$1"; shift
  if [[ -n "$prefijo" ]]; then
    # shellcheck disable=SC2086
    $prefijo env PGPASSWORD="$clave" "$@"
  else
    PGPASSWORD="$clave" "$@"
  fi
}
sql_aprov() { pg "$CHECKINOBRA_APROVISIONADOR_PASSWORD" psql -X -q -At -v ON_ERROR_STOP=1 -h "$host" -p "$puerto" -U checkinobra_aprovisionador -d postgres -c "$1"; }
sql_migrador() { pg "$CHECKINOBRA_MIGRADOR_PASSWORD" psql -X -q -v ON_ERROR_STOP=1 -h "$host" -p "$puerto" -U checkinobra_migrador -d "$base" -c "$1"; }

# pg_dump y pg_restore deben ser de la MISMA versión mayor que el servidor: uno más nuevo escribe un
# volcado con parámetros que un servidor más viejo no conoce (p. ej. transaction_timeout en 17 sobre 16)
# y la restauración falla a mitad; uno más viejo se niega a volcar. Se comprueba antes de tocar nada.
verificar_versiones() {
  local herramienta="$1" servidor cliente
  servidor="$(pg "$CHECKINOBRA_MIGRADOR_PASSWORD" psql -X -q -At -h "$host" -p "$puerto" -U checkinobra_migrador -d postgres \
    -c 'SHOW server_version_num')" || { echo "No se pudo consultar la versión del servidor." >&2; exit 1; }
  servidor=$((servidor / 10000))
  cliente="$(pg "$CHECKINOBRA_MIGRADOR_PASSWORD" "$herramienta" --version | sed -E 's/[^0-9]*([0-9]+).*/\1/')"
  if [[ "$cliente" != "$servidor" ]]; then
    echo "Versiones distintas: $herramienta es la $cliente y el servidor es la $servidor. Usa las herramientas" >&2
    echo "de la versión $servidor (con PG_PREFIX, las del contenedor de la base)." >&2
    exit 4
  fi
}

verificar_versiones pg_restore

[[ "$(sql_aprov "SELECT count(*) FROM pg_database WHERE datname = '$base'")" == "0" ]] \
  || { echo "La base $base ya existe: no se sobrescribe. Restaura con otro nombre o bórrala antes." >&2; exit 3; }
[[ "$(sql_aprov "SELECT count(*) FROM pg_roles WHERE rolname = '$usuario'")" == "1" ]] \
  || { echo "El usuario $usuario no existe en PostgreSQL." >&2; exit 3; }

sql_aprov "CREATE DATABASE \"$base\" OWNER checkinobra_migrador"
# Desde acá, si algo falla la base queda a medias: se borra para no dejar una restauración parcial.
borrar_parcial() {
  echo "La restauración falló: se borra la base $base para no dejarla a medias." >&2
  pg "$CHECKINOBRA_MIGRADOR_PASSWORD" psql -X -q -h "$host" -p "$puerto" -U checkinobra_migrador -d postgres \
    -c "DROP DATABASE IF EXISTS \"$base\"" || true
}
trap borrar_parcial ERR

sql_migrador "
  REVOKE CONNECT ON DATABASE \"$base\" FROM PUBLIC;
  GRANT CONNECT ON DATABASE \"$base\" TO \"$usuario\";
  ALTER SCHEMA public OWNER TO checkinobra_migrador;
  GRANT USAGE ON SCHEMA public TO \"$usuario\";
  ALTER DEFAULT PRIVILEGES FOR ROLE checkinobra_migrador IN SCHEMA public
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO \"$usuario\";
  ALTER DEFAULT PRIVILEGES FOR ROLE checkinobra_migrador IN SCHEMA public
    GRANT USAGE, SELECT ON SEQUENCES TO \"$usuario\";"

# Como el migrador, sin dueños ni permisos del respaldo: lo que se crea queda a su nombre y los permisos
# de arriba (por defecto) le dan DML al usuario de la empresa.
pg "$CHECKINOBRA_MIGRADOR_PASSWORD" pg_restore --no-owner --no-acl --exit-on-error \
  -h "$host" -p "$puerto" -U checkinobra_migrador -d "$base" < "$archivo"

trap - ERR
echo "Base $base restaurada desde $(basename "$archivo")."
