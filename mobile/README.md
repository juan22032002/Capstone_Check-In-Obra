# Check-In-Obra · App móvil

App Android de Check-In-Obra. Cada rol entra a su propia app dentro del mismo
APK: el administrador gestiona obras, materiales y usuarios; el bodeguero
registra movimientos y escanea credenciales y códigos de barras; el trabajador
muestra su credencial QR y pide herramientas o material.

Flutter 3.47.1 (solo Android) · Riverpod · Dio · mobile_scanner ·
flutter_secure_storage · fl_chart · Inter.

Este README cubre lo que necesitas para trabajar dentro de `mobile/`. La API
que consume está en [`../backend`](../backend), y la visión del sistema
completo, en el [README de la raíz](../README.md).

---

## Correrla

Necesitas Flutter 3.47.1, el SDK de Android y la API arriba
(`docker compose up -d` desde la raíz).

```bash
cd mobile
cp .env.example .env
flutter pub get
flutter run                      # con un celular por USB o un emulador abierto
```

`flutter devices` muestra qué ve Flutter.

**Atajo:** desde la raíz, `scripts/levantar.sh --app` enciende Docker Desktop,
levanta el backend, arranca el emulador `Check-In-Obra_Pixel5` y corre la app
en él. En Windows: `powershell -ExecutionPolicy Bypass -File
scripts\levantar.ps1 -App`. Sin `--app` (o `-App`) deja todo arriba sin correr
la app; con `--avd` (o `-Avd`) usa otro emulador.

### En tu teléfono

1. Activa **Opciones de desarrollador**: toca 7 veces *Número de compilación*
   (en Samsung está en *Ajustes → Acerca del teléfono → Información de
   software*). Luego, en *Opciones de desarrollador*, activa **Depuración USB**.
2. Conecta el cable y acepta **"¿Permitir depuración USB?"** marcando
   *Permitir siempre desde este equipo*. `adb devices` debe mostrar el
   teléfono como `device`, no como `unauthorized`.
3. Desde la raíz:

   ```bash
   scripts/levantar.sh --telefono                                            # Linux y macOS
   powershell -ExecutionPolicy Bypass -File scripts\levantar.ps1 -Telefono   # Windows
   ```

El script levanta Docker y hace `adb reverse tcp:8081 tcp:8081`, que publica
la API del computador como `localhost:8081` en el teléfono. Después corre la
app con `--dart-define=API_BASE_URL=http://localhost:8081`. No depende de la
WiFi ni de la IP, y tu `.env` queda como está. El `reverse` se pierde al
desconectar el cable: vuelve a correr el script. Con más de un teléfono
conectado, elige uno con `TELEFONO=<serie> scripts/levantar.sh --telefono`
(en Windows: `-Telefono -Serie <serie>`).

A mano, sin el script: `adb reverse tcp:8081 tcp:8081` y luego
`flutter run -d <serie> --dart-define=API_BASE_URL=http://localhost:8081`.
Por WiFi, sin cable, deja la IP del computador en el `.env` (ver la tabla de
arriba).

### La URL de la API (`.env`)

```
API_BASE_URL=http://10.0.2.2:8081
```

| Dónde corre la app | Valor |
|---|---|
| Emulador de Android | `http://10.0.2.2:8081`, que es el localhost del computador visto desde el emulador |
| Celular físico por USB | `http://localhost:8081` con `adb reverse` (lo hace `scripts/levantar.sh --telefono`) |
| Producción (release) | `https://…`, pasada al compilar con `--dart-define=API_BASE_URL=https://…` |

**Sin tráfico en claro.** Android bloquea todo HTTP salvo, en las compilaciones
de *debug*, hacia `10.0.2.2`, `localhost` y `127.0.0.1`
(`android/app/src/debug/res/xml/network_security_config.xml`). Por eso ya no
sirve apuntar el `.env` a la IP del computador en la WiFi
(`http://192.168.1.50:8081`): la petición se corta antes de salir. Para un
teléfono físico usa el cable y `adb reverse`. En **release** la app además
rechaza al arrancar cualquier `API_BASE_URL` que no empiece con `https://`, y
no cae al valor del emulador si falta.

El `.env` no se versiona porque la IP cambia según la máquina y la red. Si
falta, la app arranca igual con el valor del emulador. Una URL pasada al
compilar con `--dart-define=API_BASE_URL=...` tiene prioridad sobre el `.env`
(`core/network/app_config.dart`). Va empaquetado como
asset, así que **después de editarlo hay que reiniciar la app**: el hot reload
no lo vuelve a leer.

### Cuentas para entrar

