# Check-In-Obra — Design System
Generado con `ui-ux-pro-max-skill` (nextlevelbuilder/ui-ux-pro-max-skill) — curado a mano entre dominios.

> **Nota de método:** el generador automático de la skill (`--design-system`) coincidió con la categoría
> "Inventory & Stock Management" para el color y con un patrón de landing page tipo SaaS que no aplica a
> una app móvil de campo. Además, según la consulta exacta, la tipografía saltó entre pares muy distintos
> (uno incluso de mood "académico/biblioteca", claramente un falso positivo). Por eso este documento combina
> resultados de consultas específicas por dominio (`--domain color`, `--domain typography`, `--domain icons`,
> `--domain ux`) en vez de aceptar un único run automático completo.

---

## Categoría de producto (confirmada)
**Inventory & Stock Management** — keywords: inventory, stock, warehouse, barcode, sku, management.
Coincide con el proyecto real: escaneo de código, niveles de stock, alertas de bajo stock/vencidos.

## Paleta de color
Se combinan dos entradas del catálogo: la de la categoría de producto (funcional) y la de
**Construction/Architecture** (más específica al rubro), para status colors semáforo.

| Rol | Hex | Uso |
|---|---|---|
| Primary | `#334155` | Texto principal, navegación, headers de tabla |
| Secondary | `#64748B` | Texto secundario, íconos inactivos |
| Accent / CTA | `#EA580C` | Acción primaria — *safety orange*, específico de "Construction/Architecture" en el catálogo, más coherente con el rubro que el verde genérico de "Inventory" |
| Background | `#F8FAFC` | Fondo de pantalla |
| Card | `#FFFFFF` | Superficies |
| Border | `#E2E8F0` | Bordes, separadores |
| Success (stock ok / a tiempo) | `#059669` | Semáforo — verde |
| Warning (stock bajo / por vencer) | `#D97706` | Semáforo — ámbar |
| Destructive (vencido / stock crítico) | `#DC2626` | Semáforo — rojo |

*Esta paleta es prácticamente la misma que usamos a mano en el mockup anterior (naranja seguridad + acero + semáforo). La skill la valida en vez de contradecirla — buena señal de que la elección original no era arbitraria.*

## Tipografía
**Inter** (400, 500, 600, 700), empaquetada en `mobile/assets/fonts` con su licencia OFL.
Reemplaza al par Fira Sans + Fira Code que el documento proponía y que nunca se llegó
a empaquetar.

- **Tracking negativo en todos los tamaños** (-0,1 a -0,6 px): es lo que le da a la
  app aspecto de instrumento y no de formulario.
- **Sin monoespaciada.** Los datos que la usaban (cantidades, saldos, montos) van en
  Inter con cifras tabulares (`AppTexto.tabulares`), que conservan el alineado. Las
  cifras tabulares no se aplican a toda la app: en Inter también ensanchan el guion,
  y un SKU como `MET-MONT-90` quedaba con los guiones separados.
- `cv05` (ele con cola) en toda la app, para no confundir l con 1 en un código.
- **Rótulos en tipo oración**, no en mayúsculas espaciadas.
- Escala en `AppTexto` (`lib/core/theme/app_theme.dart`): cifra 28, título 20,
  subtítulo 16, cuerpo 15, cuerpo chico 13, rótulo 13/500, dato 12,5/500. Nada
  baja de 12 px.

## Estilo
Referencia: *white concrete, single ember* (estilo Brex/Linear), llevado a los colores
del sistema. Se conservan pizarra `#334155`, el naranjo y el semáforo.

- **Un solo acento.** `accentFill` (`#C2410C`) marca la acción principal de cada
  pantalla y la pestaña activa. Nada más va en naranjo: íconos y flechas van en tinta
  o gris, y la opción elegida de un selector se rellena en pizarra.
- **Sin sombras sobre el lienzo.** Las tarjetas se separan por el borde fino
  (`border`). Solo lo que flota —hojas, diálogos, snackbar— lleva una sombra suave.
- **Marco oscuro solo en dos lugares:** el encabezado del acceso (y del PIN) y el panel
  del turno en Inicio. En cualquier otro lugar dejaría de funcionar como marco.
- La barra superior es blanca con una línea fina abajo, y la barra de pestañas es
  blanca con una línea fina arriba.

## Forma y espacio
`lib/core/theme/app_forma.dart`.

| Token | Valor | Para qué |
|---|---|---|
| `AppForma.borde` | 12 px | Botón, campo, tarjeta, hoja, tecla, visor del escáner |
| `AppForma.bordeChip` | 6 px | Chips de estado |
| `AppEspacio` | 4 / 8 / 16 / 24 / 32 | Rótulo↔dato / dentro de un grupo / relleno de tarjeta / entre grupos / entre secciones |

Dos radios y ninguno intermedio. La franja de criticidad de una fila es un elemento
interno que la tarjeta recorta con su esquina, no un borde: Flutter no dibuja un
`Border` con un lado distinto cuando hay radio.

