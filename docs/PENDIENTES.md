# Check-In-Obra — Estado y trabajo pendiente

**Fecha:** 2026-08-27 · **Rama:** `main` · **Repo:** [1Bryvn/Check-In-Obra](https://github.com/1Bryvn/Check-In-Obra)

Informe del estado real del proyecto y lo que falta para cerrar el MVP 1.
Las cifras salen de auditar el código, no de estimaciones.

---

## 1. Resumen en números

| Área | Hecho | Total | Avance |
|---|---:|---:|---:|
| **Backend** — endpoints REST | 66 | 66 | ✅ 100 % |
| **Backend** — entidades del diagrama | 17 | 17 | ✅ 100 % |
| **App móvil** — pantallas diseñadas | 2 | 34 | 🟠 6 % |
| **App móvil** — endpoints consumidos | 2 | 66 | 🔴 3 % |
| **Pruebas** — backend | 1 | — | 🔴 solo `contextLoads` |
| **Pruebas** — móvil | 7 | — | 🟠 unitarias, sin integración |
| **CI/CD** | 0 | — | 🔴 sin configurar |

**Lectura corta:** el backend está completo y probado a mano; la app móvil
tiene la autenticación lista y le faltan 32 de 34 pantallas.

---

## 2. Lo que ya está funcionando

Verificado de punta a punta contra el backend real, no asumido:

- **Infraestructura** — `docker compose up` levanta backend + PostgreSQL con
  puertos que no chocan con otros proyectos (8081/5433). Flyway aplica el
  esquema completo y el usuario semilla.
- **Backend** — 17 entidades, 17 repositorios, 17 servicios, 16 controladores,
  66 endpoints, autorización por rol con `@PreAuthorize`, JWT, Swagger.
- **App móvil** — acceso por correo+PIN y por PIN, sesión persistente en el
  Keystore, cliente HTTP con Bearer automático, tema del design system.
- **Entorno de desarrollo** — celular físico y emulador Pixel 5 (API 33),
  ambos probados con login real.

---

## 3. App móvil — 32 pantallas pendientes

Los diseños están listos en `docs/mockups/design-movil/`. Falta implementarlos.

### 3.1 Compartidas — 4 pendientes

| Pantalla | Estado | Qué implica |
|---|---|---|
| `Acceso` | ✅ Hecha | — |
| `AccesoPin` | ✅ Hecha | — |
| `SelectorObra` | ⬜ Pendiente | Elegir obra activa; obras `CERRADA` en solo lectura |
| `SinPermiso` | ⬜ Pendiente | Acción bloqueada por rol, con quién sí puede |
| `Alertas` | ⬜ Pendiente | Bandeja filtrada por rol · `GET /api/alertas` |
| `SinConexion` | ⬜ Pendiente | **Cola offline — ver §6.1, es la más compleja** |

### 3.2 Trabajador — 6 pendientes

| Pantalla | Endpoint que consume |
|---|---|
| `TrabInicio` | `/api/trabajadores/{id}`, `/api/prestamos-herramienta` |
| `TrabCredencial` | `/api/trabajadores/{id}` · **requiere generar el QR** |
| `TrabSolicitarHerr` | `POST /api/solicitudes-herramienta` |
| `TrabSolicitarMat` | `POST /api/solicitudes-material` |
| `TrabSolicitudes` | `GET /api/solicitudes-*?trabajadorId=` |
| `TrabPrestamos` | `GET /api/prestamos-herramienta?trabajadorId=` |

### 3.3 Bodeguero — 10 pendientes

| Pantalla | Endpoint que consume |
|---|---|
| `BodInicio` | Varios · contadores del turno |
| `BodEscaneo` | **Cámara — `mobile_scanner`, aún sin usar** |
| `BodSolicitudes` | `GET /api/solicitudes-*?obraId=&soloPendientes=true` |
| `BodAprobar` | `PUT /api/solicitudes-herramienta/{id}/aprobar` |
| `BodRechazo` | `PUT /api/solicitudes-*/{id}/rechazar` |
| `BodRecepcion` | `POST /api/kardex` (RECEPCION) |
| `BodDespacho` | `POST /api/kardex` (DESPACHO) + bloqueo de stock |
| `BodStock` | `GET /api/kardex/stock` |
| `BodDevolucion` | `PUT /api/prestamos-herramienta/{id}/devolucion` |
| `BodCierreTurno` | `POST /api/alertas/cierre-turno` |

### 3.4 Jefe de terreno — 6 pendientes

| Pantalla | Endpoint que consume |
|---|---|
| `JefeInicio` | `/api/obras`, `/api/presupuestos/{id}/desviacion` |
| `JefePartidas` | `GET /api/partidas?obraId=` |
| `JefeCubicacion` | `POST /api/partidas/{id}/cubicar` |
| `JefePresupuesto` | `/api/presupuestos` + `congelar` |
| `JefeDesviacion` | `GET /api/presupuestos/{id}/desviacion` · **gráficos, `fl_chart` sin usar** |
| `JefeCuadrillas` | `GET /api/cuadrillas?obraId=` |

### 3.5 Administrador — 6 pendientes

| Pantalla | Endpoint que consume |
|---|---|
| `AdmInicio` | `GET /api/empresas/{id}` |
| `AdmUsuarios` | `GET /api/usuarios?empresaId=` |
| `AdmUsuarioNuevo` | `POST /api/usuarios` |
| `AdmMateriales` | `/api/materiales` |
| `AdmMerma` | `PUT /api/materiales/{id}/merma` |
| `AdmObras` | `/api/obras` + `cerrar` |

---

## 4. Backend — pendientes

El backend está **funcionalmente completo**, pero le falta respaldo automatizado.

### 4.1 Pruebas — prioridad alta

Hoy existe **un solo test**: `contextLoads()`, que además necesita PostgreSQL
levantado para pasar. Hay **18 validaciones de negocio sin ninguna prueba**.

Las que más duelen si se rompen en silencio:

| Regla | Dónde vive |
|---|---|
| El kardex no admite stock negativo | `KardexMovimientoService` |
| Una obra no cierra con herramientas fuera o alertas abiertas | `ObraService.cerrarObra` |
| Un presupuesto solo se congela desde `APROBADO` | `Presupuesto.congelar` |
| Una solicitud resuelta no se puede volver a resolver | `Solicitud*.aprobar/rechazar` |
| Una herramienta prestada no se puede volver a prestar | `PrestamoHerramientaService` |
| El PIN debe tener exactamente 4 dígitos | `Usuario.definirPin` |

> **Recomendación:** usar Testcontainers para levantar PostgreSQL en las
> pruebas. Así los tests corren contra la base real, incluidas las
> restricciones del esquema, sin depender de que alguien tenga Docker
> levantado a mano.

### 4.2 Endpoints que faltarían

- `GET /api/usuarios/{id}/trabajador` — hoy, para saber el `trabajadorId` de
  un usuario, la app tendría que recorrer la lista completa de trabajadores.
- Paginación en los listados. Con 34 materiales da igual, pero un kardex de
  varios meses devuelto entero es un problema.
- `GET /api/obras/{id}/resumen` — los contadores que muestran `BodInicio` y
  `JefeInicio` obligarían hoy a 4-5 llamadas separadas.

---

## 5. Infraestructura y calidad

| Pendiente | Estado | Nota |
|---|---|---|
| **CI/CD** | 🔴 Sin configurar | `.github/workflows/` está vacío |
| **`scripts/`** | 🔴 Vacío | Reservado para utilidades en Python |
| **Fuentes del design system** | 🟠 Pendiente | Fira Sans / Fira Code sin empaquetar; hoy se usa la del sistema |
| **Ícono de la app** | 🟠 Pendiente | Sigue el de Flutter por defecto |
| **Nombre visible** | 🟠 Pendiente | Aparece como `checkinobra_mobile` |

**CI mínimo sugerido** (un solo workflow):
```
backend: ./mvnw verify
mobile:  flutter analyze && flutter test
```

---

## 6. Riesgos y decisiones abiertas

### 6.1 La cola sin conexión es más difícil de lo que parece

`SinConexion` está diseñada y `drift` ya es dependencia, pero **no hay nada
implementado**. No es una pantalla más: implica

- guardar los movimientos localmente con su hora real,
- reintentar al recuperar señal,
- resolver conflictos (dos bodegueros despachando el mismo material sin red),
- y decidir qué operaciones **no** se permiten offline —
  aprobar una solicitud y congelar un presupuesto necesitan confirmar estado
  en el servidor.

> Conviene tratarla como una épica aparte, no como una pantalla del sprint.

### 6.2 Los coeficientes de cubicación son de referencia, no reales

`RecetaCubicacion.java` define cuánto material lleva cada m² por tipo de
partida. **Los valores actuales son orientativos**, puestos para que el motor
funcione. El diagrama de clases no modela una tabla de recetas, así que hubo
que inventarla.

**Acción requerida:** reemplazarlos por las tablas de rendimiento reales de la
constructora antes de que un presupuesto salga de estas cifras.

### 6.3 Seguridad — antes de cualquier despliegue

| Punto | Estado |
|---|---|
| Admin semilla con PIN `0000` | 🟢 La `V11` anula ese PIN; la clave inicial viene de `PRIMER_ADMIN_CLAVE` y la cuenta debe cambiarla en el primer ingreso (SEG3). `V2` salió de `db/migration` (MT1). Falta la pantalla en la app |
| `JWT_SECRET` con valor por defecto | 🟢 Sin valor por defecto: la API no arranca sin uno propio de 32 bytes o más (SEG1). Rotarlo en las instancias que ya corrieron con el antiguo |
| Contraseñas de PostgreSQL `postgres/postgres` | 🟢 Sin valor por defecto: vienen del `.env`; la API usa `checkinobra_app` (solo DML) y Flyway `checkinobra_migrador`; el puerto va solo en `127.0.0.1` (SEG6, MT0) |
| API por HTTP sin TLS | 🟠 Aceptable en LAN de obra; no fuera de ella |
| Sin expiración de refresh ni renovación | 🟠 El token dura 8 h y luego obliga a reingresar |

### 6.4 Dependencias declaradas pero sin usar

`mobile_scanner`, `drift`, `fl_chart` e `intl` están en `pubspec.yaml` pero no
se importan en ningún archivo. No es un error —se declararon al armar el
stack— pero marcan funcionalidad que aún no existe: escaneo QR, base local,
gráficos y formato es-CL.

---

## 7. Orden de trabajo propuesto

### Etapa 1 — Rebanada vertical: el flujo de solicitudes
> *Cruza dos roles y termina moviendo el kardex. Deja armados los patrones de
> lista, formulario y estados que después reutiliza todo lo demás.*

1. `SelectorObra` — hace falta para casi todo lo que sigue
2. `TrabInicio` + `TrabSolicitarHerr` + `TrabSolicitarMat` + `TrabSolicitudes`
3. `BodInicio` + `BodSolicitudes` + `BodAprobar` + `BodRechazo`
4. Endpoint `GET /api/usuarios/{id}/trabajador`

### Etapa 2 — Bodega completa
5. `BodEscaneo` (integrar `mobile_scanner`) + `BodStock`
6. `BodRecepcion` + `BodDespacho` + `BodDevolucion`
7. `TrabCredencial` (generar el QR) + `TrabPrestamos`
8. `Alertas` + `BodCierreTurno`

### Etapa 3 — Terreno y administración
9. `JefeInicio` + `JefePartidas` + `JefeCubicacion`
10. `JefePresupuesto` + `JefeDesviacion` (integrar `fl_chart`) + `JefeCuadrillas`
11. Las 6 pantallas de `Adm*`
12. `SinPermiso`

### Etapa 4 — Robustez
13. Pruebas del backend con Testcontainers (§4.1)
14. CI en GitHub Actions
15. Cola sin conexión (§6.1)
16. Fuentes, ícono y nombre de la app

---

## 8. Para la entrega académica

Además del código:

- [ ] Completar los nombres del equipo en el `README.md`
- [ ] Manual de usuario por rol — los mockups de `docs/mockups/` sirven de base
- [ ] Documentar la decisión de las recetas de cubicación (§6.2) en el informe
- [ ] Evidencia de pruebas — hoy solo existe la verificación manual de esta bitácora
- [ ] Diagrama de despliegue — el de clases ya está en `docs/diagrams/`
