#!/usr/bin/env bash
# Compila el APK de release firmado y ofuscado.
#
#   API_BASE_URL=https://api.checkinobra.cl \
#   CHECKINOBRA_KEYSTORE_FILE=/ruta/release.jks \
#   CHECKINOBRA_KEYSTORE_PASSWORD=... CHECKINOBRA_KEY_ALIAS=... \
#   CHECKINOBRA_KEY_PASSWORD=... \
#   scripts/release-apk.sh
#
# En local, en vez de las cuatro variables del keystore puede usarse
# mobile/android/key.properties (no versionado). Nada de esto se escribe en el
# repo: el keystore y sus claves salen de variables de entorno o, en el CI, de
# los secretos del repositorio.
#
# Deja el APK en mobile/build/app/outputs/flutter-apk/ y los símbolos de
# depuración en mobile/build/debug-info/. Esos símbolos son lo único que permite
# leer un stack trace del APK ofuscado: guárdalos junto a cada versión que
# publiques, y no los distribuyas con la app.
set -euo pipefail

cd "$(dirname "$0")/../mobile"

if [[ -z "${API_BASE_URL:-}" ]]; then
  echo "Falta API_BASE_URL (la URL https:// de la API)." >&2
  exit 1
fi
if [[ "${API_BASE_URL}" != https://* ]]; then
  echo "API_BASE_URL tiene que empezar con https:// (recibí: ${API_BASE_URL})." >&2
  exit 1
fi

flutter build apk --release \
  --obfuscate \
  --split-debug-info=build/debug-info \
  --dart-define=API_BASE_URL="${API_BASE_URL}"
