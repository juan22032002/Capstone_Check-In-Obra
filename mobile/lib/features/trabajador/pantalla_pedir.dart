import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formato.dart';
import '../../core/network/errores.dart';
import '../../core/network/idempotencia.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_forma.dart';
import '../../core/theme/app_theme.dart';
import '../../data/api/auth_api.dart';
import '../../data/api/dominio_api.dart';
import '../../data/modelos/herramienta.dart';
import '../../data/modelos/material.dart';
import '../../data/modelos/pedido_herramienta.dart';
import '../../data/modelos/perfil_trabajador.dart';
import '../../shared_widgets/campo_texto.dart';
import '../../shared_widgets/estados.dart';
import '../../shared_widgets/panel.dart';
import '../../shared_widgets/presion.dart';
import '../admin/pantalla_materiales.dart' show categorias;
import '../bodega/pantalla_bodega.dart';
import 'pantalla_pedido_especial.dart';
import 'pantalla_pedido_qr.dart';
import 'trabajador_providers.dart';

/// Buscador compartido por las dos pantallas de pedir. En obra se busca por
/// una palabra —"volcanita", "taladro"— y no se navega un catálogo.
class _Buscador extends StatelessWidget {
  const _Buscador({required this.controlador, required this.hint});

  final TextEditingController controlador;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return CampoTexto(
      controlador: controlador,
      hint: hint,
      icono: Icons.search,
      sufijo: ListenableBuilder(
        listenable: controlador,
        builder: (_, _) => controlador.text.isEmpty
            ? const SizedBox.shrink()
            : IconButton(
                tooltip: 'Borrar búsqueda',
                icon: const Icon(Icons.close, size: 20),
                onPressed: controlador.clear,
              ),
      ),
    );
  }
}

bool _coincide(String texto, String busqueda) {
  final b = busqueda.trim().toLowerCase();
  return b.isEmpty || texto.toLowerCase().contains(b);
}

/// El "para qué" de una solicitud: un globo de texto de varias líneas.
///
/// Es obligatorio porque es lo que le permite a bodega decidir sin llamar a
/// nadie: "12 placas" no dice nada; "12 placas para el tabique del baño del
/// 304" dice si es urgente y si calza con lo cubicado.
class CampoParaQue extends StatelessWidget {
  const CampoParaQue({
    super.key,
    required this.controlador,
    required this.habilitado,
    this.hint = 'Ej.: tabique del baño del depto 304, faltan 6 placas',
  });

  final TextEditingController controlador;
  final bool habilitado;
  final String hint;

  static const largoMaximo = 300;

