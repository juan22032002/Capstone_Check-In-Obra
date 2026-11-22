# Datos de prueba: tabiquería y cielos

Diez ítems con código de barras (6 materiales y 4 herramientas). Sirven para
probar el escaneo con el teléfono.

| Archivo | Qué es |
|---|---|
| `materiales-tabiqueria-y-cielos.xlsx` | 6 materiales. Se importa con `POST /api/materiales/importar` (rol ADMIN). |
| `herramientas-tabiqueria-y-cielos.xlsx` | 4 herramientas. Se importa con `POST /api/herramientas/importar` (rol ADMIN). |
| `codigos-de-barra-imprimibles.html` | Una etiqueta por ítem, con su nombre y el código dibujado. Ábrela en el navegador e imprímela, o escanéala directo desde la pantalla. |
| `demo-escaneo.html` | Para mostrar el escaneo en vivo: un código grande a la vez (flechas ← →), con el guion de la demo y lo que pasa al escanear cada ítem. También trae la grilla para imprimir. Funciona sin conexión. |

Hay dos planillas porque materiales y herramientas se importan por separado.
Cada una tiene las columnas en el orden que espera `LectorPlanilla`, que lee
por posición, así que se suben tal cual. Las dos se probaron por la API:
6/6 y 4/4 filas válidas.

## Los códigos

Todos son EAN-13 con el dígito verificador correcto. Empiezan en `200`, el
rango GS1 de uso interno, para que no choquen con productos reales. En las
herramientas, el EAN-13 va en la columna `CODIGO`, que es el código de la
etiqueta que se escanea.

| Código | Ítem | Tipo |
|---|---|---|
| 2001000000012 | Volcanita ST 10 mm 1,20 x 2,40 m | Material · VOLCANITA |
| 2001000000029 | Volcanita RH 12,5 mm 1,20 x 2,40 m | Material · VOLCANITA |
| 2001000000036 | Montante Metalcom 60 x 38 x 0,5 mm 3 m | Material · METALCOM |
| 2001000000043 | Canal Metalcom 61 x 20 x 0,5 mm 3 m | Material · METALCOM |
| 2001000000050 | Perfil omega cielo 35 x 15 mm 3 m | Material · METALCOM |
| 2001000000067 | Tornillo volcanita punta fina 6 x 1" (caja 100) | Material · FIJACION |
| 2002000000019 | Taladro percutor 800 W | Herramienta · Eléctrica |
| 2002000000026 | Atornillador inalámbrico para volcanita 18 V | Herramienta · Eléctrica |
| 2002000000033 | Huincha de medir 8 m | Herramienta · Medición |
| 2002000000040 | Nivel láser autonivelante | Herramienta · Medición |

## Qué pasa al escanearlos

- **Material:** el bodeguero lo escanea en *Escanear código* y se abre la
  pantalla de movimiento sobre su obra activa. Una recepción ahí queda en el
  kardex de esa obra; el stock es la suma de esos movimientos.
- **Herramienta:** es de la empresa, no de una obra. Al escanearla se abre su
  ficha. Solo queda ligada a una obra mientras está prestada, a través del
  préstamo.

Los SKU y los códigos son únicos, así que cada planilla se importa una sola
vez por base de datos. La segunda vez la simulación avisa que ya existen.
