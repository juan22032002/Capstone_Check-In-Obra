import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formato.dart';
import '../../core/network/errores.dart';
import '../../core/network/idempotencia.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_forma.dart';
import '../../core/theme/app_theme.dart';
import '../../data/api/dominio_api.dart';
import '../../data/modelos/material.dart';
import '../../shared_widgets/campo_texto.dart';
import '../../shared_widgets/estados.dart';
import '../../shared_widgets/opcion.dart';
import '../../shared_widgets/panel.dart';
import '../../shared_widgets/presion.dart';
import '../bodega/bodega_providers.dart';
import '../bodega/pantalla_bodega.dart';
import '../bodega/pantalla_escaneo.dart';
import 'aviso_faltantes.dart';
import 'pantalla_importacion.dart';

/// Categorías de `CategoriaMaterial`. El rubro es tabiquería y cielos, así que
/// son estas cuatro y no un campo libre.
const categorias = ['METALCOM', 'VOLCANITA', 'OSB', 'FIJACION'];

/// Catálogo de materiales de la empresa: precio unitario, stock mínimo y
/// merma. Es lo que alimenta la cubicación y el presupuesto, así que un precio
/// mal cargado se propaga a toda la obra.
class PantallaMateriales extends ConsumerWidget {
  const PantallaMateriales({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalogo = ref.watch(catalogoProvider);

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(faltantesProvider);
          ref.invalidate(catalogoProvider);
          await ref.read(catalogoProvider.future);
        },
        child: Contenido<List<MaterialObra>>(
          valor: catalogo,
          alReintentar: () => ref.invalidate(catalogoProvider),
          estaVacio: (l) => l.isEmpty,
          vacio: SingleChildScrollView(
            child: Vacio(
              icono: Icons.category_outlined,
              titulo: 'El catálogo está vacío',
              detalle:
                  'Sin materiales no se puede cubicar ni mover bodega. '
                  'Empieza por los que más se usan en la obra.',
              // Con el catálogo vacío, cargar la planilla que la constructora
              // ya tiene en Excel es mucho más razonable que teclear treinta y
              // cuatro materiales en un teléfono. Por eso la importación
              // aparece acá y no escondida en otra pestaña.
              accion: Builder(
                builder: (context) => Column(
                  children: [
                    FilledButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const PantallaImportacion(),
                        ),
                      ),
                      icon: const Icon(Icons.upload_file),
                      label: const Text('Importar desde Excel'),
                    ),
                    const SizedBox(height: 10),
                    TextButton.icon(
                      onPressed: () => _nuevo(context),
                      icon: const Icon(Icons.add),
                      label: const Text('Agregar uno a uno'),
                    ),
                  ],
                ),
              ),
            ),
          ),
          constructor: (lista) {
            final porCategoria = <String, List<MaterialObra>>{};
            for (final m in lista) {
              porCategoria.putIfAbsent(m.categoria, () => []).add(m);
            }
            // En cuántas obras falta cada material, para marcarlo en su fila.
            final faltaEn = <int, int>{};
            for (final f
                in ref.watch(faltantesProvider).valueOrNull ?? const []) {
              faltaEn[f.materialId] = (faltaEn[f.materialId] ?? 0) + 1;
            }
            return ListView(
              padding: AppEspacio.pantalla,
              children: [
                const AvisoFaltantes(),
                for (final categoria in categorias)
                  if (porCategoria[categoria] case final materiales?) ...[
                    Etiqueta(
                      '${nombreDeCategoria(categoria)} (${materiales.length})',
                    ),
                    const SizedBox(height: AppEspacio.sm + 4),
                    for (final m in materiales) ...[
                      _FilaMaterial(
                        material: m,
                        faltaEnObras: faltaEn[m.id] ?? 0,
                      ),
                      const SizedBox(height: AppEspacio.sm),
                    ],
                    const SizedBox(height: AppEspacio.md),
                  ],
                const SizedBox(height: 70),
              ],
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _nuevo(context),
        backgroundColor: AppColors.accentFill,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Nuevo material'),
      ),
    );
  }

  static void _nuevo(BuildContext context) => Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => const PantallaNuevoMaterial()));
}

