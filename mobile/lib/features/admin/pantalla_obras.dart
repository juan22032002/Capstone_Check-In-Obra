import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formato.dart';
import '../../core/network/errores.dart';
import '../../core/network/idempotencia.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../data/api/dominio_api.dart';
import '../../data/modelos/detalle_obra.dart';
import '../../data/modelos/obra.dart';
import '../../shared_widgets/campo_texto.dart';
import '../../shared_widgets/estados.dart';
import '../../shared_widgets/panel.dart';
import '../../shared_widgets/presion.dart';
import '../bodega/pantalla_bodega.dart';
import '../obra/obra_activa.dart';
import 'pantalla_detalle_obra.dart';

/// Obras de la constructora. Crear y cerrar son exclusivas de ADMIN.
class PantallaObras extends ConsumerWidget {
  const PantallaObras({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final obras = ref.watch(todasLasObrasProvider);

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(detalleObraProvider);
          ref.invalidate(todasLasObrasProvider);
          await ref.read(todasLasObrasProvider.future);
        },
        child: Contenido<List<Obra>>(
          valor: obras,
          alReintentar: () => ref.invalidate(todasLasObrasProvider),
          estaVacio: (l) => l.isEmpty,
          vacio: SingleChildScrollView(
            child: Vacio(
              icono: Icons.domain_outlined,
              titulo: 'Todavía no hay obras',
              detalle:
                  'La obra es el contenedor de todo lo demás: sin una obra no '
                  'se puede cubicar, presupuestar ni mover bodega.',
              accion: Builder(
                builder: (context) => FilledButton.icon(
                  onPressed: () => _abrirFormulario(context),
                  icon: const Icon(Icons.add),
                  label: const Text('Crear la primera obra'),
                ),
              ),
            ),
          ),
          constructor: (lista) {
            final activas = lista.where((o) => o.activa).toList();
            final cerradas = lista.where((o) => !o.activa).toList();
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Etiqueta('Activas (${activas.length})'),
                const SizedBox(height: 8),
                for (final o in activas) ...[
                  _FilaObra(obra: o),
                  const SizedBox(height: 8),
                ],
                if (cerradas.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Etiqueta('Cerradas (${cerradas.length})'),
                  const SizedBox(height: 8),
                  for (final o in cerradas) ...[
                    _FilaObra(obra: o),
                    const SizedBox(height: 8),
                  ],
                ],
                const SizedBox(height: 80),
              ],
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _abrirFormulario(context),
        backgroundColor: AppColors.accentFill,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Nueva obra'),
      ),
    );
  }

  static void _abrirFormulario(BuildContext context) =>
      Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const PantallaNuevaObra()));
}

/// Una obra en la lista: quién la dirige y, debajo, lo que tiene — gente,
/// materiales con su cantidad y herramientas. Tocarla abre la ficha completa.
///
/// El resumen se pide por obra y llega después que la fila. Mientras tanto la
/// fila ya muestra nombre, cliente y jefe, que vienen en la lista, en vez de
/// esperar con un spinner lo que no hace falta para reconocerla.
class _FilaObra extends ConsumerWidget {
  const _FilaObra({required this.obra});

  final Obra obra;

  /// Cuántos materiales y grupos de herramientas se adelantan en la fila.
  static const _vistaPrevia = 3;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final o = obra;
    final detalle = ref.watch(detalleObraProvider(o.id));
    final d = detalle.valueOrNull;