  static String? validar(String? v) {
    final t = v?.trim() ?? '';
    if (t.length < 3) return 'Cuéntale a bodega para qué lo necesitas';
    if (t.length > largoMaximo) return 'Máximo $largoMaximo caracteres';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    // El globo: la esquina inferior izquierda casi recta, como un mensaje que
    // sale de quien pide.
    const globo = BorderRadius.only(
      topLeft: Radius.circular(AppForma.radio),
      topRight: Radius.circular(AppForma.radio),
      bottomRight: Radius.circular(AppForma.radio),
      bottomLeft: Radius.circular(3),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('¿Para qué lo necesitas?', style: AppTexto.rotulo),
        const SizedBox(height: AppEspacio.sm),
        TextFormField(
          controller: controlador,
          enabled: habilitado,
          minLines: 3,
          maxLines: 5,
          maxLength: largoMaximo,
          textCapitalization: TextCapitalization.sentences,
          keyboardType: TextInputType.multiline,
          validator: validar,
          style: AppTexto.cuerpo,
          decoration: InputDecoration(
            hintText: hint,
            hintMaxLines: 2,
            prefixIcon: const Padding(
              padding: EdgeInsets.only(bottom: 44),
              child: Icon(Icons.chat_bubble_outline, size: 20),
            ),
            border: const OutlineInputBorder(borderRadius: globo),
            enabledBorder: const OutlineInputBorder(
              borderRadius: globo,
              borderSide: BorderSide(color: AppColors.borderControl),
            ),
            focusedBorder: const OutlineInputBorder(
              borderRadius: globo,
              borderSide: BorderSide(color: AppColors.accentFill, width: 2),
            ),
            errorBorder: const OutlineInputBorder(
              borderRadius: globo,
              borderSide: BorderSide(color: AppColors.destructiveDark),
            ),
            focusedErrorBorder: const OutlineInputBorder(
              borderRadius: globo,
              borderSide: BorderSide(
                color: AppColors.destructiveDark,
                width: 2,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Acceso al pedido especial al pie de las dos listas: lo que no aparece, o
/// no hay, también se puede pedir.
class _PideloIgual extends StatelessWidget {
  const _PideloIgual({required this.texto, required this.onTap});

  final String texto;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.card,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: OutlinedButton.icon(
            onPressed: onTap,
            icon: const Icon(Icons.add_shopping_cart_outlined, size: 20),
            label: Text(texto),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              foregroundColor: AppColors.primary,
              side: const BorderSide(color: AppColors.borderControl),
            ),
          ),
        ),
      ),
    );
  }
}

// --- Material ------------------------------------------------------------------

/// Pedir material a la bodega de su obra.
///
/// Elegir y decir cuánto y para qué van en dos pasos —lista y hoja— porque la
/// lista es larga: un formulario con un desplegable de treinta materiales en
/// un teléfono es peor que buscar y tocar.
class PantallaPedirMaterial extends ConsumerStatefulWidget {
  const PantallaPedirMaterial({super.key, required this.perfil});

  final PerfilTrabajador perfil;

  @override
  ConsumerState<PantallaPedirMaterial> createState() =>
      _PantallaPedirMaterialState();
}

class _PantallaPedirMaterialState extends ConsumerState<PantallaPedirMaterial> {
  final _busqueda = TextEditingController();

  @override
  void initState() {
    super.initState();
    _busqueda.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _busqueda.dispose();
    super.dispose();
  }

  void _pedidoEspecial({MaterialObra? material}) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PantallaPedidoEspecial(
          esHerramienta: false,
          nombreInicial: material?.nombre ?? _busqueda.text.trim(),
          materialId: material?.id,
          unidadInicial: material == null ? null : unidadDe(material.categoria),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final catalogo = ref.watch(catalogoTrabajadorProvider);
    // Lo que ya tiene pedido y sin atender, para no pedirlo dos veces sin
    // darse cuenta.
    final yaPedidos = {
      for (final s
          in ref.watch(misPendientesProvider).valueOrNull ??
              const <MiSolicitud>[])
        if (s.origen == OrigenSolicitud.material) s.itemId,
    };

    return Scaffold(
      appBar: AppBar(title: const Text('Pedir material')),
      bottomNavigationBar: _PideloIgual(
        texto: 'Pedir algo que no hay',
        onTap: _pedidoEspecial,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Para la bodega de ${widget.perfil.obraNombre}',
                  style: AppTexto.rotulo,
                ),
                const SizedBox(height: AppEspacio.sm),
                _Buscador(controlador: _busqueda, hint: 'Buscar material'),
              ],
            ),
          ),
          Expanded(
            child: Contenido<List<MaterialObra>>(
              valor: catalogo,
              alReintentar: () => ref.invalidate(catalogoTrabajadorProvider),
              estaVacio: (l) => l.isEmpty,
              vacio: const Vacio(
                icono: Icons.category_outlined,
                titulo: 'No hay materiales en el catálogo',
                detalle:
                    'Usa el botón de abajo para pedir lo que necesitas y '
                    'bodega lo consigue.',
              ),
              constructor: (lista) {
                final filtrados = lista
                    .where(
                      (m) =>
                          _coincide(m.nombre, _busqueda.text) ||
                          _coincide(m.sku, _busqueda.text),
                    )
                    .toList();
                if (filtrados.isEmpty) {
                  return Vacio(
                    icono: Icons.search_off,
                    titulo: 'Nada con “${_busqueda.text.trim()}”',
                    detalle:
                        'Si no está en el catálogo, pídelo con el botón de '
                        'abajo y bodega lo consigue.',
                  );
                }
                final porCategoria = <String, List<MaterialObra>>{};
                for (final m in filtrados) {
                  porCategoria.putIfAbsent(m.categoria, () => []).add(m);
                }
                return ListView(
                  padding: AppEspacio.pantalla,
                  children: [
                    for (final c in [
                      ...categorias,
                      ...porCategoria.keys.where(
                        (k) => !categorias.contains(k),
                      ),
                    ])
                      if (porCategoria[c] case final materiales?) ...[
                        Etiqueta(nombreDeCategoria(c)),
                        const SizedBox(height: AppEspacio.sm),
                        for (final m in materiales) ...[
                          _FilaElegible(
                            titulo: m.nombre,
                            detalle: m.sku,
                            yaPedido: yaPedidos.contains(m.id),
                            onTap: () => _pedir(m),
                          ),
                          const SizedBox(height: AppEspacio.sm),
                        ],
                        const SizedBox(height: AppEspacio.md),
                      ],
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pedir(MaterialObra m) async {
    final resultado = await showModalBottomSheet<_Resultado>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _HojaMaterial(material: m, perfil: widget.perfil),
    );
    if (!mounted) return;
    switch (resultado) {
      case _Resultado.pedido:
        Navigator.of(context).pop();
      case _Resultado.noHay:
        _pedidoEspecial(material: m);
      case null:
        break;
    }
  }
}

/// Cómo terminó la hoja de solicitud.
enum _Resultado { pedido, noHay }

class _HojaMaterial extends ConsumerStatefulWidget {
  const _HojaMaterial({required this.material, required this.perfil});

  final MaterialObra material;
  final PerfilTrabajador perfil;

  @override
  ConsumerState<_HojaMaterial> createState() => _HojaMaterialState();
}

class _HojaMaterialState extends ConsumerState<_HojaMaterial> {
  final _cantidad = TextEditingController();
  final _paraQue = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _enviando = false;
  String? _error;
  final _intento = IntentoIdempotente();

  @override
  void dispose() {
    _cantidad.dispose();
    _paraQue.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    if (_enviando) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    final cantidad = Formato.numero(_cantidad.text)!;
    final paraQue = _paraQue.text.trim();
    setState(() {
      _enviando = true;
      _error = null;
    });
    try {
      await ref
          .read(solicitudesApiProvider)
          .pedirMaterial(
            materialId: widget.material.id,
            obraId: widget.perfil.obraId,
            cantidad: cantidad,
            descripcion: paraQue,
            clave: _intento.clavePara([widget.material.id, cantidad, paraQue]),
          );
      recargarTrabajador(ref);
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      final unidad = unidadDe(widget.material.categoria);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Pediste ${Formato.cantidad(cantidad)} $unidad de '
            '${widget.material.nombre}. Lo verás en Inicio mientras bodega '
            'lo atiende.',
          ),
        ),
      );
      Navigator.of(context).pop(_Resultado.pedido);
    } on ApiException catch (e) {
      // Ya tenía este material pedido y sin resolver (otro teléfono, o la lista
      // no se había actualizado): no es un fallo, es un estado. Se deja el
      // mensaje del servidor, que dice qué pasó ("Ya pediste … y tu solicitud
      // sigue pendiente"), y se recarga para que la lista lo marque como
      // "Ya lo pediste" y Inicio muestre la solicitud pendiente.
      if (e.codigo == 'SOLICITUD_DUPLICADA') recargarTrabajador(ref);
      if (mounted) setState(() => _error = mensajeDeError(e));
    } catch (e) {
      if (mounted) setState(() => _error = mensajeDeError(e));
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.material;
    final unidad = unidadDe(m.categoria);
    return _Hoja(
      enviando: _enviando,
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(m.nombre, style: AppTexto.subtitulo),
            Text(m.sku, style: AppTexto.dato),
            const SizedBox(height: 18),
            CampoConEtiqueta(
              etiqueta: '¿Cuánto necesitas?',
              campo: CampoTexto(
                controlador: _cantidad,
                hint: '0',
                icono: Icons.tag,
                mono: true,
                teclado: const TextInputType.numberWithOptions(decimal: true),
                formatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                ],
                habilitado: !_enviando,
                sufijo: Padding(
                  padding: const EdgeInsets.only(right: 14),
                  child: Text(
                    unidad,
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppColors.secondary,
                    ),
                  ),
                ),
                validador: (v) {
                  final n = Formato.numero(v ?? '');
                  if (n == null || n <= 0) {
                    return 'Escribe una cantidad mayor a cero';
                  }
                  return null;
                },
              ),
            ),
            const SizedBox(height: 16),
            CampoParaQue(controlador: _paraQue, habilitado: !_enviando),
            if (_error != null) ...[
              const SizedBox(height: 10),
              MensajeError(mensaje: _error!),
            ],
            const SizedBox(height: 12),
            BotonEnvio(
              texto: 'Solicitar material',
              textoEnviando: 'Enviando…',
              enviando: _enviando,
              alPresionar: _enviar,
            ),
            const SizedBox(height: 4),
            TextButton(
              onPressed: _enviando
                  ? null
                  : () => Navigator.of(context).pop(_Resultado.noHay),
              child: const Text('¿No hay en bodega? Pide que lo consigan'),
            ),
          ],
        ),
      ),
    );
  }
}