class _FilaMaterial extends ConsumerWidget {
  const _FilaMaterial({required this.material, required this.faltaEnObras});

  final MaterialObra material;

  /// En cuántas obras activas se está agotando. Cero si en ninguna.
  final int faltaEnObras;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final m = material;
    final unidad = unidadDe(m.categoria);
    return PanelTocable(
      semanticLabel:
          '${m.nombre}, ${_costoHablado(m, unidad)}'
          '${faltaEnObras > 0 ? '. Se está agotando en $faltaEnObras obras' : ''}'
          '. Tocar para editar precio y merma',
      borderIzquierdo: faltaEnObras > 0 ? AppColors.warning : null,
      onTap: () => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => _HojaEdicion(material: m),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  m.nombre,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${m.sku} · mín. ${Formato.cantidad(m.stockMinimo)} $unidad',
                  style: const TextStyle(
                    fontFamily: AppTheme.monoFamily,
                    fontSize: 12.5,
                    color: AppColors.secondary,
                  ),
                ),
                if (m.tieneCostoReal) ...[
                  const SizedBox(height: AppEspacio.xs),
                  _LineaCompra(material: m),
                ],
                if (faltaEnObras > 0) ...[
                  const SizedBox(height: AppEspacio.sm),
                  ChipEstado.aviso(
                    faltaEnObras == 1
                        ? 'Se agota en 1 obra'
                        : 'Se agota en $faltaEnObras obras',
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          CostoMaterial(material: m, unidad: unidad),
        ],
      ),
    );
  }
}

String _costoHablado(MaterialObra m, String unidad) => m.tieneCostoReal
    ? 'costó ${Formato.pesos(m.ultimoCostoUnitario!)} por $unidad en la '
          'última compra; precio de catálogo ${Formato.pesos(m.precioUnitario)}'
    : 'precio de catálogo ${Formato.pesos(m.precioUnitario)} por $unidad, '
          'sin compras registradas con costo';

/// El precio de un material dicho con su origen.
///
/// "$5.980" solo no dice nada: puede ser lo que se estimó al cargar el
/// catálogo o lo que efectivamente se pagó la semana pasada, y en una obra
/// esas dos cifras se separan. Por eso la cifra grande es la del costo real
/// cuando existe, con el rótulo "costo" y la fecha de la compra, y el precio
/// de catálogo queda debajo para comparar. Sin compras con costo, se dice que
/// es de catálogo.
class CostoMaterial extends StatelessWidget {
  const CostoMaterial({
    super.key,
    required this.material,
    required this.unidad,
  });

  final MaterialObra material;
  final String unidad;

  @override
  Widget build(BuildContext context) {
    final m = material;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          Formato.pesos(m.costoVigente),
          style: const TextStyle(
            fontFeatures: AppTexto.tabulares,
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          m.tieneCostoReal ? 'costo / $unidad' : 'catálogo / $unidad',
          style: AppTexto.dato.copyWith(fontSize: 11.5),
        ),
      ],
    );
  }
}

/// Precio y merma se editan juntos porque son las dos cosas que cambian de un
/// material ya creado: el SKU y el nombre no se tocan, y el stock mínimo se
/// define al darlo de alta.
class _HojaEdicion extends ConsumerStatefulWidget {
  const _HojaEdicion({required this.material});

  final MaterialObra material;

  @override
  ConsumerState<_HojaEdicion> createState() => _HojaEdicionState();
}

class _HojaEdicionState extends ConsumerState<_HojaEdicion> {
  late final _precio = TextEditingController(
    text: widget.material.precioUnitario.toStringAsFixed(0),
  );
  final _merma = TextEditingController();
  bool _enviando = false;
  String? _error;