## Superficies
| Token | Hex | Uso |
|---|---|---|
| `background` | `#F8FAFC` | Lienzo. Se evaluó slate-100, pero ahí `secondary` baja a 4.34:1 |
| `card` | `#FFFFFF` | Tarjetas, barra superior, pestañas, hojas |
| `sunken` | `#F1F5F9` | Cuadro de ícono, iniciales, chip neutro |
| `accentTint` | `#FFF7ED` | Indicador de pestaña activa (`accentFill` encima: 4.88:1) |
| `surfaceDark` | `#1E293B` | Marco oscuro |
| `accentOnDark`, `destructiveOnDark`, `warningOnDark` | `#FB923C`, `#F87171`, `#FBBF24` | Acento y semáforo sobre el marco oscuro (sobre 4.5:1) |

## Componentes compartidos
`Panel`, `PanelTocable`, `FilaAccion` (tarjeta que lleva a otra pantalla), `Opcion`
(opción de un grupo excluyente), `BotonEnvio` (confirma una escritura), `ChipEstado`,
`Etiqueta` (título de sección), `CampoTexto`/`CampoConEtiqueta`, `Contador`, `Vacio`,
`MensajeError`, `BarraDePestanas`. Antes había cuatro copias del selector segmentado.

## Movimiento
`lib/core/theme/movimiento.dart`: presión 110 ms (escala 0,97), cambio de estado
180 ms, curva de salida fuerte `cubic-bezier(0.23, 1, 0.32, 1)`. Todo pasa a
`Duration.zero` si Android tiene activado "Quitar animaciones".

## Iconografía
Librería recomendada por la skill: **Phosphor Icons**, estilo *outline*.
`import { Camera, QrCode, Package, Bell } from '@phosphor-icons/react'`

## Reglas UX aplicables (dominio `ux`, con impacto directo en las pantallas ya diseñadas)
1. **Badges/chips no deben quebrar línea.** Los chips de estado ("A TIEMPO", "VENCIDA") deben mantenerse en una sola línea con ancho flexible — ya cumplido en el mockup, mantenerlo al implementar.
2. **Actualizaciones de estado en vivo deben anunciarse de forma atómica** (`role="status" aria-atomic="true"`), no como número suelto — relevante para cuando una herramienta pasa de "a tiempo" a "vencida" en la pantalla de Alertas en tiempo real.
3. **Contraste mínimo 4.5:1** en modo claro, foco visible para navegación por teclado (aplica al panel web de Jefe de Terreno/Admin, no solo a la app móvil).

## Checklist pre-entrega (de la skill)
- [ ] Sin emojis como íconos — usar SVG (Phosphor)
- [ ] `cursor: pointer` en todo elemento clickeable (versión web)
- [ ] Transiciones 150–300ms, `prefers-reduced-motion` respetado
- [ ] Responsive: 375px / 768px / 1024px / 1440px
- [ ] Contraste de texto 4.5:1 mínimo en modo claro

---

## Estado en la app Flutter

Revisión con `ui-ux-pro-max` (prioridades 1 y 2: accesibilidad e interacción)
sobre las pantallas de acceso, PIN e inicio.

### Contraste medido

Se midió cada par de colores en uso, no se estimó a ojo. Cuatro no pasaban:

| Uso | Antes | Ahora | Umbral |
|---|---|---|---|
| Texto secundario sobre el encabezado azul | 4.04:1 | 6.97:1 (`textOnDark`) | 4.5:1 |
| Rótulo del separador sobre blanco | 2.56:1 | 4.76:1 (`secondary`) | 4.5:1 |
| Borde de campo de texto y de tecla | 1.18:1 | 3.27:1 (`borderControl`) | 3:1 |
| Punto vacío del PIN | 1.48:1 | 3.42:1 (`borderControl`) | 3:1 |

`test/accesibilidad_test.dart` recalcula estos umbrales sobre los tokens, para
que un cambio de paleta no los rompa en silencio.

### Distinción entre `border` y `borderControl`

El design system tenía un solo token de borde. Son dos cosas: el separador
decorativo entre superficies (`border`, 1.2:1, y con eso basta) y el contorno
que identifica un control (`borderControl`, 3:1, exigido por WCAG 1.4.11). Un
campo de texto dibujado con el primero se lee como un bloque de texto, no como
algo donde escribir.

### Interacción

- El teclado del PIN y el panel de acceso rápido no daban ninguna respuesta al
  tacto: el fondo opaco tapaba el splash del `InkWell`. Corregido con
  `Material` → `InkWell` → contenido transparente (`PanelTocable`).
- El botón "Entrar" conserva su rótulo mientras carga, en vez de quedar solo
  con un spinner.

### Lectores de pantalla

- Errores y cambios de estado se anuncian con `liveRegion`.
- Los controles de solo ícono (ojo del PIN, volver, borrar) tienen nombre.
- Los íconos decorativos que acompañan a un texto salen del árbol accesible.
- Los puntos del PIN se anuncian como "N de 4 dígitos ingresados".

### Escalado de texto

Chips, iniciales y teclado tienen caja de proporción fija, así que topan el
escalado en vez de desbordar: el chip en 1.15 (parte de 12 px, así que al máximo
queda en 13,8 px) y el teclado en 1.4. El resto de la app crece libremente.

### Modo oscuro

Deliberadamente no existe: `MaterialApp` fija `themeMode: ThemeMode.light`. La
app se usa a pleno sol. Si se agrega, hay que medirle el contraste por
separado — los valores del modo claro no se heredan.
