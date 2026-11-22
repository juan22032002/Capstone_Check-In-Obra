# Check-In-Obra · Backend

API REST de Check-In-Obra: cubicación, presupuesto, bodega e inventario para
constructoras PYME. La consume la app Flutter de [`../mobile`](../mobile).

Java 21 · Spring Boot 4.1.1 · PostgreSQL 16 · Flyway · JJWT · Apache POI ·
springdoc-openapi.

Este README cubre lo que necesitas para trabajar dentro de `backend/`. La
visión del sistema completo, los roles y el esquema de la base están en el
[README de la raíz](../README.md).

---

## Levantarlo

### Atajo

```bash
scripts/levantar.sh                                            # Linux y macOS
powershell -ExecutionPolicy Bypass -File scripts\levantar.ps1  # Windows
```

Enciende Docker Desktop si está apagado, construye y levanta las imágenes,
espera a que la API responda y arranca el emulador de Android. Con
`--sin-emulador` (`-SinEmulador` en Windows) se queda solo con Docker. Las
demás opciones aparecen con `scripts/levantar.sh --help`.

### Con Docker (lo normal)

Desde la raíz del repo:

```bash
docker compose up -d
```

| Qué | Dónde |
|---|---|
| API | http://localhost:8081 (dentro del contenedor escucha en `8080`) |
| Swagger UI | http://localhost:8081/swagger-ui.html |
| PostgreSQL | `localhost:5433`, base `checkinobra`, usuario y clave `postgres` |

