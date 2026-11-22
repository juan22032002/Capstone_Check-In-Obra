# Check-In-Obra — Especificación del sistema

**Versión:** 1.1 · **Fecha:** 2026-09-02 · **Alcance:** MVP 1
**Repo:** [1Bryvn/Check-In-Obra](https://github.com/1Bryvn/Check-In-Obra) · Rama de referencia: `flujos-bodega-admin-y-aislamiento`

Esta especificación describe **qué hace el sistema y bajo qué reglas**, no cómo
se instala ni cómo se corre. Para eso está el [`README.md`](../README.md). Para
saber qué falta y en qué orden, [`PENDIENTES.md`](PENDIENTES.md) — que está
fechado el 2026-08-27 y todavía no recoge los flujos de bodega y administración
ni la CI; ante una diferencia, manda la §13 de este documento.

Todo lo que aquí se afirma está verificado contra el código de esa rama: los
endpoints salen de las anotaciones de los controladores, las reglas de negocio
de los servicios y las entidades, y el esquema de las migraciones Flyway. Donde
algo está diseñado pero no construido, se dice.

---

## Índice

1. [Propósito y alcance](#1-propósito-y-alcance)
2. [Actores](#2-actores)
3. [Glosario del dominio](#3-glosario-del-dominio)
4. [Arquitectura](#4-arquitectura)
5. [Modelo de datos](#5-modelo-de-datos)
6. [Requisitos funcionales](#6-requisitos-funcionales)
7. [Reglas de negocio](#7-reglas-de-negocio)
8. [Ciclos de vida](#8-ciclos-de-vida)
9. [Interfaz de la API](#9-interfaz-de-la-api)
10. [Aplicación móvil](#10-aplicación-móvil)
11. [Requisitos no funcionales](#11-requisitos-no-funcionales)
12. [Restricciones, supuestos y riesgos](#12-restricciones-supuestos-y-riesgos)
13. [Estado de cumplimiento](#13-estado-de-cumplimiento)
14. [Trazabilidad](#14-trazabilidad)
15. [Criterios de aceptación del MVP 1](#15-criterios-de-aceptación-del-mvp-1)

---

## 1. Propósito y alcance

### 1.1 El problema

En obras de tabiquería y cielos, la cubicación se hace en planilla, la compra se
decide a ojo y el consumo real nunca se compara contra lo presupuestado. La
desviación aparece cuando la obra ya cerró, que es cuando ya no se puede hacer
nada con ella.

### 1.2 El objetivo

Cerrar ese ciclo dentro de la obra abierta: cubicar la partida con una regla
explícita, congelar el presupuesto, registrar cada movimiento de bodega con
trazabilidad de persona, y exponer la desviación mientras todavía es
corregible.

### 1.3 Dentro del alcance (MVP 1)

| # | Capacidad |
|---|---|
| 1 | Autenticación por PIN y autorización por rol, con aislamiento entre constructoras |
| 2 | Administración de la empresa: usuarios, catálogo de materiales, mermas, obras |
| 3 | Cubicación de partidas de tabique, cielo y revestimiento con merma por material |
| 4 | Presupuesto por obra con estados y congelamiento |
| 5 | Kardex de obra: recepción, despacho y consumo, con saldo derivado |
| 6 | Herramientas: catálogo, préstamo, devolución con estado de retorno |
| 7 | Solicitudes de material y herramienta del trabajador, con aprobación del bodeguero tras escanear su credencial QR |
| 8 | Alertas de stock crítico, herramienta no devuelta y cierre de turno |
| 9 | Reporte de desviación presupuestado vs. ejecutado |
| 10 | Escáner de código de barras para encontrar material y herramientas en bodega |
| 11 | Alta masiva del catálogo desde planilla Excel |
| 12 | App Android para los cuatro roles |

### 1.4 Fuera del alcance

- **Compras y proveedores.** Una recepción entra al kardex sin orden de compra
  ni factura asociada.
- **Multi-obra simultánea para un mismo bodeguero.** Se elige una obra y se
  trabaja sobre ella.
- **Alta de constructoras por API.** Ver [RF-A8](#a-acceso-y-configuración).
- **Web.** Hay mockups de escritorio en `docs/mockups/design/`, pero el MVP 1
  entrega solo la app Android.
- **Nómina, asistencia y avance físico de obra.**

---

## 2. Actores

Una sola clase `Usuario` para los cuatro roles; lo que cambia es el enum
`RolUsuario`. No hay subclase por rol, y por lo tanto tampoco un usuario con
dos roles.

| Actor | Entra por | Trabaja sobre | Pregunta que responde el sistema |
|---|---|---|---|
| **Trabajador** | PIN (usuario recordado en el teléfono) | Lo suyo | ¿Qué pedí, qué tengo prestado, cómo me identifico? |
| **Bodeguero** | Correo + PIN | Una obra | ¿Qué queda, qué salió, quién lo tiene? |
| **Jefe de terreno** | Correo + PIN | Una obra | ¿Cuánto material necesita esta partida y cómo va la desviación? |
| **Administrador** | Correo + PIN | La empresa entera | ¿Quién trabaja aquí, a qué precio compramos, qué obras están abiertas? |

**Actor no humano:** ninguno. No hay tareas programadas — las alertas se
detectan cuando alguien las mira ([RN-24](#7-reglas-de-negocio)).

La matriz de permisos completa está en el
[README](../README.md#roles-y-permisos); cada requisito de la §6 indica el rol
que lo autoriza.

---

## 3. Glosario del dominio

| Término | Significado en este sistema |
|---|---|
| **Partida** | Un elemento constructivo a ejecutar (tabique, cielo, revestimiento) con su ancho, alto y separación de montantes |
| **Cubicar** | Calcular, a partir de la geometría de la partida y una receta de rendimiento, qué materiales y cuántos lleva |
| **Merma** | Porcentaje de material que se pierde al ejecutar. Se define por material y se aplica sobre la cantidad calculada |
| **Ítem cubicado** | Resultado de cubicar: material, cantidad calculada y cantidad con merma |
| **Presupuesto** | Conjunto de ítems valorizados de una obra, con un estado que decide si aún se puede tocar |
| **Congelar** | Fijar el presupuesto: desde ahí deja de seguir al catálogo y pasa a ser la referencia contra la que se mide la desviación |
| **Kardex** | Libro de movimientos de material de una obra. Es el registro; el stock es su consecuencia |
| **Saldo / stock** | Suma con signo de los movimientos de un material en una obra. **No se almacena** |
| **Recepción / despacho / consumo** | Entrada de material a la obra / entrega a un trabajador / gasto en la obra sin receptor |
| **Préstamo** | Salida de una herramienta a nombre de un trabajador, con fecha de devolución esperada |
| **Solicitud** | Pedido del trabajador que el bodeguero aprueba o rechaza. Aprobar produce un despacho o un préstamo |
| **Alerta** | Condición de la obra que requiere atención: stock bajo el mínimo, herramienta vencida, o traspaso de turno |
| **Credencial** | El QR que identifica a un trabajador. El bodeguero lo escanea para traer a pantalla lo que esa persona pidió |
| **Código de barras** | El código impreso de fábrica en el envase de un material. Distinto del SKU, que es interno de la constructora |
| **Cierre de turno** | Revisión con la que el bodeguero deja constancia de lo que hereda el turno siguiente |
| **Desviación** | Diferencia porcentual entre lo ejecutado (despachos y consumos valorizados) y lo presupuestado |

---

## 4. Arquitectura

```
┌──────────────────────┐        HTTP/JSON        ┌──────────────────────────┐
│  App Android         │  ───── Bearer JWT ───▶  │  API REST (Spring Boot)  │
│  Flutter + Riverpod  │                         │  6 módulos de dominio    │
└──────────────────────┘                         └───────────┬──────────────┘
                                                             │ JPA / Flyway
                                                 ┌───────────▼──────────────┐
                                                 │  PostgreSQL 16           │
                                                 └──────────────────────────┘
```

### 4.1 Módulos del backend

Paquetes por dominio, no por capa. Cada uno agrupa entidad, repositorio,
servicio, controlador y *records* de respuesta.

| Módulo | Contenido | Depende de |
|---|---|---|
| `config` | Empresa, Usuario, seguridad, JWT, aislamiento, manejo de errores | — |
| `obra` | Obra, Cuadrilla, Trabajador | `config` |
| `cubicacion` | Material, ParametroMerma, Partida, ItemCubicado, MotorCubicacion | `config`, `obra` |
| `presupuesto` | Presupuesto, PresupuestoItem, ComparadorPresupuesto | `cubicacion`, `inventario`, `obra` |
| `inventario` | Herramienta, Préstamo, Kardex, Solicitudes | `cubicacion`, `obra`, `config` |
| `control` | Alerta | `inventario`, `cubicacion`, `obra` |

`control` depende de los demás y **nunca al revés**: detectar una alerta exige
mirar préstamos y stock, pero registrar un movimiento no debe saber que existen
las alertas.

### 4.2 Componentes y versiones

| Componente | Versión | Rol |
|---|---|---|
| Java / Spring Boot | 21 / 4.1.1 | API REST, seguridad, JPA |
| PostgreSQL | 16 | Persistencia |
| Flyway | — | Esquema versionado (`V1`–`V5`) |
| JJWT | 0.12.6 | Emisión y validación de JWT |
| springdoc-openapi | 2.8.6 | Swagger UI |
| Apache POI | 5.4.1 | Lectura y generación de las planillas `.xlsx` |
| Flutter | 3.47.1 | App Android |
| Riverpod / dio / flutter_secure_storage | 2.6 / 5.11 / 11.0 | Estado, HTTP, almacenamiento cifrado |
| mobile_scanner / file_picker | 7.4 / 12.2 | Escáner de cámara y elección de la planilla a importar |
| Docker Compose | — | Backend + base para desarrollo |

---

## 5. Modelo de datos

17 entidades, derivadas del diagrama de clases
(`docs/diagrams/Check-In-Obra_Diagrama_Clases_MVP1.png`) y materializadas en
cinco migraciones.

| Entidad | Tabla | Claves y relaciones que importan |
|---|---|---|
| Empresa | `empresas` | `rut` único. Raíz del aislamiento |
| Usuario | `usuarios` | `email` único, `rut` único, `pin_hash` (BCrypt), `empresa_id` |
| Obra | `obras` | `estado`, `empresa_id`, `jefe_terreno_id` → `usuarios` |
| Cuadrilla | `cuadrillas` | `obra_id` |
| Trabajador | `trabajadores` | `usuario_id` único, `cuadrilla_id`, `credencial_qr` único |
| Material | `materiales` | `sku` único, `codigo_barra` único **por empresa** (nullable), `categoria`, `precio_unitario`, `stock_minimo`, `empresa_id` |
| ParametroMerma | `parametros_merma` | `material_id` único — a lo más una merma por material |
| Partida | `partidas` | `tipo`, `ancho_m`, `alto_m`, `separacion_montantes`, `obra_id` |
| ItemCubicado | `items_cubicados` | `partida_id`, `material_id`, cantidad calculada y con merma |
| Presupuesto | `presupuestos` | `obra_id` **único** — a lo más un presupuesto por obra |
| PresupuestoItem | `presupuesto_items` | `presupuesto_id`, `material_id`, precio unitario congelado en el ítem |
| Herramienta | `herramientas` | `codigo_qr` único, `estado`, `valor_reposicion`, `empresa_id` |
| PrestamoHerramienta | `prestamos_herramienta` | herramienta, trabajador, obra, autorizador, fechas esperada y real |
| KardexMovimiento | `kardex_movimientos` | obra, material, `usuario_id` (quien registra), `trabajador_id` (quien recibe) |
| SolicitudHerramienta | `solicitudes_herramienta` | trabajador, herramienta, estado, `resuelto_por_id` |
| SolicitudMaterial | `solicitudes_material` | trabajador, material, obra, estado, `resuelto_por_id` |
| Alerta | `alertas` | `tipo`, `resuelto`, `obra_id`, `prestamo_herramienta_id` (nullable) |

### 5.1 Decisiones de modelado que no se leen en el diagrama

- **El RUT vive en `Usuario`, no en `Trabajador`.** Identifica a una persona, no
  a un rol: un jefe de terreno o un bodeguero no tienen registro de trabajador y
  también tienen RUT (`V3`).
- **`kardex_movimientos` distingue quién registra de quién recibe.** Sin esa
  columna el kardex no puede responder «¿a quién se le entregaron esas 36
  planchas?», que es exactamente la pregunta que aparece con un descuadre (`V3`).
- **El stock no es una columna.** Es la suma con signo del kardex
  ([RN-04](#7-reglas-de-negocio)). Un saldo almacenado se desincroniza en
  silencio; uno derivado no puede.
- **El material tiene dos códigos, y hacen falta los dos.** El `sku` es interno
  —lo define la constructora y es lo que aparece en la guía de despacho— y el
  `codigo_barra` es el de fábrica, el único que está físicamente impreso en lo
  que el bodeguero tiene en la mano. Sin el segundo, escanear una plancha
  obligaría igual a buscarla a mano (`V4`). Es nullable porque no todo material
  lo trae: los perfiles Metalcom se venden por tira, sin etiqueta.
- **La unicidad del código de barras es por empresa; la del SKU, global.** No es
  una inconsistencia: el SKU lo inventa cada constructora, pero un EAN-13 es del
  producto y la misma plancha trae el mismo código en todas las bodegas del
  país. Con un único global, la segunda constructora que la registrara no
  podría —y al importar perdería la planilla entera, porque la importación es
  todo o nada— por una fila que ni siquiera es suya.
- **No hay tabla de recetas de cubicación.** El diagrama no la modela, así que
  los coeficientes viven en código (`RecetaCubicacion`). Ver
  [§12.2](#122-riesgos).

### 5.2 Índices

`(obra_id, material_id)` en kardex, `(obra_id, fecha_devol_real)` en préstamos,
`(trabajador_id)` en solicitudes de herramienta, `(obra_id)` en solicitudes de
material, `(obra_id, resuelto)` en alertas y `(trabajador_id)` en kardex. Cada
uno responde a una consulta concreta de una pantalla, no a una intuición.

---

## 6. Requisitos funcionales

Formato: **ID · requisito · rol autorizado · endpoint · estado**.
Estado: ✅ backend y app · 🟡 backend listo, app pendiente · ⬜ ninguno de los dos.

### A. Acceso y configuración

| ID | Requisito | Rol | Endpoint | Estado |
|---|---|---|---|---|
| RF-A1 | Autenticarse con correo y PIN de 4 dígitos | Público | `POST /api/auth/login` | ✅ |
| RF-A2 | Autenticarse solo con PIN cuando el teléfono ya recuerda al usuario | Público | `POST /api/auth/login-pin` | ✅ |
| RF-A3 | Mantener la sesión abierta entre aperturas de la app | — | almacenamiento cifrado del teléfono | ✅ |
| RF-A4 | Dar de alta un usuario con nombre, correo, RUT, rol y PIN inicial | ADMIN | `POST /api/usuarios` | ✅ |
| RF-A5 | Consultar el padrón de la empresa y un usuario puntual | ADMIN | `GET /api/usuarios`, `GET /api/usuarios/{id}` | ✅ (el detalle, 🟡) |
| RF-A6 | Restablecer el PIN de un usuario | ADMIN | `PUT /api/usuarios/{id}/pin` | ✅ |
| RF-A7 | Consultar los datos de la propia constructora | Autenticado | `GET /api/empresas/mia`, `GET /api/empresas/{id}` | ✅ |
| RF-A8 | Dar de alta una constructora | — | **sin endpoint, por migración SQL** | ✅ |

> **RF-A8 no es un olvido.** Crear un tenant no es una operación de un tenant:
> el ADMIN que creara la empresa no podría verla después, porque el aislamiento
> lo dejaría fuera de la que acaba de crear. Haría falta un rol por encima de
> los cuatro, y el sistema tiene cuatro por diseño.

### B. Obra y equipos

| ID | Requisito | Rol | Endpoint | Estado |
|---|---|---|---|---|
| RF-B1 | Crear una obra con nombre, cliente y ubicación | ADMIN | `POST /api/obras` | ✅ |
| RF-B2 | Asignar o cambiar el jefe de terreno a cargo | ADMIN | `PUT /api/obras/{id}/jefe-terreno` | ✅ |
| RF-B3 | Cerrar una obra | ADMIN | `PUT /api/obras/{id}/cerrar` | ✅ |
| RF-B4 | Listar las obras de la empresa y ver una | Autenticado | `GET /api/obras`, `GET /api/obras/{id}` | ✅ |
| RF-B5 | Crear cuadrillas y listarlas por obra | ADMIN, JEFE_TERRENO | `POST /api/cuadrillas`, `GET /api/cuadrillas` | 🟡 |
| RF-B6 | Extender un usuario TRABAJADOR a trabajador de una cuadrilla | ADMIN | `POST /api/trabajadores` | 🟡 |
| RF-B7 | Listar los trabajadores de una obra o cuadrilla | Autenticado | `GET /api/trabajadores` | ✅ |
| RF-B8 | Identificar a un trabajador escaneando su credencial QR | ADMIN, BODEGUERO, JEFE_TERRENO | `GET /api/trabajadores/por-credencial/{qr}` | ✅ |
| RF-B9 | Renovar la credencial QR de un trabajador | Autenticado | `PUT /api/trabajadores/{id}/credencial` | 🟡 |

### C. Cubicación

| ID | Requisito | Rol | Endpoint | Estado |
|---|---|---|---|---|
| RF-C1 | Mantener el catálogo de materiales de la empresa | ADMIN | `POST /api/materiales`, `GET /api/materiales` | ✅ |
| RF-C2 | Actualizar el precio unitario de un material | ADMIN | `PUT /api/materiales/{id}/precio` | ✅ |
| RF-C3 | Definir y consultar la merma de un material | ADMIN | `PUT`/`GET /api/materiales/{id}/merma` | ✅ (consulta, 🟡) |
| RF-C8 | Encontrar un material por su código de barras o su SKU | Autenticado | `GET /api/materiales/por-codigo/{codigo}` | ✅ |
| RF-C9 | Dar de alta materiales en masa desde una planilla Excel | ADMIN | `POST /api/materiales/importar` | ✅ |
| RF-C10 | Descargar la plantilla de importación de materiales | ADMIN | `GET /api/materiales/plantilla-importacion` | ✅ |
| RF-C4 | Crear una partida con su geometría | ADMIN, JEFE_TERRENO | `POST /api/partidas` | 🟡 |
| RF-C5 | Listar las partidas de una obra y ver una | Autenticado | `GET /api/partidas`, `GET /api/partidas/{id}` | 🟡 |
| RF-C6 | Cubicar una partida: calcular sus ítems con merma | ADMIN, JEFE_TERRENO | `POST /api/partidas/{id}/cubicar` | 🟡 |
| RF-C7 | Consultar los ítems cubicados de una partida | Autenticado | `GET /api/partidas/{id}/items-cubicados` | 🟡 |

### D. Presupuesto

| ID | Requisito | Rol | Endpoint | Estado |
|---|---|---|---|---|
| RF-D1 | Crear el presupuesto de una obra | ADMIN, JEFE_TERRENO | `POST /api/presupuestos` | 🟡 |
| RF-D2 | Agregar un ítem tomando el precio vigente del catálogo | ADMIN, JEFE_TERRENO | `POST /api/presupuestos/{id}/items` | 🟡 |
| RF-D3 | Consultar el presupuesto de una obra y sus ítems | Autenticado | `GET /api/presupuestos?obraId=`, `/{id}/items` | 🟡 |
| RF-D4 | Aprobar el presupuesto | ADMIN, JEFE_TERRENO | `PUT /api/presupuestos/{id}/aprobar` | 🟡 |
| RF-D5 | Congelar el presupuesto aprobado | ADMIN, JEFE_TERRENO | `PUT /api/presupuestos/{id}/congelar` | 🟡 |
| RF-D6 | Obtener la desviación presupuestado vs. ejecutado | Autenticado | `GET /api/presupuestos/{id}/desviacion` | 🟡 |

**Cálculo de RF-D6.** `ejecutado` = Σ (cantidad × precio unitario del catálogo)
de los despachos y consumos de la obra. `desviacionPct` = (ejecutado −
presupuestado) / presupuestado × 100. Además se reporta `mermaRealVsEstimada`:
la merma real promedio por material (consumido vs. neto cubicado) menos la
merma con que se cubicó.

### E. Inventario y trazabilidad

| ID | Requisito | Rol | Endpoint | Estado |
|---|---|---|---|---|
| RF-E1 | Registrar una recepción de material en la obra | ADMIN, BODEGUERO | `POST /api/kardex` (`RECEPCION`) | ✅ |
| RF-E2 | Registrar un despacho indicando a qué trabajador se entrega | ADMIN, BODEGUERO | `POST /api/kardex` (`DESPACHO`) | ✅ |
| RF-E3 | Registrar un consumo de obra, con receptor opcional | ADMIN, BODEGUERO | `POST /api/kardex` (`CONSUMO`) | ✅ |
| RF-E4 | Consultar el kardex completo de una obra | ADMIN, JEFE_TERRENO, BODEGUERO | `GET /api/kardex?obraId=` | ✅ |
| RF-E5 | Consultar el saldo de un material en una obra | ADMIN, JEFE_TERRENO, BODEGUERO | `GET /api/kardex/stock` | ✅ |
| RF-E6 | Mantener el catálogo de herramientas | ADMIN, BODEGUERO | `POST /api/herramientas`, `GET /api/herramientas` | ✅ |
| RF-E7 | Identificar una herramienta escaneando el código de su etiqueta | Autenticado | `GET /api/herramientas/por-codigo/{codigo}` | ✅ |
| RF-E8 | Autorizar el préstamo de una herramienta disponible | ADMIN, BODEGUERO | `POST /api/prestamos-herramienta` | ✅ |
| RF-E9 | Registrar la devolución indicando en qué estado vuelve | ADMIN, BODEGUERO | `PUT /api/prestamos-herramienta/{id}/devolucion` | ✅ |
| RF-E10 | Listar préstamos por obra, por trabajador o solo vencidos | Autenticado | `GET /api/prestamos-herramienta` | ✅ |
| RF-E11 | Solicitar una herramienta | TRABAJADOR | `POST /api/solicitudes-herramienta` | 🟡 |
| RF-E12 | Aprobar una solicitud de herramienta, generando el préstamo | ADMIN, BODEGUERO | `PUT /api/solicitudes-herramienta/{id}/aprobar` | ✅ |
| RF-E13 | Rechazar una solicitud con motivo | ADMIN, BODEGUERO | `PUT /api/solicitudes-*/{id}/rechazar` | ✅ |
| RF-E14 | Solicitar material para una obra | TRABAJADOR | `POST /api/solicitudes-material` | 🟡 |
| RF-E15 | Aprobar una solicitud de material indicando cuánto se entrega | ADMIN, BODEGUERO | `PUT /api/solicitudes-material/{id}/aprobar` | ✅ |
| RF-E16 | Listar solicitudes por trabajador, por obra o solo pendientes | Autenticado | `GET /api/solicitudes-*` | ✅ |
| RF-E17 | Dar de alta herramientas en masa desde una planilla Excel | ADMIN, BODEGUERO | `POST /api/herramientas/importar` | ✅ |
| RF-E18 | Descargar la plantilla de importación de herramientas | ADMIN, BODEGUERO | `GET /api/herramientas/plantilla-importacion` | ✅ |

### F. Control

| ID | Requisito | Rol | Endpoint | Estado |
|---|---|---|---|---|
| RF-F1 | Detectar herramientas vencidas sin devolver | ADMIN, JEFE_TERRENO, BODEGUERO | `POST /api/alertas/detectar-no-devueltas` | ✅ |
| RF-F2 | Detectar materiales bajo el stock mínimo | ADMIN, JEFE_TERRENO, BODEGUERO | `POST /api/alertas/detectar-stock-critico` | ✅ |
| RF-F3 | Dejar constancia del cierre de turno | ADMIN, BODEGUERO | `POST /api/alertas/cierre-turno` | ✅ |
| RF-F4 | Resolver una alerta | ADMIN, JEFE_TERRENO, BODEGUERO | `PUT /api/alertas/{id}/resolver` | ✅ |
| RF-F5 | Listar las alertas de una obra, todas o solo sin resolver | Autenticado | `GET /api/alertas?obraId=` | ✅ |

---

## 7. Reglas de negocio

Invariantes que el backend hace cumplir. La columna «Respuesta» es el código
HTTP que ve quien llama.

| ID | Regla | Dónde vive | Respuesta |
|---|---|---|---|
| RN-01 | Un despacho o consumo no puede dejar el saldo negativo | `KardexMovimientoService` | 409 |
| RN-02 | La cantidad de un movimiento debe ser mayor que cero | `KardexMovimiento.registrar` | 409 |
| RN-03 | Un despacho exige receptor; una recepción no lo admite; un consumo lo deja opcional | `KardexMovimientoService.resolverReceptor` | 400 |
| RN-04 | El saldo es la suma con signo del kardex (+1 recepción, −1 despacho y consumo). No se almacena | `KardexMovimiento.signo` | — |
| RN-05 | Solo se presta una herramienta en estado `DISPONIBLE` | `PrestamoHerramientaService` | 409 |
| RN-06 | Un préstamo se devuelve una sola vez, y el estado de retorno no puede ser `PRESTADA` | `PrestamoHerramienta.registrarDevolucion` | 409 / 400 |
| RN-07 | Una solicitud ya resuelta no se vuelve a aprobar ni a rechazar | `Solicitud*.exigirPendiente` | 409 |
| RN-08 | Aprobar una solicitud de material genera el despacho con el solicitante como receptor | `SolicitudMaterialService.aprobar` | — |
| RN-09 | Aprobar una solicitud de herramienta genera el préstamo en la obra de la cuadrilla del trabajador | `SolicitudHerramientaService.aprobar` | — |
| RN-10 | Una obra tiene a lo más un presupuesto | `PresupuestoService.crear` + `UNIQUE` | 409 |
| RN-11 | El presupuesto avanza `BORRADOR → APROBADO → CONGELADO` y no retrocede | `Presupuesto.congelar`, `PresupuestoService.aprobar` | 409 |
| RN-12 | Un presupuesto congelado no admite más ítems | `PresupuestoService.exigirEditable` | 409 |
| RN-13 | El precio de un ítem se copia del catálogo al agregarlo: cambiar el catálogo después no reescribe el presupuesto | `PresupuestoService.agregarItem` | — |
| RN-14 | Una obra no cierra con herramientas fuera ni con alertas sin resolver, y una obra cerrada no se vuelve a cerrar | `ObraService.cerrarObra`, `Obra.cerrar` | 409 |
| RN-15 | El jefe de una obra debe tener rol `JEFE_TERRENO` o `ADMIN` | `ObraService.jefeDeTerrenoValido` | 409 |
| RN-16 | Solo un usuario con rol `TRABAJADOR` puede extenderse a `Trabajador` | `TrabajadorService.crear` | 409 |
| RN-17 | El PIN tiene exactamente 4 dígitos y se guarda solo como hash BCrypt | `Usuario.definirPin` | 400 |
| RN-18 | El correo y el RUT son obligatorios y únicos por usuario; el SKU, único por material | `UsuarioService`, `MaterialService` | 400 / 409 |
| RN-19 | `cantidadConMerma = cantidadCalculada × (1 + porcentaje/100)`; sin merma definida, ambas coinciden | `ParametroMerma.aplicar` | — |
| RN-20 | Los montantes se calculan `ceil(ancho / separación) + 1`, no por m² | `MotorCubicacionService` | — |
| RN-21 | Cubicar una partida **reemplaza** sus ítems anteriores, no los acumula | `MotorCubicacionService.calcular` | — |
| RN-22 | La empresa siempre sale del token; ningún endpoint la recibe desde afuera | `SesionActual`, `AccesoEmpresa` | — |
| RN-23 | Un recurso de otra empresa devuelve el mismo 404, con el mismo mensaje, que uno inexistente | `AccesoEmpresa.esPropio` | 404 |
| RN-24 | No se duplica una alerta mientras la anterior por la misma causa siga sin resolver | `AlertaService` | — |
| RN-25 | Una alerta resuelta no se vuelve a resolver | `Alerta.resolver` | 409 |
| RN-26 | Ningún controlador devuelve entidades JPA; `pinHash` nunca se serializa | *records* de respuesta + `@JsonIgnore` | — |
| RN-27 | La credencial QR es un UUID portador y es renovable: quien la tiene se presenta como ese trabajador | `TrabajadorService` | — |
| RN-28 | Escanear una credencial no autoriza nada por sí solo: identifica a la persona, y quien aprueba sigue siendo el usuario autenticado, que queda registrado en el despacho o el préstamo | `Solicitud*Service.aprobar` | — |
| RN-29 | Resolver una credencial ajena es de quien opera bodega (ADMIN, BODEGUERO, JEFE_TERRENO), no de cualquier autenticado | `TrabajadorController` | 403 |
| RN-30 | El código de barras es único **dentro de la empresa** cuando existe, y el escáner lo resuelve en ese mismo alcance | `MaterialService.buscarPorCodigo` + `uq_materiales_empresa_codigo_barra` | 404 / 409 |
| RN-31 | Una importación masiva es todo o nada: con una fila inválida no se guarda ninguna | `MaterialService.importar`, `HerramientaService.importar` | 200 con informe |
| RN-32 | Los códigos que se escanean —SKU de material y código de herramienta— se guardan y se buscan en mayúsculas: «her-014» y «HER-014» son el mismo | `HerramientaService`, `MaterialService.crear`, `V5` | 409 al repetirse |
| RN-33 | Al aprobar una solicitud de material, lo que se entrega es mayor que 0 y no pasa de lo solicitado (sí puede ser menos) | `SolicitudMaterialService.aprobar` | 400 |
| RN-34 | Un despacho, un consumo o un préstamo directo solo pueden nombrar a un trabajador asignado, por su cuadrilla, a la obra indicada | `TrabajadorService.exigirQueSeaDeLaObra` | 409 `OBRA_NO_ASIGNADA` o `SIN_CUADRILLA` |
| RN-35 | El SKU de un material y el código de una herramienta son únicos **por empresa**, no en toda la base | `V13`, `MaterialService.crear`, `HerramientaService.crear` | 409 al repetirse en la misma empresa |
| RN-36 | Las fichas y listas de trabajadores, las alertas, las partidas y las cuadrillas se leen solo con rol ADMIN, JEFE_TERRENO o BODEGUERO; un TRABAJADOR usa sus rutas «mías» y `/yo` | controladores `obra/`, `control/`, `cubicacion/` | 403 |

> **Sobre RN-31.** La alternativa —importar lo válido y reportar el resto— deja
> el catálogo a medias y obliga a adivinar qué entró antes de volver a subir el
> archivo corregido. Acá la planilla es la unidad: se arregla y se sube de
> nuevo. Por eso el endpoint simula por defecto (`confirmar=false`) y devuelve
> el mismo informe que devolvería la importación real.

> **Tensión conocida entre RN-14 y RF-F3.** El cierre de turno crea alertas y la
> obra no cierra con alertas abiertas. Es deliberado: lo que un turno dejó
> pendiente tiene que resolverse explícitamente antes de cerrar la obra, no
> desaparecer con ella.

---

## 8. Ciclos de vida

**Obra**

```
        crear                    cerrar (RN-14)
   ∅ ─────────▶ ACTIVA ──────────────────────────▶ CERRADA ──▶ (final)
```

**Presupuesto**

```
   ∅ ──▶ BORRADOR ──aprobar──▶ APROBADO ──congelar──▶ CONGELADO
            ▲                                            │
            └────────── admite ítems ─────────┘   ya no admite cambios
```

**Solicitud (material o herramienta)**

```
                     ┌── aprobar ──▶ APROBADA ──▶ genera despacho o préstamo
   ∅ ──▶ PENDIENTE ──┤
                     └── rechazar ─▶ RECHAZADA  (con motivo)
```

`ENTREGADA` existe en el enum `EstadoSolicitud` pero ningún flujo la asigna
hoy: la entrega queda registrada en el kardex o en el préstamo que la
aprobación genera.

**Herramienta y préstamo**

```
   DISPONIBLE ──prestar──▶ PRESTADA ──devolución──▶ DISPONIBLE
                                     └───────────▶ MANTENCION   (vuelve dañada)
```

Un préstamo abierto (`fecha_devol_real` nula) pasada su fecha esperada está
**vencido**, y eso es lo que detecta RF-F1.

**Alerta**

```
   ∅ ──generar──▶ sin resolver ──resolver──▶ resuelta   (RN-25: una sola vez)
```

---

## 9. Interfaz de la API

Base local: `http://localhost:8081` · OpenAPI: `/v3/api-docs` · Swagger:
`/swagger-ui.html`. **71 endpoints** en 16 controladores.

### 9.1 Autenticación

JWT firmado con HMAC-SHA. El token dura **30 minutos** y se renueva con un refresh token (ver el README; configurable con
`checkinobra.jwt.expiracion-minutos`) y lleva `sub` (id de usuario), `email`,
`rol`, `empresaId`, `iss`, `aud` y `tv` (versión de sesión). El refresh token rota en cada uso (`POST /api/auth/refresh`); un refresh reutilizado cierra todas las sesiones del usuario.

Rutas públicas: `/api/auth/**` y la documentación OpenAPI. Todo lo demás exige
`Authorization: Bearer <token>`.

### 9.2 Autorización

Dos capas independientes:

1. **Rol** — `@PreAuthorize` en el controlador decide *qué* puede hacer alguien.
2. **Empresa** — `AccesoEmpresa` decide *sobre qué datos*. Toda entidad
   implementa `PerteneceAEmpresa` y sabe recorrer su cadena hasta la empresa
   (`Cuadrilla → Obra → Empresa`).

Un endpoint sin `@PreAuthorize` queda abierto a los cuatro roles; en este
sistema eso es una decisión, no un descuido (las lecturas de obra, materiales y
herramientas lo son).

### 9.3 Códigos de respuesta

| Código | Cuándo |
|---|---|
| `200` | Operación exitosa |
| `201` | Recurso creado |
| `400` | Datos inválidos, enum inexistente, parámetro faltante, credenciales incorrectas |
| `403` | Sin token, token inválido, o el rol no autoriza la acción |
| `404` | El recurso no existe **o es de otra empresa** (RN-23) |
| `409` | La operación choca con una regla de negocio |

Cuerpo de error uniforme: `{ instante, status, mensaje }`. Un enum inválido
lista los valores aceptados, para no obligar a leer el código.

### 9.4 Importación masiva

Los dos endpoints de importación (`POST /api/materiales/importar` y
`POST /api/herramientas/importar`) son `multipart/form-data` con el archivo en
el campo `archivo` y un `?confirmar=` que decide si escriben:

| `confirmar` | Qué hace |
|---|---|
| `false` (por defecto) | Valida el archivo completo y devuelve el informe. **No escribe nada** |
| `true` | Importa, y solo si ninguna fila tiene problemas (RN-31) |

El informe es el mismo objeto en los dos casos —`{ confirmado, filasLeidas,
filasValidas, importadas, errores[] }`— y cada error trae el **número de fila
como lo muestra Excel** más el detalle en castellano. Que la simulación devuelva
exactamente la misma validación que la importación real es lo que permite a la
app mostrar el informe antes de dejar confirmar sin arriesgarse a que difieran.

Límites: 2.000 filas y 5 MB por archivo. Las celdas se leen como texto y los
números se interpretan en formato chileno (`5.980` son cinco mil novecientos
ochenta); un `.xls`, un `.csv` renombrado o un archivo con contraseña responden
400 con el motivo. **Solo se admite `.xlsx`**: el nombre debe terminar en `.xlsx` y el
contenido debe empezar con la firma de un ZIP (un `.xls` antiguo se rechaza aunque sea un
Excel válido). Se rechaza también una «bomba de compresión»: una parte del archivo que
se descomprima más de 50 veces o pase de 20 MB (`ZipSecureFile`).

### 9.5 Forma de las respuestas

Cada controlador devuelve un *record* propio con las relaciones aplanadas a su
id más la etiqueta mínima para leerlas. Devolver la entidad arrastraba el grafo
completo por los `@ManyToOne(EAGER)` — y con él, en su momento, el hash del PIN.
Hay dos records de trabajador a propósito: uno sin la credencial QR y otro solo
al emitirla o renovarla.

---

## 10. Aplicación móvil

Android, Flutter 3.47, un solo `MaterialApp` en tema claro. El enrutado por rol
está en `main.dart` (`_paraElRol`): **cada rol entra a su propia app**. No es
estética — el bodeguero trabaja sobre una obra y necesita elegirla antes de ver
nada, el administrador trabaja sobre la empresa entera y no tiene obra activa.
Un shell común tendría que negar la mitad de sí mismo en cada caso.

### 10.1 Estado por rol

| Rol | Shell | Estado |
|---|---|---|
| Bodeguero | `features/bodega/shell_bodega.dart` | ✅ Construido |
| Administrador | `features/admin/shell_admin.dart` | ✅ Construido |
| Jefe de terreno | — | ⬜ `PantallaRolPendiente` |
| Trabajador | — | ⬜ `PantallaRolPendiente` |

### 10.2 Flujo del bodeguero

Cuatro pestañas sobre una obra elegida al entrar y recordada por el teléfono:

1. **Inicio** — contadores del turno, la cola de solicitudes, los dos escaneos,
   capital en la obra, alertas sin resolver, últimos movimientos y acceso al
   cierre de turno.
2. **Bodega** — catálogo cruzado con el saldo de la obra, ordenado por
   criticidad; detalle del material con su kardex completo; registro de
   recepción, despacho y consumo.
3. **Herramientas** — lo que está fuera y el catálogo; la devolución pregunta en
   qué estado vuelve la herramienta.
4. **Alertas** — dispara la detección al abrirse y permite resolverlas.

Requisitos de interacción propios de este flujo:

- **RF-M1** La pantalla de movimiento muestra el saldo resultante **antes** de
  confirmar y advierte si cruza el mínimo de obra. El backend igual rechaza el
  negativo (RN-01); la advertencia es para decidir, no para validar.
- **RF-M2** El selector de personas muestra siempre nombre **y** RUT: en una
  obra hay dos Marcelos.
- **RF-M3** El capital en obra se presenta como dos cifras separadas —material
  en bodega (capital inmovilizado) y herramientas fuera (valor por recuperar)—
  porque sumarlas produce un número decorativo.
- **RF-M4** El cierre de turno no bloquea si quedan herramientas fuera: las
  registra como alerta, para que el turno siguiente sepa qué heredó.
- **RF-M8** El **QR identifica a la persona, no al material**. El bodeguero
  escanea la credencial del trabajador y la pantalla siguiente trae lo que esa
  persona pidió, listo para aprobar o rechazar (RN-28). Antes había que buscar
  el nombre en la lista de toda la obra, que con dos Marcelos y guantes puestos
  es exactamente donde se entrega el material a quien no era.
- **RF-M9** Aprobar material pregunta **cuánto se entrega** en vez de asumir lo
  pedido: entregar 30 de las 36 planchas es una decisión frecuente y el kardex
  tiene que reflejarla. Rechazar exige motivo, que es lo único que el trabajador
  ve en su teléfono.
- **RF-M10** El **escáner de código de barras** acepta el código de fábrica, el
  SKU o la etiqueta de una herramienta, y lleva directo a la ficha
  correspondiente. Con una herramienta, la acción depende del estado: en bodega
  lleva a prestarla; prestada, a recibirla.
- **RF-M11** Los dos escaneos tienen **ingreso manual** al lado. Una etiqueta
  rota, una credencial mojada o un permiso de cámara denegado no pueden dejar al
  bodeguero sin poder despachar; además hace la pantalla utilizable con lector
  de pantalla.

### 10.3 Flujo del administrador

Cuatro pestañas sobre la empresa: **Obras** (crear, cerrar, asignar jefe),
**Materiales** (catálogo por categoría, precio, merma y el código de barras que
se puede leer con la cámara al dar de alta), **Usuarios** (padrón, alta con RUT
y rol, restablecer PIN) y **Empresa** (datos, contadores, importación masiva y
acceso a la vista de bodega, porque la matriz de permisos se lo concede).

- **RF-M12** La **importación masiva** descarga la plantilla, sube la planilla
  llena, muestra el informe fila por fila y recién entonces deja confirmar. El
  catálogo de la constructora ya vive en Excel: cargarlo a mano en un teléfono
  son treinta y cuatro formularios y varios errores de dedo que después se
  propagan a cada presupuesto. El bodeguero tiene la misma pantalla acotada a
  herramientas, porque es quien las etiqueta cuando llegan.

### 10.4 Acceso

- **RF-M5** Correo + PIN para admin, jefe de terreno y bodeguero; PIN solo, con
  teclado propio de teclas grandes, para el usuario recordado. Nadie escribe un
  correo con guantes puestos, y el PIN no pasa por el teclado predictivo.
- **RF-M6** La sesión sobrevive al cierre de la app: el token vive en el
  almacenamiento cifrado del sistema.
- **RF-M7** «Salir» olvida la sesión pero recuerda al usuario; «Cambiar» olvida
  también al usuario.

### 10.5 Cobertura de la API

La capa de datos de la app implementa **43 de los 71 endpoints**. Sin consumir:
cuadrillas (3), partidas y cubicación (5), presupuestos (8), el alta de
solicitudes —que es del trabajador, cuyo flujo falta— y varias lecturas de
detalle.

### 10.6 Configuración

`mobile/.env` (no versionado) define `API_BASE_URL`. Si falta, la app arranca
igual con `http://10.0.2.2:8081` —el localhost del computador visto desde el
emulador— y lo informa en pantalla. La misma URL de la WiFi sirve para el
emulador y para un teléfono físico, así que no hay que recompilar al cambiar de
dispositivo.

---

## 11. Requisitos no funcionales

| ID | Requisito | Cómo se cumple hoy |
|---|---|---|
| RNF-01 | **Aislamiento multiempresa.** Ningún usuario alcanza datos de otra constructora, ni siquiera por enumeración de ids | Empresa desde el token; `PerteneceAEmpresa` en las 17 entidades; recurso ajeno = 404 idéntico. `AislamientoEntreEmpresasTest` falla si alguien agrega una entidad sin implementar la interfaz o un endpoint que reciba `empresaId` |
| RNF-02 | **Credenciales.** El PIN nunca se guarda ni se transmite en claro desde la base | BCrypt (factor 10); `pinHash` con `@JsonIgnore` y fuera de todo *record*. `PinHashNoSeSerializaTest` |
| RNF-03 | **Superficie de respuesta.** Ninguna respuesta expone más de lo necesario | *Records* por controlador. `RespuestasNoExponenEntidadesTest`, `PersonasEnLasRespuestasTest` |
| RNF-04 | **Sesión en terreno.** Reingresar credenciales al abrir la app es inaceptable con guantes y sin señal estable | Token de 8 h en almacenamiento cifrado; reingreso solo con PIN |
| RNF-05 | **Rendimiento percibido.** La bodega carga con una sola llamada, no con una por material | El kardex de la obra se trae completo y el saldo se reconstruye en el cliente igual que en el servidor |
| RNF-06 | **Trazabilidad.** Todo movimiento identifica a quién lo registró y, cuando corresponde, a quién recibió | `usuario_id` + `trabajador_id` en el kardex; `autorizado_por_id` en los préstamos; `resuelto_por_id` en las solicitudes |
| RNF-07 | **Accesibilidad.** Contraste ≥ 4.5:1 en texto y ≥ 3:1 en bordes de control; toques de 48 dp; soporte de escalado de texto del sistema | Paleta verificada por prueba (`accesibilidad_test.dart`); `docs/design-system/` |
| RNF-08 | **Formato local.** Cifras y fechas en formato chileno | `intl` con locale `es_CL`, inicializado en el arranque |
| RNF-09 | **Reproducibilidad del entorno.** Levantar el sistema completo no debe depender de la máquina | `docker compose up` (puertos 8081/5433 para no chocar con otros stacks); Flyway aplica el esquema y la semilla |
| RNF-10 | **Integración continua.** Ningún merge sin compilar y probar | GitHub Actions sobre `main` y `develop`: `./mvnw verify` con PostgreSQL real + `flutter analyze && flutter test` |
| RNF-11 | **Portabilidad del desarrollo.** Ubuntu y Windows | Maven Wrapper con finales de línea fijados; comandos de Flutter idénticos; script `scripts/run-emulador.sh` para el emulador |
| RNF-12 | **Disponibilidad sin señal** | ⬜ **No cumplido.** Ver [§12.2](#122-riesgos) |

---

## 12. Restricciones, supuestos y riesgos

### 12.1 Restricciones y supuestos

- **Una obra por sesión de bodega.** El bodeguero elige obra al entrar; todas
  las cifras que ve son de esa obra.
- **Un rol por usuario**, y ese rol vale para todas las obras de la empresa.
- **Un presupuesto por obra** y **una merma por material**.
- **La app es solo Android.** No hay build de iOS ni web.
- **Red de obra (LAN o WiFi del computador).** La API se sirve por HTTP sin TLS;
  el supuesto es que backend y teléfonos están en la misma red controlada.
- **Las alertas nacen cuando alguien mira.** No hay planificador; la pantalla de
  alertas dispara la detección al abrirse.
- **Sin paginación.** Los listados devuelven todo. Con 34 materiales y un turno
  de bodega es correcto; con un kardex de varios meses, no.

### 12.2 Riesgos

| # | Riesgo | Impacto | Mitigación pendiente |
|---|---|---|---|
| R1 | **Los coeficientes de cubicación son de referencia.** `RecetaCubicacion` los define porque el diagrama no modela recetas; no salen de tablas de rendimiento reales | Un presupuesto calculado con ellos no es defendible ante la constructora | Reemplazarlos por las tablas reales antes de que un presupuesto salga de estas cifras, y documentarlo en el informe |
| R2 | **Sin cola sin conexión.** `drift` es dependencia pero no hay nada implementado | En obra sin señal no se puede registrar nada | Épica aparte: guardar con hora real, reintentar, resolver conflictos y decidir qué **no** se permite offline (aprobar y congelar exigen confirmar estado en el servidor) |
| R3 | **La credencial QR es un código portador.** Quien la tenga —una foto de la pantalla ajena sirve— se presenta como ese trabajador (RN-27) | Un tercero podría hacer que le aprueben material a nombre de otro | Renovar la credencial es inmediato (`PUT /api/trabajadores/{id}/credencial`); a futuro, un código que rote por tiempo. Mitiga que aprobar exige un bodeguero autenticado y que el despacho queda a nombre del trabajador, no de quien escaneó |
| R4 | **Secretos por defecto.** PIN semilla `0000`, `JWT_SECRET` de ejemplo, PostgreSQL `postgres/postgres` | Cualquier despliegue fuera de local queda comprometido | **Mitigado (SEG1, SEG3, SEG6):** sin valor por defecto en el repo. `JWT_SECRET` y las contraseñas de la base vienen del `.env`; la migración V11 anula el PIN semilla y la clave del primer admin viene de `PRIMER_ADMIN_CLAVE`, con cambio obligatorio en el primer ingreso |
| R5 | **Cobertura de pruebas del backend.** Las pruebas cuidan la forma de las respuestas, el aislamiento y las reglas de importación y escaneo (RN-30…32), no las del kardex, el préstamo ni el presupuesto | Las reglas RN-01…RN-21 de la §7 pueden romperse en silencio | Pruebas con Testcontainers sobre PostgreSQL real |
| R6 | **Sin paginación ni endpoints de resumen.** Los contadores de inicio exigen varias llamadas | Degrada con obras largas | `GET /api/obras/{id}/resumen` y paginación en los listados |
| R7 | **La importación masiva confía en el archivo.** Se valida formato, rangos y duplicados, no que los precios sean los correctos | Un catálogo cargado con precios equivocados se propaga a cada presupuesto | El informe previo obliga a mirar antes de confirmar; queda revisar el catálogo tras importar |

---

## 13. Estado de cumplimiento

Cifras verificadas contra el código de la rama de referencia.

| Área | Medida | Valor |
|---|---|---|
| Backend — endpoints | Anotaciones de mapeo en 16 controladores | **71** |
| Backend — entidades | Clases `@Entity` | **17** |
| Backend — servicios | Clases `*Service` | **18** |
| Backend — migraciones | Flyway `V1`–`V5` | **5** |
| Backend — pruebas | `contextLoads` + 4 de arquitectura y seguridad + 3 de importación y escaneo | **8 clases · 51 casos** |
| App — endpoints consumidos | En `dominio_api.dart` + `auth_api.dart` | **43 / 71** |
| App — flujos por rol | Bodeguero y administrador construidos | **2 / 4** |
| App — pantallas | `pantalla_*.dart` + shells | **21** |
| App — pruebas | Unitarias y de widget | **6 archivos · 46 casos** |
| CI | GitHub Actions sobre `main` y `develop` | ✅ |

**Requisitos funcionales:** los **56** requisitos de la §6 están soportados por
el backend —RF-A3 es del lado de la app y RF-A8 se resuelve por migración— y
**41** de ellos están además disponibles en la app. Lo que falta ahí es, en
bloque, el flujo del jefe de terreno (cubicación, presupuesto y desviación) y el
del trabajador (solicitudes y credencial).

---

## 14. Trazabilidad

De requisito a código, en un solo salto.

| Grupo | Backend | App |
|---|---|---|
| RF-A · Acceso y configuración | `config/AuthController`, `UsuarioController`, `EmpresaController` | `features/auth/`, `features/admin/pantalla_usuarios.dart` |
| RF-B · Obra y equipos | `obra/ObraController`, `CuadrillaController`, `TrabajadorController` | `features/admin/pantalla_obras.dart`, `features/obra/` |
| RF-C · Cubicación | `cubicacion/PartidaController`, `MotorCubicacionService`, `MaterialController` | `features/admin/pantalla_materiales.dart` (catálogo); cubicación ⬜ |
| RF-D · Presupuesto | `presupuesto/PresupuestoController`, `ComparadorPresupuestoService` | ⬜ |
| RF-E · Inventario | `inventario/*` | `features/bodega/` |
| Escaneo de credencial y de código | `obra/TrabajadorController`, `cubicacion/MaterialController`, `inventario/HerramientaController` | `features/bodega/escaner.dart`, `pantalla_escaneo.dart`, `pantalla_solicitudes.dart`, `solicitudes_acciones.dart` |
| Importación masiva (RF-C9, RF-E17) | `importacion/*`, `cubicacion/FilaMaterial`, `inventario/FilaHerramienta` | `features/admin/pantalla_importacion.dart` |
| RF-F · Control | `control/AlertaController`, `AlertaService` | `features/bodega/pantalla_alertas.dart` |
| RN-01…04 · Kardex | `inventario/KardexMovimientoService`, `KardexMovimiento` | `pantalla_movimiento.dart`, `bodega_providers.dart` |
| RN-22…23 · Aislamiento | `config/AccesoEmpresa`, `SesionActual`, `PerteneceAEmpresa` | — (sale del token) |
| RNF-07 · Accesibilidad | — | `core/theme/`, `test/accesibilidad_test.dart` |

---

## 15. Criterios de aceptación del MVP 1

El MVP 1 está completo cuando, sobre una instalación limpia:

- [x] `docker compose up` deja la API respondiendo con el esquema migrado y el admin semilla.
- [x] Un ADMIN crea usuarios de los cuatro roles, materiales con merma y una obra con jefe de terreno.
- [x] Un BODEGUERO elige obra, registra recepción, despacho y consumo, y el saldo cuadra con el kardex.
- [x] Un despacho queda con el nombre y el RUT de quien recibió.
- [x] Una herramienta se presta, se devuelve dañada y queda en `MANTENCION`.
- [x] Una alerta de stock crítico aparece al cruzar el mínimo y se resuelve.
- [x] Un usuario de otra constructora recibe 404 al pedir cualquier recurso ajeno.
- [ ] Un JEFE_TERRENO crea una partida, la cubica, arma el presupuesto y lo congela.
- [ ] La desviación se muestra en la app con lo ejecutado hasta el momento.
- [x] Un ADMIN carga el catálogo completo desde una planilla Excel, con el informe de validación antes de confirmar.
- [x] Un bodeguero escanea el código de barras de un envase y llega a registrar el movimiento de ese material.
- [x] Un trabajador muestra su credencial QR, el bodeguero la escanea y resuelve sus solicitudes desde ahí.
- [ ] Un TRABAJADOR solicita material desde su teléfono (falta la pantalla del trabajador; el bodeguero ya lo aprueba desde el suyo).
- [ ] Las reglas de la §7 están cubiertas por pruebas automatizadas.

Lo marcado corresponde al estado de la rama de referencia al 2026-09-02.