    return PanelTocable(
      semanticLabel:
          '${o.nombre}, ${o.activa ? 'activa' : 'cerrada'}. ${o.cliente}. '
          '${o.jefeIdentificacion}. '
          '${d == null ? '' : '${d.resumen.cantidadTrabajadores} trabajadores, '
                    '${d.materiales.length} materiales, '
                    '${d.herramientas.length} herramientas. '}'
          'Tocar para ver el detalle',
      color: o.activa ? AppColors.card : AppColors.background,
      borderColor: o.activa ? AppColors.borderControl : AppColors.border,
      borderIzquierdo: d != null && d.resumen.materialesCriticos > 0
          ? AppColors.destructive
          : null,
      onTap: () => Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => PantallaDetalleObra(obra: o))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  o.nombre,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              o.activa
                  ? ChipEstado.exito('Activa')
                  : ChipEstado.neutro('Cerrada'),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right, color: AppColors.secondary),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${o.cliente} · ${o.ubicacion}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(
                Icons.engineering_outlined,
                size: 17,
                color: o.tieneJefe
                    ? AppColors.secondary
                    : AppColors.warningDark,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  o.jefeIdentificacion,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: o.tieneJefe ? FontWeight.w500 : FontWeight.w400,
                    color: o.tieneJefe
                        ? AppColors.primary
                        : AppColors.warningDark,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1, color: AppColors.border),
          const SizedBox(height: 12),
          switch (detalle) {
            AsyncData(:final value) => _VistaPrevia(detalle: value),
            AsyncError() when d == null => Text(
              'No se pudo cargar el resumen. Toca para reintentar en la ficha.',
              style: AppTexto.cuerpoChico,
            ),
            _ when d != null => _VistaPrevia(detalle: d),
            _ => const _VistaPreviaCargando(),
          },
        ],
      ),
    );
  }
}

class _VistaPrevia extends StatelessWidget {
  const _VistaPrevia({required this.detalle});

  final DetalleObra detalle;

  @override
  Widget build(BuildContext context) {
    final r = detalle.resumen;
    // Primero lo que falta y después el resto, como en la ficha.
    final materiales = [
      ...detalle.faltantes,
      ...detalle.materiales.where((m) => m.estado == EstadoStock.ok),
    ].take(_FilaObra._vistaPrevia).toList();
    final grupos = detalle.herramientasAgrupadas
        .take(_FilaObra._vistaPrevia)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 16,
          runSpacing: 6,
          children: [
            _Dato(
              icono: Icons.groups_outlined,
              texto: r.cantidadTrabajadores == 1
                  ? '1 trabajador'
                  : '${r.cantidadTrabajadores} trabajadores',
            ),
            _Dato(
              icono: Icons.inventory_2_outlined,
              texto: '${detalle.materiales.length} materiales',
            ),
            _Dato(
              icono: Icons.handyman_outlined,
              texto: '${detalle.herramientas.length} herramientas',
            ),
          ],
        ),
        if (r.materialesPorReponer > 0) ...[
          const SizedBox(height: 10),
          r.materialesCriticos > 0
              ? ChipEstado.critico(
                  r.materialesCriticos == 1
                      ? '1 material bajo el mínimo'
                      : '${r.materialesCriticos} materiales bajo el mínimo',
                )
              : ChipEstado.aviso(
                  r.materialesBajos == 1
                      ? '1 material por agotarse'
                      : '${r.materialesBajos} materiales por agotarse',
                ),
        ],
        if (materiales.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('Materiales', style: AppTexto.rotulo),
          const SizedBox(height: 4),
          for (final m in materiales)
            _LineaCantidad(
              nombre: m.nombre,
              cantidad: '${Formato.cantidad(m.stock)} ${unidadDe(m.categoria)}',
              color: switch (m.estado) {
                EstadoStock.critico => AppColors.destructiveDark,
                EstadoStock.bajo => AppColors.warningDark,
                EstadoStock.ok => AppColors.primary,
              },
            ),
          if (detalle.materiales.length > materiales.length)
            _Mas(detalle.materiales.length - materiales.length),
        ],
        if (grupos.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text('Herramientas', style: AppTexto.rotulo),
          const SizedBox(height: 4),
          for (final g in grupos)
            _LineaCantidad(
              nombre: g.nombre,
              cantidad: '× ${g.cantidad}',
              color: g.vencidas > 0
                  ? AppColors.destructiveDark
                  : AppColors.primary,
            ),
          if (detalle.herramientasAgrupadas.length > grupos.length)
            _Mas(detalle.herramientasAgrupadas.length - grupos.length),
        ],
      ],
    );
  }
}

class _Dato extends StatelessWidget {
  const _Dato({required this.icono, required this.texto});