Flyway aplica las migraciones al arrancar. En una base vacía la API crea la primera
empresa y a su administrador `admin@arauco-ltda.cl` (la `V2` que lo sembraba con el
PIN `0000` salió de `db/migration`; en las bases que ya la habían aplicado, la `V11`
anula ese PIN): su clave inicial es `PRIMER_ADMIN_CLAVE` (del `.env` de la raíz, que `scripts/levantar.sh`
genera) y la cuenta queda obligada a cambiarla con `PUT /api/auth/pin` antes de
hacer cualquier otra cosa. Detalle en el
[README de la raíz](../README.md#2-primer-login).

```bash
curl -X POST http://localhost:8081/api/auth/login \
  -H 'Content-Type: application/json' \
  -d "{\"email\":\"admin@arauco-ltda.cl\",\"pin\":\"$PRIMER_ADMIN_CLAVE\"}"
```

Para tener las cuentas de los cuatro roles y una obra de ejemplo:
`python3 scripts/cuentas_de_prueba.py` (desde la raíz, con la API arriba).

Después de cambiar código Java, hay que reconstruir la imagen:
`docker compose up -d --build backend`.

### Sin Docker (desde el IDE o la terminal)

Levanta solo la base y corre la API en tu máquina:

```bash
docker compose up -d db
cd backend
cp .env.example .env
set -a; source .env; set +a      # exporta las variables a esta terminal
./mvnw spring-boot:run           # Windows: .\mvnw.cmd spring-boot:run
```

> **Spring no lee `.env` por su cuenta.** Si arrancas sin exportar las
> variables, la API no arranca (no hay usuario ni contraseña por defecto) y la
> URL por defecto es `localhost:5432`, no el `5433` que publica Docker. En
> IntelliJ, carga el `.env` en la configuración de ejecución (*Environment
> variables* o el plugin EnvFile).

### Variables de entorno

| Variable | Para qué | Valor por defecto |
|---|---|---|
| `SPRING_DATASOURCE_URL` | JDBC de PostgreSQL | `jdbc:postgresql://localhost:5432/checkinobra` |
| `SPRING_DATASOURCE_USERNAME` | Usuario de la API: `checkinobra_app`, solo DML. **Obligatorio** | Ninguno |
| `SPRING_DATASOURCE_PASSWORD` | Su contraseña (`DB_APP_PASSWORD`). **Obligatoria** | Ninguna |
| `FLYWAY_USER` / `FLYWAY_PASSWORD` | Flyway: `checkinobra_migrador`, dueño del esquema. También migra el catálogo | Los de la API (solo sirve con un único usuario) |
| `CATALOGO_URL` | JDBC de la base de catálogo (`checkinobra_catalogo`) | `jdbc:postgresql://localhost:5432/checkinobra_catalogo` |
| `CATALOGO_USER` / `CATALOGO_PASSWORD` | Usuario `checkinobra_plataforma` y su contraseña (`DB_PLATAFORMA_PASSWORD`). **Obligatorios** | Ninguno |
| `PRIMERA_EMPRESA_RUT` / `PRIMERA_EMPRESA_NOMBRE` | La primera empresa, que nace en una base vacía y es la que se registra en el catálogo | Constructora Arauco Ltda. |
| `JWT_SECRET` | Firma de los JWT. **Obligatorio**: la API no arranca si falta, tiene menos de 32 bytes o es el valor de ejemplo | Ninguno |

### Perfil `prod`

En un despliegue real se arranca con `SPRING_PROFILES_ACTIVE=prod`, que apaga **Swagger y `/v3/api-docs`**
(`application-prod.properties`): en desarrollo ayudan a probar, y en producción le entregan a cualquiera
el mapa completo de endpoints y cuerpos. Lo demás es igual. El contenedor declara un `HEALTHCHECK`
sobre `/actuator/health/liveness`, que es lo único del actuator que se expone (sin detalles; no incluye
la base de datos, porque hay una por empresa y no hay conexión que probar sin una empresa). La imagen
corre como un usuario sin privilegios, y sus imágenes base van fijadas por digest.

`docker-compose.yml` define las del datasource y lee `JWT_SECRET` del `.env` de
la raíz (no se versiona). `scripts/levantar.sh` lo genera la primera vez; a
mano: copia `.env.example` a `.env` y reemplaza el marcador con
`openssl rand -base64 48`. Sin él, el backend sale al arrancar con un mensaje que lo
explica (`docker compose logs backend`). `./mvnw test` y la CI usan un secreto de pruebas definido en el `pom.xml`.

Si una instancia ya corrió con el valor por defecto antiguo, rota el secreto:
los tokens firmados con él valían.

---

## Pruebas

```bash
./mvnw test        # pruebas
./mvnw verify      # lo mismo que corre la CI
```

Hay dos tipos:

- **Unitarias**, sin base: `RutTest`, `AislamientoEntreEmpresasTest`,
  `RespuestasNoExponenEntidadesTest`, la lectura de planillas, entre otras.
- **De integración** (`@SpringBootTest`): levantan el contexto completo, corren
  Flyway y necesitan una PostgreSQL real. Son `CheckinobraApplicationTests`,
  `PedidosEspecialesTest`, `TrabajadorEnSuTelefonoTest`,
  `DobleTapYConcurrenciaTest` y `CostosFaltantesYDetalleDeObraTest`.

Las de integración crean empresas y obras con un sufijo aleatorio y no las
borran. Para no ensuciar la base con la que pruebas la app, usa una aparte:

```bash
docker compose exec db createdb -U postgres checkinobra_test
docker compose exec -T -e PGDATABASE=checkinobra_test db /docker-entrypoint-initdb.d/01-roles.sh
SPRING_DATASOURCE_URL=jdbc:postgresql://localhost:5433/checkinobra_test ./mvnw test
```

La segunda línea crea los roles en esa base (ver
[Roles de la base](../README.md#roles-de-la-base)), y con el `.env` de la raíz
exportado la prueba corre como `checkinobra_app` y migra como
`checkinobra_migrador`, igual que en producción. `RolesDeBaseDeDatosTest` falla si
no es así.

Las pruebas **comparten una sola base entre muchas empresas de prueba**: el `pom.xml` define
`checkinobra.pruebas.conexion-compartida=true` y `ConexionCompartidaParaPruebas` pone un
resolutor que manda todas a la misma base (ningún despliegue lo trae). El enrutamiento real
se prueba con dos bases en `TenantRoutingDataSourceTest`, y las pruebas que inician sesión por
correo registran su empresa y sus usuarios en el catálogo (`CatalogoDePrueba`).

**Pruebas de aislamiento con dos bases** (`AislamientoConDosBasesTest`): registran dos empresas en
el catálogo, cada una en su base, y usan el enrutador de verdad. Necesitan una segunda base **vacía**,
`checkinobra_b` (o la de `checkinobra.pruebas.segunda-base`), que crea `db/crear-roles.sh` si se le
pasa `CHECKINOBRA_BASES_EXTRA=checkinobra_b` (con `docker compose`: `docker compose exec -T -e
CHECKINOBRA_BASES_EXTRA=checkinobra_b db /docker-entrypoint-initdb.d/01-roles.sh`). La CI lo hace. Las
tablas las migra `MigradorDeBases` durante la prueba. Sin esa base, la prueba falla diciendo cuál falta.

La CI (`.github/workflows/ci.yml`) crea los roles con `db/crear-roles.sh` sobre un
PostgreSQL 16 vacío en `localhost:5432` y corre `./mvnw -B verify` con ellos.

---

## Estructura

```
src/main/java/cl/duocuc/checkinobra/
├── config/         Empresa, Usuario, JWT, seguridad, idempotencia, errores
├── obra/           Obra, Cuadrilla, Trabajador
├── cubicacion/     Material, ParametroMerma, Partida, MotorCubicacion
├── presupuesto/    Presupuesto, ComparadorPresupuesto
├── inventario/     Kardex, herramientas, préstamos, solicitudes, pedidos especiales
├── importacion/    Lectura y plantilla de las planillas .xlsx
└── control/        Alertas y ficha de obra
src/main/resources/
├── application.properties
└── db/migration/   V1 … V9 (Flyway)
```

Cada paquete separa entidad, repositorio, servicio, controlador y los `record`
de request y respuesta. La única regla entre paquetes: **`control` puede
depender de todos, y nadie depende de `control`**.

---

## Reglas que el código da por hechas

Antes de tocar algo, conviene conocer estas cinco:

1. **La empresa sale del token, nunca de la petición.** Toda entidad
   implementa `PerteneceAEmpresa`, y los servicios filtran con
   `AccesoEmpresa.esPropio`. Un recurso de otra empresa responde el mismo 404
   que uno inexistente. `AislamientoEntreEmpresasTest` falla si una entidad
   nueva no implementa la interfaz.
2. **El stock no es una columna.** Es la suma con signo de los
   `KardexMovimiento`. Un despacho mayor al disponible responde 409
   `STOCK_INSUFICIENTE`.
3. **Los controladores no devuelven entidades.** Cada uno tiene su `record` de
   respuesta. `RespuestasNoExponenEntidadesTest` lo verifica.
4. **Las escrituras aceptan `Idempotency-Key`.** Es un UUID por intención del
   usuario. Si llega la misma clave repetida, se devuelve la respuesta guardada
   y no se ejecuta la operación otra vez. Lo implementa `IdempotenciaFilter`, y
   la app móvil depende de eso para reintentar sin duplicar despachos.
5. **Un endpoint sin `@PreAuthorize` queda abierto a los cuatro roles.** Las
   únicas rutas públicas son `/api/auth/**` y Swagger.

### Errores

`ApiExceptionHandler` traduce las excepciones a un cuerpo único
`{ instante, status, mensaje, codigo }`:

| Excepción | Status |
|---|---|
| `IllegalArgumentException`, validación, JSON mal formado | `400` |
| `AccesoDenegadoException` | `403` |
| `NoSuchElementException` | `404` |
| `IllegalStateException` / `ConflictoException` (con `codigo`) | `409` |
| Choque de bloqueo o de integridad en la base | `409` |
| Archivo de más de 5 MB | `413` |

Para una regla de negocio nueva, lanza `ConflictoException` con un código
estable. La app reacciona al `codigo`, no al texto del mensaje.

---

## Agregar un endpoint o una entidad

1. Crea la migración `V<n>__descripcion.sql` en `db/migration/`. Nunca edites
   una que ya se aplicó: Flyway compara checksums y la API no arranca.
2. Escribe la entidad. `ddl-auto=validate`, así que Hibernate solo comprueba
   que calce con la migración y no crea nada.
3. Implementa `PerteneceAEmpresa` en la entidad y filtra con `AccesoEmpresa`
   en el servicio.
4. Agrega un `record` de respuesta y `@PreAuthorize` en el controlador.
5. Si la escritura puede repetirse desde el teléfono, la app debe mandar
   `Idempotency-Key`.

La guía con plantillas de cada capa está en
[`.claude/skills/spring-boot-modulo`](../.claude/skills/spring-boot-modulo/SKILL.md).
Si el cambio toca stock, kardex o presupuesto, revísalo también contra
[`kardex-invariantes`](../.claude/skills/kardex-invariantes/SKILL.md).

---

## Problemas frecuentes

**`Connection refused` a `localhost:5432` al correr fuera de Docker.**
Docker publica la base en `5433`. Exporta las variables del `.env` (ver
[Sin Docker](#sin-docker-desde-el-ide-o-la-terminal)).

**`Validate failed: Migration checksum mismatch`.**
Se modificó una migración ya aplicada. Revierte el cambio y crea una
migración nueva. En local también puedes partir de cero con
`docker compose down -v`, que **borra la base**.

**`Schema-validation: missing column` al arrancar.**
La entidad tiene un campo que ninguna migración crea. Falta la `V<n>`.

**El cambio en Java no se ve en `localhost:8081`.**
El contenedor sigue corriendo la imagen anterior. Usa
`docker compose up -d --build backend`.
