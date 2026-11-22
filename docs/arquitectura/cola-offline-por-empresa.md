# La cola sin conexión y las empresas — requisitos para R2

**Estado:** diseño. No hay código: la cola sin conexión (riesgo **R2** de
`docs/ESPECIFICACION.md` §12.2) todavía no existe. Este documento fija lo que
tiene que cumplir **cuando se construya**, para que nazca aislada por empresa
y no haya que corregirla después.

**Origen:** issue #113 (MT10). Sus cuatro criterios de aceptación presuponen
una cola; sin ella no hay nada que implementar ni que probar. Se decidió no
construir la cola dentro de MT10 y dejar estos criterios como **requisitos
obligatorios de la épica R2**: la épica no se da por terminada si alguno falta.

## Por qué importa

Con una base por empresa (`docs/arquitectura/multitenant.html`) los ids se
repiten entre empresas: la obra 3 o el material 12 existen en cada una. Un
movimiento de kardex guardado en el teléfono dice `obraId: 3, materialId: 12`
y **no dice de qué empresa es**. Si el teléfono lo envía con la sesión de
otra empresa, el servidor no tiene cómo notar el error: el movimiento caería
sobre la obra 3 de la empresa equivocada, y es un movimiento de stock
—difícil de detectar y de deshacer—.

Pasa en el uso real: un teléfono compartido entre turnos, una persona con
cuentas en dos constructoras, o un bodeguero que cierra sesión sin señal (con
movimientos en cola) y le pasa el teléfono a otro.

Lo que ya está resuelto, y por tanto no es parte de R2 (PR #126, MT9): el
usuario recordado guarda su empresa, y la obra activa y la copia de la
credencial se guardan por empresa y usuario.

## Requisitos

### R2-E1 · Un archivo de base local por empresa

La base local (drift) se llama `checkinobra_<empresaId>.sqlite`. Una empresa,
un archivo: dos empresas nunca comparten tabla.

**No se acepta** la alternativa "borrar la base al cerrar sesión": la cola
existe justamente para movimientos que **todavía no llegaron al servidor**, y
borrarla al salir los pierde en silencio. Un movimiento de stock perdido es
peor que uno que tarda en enviarse.

### R2-E2 · Cada movimiento en cola guarda con qué se creó

Cada fila lleva, como mínimo:

- `empresaId` y `usuarioId` de la sesión con la que se creó,
- la hora real del movimiento (no la del envío),
- la `Idempotency-Key` generada **al crear la fila** y no al enviar, para que
  reintentar —aunque sea mil veces o tras reiniciar la app— no duplique el
  movimiento (ver `core/network/idempotencia.dart`).

El `empresaId` se escribe aunque el archivo ya sea de esa empresa: es una
segunda defensa, y barata, si alguna vez se copia, restaura o mueve un archivo.

### R2-E3 · No se envía con la sesión de otra empresa

Antes de enviar **cada** fila, se compara `fila.empresaId` con
`sesion.empresaId`. Si difieren, la fila no se envía ni se modifica. Se
comprueba por fila y no solo por archivo, por lo mismo que en R2-E2.

El envío usa siempre el token de la sesión actual; nunca se guarda un token
con la cola.

### R2-E4 · La cola de otra empresa se conserva, no se envía y no se pierde

Caso que la épica tiene que resolver explícitamente: la persona A (empresa 1)
cierra sesión con movimientos pendientes y entra la persona B (empresa 2).

- La cola de la empresa 1 **sigue en su archivo**, intacta.
- B **no la ve, no la envía y no puede alterarla**: B solo abre el archivo de
  la empresa 2.
- Cuando alguien de la empresa 1 vuelve a entrar en ese teléfono, la cola se
  envía con su sesión (R2-E3 lo permite porque la empresa coincide).
- "No soy…" (olvidar al usuario) **no borra la cola**. Si hay movimientos
  pendientes, avisa cuántos son y de qué empresa antes de seguir, y borrarlos
  exige una confirmación explícita aparte.

Decisión abierta para la épica: cuánto tiempo se conserva una cola de una
empresa que no vuelve a entrar. Hasta decidirlo, no se borra por tiempo.

### R2-E5 · Base local cifrada (SQLCipher)

Se cifra al introducirla, no después: migrar una base ya poblada a SQLCipher
es más caro y arriesgado que empezar cifrada. La clave es aleatoria, una por
archivo, y vive en `flutter_secure_storage` (Keystore), nunca en el código ni
junto al archivo. Perderla equivale a perder esa cola, así que la clave se
borra solo cuando se borra el archivo, por confirmación explícita (R2-E4).

## Pruebas que debe traer la épica

| # | Verifica | Requisito |
|---|---|---|
| 1 | Dos empresas con la misma `obraId` tienen colas en archivos distintos | R2-E1 |
| 2 | Cerrar sesión **no** borra los movimientos pendientes | R2-E1 |
| 3 | Cada fila guarda `empresaId`, `usuarioId`, hora real y clave de idempotencia | R2-E2 |
| 4 | Reintentar una fila tras reiniciar la app reutiliza su clave | R2-E2 |
| 5 | Con la sesión de la empresa 2, una fila de la empresa 1 **no se envía** (ni se toca), aunque esté en el archivo abierto | R2-E3 |
| 6 | La cola de la empresa 1 queda intacta tras entrar y salir la empresa 2, y se envía cuando vuelve la empresa 1 | R2-E4 |
| 7 | "No soy…" con movimientos pendientes avisa cuántos y de qué empresa, y no los borra sin confirmar | R2-E4 |
| 8 | El archivo no se puede leer como SQLite común sin la clave | R2-E5 |

Mientras exista una sola empresa, el comportamiento tiene que ser el de
siempre: la cola de esa empresa se envía como cualquier otra.

## Fuera de alcance de este documento

El diseño de la cola misma —guardar con hora real, reintentos, resolución de
conflictos y qué **no** se permite sin conexión (aprobar y congelar exigen
confirmar el estado en el servidor)— es la épica R2 y se decide ahí.

## Trazabilidad

- Issue #113 (MT10): este documento es su entrega; queda bloqueado por R2.
- Issue #112 (MT9) y PR #126: la parte de MT10 que ya se puede hacer sin cola.
- `docs/ESPECIFICACION.md` §12.2, riesgo R2.
- `docs/arquitectura/multitenant.html`: una base por empresa.