// --- Herramienta ---------------------------------------------------------------

/// Pedir herramientas, varias de una vez.
///
/// Se muestran agrupadas por nombre con cuántas quedan —"Taladro percutor ·
/// quedan 3"— y no una fila por QR: al trabajador le da lo mismo cuál de los
/// tres taladros le toque. Marcar un grupo elige la primera unidad disponible.
///
/// Lo marcado sale en un solo pedido y la app le da un QR para retirarlo: el
/// bodeguero lo escanea y entrega todo junto, en vez de aprobar una solicitud
/// por herramienta con el trabajador esperando en el mesón.
///
/// Si no queda ninguna, la fila no se puede marcar: sigue ahí y ofrece pedir
/// que la consigan. Las que ya tiene pedidas tampoco, para no pedirlas dos
/// veces sin darse cuenta.
class PantallaPedirHerramienta extends ConsumerStatefulWidget {
  const PantallaPedirHerramienta({super.key});

  @override
  ConsumerState<PantallaPedirHerramienta> createState() =>
      _PantallaPedirHerramientaState();
}

class _PantallaPedirHerramientaState
    extends ConsumerState<PantallaPedirHerramienta> {
  final _busqueda = TextEditingController();

  /// El "para qué" vive acá y no en la hoja: si el pedido choca con otro que
  /// se llevó una herramienta, la hoja se cierra y lo escrito no se pierde.
  final _paraQue = TextEditingController();

  /// Los grupos marcados, por nombre. Se guarda el grupo y no la unidad: la
  /// unidad se elige al enviar, con la lista recién cargada.
  final _marcados = <String>{};

  @override
  void initState() {
    super.initState();
    _busqueda.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _busqueda.dispose();
    _paraQue.dispose();
    super.dispose();
  }

  void _pedidoEspecial({Herramienta? herramienta}) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PantallaPedidoEspecial(
          esHerramienta: true,
          nombreInicial: herramienta?.nombre ?? _busqueda.text.trim(),
          herramientaId: herramienta?.id,
        ),
      ),
    );
  }

  static Map<String, List<Herramienta>> _agrupar(Iterable<Herramienta> l) {
    final grupos = <String, List<Herramienta>>{};
    for (final h in l) {
      grupos.putIfAbsent(h.nombre, () => []).add(h);
    }
    return grupos;
  }

  /// Una unidad disponible por cada grupo marcado que todavía se puede pedir.
  ///
  /// Tras recargar la lista, un grupo marcado puede haber quedado sin unidades
  /// o con una solicitud propia: deja de contar sin que haya que desmarcarlo.
  List<Herramienta> _elegidas(
    Map<String, List<Herramienta>> grupos,
    Set<String> yaPedidas,
  ) => [
    for (final nombre in _marcados)
      if (!yaPedidas.contains(nombre))
        ?grupos[nombre]?.where((h) => h.disponible).firstOrNull,
  ];

  Future<void> _solicitar(List<Herramienta> elegidas) async {
    if (elegidas.isEmpty) return;
    final salida = await showModalBottomSheet<_SalidaPedido>(
      context: context,
      isScrollControlled: true,
      builder: (_) =>
          _HojaPedidoHerramientas(elegidas: elegidas, paraQue: _paraQue),
    );
    if (!mounted || salida == null) return;
    switch (salida) {
      case _PedidoCreado(:final pedido):
        // Reemplaza en vez de apilar: al volver del QR, el trabajador quiere
        // Inicio, no la lista de la que ya pidió.
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) => PantallaPedidoQr(pedido: pedido),
          ),
        );
      case _PedidoEnConflicto(:final mensaje):
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${mensaje.trim().replaceFirst(RegExp(r'\.$'), '')}. No se '
              'pidió ninguna: revisa lo marcado y vuelve a pedir.',
            ),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final herramientas = ref.watch(herramientasParaPedirProvider);
    final yaPedidas = {
      for (final s
          in ref.watch(misPendientesProvider).valueOrNull ??
              const <MiSolicitud>[])
        if (s.esHerramienta) s.nombre,
    };
    final elegidas = _elegidas(
      _agrupar(herramientas.valueOrNull ?? const []),
      yaPedidas,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Pedir herramienta')),
      bottomNavigationBar: _BarraSolicitar(
        cantidad: elegidas.length,
        alSolicitar: () => _solicitar(elegidas),
        alPedirEspecial: _pedidoEspecial,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: _Buscador(
              controlador: _busqueda,
              hint: 'Buscar herramienta',
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(herramientasParaPedirProvider);
                await ref.read(herramientasParaPedirProvider.future);
              },
              child: Contenido<List<Herramienta>>(
                valor: herramientas,
                alReintentar: () =>
                    ref.invalidate(herramientasParaPedirProvider),
                estaVacio: (l) => l.isEmpty,
                vacio: const SingleChildScrollView(
                  physics: AlwaysScrollableScrollPhysics(),
                  child: Vacio(
                    icono: Icons.handyman_outlined,
                    titulo: 'La empresa no tiene herramientas cargadas',
                    detalle:
                        'Usa el botón de abajo para pedir la que necesitas y '
                        'bodega la consigue.',
                  ),
                ),
                constructor: (lista) {
                  final grupos = _agrupar(
                    lista.where(
                      (h) =>
                          _coincide(h.nombre, _busqueda.text) ||
                          _coincide(h.categoria, _busqueda.text),
                    ),
                  );
                  if (grupos.isEmpty) {
                    return Vacio(
                      icono: Icons.search_off,
                      titulo: 'Nada con “${_busqueda.text.trim()}”',
                      detalle:
                          'Si no la tenemos, pídela con el botón de abajo y '
                          'bodega la consigue.',
                    );
                  }
                  // Las que se pueden llevar hoy, arriba.
                  final orden = grupos.entries.toList()
                    ..sort((a, b) {
                      final da = a.value.any((h) => h.disponible) ? 0 : 1;
                      final db = b.value.any((h) => h.disponible) ? 0 : 1;
                      return da != db ? da - db : a.key.compareTo(b.key);
                    });
                  return ListView(
                    padding: AppEspacio.pantalla,
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      for (final e in orden) ...[
                        _filaDeGrupo(
                          e.key,
                          e.value,
                          yaPedidas,
                          elegidas: elegidas.length,
                        ),
                        const SizedBox(height: AppEspacio.sm),
                      ],
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _alternar(String nombre, {required int elegidas}) {
    if (_marcados.remove(nombre)) {
      setState(() {});
      return;
    }
    if (elegidas >= PedidoHerramienta.maximoHerramientas) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              'Hasta ${PedidoHerramienta.maximoHerramientas} herramientas por '
              'pedido. Pide estas primero y después el resto.',
            ),
          ),
        );
      return;
    }
    setState(() => _marcados.add(nombre));
  }

  Widget _filaDeGrupo(
    String nombre,
    List<Herramienta> grupo,
    Set<String> yaPedidas, {
    required int elegidas,
  }) {
    final quedan = grupo.where((h) => h.disponible).length;
    final yaPedida = yaPedidas.contains(nombre);
    return _FilaHerramientaMarcable(
      titulo: nombre,
      detalle: quedan == 0
          ? '${grupo.first.categoria} · ninguna en bodega'
          : '${grupo.first.categoria} · '
                '${quedan == 1 ? 'queda 1' : 'quedan $quedan'}',
      yaPedida: yaPedida,
      agotada: quedan == 0,
      marcada: !yaPedida && quedan > 0 && _marcados.contains(nombre),
      onTap: quedan == 0
          ? () => _pedidoEspecial(herramienta: grupo.first)
          : yaPedida
          ? null
          : () => _alternar(nombre, elegidas: elegidas),
    );
  }
}