Con `python3 scripts/cuentas_de_prueba.py` (desde la raíz) quedan creadas
cuentas de cada rol con PIN conocido. La tabla está en el
[README de la raíz](../README.md#cuentas-de-prueba-los-cuatro-roles).

| Rol | Qué abre |
|---|---|
| `ADMIN` | `ShellAdmin`: obras, materiales, usuarios, importación desde Excel y solicitudes |
| `BODEGUERO` | `ShellBodega`: elige obra y después ve el inicio, el escáner, los movimientos, los préstamos, las alertas y el cierre de turno |
| `TRABAJADOR` | `ShellTrabajador`: credencial QR a pantalla completa, pedidos, pedidos especiales e historial |
| `JEFE_TERRENO` | `PantallaRolPendiente`: su flujo todavía no está construido |

---

## Comandos

```bash
flutter analyze                                  # análisis estático
dart format .                                    # formatear (la CI falla si algo queda sin formato)
flutter test                                     # pruebas
flutter test test/bodega_test.dart               # un solo archivo
flutter build apk --debug                        # el APK que compila la CI
```

La CI (`.github/workflows/ci.yml`) corre, en este orden:
`dart format --output=none --set-exit-if-changed .`, `flutter analyze`,
`flutter test` y `flutter build apk --debug`. Correr los tres primeros antes de
abrir un PR ahorra una vuelta.

---

## Estructura

```
lib/
├── main.dart              Arranque y elección del shell según el rol
├── core/
│   ├── network/           ApiClient (Dio), AppConfig (.env), errores, idempotencia
│   ├── storage/           SesionStorage sobre flutter_secure_storage
│   ├── theme/             Colores, forma, tipografía y movimiento
│   ├── navegacion.dart    Navigator y ScaffoldMessenger raíz
│   ├── formato.dart       Fechas, montos y cantidades en es-CL
│   └── pantalla.dart
├── data/
│   ├── api/               auth_api, dominio_api, cliente_rest
│   └── modelos/           Un modelo por respuesta de la API
├── features/
│   ├── auth/              Acceso por correo + PIN, acceso solo con PIN, sesión
│   ├── admin/             Pantallas del administrador
│   ├── bodega/            Pantallas del bodeguero y el escáner
│   ├── trabajador/        Pantallas del trabajador
│   ├── obra/              Obra activa y selector de obra
│   └── inicio/            Pantalla para roles sin flujo
└── shared_widgets/        Campos, filas, paneles, estados vacíos y de error
```

Las carpetas `features/cubicacion`, `inventario`, `presupuesto` y
`solicitudes`, igual que `data/local_db`, existen pero todavía están vacías.
`features/auth/pantalla_diagnostico.dart` prueba la conexión
teléfono → API → base. Hoy no se llega a ella desde ninguna pantalla.

---

## Decisiones que conviene conocer

**La sesión vive en el Keystore.** `SesionStorage` guarda el JWT y el último
usuario en `flutter_secure_storage`. El PIN no se guarda nunca: el acceso
rápido del trabajador vuelve a mandarlo al servidor (`/api/auth/login-pin`).

**Quién entra con qué.** El TRABAJADOR entra con un PIN de 4 dígitos, y solo él
usa el acceso rápido por PIN (`login-pin`). ADMIN, JEFE_TERRENO y BODEGUERO
entran con correo y una clave de 8 a 72 caracteres; el teléfono no les ofrece
el acceso rápido aunque los recuerde. Tras 5 intentos fallidos el servidor
bloquea la cuenta (aunque la clave sea la correcta) y responde 429 con
`Retry-After`: la app dice cuánto esperar. La regla de la clave está en
`core/politica_clave.dart`, igual a la del backend.

**Clave provisoria.** Si el login responde `debeCambiarClave: true` —o cualquier
petición recibe 403 con `codigo: DEBE_CAMBIAR_PIN`—, la raíz de la app muestra
`PantallaCambiarClave` en vez de la app: el servidor rechaza todo salvo
`PUT /api/auth/pin`. Al cambiarla, la sesión nueva que devuelve reemplaza a la
provisoria. No hay "omitir"; solo cerrar sesión.

**El token dura 30 minutos y se renueva solo.** El login trae también un
`refreshToken` (7 días sin usarse) que se guarda junto a la sesión, en el mismo
almacenamiento cifrado. Ante un 401, el interceptor lo canjea en
`POST /api/auth/refresh` y reintenta la petición **una vez**; nadie lo nota. El
refresh se **rota**: cada uso entrega uno nuevo y deja inservible el anterior, y
usar uno ya gastado hace que el servidor cierre todas las sesiones de esa
persona, por eso `RenovadorDeSesion` hace un solo refresh a la vez y las demás
peticiones esperan su resultado. La sesión local solo se cierra si el servidor
dice que ya no vale (`SESION_INVALIDA` o el refresh rechazado): sin señal no se
cierra nada. Al cerrar sesión, la app revoca el refresh con
`POST /api/auth/logout`, sin esperarlo ni depender de él.

**Lo que recuerda el teléfono va por empresa y usuario.** Con una base por
empresa los ids se repiten: la obra 3 o el usuario 4 existen en cada una. Por
eso el usuario recordado guarda también su `empresaId` (que viaja en
`login-pin` junto al `usuarioId`), y la obra activa y la copia de la
credencial se guardan bajo `obra_activa:<empresa>:<usuario>` y
`perfil_trabajador:<empresa>:<usuario>`. Al entrar otra cuenta, la obra
activa se reconstruye con la identidad nueva: no hereda la de la anterior.
Lo guardado en el formato viejo (sin empresa) se descarta al entrar, y quien
tenía un usuario recordado sin empresa vuelve a escribir su correo una vez.

**Los timeouts son de 8 segundos.** En la obra la señal es mala, y conviene
más que el usuario reintente pronto a que quede esperando 30 segundos.

**Reintentar no duplica movimientos.** Cada pantalla que registra algo genera
una `Idempotency-Key` por intención (`core/network/idempotencia.dart`).
Mientras el usuario reintenta con los mismos datos, la clave es la misma y el
backend devuelve la respuesta del primer envío. Si cambia un dato después de un
fallo, la clave cambia. Al agregar una pantalla que escribe, úsala: sin la
clave, un toque doble puede registrar dos despachos.

**Todavía no hay cola sin conexión.** `drift` está en el `pubspec.yaml`, pero
ninguna tabla local está definida. Hoy, sin red, la acción falla con un
mensaje y el usuario reintenta. Cuando se construya la cola, la guía está en
[`flutter-offline-first`](../.claude/skills/flutter-offline-first/SKILL.md), y
habrá que correr `dart run build_runner build` para generar el código de Drift.

**Solo tema claro.** Las pantallas se diseñaron para leerse al sol. Los colores
y su contraste están en `core/theme/app_colors.dart` y en el
[design system](../docs/design-system/Check-In-Obra_Design_System.md).

---

## Pruebas

Están en `test/`, una por flujo (`bodega_test`, `trabajador_test`,
`idempotencia_test`, `cantidad_entregada_test`…). Ninguna llama a la API real:
las que dependen de ella la reemplazan con un doble, así que no hace falta el
backend arriba.

- `fuentes.dart` carga Inter real para las pruebas de layout. Con la fuente de
  prueba de Flutter cada letra mide un cuadrado y cualquier fila parece
  desbordar. Llama a `cargarInter()` en el `setUpAll` de toda prueba que mida
  texto.
- `accesibilidad_test.dart` fija lo que dejó la revisión de UI: botones que el
  lector de pantalla anuncia con su etiqueta, filas que no desbordan con el
  texto del sistema al máximo y contrastes de 4.5:1 en texto y 3:1 en bordes.
- `fixtures_obra.dart` trae datos de ejemplo de una obra para reutilizar.

---

## Problemas frecuentes

**"No se pudo alcanzar el servidor".** Revisa en este orden: la API responde
(`docker compose ps`); el celular y el computador están en la misma WiFi; la
IP del `.env` es la actual (cambia al cambiar de red); reiniciaste la app
después de editar el `.env`.

**El celular no aparece en `flutter devices`.** Activa la depuración USB y
cambia el modo USB del teléfono a *Transferencia de archivos*, porque algunos
cables solo cargan. En Windows suele faltar el driver: instala el *Google USB
Driver* desde el SDK Manager de Android Studio.

**`adb devices` lo muestra como `unauthorized`.** Desbloquea el teléfono y
acepta el aviso de depuración USB. Si no aparece, en *Opciones de
desarrollador* toca *Revocar autorizaciones de depuración USB* y reconecta.

**La CI falla en "Verificar formato".** Corre `dart format .` y commitea el
resultado.

**La CI falla en `flutter build apk` con `Hash of downloaded file
libsqlite3…`.** Es una descarga corrupta del binario de `sqlite3` en el runner
de GitHub, no un problema del código. Relanza el job.

**Generar un APK de release.** Usa `scripts/release-apk.sh` desde la raíz (o
el workflow manual *APK de release* del CI). Hace tres cosas que `flutter build
apk --release` a secas no hace:

- exige `API_BASE_URL=https://…` y la pasa con `--dart-define` (en release la
  app **no** lee el `.env`);
- firma con tu keystore, tomado de `CHECKINOBRA_KEYSTORE_FILE`,
  `CHECKINOBRA_KEYSTORE_PASSWORD`, `CHECKINOBRA_KEY_ALIAS` y
  `CHECKINOBRA_KEY_PASSWORD`, o de `android/key.properties`
  (`storeFile`, `storePassword`, `keyAlias`, `keyPassword`; no se versiona).
  Sin keystore el build se detiene con un mensaje: ya no firma con la clave de
  debug;
- ofusca el código (`--obfuscate`) y deja los símbolos en `build/debug-info/`.
  Guárdalos junto a cada versión que publiques: sin ellos un stack trace del
  APK no se puede leer.

En el CI, el workflow toma el keystore de los secretos del repositorio
(`ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`,
`ANDROID_KEY_PASSWORD`) y la URL de la variable `API_BASE_URL`. El keystore
nunca se sube al repo. La app tampoco se respalda en Google ni se copia a otro
teléfono (`allowBackup="false"` y reglas de extracción).