  final IconData icono;
  final String texto;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icono, size: 16, color: AppColors.secondary),
        const SizedBox(width: 6),
        Text(
          texto,
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w500,
            color: AppColors.primary,
          ),
        ),
      ],
    );
  }
}

class _LineaCantidad extends StatelessWidget {
  const _LineaCantidad({
    required this.nombre,
    required this.cantidad,
    required this.color,
  });

  final String nombre;
  final String cantidad;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              nombre,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTexto.cuerpoChico.copyWith(color: AppColors.primary),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            cantidad,
            style: TextStyle(
              fontFeatures: AppTexto.tabulares,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _Mas extends StatelessWidget {
  const _Mas(this.cuantos);

  final int cuantos;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 2),
    child: Text('y $cuantos más', style: AppTexto.dato),
  );
}

/// Siluetas del resumen mientras llega: reservan el alto para que la lista no
/// salte cuando carga.
class _VistaPreviaCargando extends StatelessWidget {
  const _VistaPreviaCargando();

  @override
  Widget build(BuildContext context) {
    Widget barra(double ancho) => Container(
      width: ancho,
      height: 10,
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: const BoxDecoration(
        color: AppColors.sunken,
        borderRadius: BorderRadius.all(Radius.circular(4)),
      ),
    );
    return ExcludeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [barra(220), barra(160), barra(190)],
      ),
    );
  }
}

class PantallaNuevaObra extends ConsumerStatefulWidget {
  const PantallaNuevaObra({super.key});

  @override
  ConsumerState<PantallaNuevaObra> createState() => _PantallaNuevaObraState();
}

class _PantallaNuevaObraState extends ConsumerState<PantallaNuevaObra> {
  final _nombre = TextEditingController();
  final _cliente = TextEditingController();
  final _ubicacion = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _enviando = false;
  String? _error;
  final _intento = IntentoIdempotente();

  @override
  void dispose() {
    _nombre.dispose();
    _cliente.dispose();
    _ubicacion.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (_enviando) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _enviando = true;
      _error = null;
    });
    final nombre = _nombre.text.trim();
    final cliente = _cliente.text.trim();
    final ubicacion = _ubicacion.text.trim();
    try {
      await ref
          .read(obrasApiProvider)
          .crear(
            nombre: nombre,
            cliente: cliente,
            ubicacion: ubicacion,
            clave: _intento.clavePara([nombre, cliente, ubicacion]),
          );
      ref.invalidate(todasLasObrasProvider);
      ref.invalidate(obrasActivasProvider);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Obra creada')));
    } catch (e) {
      if (mounted) setState(() => _error = mensajeDeError(e));
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nueva obra')),
      body: SafeArea(
        top: false,
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              CampoConEtiqueta(
                etiqueta: 'Nombre de la obra',
                campo: CampoTexto(
                  controlador: _nombre,
                  hint: 'Los Almendros · Torre B',
                  icono: Icons.domain_outlined,
                  habilitado: !_enviando,
                  validador: _obligatorio,
                ),
              ),
              const SizedBox(height: 16),
              CampoConEtiqueta(
                etiqueta: 'Cliente',
                campo: CampoTexto(
                  controlador: _cliente,
                  hint: 'Inmobiliaria Aconcagua',
                  icono: Icons.business_outlined,
                  habilitado: !_enviando,
                  validador: _obligatorio,
                ),
              ),
              const SizedBox(height: 16),
              CampoConEtiqueta(
                etiqueta: 'Ubicación',
                campo: CampoTexto(
                  controlador: _ubicacion,
                  hint: 'Av. Los Almendros 1240, Ñuñoa',
                  icono: Icons.place_outlined,
                  habilitado: !_enviando,
                  validador: _obligatorio,
                ),
                ayuda:
                    'Sirve para distinguir obras del mismo cliente en el '
                    'selector de bodega.',
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                MensajeError(mensaje: _error!),
              ],
              const SizedBox(height: 22),
              BotonEnvio(
                texto: 'Crear obra',
                textoEnviando: 'Creando…',
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

String? _obligatorio(String? v) =>
    (v == null || v.trim().isEmpty) ? 'Este campo es obligatorio' : null;