/// Cómo terminó la hoja del pedido.
sealed class _SalidaPedido {
  const _SalidaPedido();
}

class _PedidoCreado extends _SalidaPedido {
  const _PedidoCreado(this.pedido);

  final PedidoHerramienta pedido;
}

/// El backend lo rechazó entero —es todo o nada— porque algo de lo marcado
/// ya no estaba disponible.
class _PedidoEnConflicto extends _SalidaPedido {
  const _PedidoEnConflicto(this.mensaje);

  final String mensaje;
}

/// Pie fijo de la lista: el envío de lo marcado y, aparte, el pedido especial.
class _BarraSolicitar extends StatelessWidget {
  const _BarraSolicitar({
    required this.cantidad,
    required this.alSolicitar,
    required this.alPedirEspecial,
  });

  final int cantidad;
  final VoidCallback alSolicitar;
  final VoidCallback alPedirEspecial;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.card,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FilledButton.icon(
                onPressed: cantidad == 0 ? null : alSolicitar,
                icon: const Icon(Icons.qr_code_2, size: 20),
                label: Text('Solicitar ($cantidad)'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
              ),
              TextButton.icon(
                onPressed: alPedirEspecial,
                icon: const Icon(Icons.add_shopping_cart_outlined, size: 18),
                label: const Text('Pedir una que no hay'),
                style: TextButton.styleFrom(
                  minimumSize: const Size.fromHeight(44),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HojaPedidoHerramientas extends ConsumerStatefulWidget {
  const _HojaPedidoHerramientas({
    required this.elegidas,
    required this.paraQue,
  });

  final List<Herramienta> elegidas;
  final TextEditingController paraQue;

  @override
  ConsumerState<_HojaPedidoHerramientas> createState() =>
      _HojaPedidoHerramientasState();
}

class _HojaPedidoHerramientasState
    extends ConsumerState<_HojaPedidoHerramientas> {
  final _formKey = GlobalKey<FormState>();
  bool _enviando = false;
  String? _error;
  final _intento = IntentoIdempotente();

  Future<void> _enviar() async {
    if (_enviando) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    final ids = widget.elegidas.map((h) => h.id).toList()..sort();
    final paraQue = widget.paraQue.text.trim();
    setState(() {
      _enviando = true;
      _error = null;
    });
    try {
      final pedido = await ref
          .read(pedidosHerramientaApiProvider)
          .crear(
            herramientaIds: ids,
            descripcion: paraQue,
            clave: _intento.clavePara([...ids, paraQue]),
          );
      recargarTrabajador(ref);
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      Navigator.of(context).pop(_PedidoCreado(pedido));
    } on ApiException catch (e) {
      if (e.statusCode == 409) {
        // Otra persona se llevó alguna mientras se miraba la lista. El pedido
        // es todo o nada, así que no quedó ninguna pedida: se recarga y se
        // vuelve a la lista para que se vea qué cambió.
        recargarTrabajador(ref);
        if (mounted) Navigator.of(context).pop(_PedidoEnConflicto(e.mensaje));
        return;
      }
      if (mounted) setState(() => _error = mensajeDeError(e));
    } catch (e) {
      if (mounted) setState(() => _error = mensajeDeError(e));
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.elegidas.length;
    return _Hoja(
      enviando: _enviando,
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              n == 1 ? 'Pedir 1 herramienta' : 'Pedir $n herramientas',
              style: AppTexto.subtitulo,
            ),
            const SizedBox(height: AppEspacio.sm),
            for (final h in widget.elegidas)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    const Icon(
                      Icons.check,
                      size: 18,
                      color: AppColors.accentFill,
                    ),
                    const SizedBox(width: AppEspacio.sm),
                    Expanded(
                      child: Text(
                        h.nombre,
                        style: AppTexto.cuerpo.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            Text(
              'Te daremos un código QR. Muéstralo en bodega y te las '
              'entregan todas juntas, con su fecha de devolución.',
              style: AppTexto.cuerpoChico,
            ),
            const SizedBox(height: 16),
            CampoParaQue(
              controlador: widget.paraQue,
              habilitado: !_enviando,
              hint: 'Ej.: perforar losa del 5º piso para la tabiquería',
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              MensajeError(mensaje: _error!),
            ],
            const SizedBox(height: 12),
            BotonEnvio(
              texto: 'Pedir y generar QR',
              textoEnviando: 'Enviando…',
              enviando: _enviando,
              alPresionar: _enviar,
            ),
          ],
        ),
      ),
    );
  }
}

/// Una herramienta (un grupo del mismo nombre) que se marca para el pedido.
class _FilaHerramientaMarcable extends StatelessWidget {
  const _FilaHerramientaMarcable({
    required this.titulo,
    required this.detalle,
    required this.yaPedida,
    required this.agotada,
    required this.marcada,
    required this.onTap,
  });

  final String titulo;
  final String detalle;
  final bool yaPedida;

  /// No queda en bodega: tocarla abre el pedido especial y no se marca.
  final bool agotada;
  final bool marcada;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final apagada = agotada || yaPedida;
    return Semantics(
      checked: apagada ? null : marcada,
      child: PanelTocable(
        semanticLabel:
            '$titulo. $detalle.${yaPedida ? ' Ya la pediste.' : ''} '
            '${agotada
                ? 'Tocar para pedir que la consigan'
                : yaPedida
                ? ''
                : 'Tocar para ${marcada ? 'desmarcar' : 'marcar'}'}',
        onTap: onTap,
        color: marcada
            ? AppColors.accentTint
            : apagada
            ? AppColors.background
            : AppColors.card,
        borderColor: marcada ? AppColors.accentFill : AppColors.borderControl,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    titulo,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      color: apagada ? AppColors.textMuted : AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(detalle, style: AppTexto.dato),
                  if (yaPedida) ...[
                    const SizedBox(height: AppEspacio.sm),
                    ChipEstado.aviso('Ya la pediste'),
                  ],
                ],
              ),
            ),
            const SizedBox(width: AppEspacio.sm),
            if (agotada)
              Text(
                'Pedir que\nla consigan',
                textAlign: TextAlign.end,
                style: AppTexto.dato.copyWith(
                  fontSize: 11.5,
                  color: AppColors.accentFill,
                ),
              )
            else
              Checkbox(
                value: marcada,
                onChanged: onTap == null ? null : (_) => onTap!(),
              ),
          ],
        ),
      ),
    );
  }
}

/// Hoja inferior que sube con el teclado y no se cierra con la solicitud en
/// vuelo: saldría sin saber si quedó registrada.
class _Hoja extends StatelessWidget {
  const _Hoja({required this.enviando, required this.child});

  final bool enviando;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !enviando,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Una fila de algo que se puede pedir.
class _FilaElegible extends StatelessWidget {
  const _FilaElegible({
    required this.titulo,
    required this.detalle,
    required this.yaPedido,
    required this.onTap,
  });

  final String titulo;
  final String detalle;
  final bool yaPedido;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return PanelTocable(
      semanticLabel:
          '$titulo. $detalle.${yaPedido ? ' Ya lo tienes pedido.' : ''} '
          'Tocar para solicitar',
      onTap: onTap,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(detalle, style: AppTexto.dato),
                if (yaPedido) ...[
                  const SizedBox(height: AppEspacio.sm),
                  ChipEstado.aviso('Ya lo pediste'),
                ],
              ],
            ),
          ),
          const SizedBox(width: AppEspacio.sm),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: const BoxDecoration(
              color: AppColors.accentTint,
              borderRadius: AppForma.borde,
            ),
            child: const Text(
              'Solicitar',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.accentFill,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