  @override
  void dispose() {
    _precio.dispose();
    _merma.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (_enviando) return;
    setState(() {
      _enviando = true;
      _error = null;
    });
    try {
      final api = ref.read(materialesApiProvider);

      final precio = double.tryParse(_precio.text.replaceAll('.', ''));
      if (precio != null && precio != widget.material.precioUnitario) {
        await api.actualizarPrecio(widget.material.id, precio);
      }

      final merma = Formato.numero(_merma.text);
      if (merma != null) {
        await api.definirMerma(widget.material.id, merma);
      }

      ref.invalidate(catalogoProvider);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Material actualizado')));
    } catch (e) {
      if (mounted) setState(() => _error = mensajeDeError(e));
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.material.nombre,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 14),
              _ResumenCosto(material: widget.material),
              const SizedBox(height: 18),
              CampoConEtiqueta(
                etiqueta: 'Precio de catálogo',
                campo: CampoTexto(
                  controlador: _precio,
                  hint: '5980',
                  icono: Icons.attach_money,
                  mono: true,
                  teclado: TextInputType.number,
                  formatters: [FilteringTextInputFormatter.digitsOnly],
                  habilitado: !_enviando,
                ),
                ayuda:
                    'Lo que se estima pagar: alimenta el presupuesto. El costo '
                    'real sale de las recepciones. Cambiarlo no altera los '
                    'presupuestos ya congelados.',
              ),
              const SizedBox(height: 16),
              CampoConEtiqueta(
                etiqueta: 'Merma parametrizada (%)',
                campo: CampoTexto(
                  controlador: _merma,
                  hint: '12',
                  icono: Icons.content_cut,
                  mono: true,
                  teclado: const TextInputType.numberWithOptions(decimal: true),
                  formatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                  ],
                  habilitado: !_enviando,
                ),
                ayuda:
                    'Lo que el motor de cubicación agrega sobre la cantidad '
                    'calculada. Déjalo en blanco para no modificarlo.',
              ),
              if (_error != null) ...[
                const SizedBox(height: 14),
                MensajeError(mensaje: _error!),
              ],
              const SizedBox(height: 20),
              BotonEnvio(
                texto: 'Guardar cambios',
                textoEnviando: 'Guardando…',
                enviando: _enviando,
                alPresionar: _guardar,
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class PantallaNuevoMaterial extends ConsumerStatefulWidget {
  const PantallaNuevoMaterial({super.key});

  @override
  ConsumerState<PantallaNuevoMaterial> createState() =>
      _PantallaNuevoMaterialState();
}

class _PantallaNuevoMaterialState extends ConsumerState<PantallaNuevoMaterial> {
  final _sku = TextEditingController();
  final _codigoBarra = TextEditingController();
  final _nombre = TextEditingController();
  final _precio = TextEditingController();
  final _minimo = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  String _categoria = categorias.first;
  bool _enviando = false;
  String? _error;
  final _intento = IntentoIdempotente();

  @override
  void dispose() {
    _sku.dispose();
    _codigoBarra.dispose();
    _nombre.dispose();
    _precio.dispose();
    _minimo.dispose();
    super.dispose();
  }

  Future<void> _leerCodigo() async {
    final codigo = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const PantallaCapturaCodigo()),
    );
    if (codigo != null && mounted) {
      setState(() => _codigoBarra.text = codigo);
    }
  }

  Future<void> _guardar() async {
    if (_enviando) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _enviando = true;
      _error = null;
    });
    final sku = _sku.text.trim().toUpperCase();
    final nombre = _nombre.text.trim();
    final precio = double.parse(_precio.text.replaceAll('.', ''));
    final minimo = Formato.numero(_minimo.text)!;
    final codigo = _codigoBarra.text.trim().isEmpty
        ? null
        : _codigoBarra.text.trim();
    try {
      await ref
          .read(materialesApiProvider)
          .crear(
            sku: sku,
            nombre: nombre,
            categoria: _categoria,
            precioUnitario: precio,
            stockMinimo: minimo,
            codigoBarra: codigo,
            clave: _intento.clavePara([
              sku,
              nombre,
              _categoria,
              precio,
              minimo,
              codigo,
            ]),
          );
      ref.invalidate(catalogoProvider);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Material agregado')));
    } catch (e) {
      if (mounted) setState(() => _error = mensajeDeError(e));
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nuevo material')),
      body: SafeArea(
        top: false,
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              CampoConEtiqueta(
                etiqueta: 'SKU',
                campo: CampoTexto(
                  controlador: _sku,
                  hint: 'VOL-ST-10-120240',
                  icono: Icons.qr_code_2,
                  mono: true,
                  habilitado: !_enviando,
                  validador: (v) => (v == null || v.trim().isEmpty)
                      ? 'El SKU identifica al material y es obligatorio'
                      : null,
                ),
                ayuda: 'Único en la empresa. Es lo que viene en la guía de despacho.',
              ),
              const SizedBox(height: 16),
              CampoConEtiqueta(
                etiqueta: 'Código de barras (opcional)',
                campo: CampoTexto(
                  controlador: _codigoBarra,
                  hint: '7801234567890',
                  icono: Icons.barcode_reader,
                  mono: true,
                  teclado: TextInputType.number,
                  habilitado: !_enviando,
                  sufijo: IconButton(
                    tooltip: 'Leerlo con la cámara',
                    icon: const Icon(Icons.qr_code_scanner, size: 20),
                    color: AppColors.accentFill,
                    onPressed: _enviando ? null : _leerCodigo,
                  ),
                ),
                ayuda:
                    'El que viene impreso en el envase. Con él, el bodeguero '
                    'encuentra este material escaneándolo en vez de buscarlo '
                    'en la lista.',
              ),
              const SizedBox(height: 16),
              CampoConEtiqueta(
                etiqueta: 'Nombre',
                campo: CampoTexto(
                  controlador: _nombre,
                  hint: 'Volcanita ST 10 mm · 1,20 × 2,40',
                  icono: Icons.label_outline,
                  habilitado: !_enviando,
                  validador: (v) => (v == null || v.trim().isEmpty)
                      ? 'Este campo es obligatorio'
                      : null,
                ),
              ),
              const SizedBox(height: 16),
              const Etiqueta('Categoría'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final c in categorias)
                    _ChipCategoria(
                      categoria: c,
                      activa: _categoria == c,
                      onTap: _enviando
                          ? null
                          : () => setState(() => _categoria = c),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              CampoConEtiqueta(
                etiqueta: 'Precio unitario',
                campo: CampoTexto(
                  controlador: _precio,
                  hint: '5980',
                  icono: Icons.attach_money,
                  mono: true,
                  teclado: TextInputType.number,
                  formatters: [FilteringTextInputFormatter.digitsOnly],
                  habilitado: !_enviando,
                  validador: (v) => double.tryParse(v ?? '') == null
                      ? 'Escribe el precio'
                      : null,
                ),
              ),
              const SizedBox(height: 16),
              CampoConEtiqueta(
                etiqueta: 'Stock mínimo de obra',
                campo: CampoTexto(
                  controlador: _minimo,
                  hint: '40',
                  icono: Icons.warning_amber_outlined,
                  mono: true,
                  teclado: const TextInputType.numberWithOptions(decimal: true),
                  formatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                  ],
                  habilitado: !_enviando,
                  validador: (v) => Formato.numero(v ?? '') == null
                      ? 'Escribe el mínimo'
                      : null,
                ),
                ayuda:
                    'Bajo esta cantidad se genera una alerta de stock crítico '
                    'en la obra.',
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                MensajeError(mensaje: _error!),
              ],
              const SizedBox(height: 22),
              BotonEnvio(
                texto: 'Agregar al catálogo',
                textoEnviando: 'Guardando…',
                enviando: _enviando,
                alPresionar: _guardar,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChipCategoria extends StatelessWidget {
  const _ChipCategoria({
    required this.categoria,
    required this.activa,
    required this.onTap,
  });

  final String categoria;
  final bool activa;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Opcion(
      texto: nombreDeCategoria(categoria),
      elegida: activa,
      alTocar: onTap,
    );
  }
}

/// "Compra hoy 10:15 · ▲ 10 % sobre catálogo": cuándo se pagó el costo que
/// se muestra y cuánto se alejó de lo estimado. Va bajo el nombre, a todo el
/// ancho, y no junto a la cifra: ahí angostaba el nombre hasta partirlo.
class _LineaCompra extends StatelessWidget {
  const _LineaCompra({required this.material});

  final MaterialObra material;

  @override
  Widget build(BuildContext context) {
    final m = material;
    final variacion = m.variacionCosto;
    final fecha = m.fechaUltimoCosto;
    return Text.rich(
      TextSpan(
        style: AppTexto.dato.copyWith(fontSize: 11.5),
        children: [
          TextSpan(
            text: fecha == null
                ? 'Última compra'
                : 'Compra ${Formato.relativa(fecha)}',
          ),
          if (variacion != null && variacion.abs() >= 0.005)
            TextSpan(
              text:
                  ' · ${variacion > 0 ? '▲' : '▼'} '
                  '${(variacion.abs() * 100).toStringAsFixed(0)} % '
                  '${variacion > 0 ? 'sobre' : 'bajo'} catálogo '
                  '(${Formato.pesos(m.precioUnitario)})',
              style: TextStyle(
                color: variacion > 0
                    ? AppColors.destructiveDark
                    : AppColors.successDark,
              ),
            ),
        ],
      ),
    );
  }
}

/// Lo que costó el material en las compras registradas, dentro de la hoja de
/// edición: es la referencia para decidir si el precio de catálogo quedó
/// corto.
class _ResumenCosto extends StatelessWidget {
  const _ResumenCosto({required this.material});

  final MaterialObra material;

  @override
  Widget build(BuildContext context) {
    final m = material;
    final unidad = unidadDe(m.categoria);
    if (!m.tieneCostoReal) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: const BoxDecoration(
          color: AppColors.sunken,
          borderRadius: AppForma.borde,
        ),
        child: Text(
          'Todavía no hay recepciones con costo. Al recibir material en '
          'bodega, anota lo que se pagó por $unidad y aparecerá acá.',
          style: AppTexto.cuerpoChico,
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: const BoxDecoration(
        color: AppColors.sunken,
        borderRadius: AppForma.borde,
      ),
      child: Row(
        children: [
          Expanded(
            child: _Cifra(
              rotulo: 'Última compra',
              valor: Formato.pesos(m.ultimoCostoUnitario!),
              detalle: m.fechaUltimoCosto == null
                  ? 'por $unidad'
                  : 'por $unidad · ${Formato.relativa(m.fechaUltimoCosto!)}',
            ),
          ),
          if (m.costoPromedio != null)
            Expanded(
              child: _Cifra(
                rotulo: 'Costo promedio',
                valor: Formato.pesos(m.costoPromedio!),
                detalle: 'ponderado por cantidad',
              ),
            ),
        ],
      ),
    );
  }
}

class _Cifra extends StatelessWidget {
  const _Cifra({
    required this.rotulo,
    required this.valor,
    required this.detalle,
  });

  final String rotulo;
  final String valor;
  final String detalle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(rotulo, style: AppTexto.rotulo),
        const SizedBox(height: 2),
        Text(
          valor,
          style: const TextStyle(
            fontFeatures: AppTexto.tabulares,
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: AppColors.primary,
          ),
        ),
        Text(detalle, style: AppTexto.dato.copyWith(fontSize: 11.5)),
      ],
    );
  }
}
