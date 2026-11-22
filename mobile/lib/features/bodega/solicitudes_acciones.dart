import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formato.dart';
import '../../core/network/errores.dart';
import '../../core/network/idempotencia.dart';
import '../../data/api/auth_api.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../data/api/dominio_api.dart';
import '../../data/modelos/solicitud.dart';
import '../../shared_widgets/campo_texto.dart';
import '../../shared_widgets/estados.dart';
import '../../shared_widgets/globo_texto.dart';
import '../../shared_widgets/panel.dart';
import '../../shared_widgets/presion.dart';
import '../auth/sesion_controller.dart';
import 'bodega_providers.dart';
import 'pantalla_bodega.dart';

/// Las filas de solicitud y las dos acciones que las resuelven.
///
/// Están en un archivo aparte porque las usan dos pantallas distintas: la cola
/// de la obra entera y la del trabajador que acaba de mostrar su credencial.
/// Aprobar tiene que hacer exactamente lo mismo en las dos.

/// Una solicitud de material, con lo que hace falta para decidirla: cuánto se
/// pidió y cuánto queda en bodega. Sin el saldo al lado, aprobar es a ciegas.
class FilaSolicitudMaterial extends ConsumerWidget {
  const FilaSolicitudMaterial({
    super.key,
    required this.solicitud,
    this.mostrarTrabajador = true,
  });

  final SolicitudMaterial solicitud;

  /// En la pantalla del trabajador escaneado sobra: ya está en el encabezado.
  final bool mostrarTrabajador;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final saldos = ref.watch(stockPorMaterialProvider).valueOrNull;
    final stock = saldos?[solicitud.materialId];
    final alcanza = stock == null || stock >= solicitud.cantidad;
    // La unidad ("pl", "tira", "un") sale de la categoría del catálogo. Se
    // resuelve una vez: recorrerlo dos veces por fila multiplica el barrido en
    // una lista de solicitudes.
    final unidad = unidadDe(_categoriaDe(ref, solicitud.materialId));

    return Panel(
      borderIzquierdo: solicitud.pendiente
          ? (alcanza ? AppColors.warning : AppColors.destructive)
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _ChipDeEstado(estado: solicitud.estado),
              const SizedBox(width: 8),
              const ChipEstado(
                texto: 'Material',
                fondo: AppColors.sunken,
                textoColor: AppColors.textMuted,
              ),
              const Spacer(),
              if (solicitud.fechaSolicitud case final fecha?)
                Text(
                  Formato.antiguedad(fecha),
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.secondary,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            solicitud.materialNombre,
            style: const TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w600,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${solicitud.materialSku} · pidió '
            '${Formato.cantidad(solicitud.cantidad)} $unidad',
            style: const TextStyle(
              fontFamily: AppTheme.monoFamily,
              fontSize: 12.5,
              color: AppColors.secondary,
            ),
          ),
          if (mostrarTrabajador) ...[
            const SizedBox(height: 6),
            _Quien(
              nombre: solicitud.trabajadorNombre,
              rut: solicitud.trabajadorRut,
            ),
          ],
          // Para qué lo pidió: es lo que permite decidir sin ir a preguntar.
          if (solicitud.descripcion case final para? when para.isNotEmpty) ...[
            const SizedBox(height: 8),
            GloboTexto(texto: para),
          ],
          if (stock != null && solicitud.pendiente) ...[
            const SizedBox(height: 8),
            _SaldoDisponible(
              stock: stock,
              pedido: solicitud.cantidad,
              unidad: unidad,
            ),
          ],
          if (solicitud.motivoRechazo case final motivo?) ...[
            const SizedBox(height: 8),
            Text(
              'Rechazada: $motivo',
              style: const TextStyle(
                fontSize: 12.5,
                height: 1.35,
                color: AppColors.destructiveDark,
              ),
            ),
          ],
          if (solicitud.pendiente) ...[
            const SizedBox(height: 12),
            _Acciones(
              alAprobar: () => aprobarMaterial(context, solicitud),
              alRechazar: () => rechazarSolicitud(
                context,
                titulo: 'Rechazar ${solicitud.materialNombre}',
                alConfirmar: (motivo, clave) => ref
                    .read(solicitudesApiProvider)
                    .rechazarMaterial(
                      solicitud.id,
                      motivo: motivo,
                      clave: clave,
                    ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// La categoría del material en el catálogo, que ya está cargado para el
  /// stock. Si todavía no llegó se devuelve vacía, y `unidadDe` cae en la
  /// unidad genérica en vez de dejar el número desnudo.
  String _categoriaDe(WidgetRef ref, int materialId) {
    final catalogo = ref.watch(catalogoProvider).valueOrNull;
    if (catalogo == null) return '';
    for (final m in catalogo) {
      if (m.id == materialId) return m.categoria;
    }
    return '';
  }
}

/// Una solicitud de herramienta. Aprobarla genera el préstamo, así que lo único
/// que falta preguntar es hasta cuándo.
class FilaSolicitudHerramienta extends ConsumerWidget {
  const FilaSolicitudHerramienta({
    super.key,
    required this.solicitud,
    this.mostrarTrabajador = true,
  });

  final SolicitudHerramienta solicitud;
  final bool mostrarTrabajador;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final herramienta = ref
        .watch(herramientasProvider)
        .valueOrNull
        ?.where((h) => h.id == solicitud.herramientaId)
        .firstOrNull;
    final disponible = herramienta?.disponible ?? true;

    return Panel(
      borderIzquierdo: solicitud.pendiente
          ? (disponible ? AppColors.warning : AppColors.destructive)
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _ChipDeEstado(estado: solicitud.estado),
              const SizedBox(width: 8),
              const ChipEstado(
                texto: 'Herramienta',
                fondo: AppColors.sunken,
                textoColor: AppColors.textMuted,
              ),
              const Spacer(),
              if (solicitud.fechaSolicitud case final fecha?)
                Text(
                  Formato.antiguedad(fecha),
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.secondary,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            solicitud.herramientaNombre,
            style: const TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w600,
              color: AppColors.primary,
            ),
          ),
          if (herramienta != null) ...[
            const SizedBox(height: 4),
            Text(
              '${herramienta.codigoQr} · reposición '
              '${Formato.pesos(herramienta.valorReposicion)}',
              style: const TextStyle(
                fontFamily: AppTheme.monoFamily,
                fontSize: 12.5,
                color: AppColors.secondary,
              ),
            ),
          ],
          if (mostrarTrabajador) ...[
            const SizedBox(height: 6),
            _Quien(
              nombre: solicitud.trabajadorNombre,
              rut: solicitud.trabajadorRut,
            ),
          ],
          // Para qué lo pidió: es lo que permite decidir sin ir a preguntar.
          if (solicitud.descripcion case final para? when para.isNotEmpty) ...[
            const SizedBox(height: 8),
            GloboTexto(texto: para),
          ],
          if (solicitud.pendiente && !disponible) ...[
            const SizedBox(height: 8),
            const _Aviso(
              mensaje:
                  'Esta herramienta no está en bodega: sigue prestada o está '
                  'en mantención. Aprobar va a fallar hasta que vuelva.',
            ),
          ],
          if (solicitud.motivoRechazo case final motivo?) ...[
            const SizedBox(height: 8),
            Text(
              'Rechazada: $motivo',
              style: const TextStyle(
                fontSize: 12.5,
                height: 1.35,
                color: AppColors.destructiveDark,
              ),
            ),
          ],
          // La que va en un pedido con QR se entrega junto con las demás al
          // escanear el código: aprobarla o rechazarla sola da 409 EN_PEDIDO.
          if (solicitud.pendiente && solicitud.pedidoId != null) ...[
            const SizedBox(height: 8),
            const _Aviso(
              mensaje:
                  'Va en un pedido con QR. Se entrega junto con las demás '
                  'cuando el trabajador muestre el código en el mesón.',
            ),
          ] else if (solicitud.pendiente) ...[
            const SizedBox(height: 12),
            _Acciones(
              alAprobar: () => aprobarHerramienta(context, solicitud),
              alRechazar: () => rechazarSolicitud(
                context,
                titulo: 'Rechazar ${solicitud.herramientaNombre}',
                alConfirmar: (motivo, clave) => ref
                    .read(solicitudesApiProvider)
                    .rechazarHerramienta(
                      solicitud.id,
                      motivo: motivo,
                      clave: clave,
                    ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Aprobar material: se pregunta cuánto se entrega, no se asume lo pedido.
///
/// El backend despacha exactamente la cantidad que se le manda, y en bodega
/// pasa seguido que no alcanza para todo: entregar 30 de las 36 planchas
/// pedidas es una decisión legítima y frecuente. Si se aprobara siempre por lo
/// pedido, esa entrega parcial habría que registrarla después a mano y el
/// kardex quedaría diciendo otra cosa.
Future<void> aprobarMaterial(
  BuildContext context,
  SolicitudMaterial solicitud,
) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _HojaAprobarMaterial(solicitud: solicitud),
  );
}

/// Aprobar herramienta: se pregunta hasta cuándo, que es lo que después vence.
Future<void> aprobarHerramienta(
  BuildContext context,
  SolicitudHerramienta solicitud,
) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _HojaAprobarHerramienta(solicitud: solicitud),
  );
}

/// Rechazar con motivo obligatorio.
///
/// El motivo no es burocracia: es lo único que el trabajador va a ver en su
/// teléfono para entender por qué no le entregaron lo que pidió.
Future<void> rechazarSolicitud(
  BuildContext context, {
  required String titulo,
  required Future<void> Function(String motivo, String clave) alConfirmar,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _HojaRechazo(titulo: titulo, alConfirmar: alConfirmar),
  );
}

class _HojaAprobarMaterial extends ConsumerStatefulWidget {
  const _HojaAprobarMaterial({required this.solicitud});

  final SolicitudMaterial solicitud;

  @override
  ConsumerState<_HojaAprobarMaterial> createState() =>
      _HojaAprobarMaterialState();
}

class _HojaAprobarMaterialState extends ConsumerState<_HojaAprobarMaterial> {
  late final _cantidad = TextEditingController(
    text: Formato.cantidad(widget.solicitud.cantidad),
  );
  bool _enviando = false;
  String? _error;
  final _intento = IntentoIdempotente();

  @override
  void initState() {
    super.initState();
    // "Saldo tras el despacho" tiene que seguir a lo que se escribe: es justo
    // cuando alguien baja de 36 a 30 planchas que necesita verlo.
    _cantidad.addListener(_alCambiarCantidad);
  }

  void _alCambiarCantidad() => setState(() {});

  @override
  void dispose() {
    _cantidad.removeListener(_alCambiarCantidad);
    _cantidad.dispose();
    super.dispose();
  }

  double get _valor => Formato.numero(_cantidad.text) ?? 0;

  Future<void> _aprobar() async {
    if (_enviando) return;
    final sesion = ref.read(sesionProvider).valueOrNull;
    if (sesion == null) return;

    if (_valor <= 0) {
      setState(() => _error = 'Escribe una cantidad mayor a cero.');
      return;
    }
    // Entregar de menos es una entrega parcial y se permite; de más, no: el
    // backend lo rechaza con un 400 (S-17).
    if (_valor > widget.solicitud.cantidad) {
      setState(
        () => _error =
            'No puedes entregar más de lo pedido '
            '(${Formato.cantidad(widget.solicitud.cantidad)}).',
      );
      return;
    }

    setState(() {
      _enviando = true;
      _error = null;
    });

    try {
      await ref
          .read(solicitudesApiProvider)
          .aprobarMaterial(
            widget.solicitud.id,
            cantidadAEntregar: _valor,
            clave: _intento.clavePara([widget.solicitud.id, _valor]),
          );

      recargarBodega(ref);
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Entregadas ${Formato.cantidad(_valor)} de '
            '${widget.solicitud.materialNombre} a '
            '${widget.solicitud.trabajadorNombre}',
          ),
        ),
      );
    } catch (e) {
      // Un 409 acá es stock insuficiente (el backend no deja el saldo
      // negativo aunque la solicitud sea legítima) o que el trabajador no es de
      // la obra (`OBRA_NO_ASIGNADA`, `SIN_CUADRILLA`). Ninguno se arregla
      // reintentando: se muestra el mensaje del servidor.
      if (!mounted) return;
      if (_yaResuelta(context, ref, e)) return;
      setState(() => _error = mensajeDeError(e));
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final stock = ref
        .watch(stockPorMaterialProvider)
        .valueOrNull?[widget.solicitud.materialId];
    final quedaria = stock == null ? null : stock - _valor;

    return _Hoja(
      titulo: 'Aprobar y despachar',
      enviando: _enviando,
      children: [
        Text(
          widget.solicitud.materialNombre,
          style: const TextStyle(
            fontSize: 14.5,
            fontWeight: FontWeight.w600,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${widget.solicitud.trabajadorNombre} pidió '
          '${Formato.cantidad(widget.solicitud.cantidad)}'
          '${stock == null ? '' : ' · en bodega ${Formato.cantidad(stock)}'}',
          style: const TextStyle(fontSize: 12.5, color: AppColors.secondary),
        ),
        const SizedBox(height: 18),
        CampoConEtiqueta(
          etiqueta: 'Cantidad que se entrega',
          campo: CampoTexto(
            controlador: _cantidad,
            hint: '0',
            icono: Icons.tag,
            mono: true,
            teclado: const TextInputType.numberWithOptions(decimal: true),
            formatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
            habilitado: !_enviando,
            alEnviar: (_) => _aprobar(),
          ),
          ayuda:
              'Puede ser menos de lo pedido si no alcanza. El despacho queda '
              'en el kardex a nombre de quien lo pidió.',
        ),
        if (quedaria != null) ...[
          const SizedBox(height: 14),
          _SaldoResultante(saldo: quedaria),
        ],
        if (_error != null) ...[
          const SizedBox(height: 14),
          MensajeError(mensaje: _error!),
        ],
        const SizedBox(height: 20),
        BotonEnvio(
          texto: 'Aprobar y despachar',
          textoEnviando: 'Despachando…',
          enviando: _enviando,
          alPresionar: _aprobar,
        ),
      ],
    );
  }
}

class _HojaAprobarHerramienta extends ConsumerStatefulWidget {
  const _HojaAprobarHerramienta({required this.solicitud});

  final SolicitudHerramienta solicitud;

  @override
  ConsumerState<_HojaAprobarHerramienta> createState() =>
      _HojaAprobarHerramientaState();
}

class _HojaAprobarHerramientaState
    extends ConsumerState<_HojaAprobarHerramienta> {
  // Fin del turno: es lo que pasa en la mayoría de los préstamos, así que el
  // caso común no obliga a tocar nada.
  late DateTime _devolucion = devolucionPorDefecto(DateTime.now());

  bool _enviando = false;
  String? _error;
  final _intento = IntentoIdempotente();

  Future<void> _aprobar() async {
    if (_enviando) return;
    final sesion = ref.read(sesionProvider).valueOrNull;
    if (sesion == null) return;

    // Una devolución en el pasado haría nacer el préstamo vencido, con su
    // alerta, antes de que la herramienta salga de bodega.
    if (!_devolucion.isAfter(DateTime.now())) {
      setState(
        () => _error =
            'La devolución esperada ya pasó. Elige una fecha y hora futuras.',
      );
      return;
    }

    setState(() {
      _enviando = true;
      _error = null;
    });

    try {
      await ref
          .read(solicitudesApiProvider)
          .aprobarHerramienta(
            widget.solicitud.id,
            fechaDevolEsperada: _devolucion,
            clave: _intento.clavePara([widget.solicitud.id, _devolucion]),
          );

      recargarBodega(ref);
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${widget.solicitud.herramientaNombre} entregada a '
            '${widget.solicitud.trabajadorNombre}',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      if (_yaResuelta(context, ref, e)) return;
      setState(() => _error = mensajeDeError(e));
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _Hoja(
      titulo: 'Aprobar y prestar',
      enviando: _enviando,
      children: [
        Text(
          widget.solicitud.herramientaNombre,
          style: const TextStyle(
            fontSize: 14.5,
            fontWeight: FontWeight.w600,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'La recibe ${widget.solicitud.trabajadorNombre}',
          style: const TextStyle(fontSize: 12.5, color: AppColors.secondary),
        ),
        const SizedBox(height: 18),
        CampoDevolucion(
          valor: _devolucion,
          habilitado: !_enviando,
          alCambiar: (d) => setState(() {
            _devolucion = d;
            _error = null;
          }),
        ),
        if (_error != null) ...[
          const SizedBox(height: 14),
          MensajeError(mensaje: _error!),
        ],
        const SizedBox(height: 20),
        BotonEnvio(
          texto: 'Aprobar y prestar',
          textoEnviando: 'Autorizando…',
          enviando: _enviando,
          alPresionar: _aprobar,
        ),
      ],
    );
  }
}

class _HojaRechazo extends ConsumerStatefulWidget {
  const _HojaRechazo({required this.titulo, required this.alConfirmar});

  final String titulo;
  final Future<void> Function(String motivo, String clave) alConfirmar;

  @override
  ConsumerState<_HojaRechazo> createState() => _HojaRechazoState();
}

class _HojaRechazoState extends ConsumerState<_HojaRechazo> {
  final _motivo = TextEditingController();
  bool _enviando = false;
  String? _error;
  final _intento = IntentoIdempotente();

  /// Los motivos que se repiten en bodega. Tocarlos llena el campo, que se
  /// puede seguir editando: con guantes, escribir es lo último que uno quiere.
  static const _frecuentes = [
    'No hay stock suficiente',
    'La herramienta está en mantención',
    'Falta autorización del jefe de terreno',
    'Ya se le entregó hoy',
  ];

  @override
  void dispose() {
    _motivo.dispose();
    super.dispose();
  }

  Future<void> _rechazar() async {
    if (_enviando) return;
    final sesion = ref.read(sesionProvider).valueOrNull;
    if (sesion == null) return;

    final motivo = _motivo.text.trim();
    if (motivo.isEmpty) {
      setState(
        () => _error =
            'Escribe el motivo: es lo único que el trabajador va a ver.',
      );
      return;
    }

    setState(() {
      _enviando = true;
      _error = null;
    });

    try {
      await widget.alConfirmar(motivo, _intento.clavePara([motivo]));
      recargarBodega(ref);
      if (!mounted) return;
      HapticFeedback.lightImpact();
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Solicitud rechazada')));
    } catch (e) {
      if (!mounted) return;
      if (_yaResuelta(context, ref, e)) return;
      setState(() => _error = mensajeDeError(e));
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _Hoja(
      titulo: widget.titulo,
      enviando: _enviando,
      children: [
        CampoConEtiqueta(
          etiqueta: 'Motivo del rechazo',
          campo: CampoTexto(
            controlador: _motivo,
            hint: 'Por qué no se entrega',
            icono: Icons.edit_note,
            habilitado: !_enviando,
            alEnviar: (_) => _rechazar(),
          ),
          ayuda: 'Queda guardado y es lo que ve el trabajador en su teléfono.',
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final frase in _frecuentes)
              ActionChip(
                label: Text(frase, style: const TextStyle(fontSize: 12)),
                onPressed: _enviando
                    ? null
                    : () => setState(() {
                        _motivo.text = frase;
                        _error = null;
                      }),
              ),
          ],
        ),
        if (_error != null) ...[
          const SizedBox(height: 14),
          MensajeError(mensaje: _error!),
        ],
        const SizedBox(height: 20),
        BotonEnvio(
          texto: 'Rechazar solicitud',
          textoEnviando: 'Rechazando…',
          enviando: _enviando,
          alPresionar: _rechazar,
          color: AppColors.destructiveDark,
        ),
      ],
    );
  }
}

/// La devolución esperada de un préstamo, con su selector de fecha y hora.
///
/// La usan aprobar una solicitud y entregar un pedido por QR: las dos crean
/// préstamos y la fecha se elige igual.
class CampoDevolucion extends StatelessWidget {
  const CampoDevolucion({
    super.key,
    required this.valor,
    required this.alCambiar,
    this.habilitado = true,
  });

  final DateTime valor;
  final ValueChanged<DateTime> alCambiar;
  final bool habilitado;

  Future<void> _elegir(BuildContext context) async {
    final ahora = DateTime.now();
    final fecha = await showDatePicker(
      context: context,
      initialDate: valor,
      firstDate: DateTime(ahora.year, ahora.month, ahora.day),
      lastDate: ahora.add(const Duration(days: 90)),
      helpText: 'Devolución esperada',
    );
    if (fecha == null || !context.mounted) return;

    final hora = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(valor),
      helpText: 'Hora de devolución',
    );
    if (!context.mounted) return;

    alCambiar(
      DateTime(
        fecha.year,
        fecha.month,
        fecha.day,
        hora?.hour ?? 18,
        hora?.minute ?? 0,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CampoConEtiqueta(
      etiqueta: 'Devolución esperada',
      campo: PanelTocable(
        semanticLabel:
            'Devolución esperada ${Formato.fechaHora(valor)}. '
            'Tocar para cambiar',
        onTap: habilitado ? () => _elegir(context) : null,
        child: Row(
          children: [
            const Icon(
              Icons.event_outlined,
              size: 22,
              color: AppColors.secondary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                Formato.fechaHora(valor),
                style: const TextStyle(
                  fontFamily: AppTheme.monoFamily,
                  fontSize: 14,
                  color: AppColors.primary,
                ),
              ),
            ),
            const Text(
              'Cambiar',
              style: TextStyle(fontSize: 12.5, color: AppColors.accentFill),
            ),
          ],
        ),
      ),
      ayuda:
          'Pasada esta hora la herramienta aparece como vencida y se genera '
          'una alerta.',
    );
  }
}

/// La devolución que se propone al aprobar: hoy a las 18:00, fin del turno.
///
/// Pasadas las 18:00 —un turno largo, una entrega de último minuto— eso ya es
/// pasado y el préstamo nacería vencido, con alerta incluida. Ahí se propone
/// mañana a la misma hora.
DateTime devolucionPorDefecto(DateTime ahora) {
  final hoy = DateTime(ahora.year, ahora.month, ahora.day, 18);
  if (ahora.isBefore(hoy)) return hoy;
  return DateTime(ahora.year, ahora.month, ahora.day + 1, 18);
}

/// Si el backend dice que la solicitud ya estaba resuelta, no es un error que
/// el bodeguero tenga que corregir: otro se adelantó, o un reintento llegó
/// después de un éxito cuya respuesta se perdió. Se cierra la hoja, se refresca
/// la cola y se dice qué pasó.
bool _yaResuelta(BuildContext context, WidgetRef ref, Object error) {
  if (error is! ApiException || !error.yaEstabaHecho) return false;
  recargarBodega(ref);
  final mensajero = ScaffoldMessenger.of(context);
  Navigator.of(context).pop();
  mensajero.showSnackBar(
    SnackBar(
      content: Text(
        '${error.mensaje.trim().replaceFirst(RegExp(r'\.$'), '')}. '
        'La cola ya está al día.',
      ),
    ),
  );
  return true;
}

/// Envoltorio común de las tres hojas: respeta el teclado y el área segura.
///
/// Mientras se envía no se puede cerrar —ni con atrás ni arrastrando—: si la
/// hoja desaparece con la petición en vuelo, el bodeguero no se entera de si el
/// despacho quedó hecho y la tentación es volver a aprobar.
class _Hoja extends StatelessWidget {
  const _Hoja({
    required this.titulo,
    required this.children,
    this.enviando = false,
  });

  final String titulo;
  final List<Widget> children;
  final bool enviando;

  @override
  Widget build(BuildContext context) {
    return PopScope(canPop: !enviando, child: _cuerpo(context));
  }

  Widget _cuerpo(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                titulo,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 16),
              ...children,
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class _Acciones extends StatelessWidget {
  const _Acciones({required this.alAprobar, required this.alRechazar});

  final VoidCallback alAprobar;
  final VoidCallback alRechazar;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Presionable(
            child: OutlinedButton(
              onPressed: alRechazar,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.destructiveDark,
                side: const BorderSide(color: AppColors.destructive),
              ),
              child: const Text('Rechazar'),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Presionable(
            child: FilledButton(
              onPressed: alAprobar,
              child: const Text('Aprobar'),
            ),
          ),
        ),
      ],
    );
  }
}

class _Quien extends StatelessWidget {
  const _Quien({required this.nombre, required this.rut});

  final String nombre;
  final String? rut;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.person_outline, size: 15, color: AppColors.secondary),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            rut == null ? nombre : '$nombre · $rut',
            style: const TextStyle(fontSize: 12.5, color: AppColors.secondary),
          ),
        ),
      ],
    );
  }
}

class _SaldoDisponible extends StatelessWidget {
  const _SaldoDisponible({
    required this.stock,
    required this.pedido,
    required this.unidad,
  });

  final double stock;
  final double pedido;
  final String unidad;

  @override
  Widget build(BuildContext context) {
    final alcanza = stock >= pedido;
    return Text(
      alcanza
          ? 'En bodega: ${Formato.cantidad(stock)} $unidad'
          : 'Solo quedan ${Formato.cantidad(stock)} $unidad de las '
                '${Formato.cantidad(pedido)} pedidas',
      style: TextStyle(
        fontSize: 12.5,
        height: 1.35,
        color: alcanza ? AppColors.secondary : AppColors.destructiveDark,
      ),
    );
  }
}

class _SaldoResultante extends StatelessWidget {
  const _SaldoResultante({required this.saldo});

  final double saldo;

  @override
  Widget build(BuildContext context) {
    final negativo = saldo < 0;
    return Semantics(
      liveRegion: true,
      child: Panel(
        animado: true,
        color: negativo ? AppColors.destructiveTint : AppColors.background,
        borderColor: negativo ? AppColors.destructive : AppColors.border,
        child: Row(
          children: [
            const Expanded(
              child: Text(
                'Saldo tras el despacho',
                style: TextStyle(fontSize: 12.5, color: AppColors.textMuted),
              ),
            ),
            Text(
              Formato.cantidad(saldo),
              style: TextStyle(
                fontFeatures: AppTexto.tabulares,
                fontFamily: AppTheme.monoFamily,
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: negativo ? AppColors.destructiveDark : AppColors.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Aviso extends StatelessWidget {
  const _Aviso({required this.mensaje});

  final String mensaje;

  @override
  Widget build(BuildContext context) {
    return Text(
      mensaje,
      style: const TextStyle(
        fontSize: 12.5,
        height: 1.35,
        color: AppColors.warningDark,
      ),
    );
  }
}

class _ChipDeEstado extends StatelessWidget {
  const _ChipDeEstado({required this.estado});

  final String estado;

  @override
  Widget build(BuildContext context) => switch (estado) {
    'PENDIENTE' => ChipEstado.aviso('Pendiente'),
    // Aprobada = bodega ya la entregó; Entregada = el trabajador confirmó.
    'APROBADA' => ChipEstado.exito('Entregada, sin confirmar', conPunto: false),
    'ENTREGADA' => ChipEstado.exito('Recibida', conPunto: false),
    'RECHAZADA' => ChipEstado.critico('Rechazada', conPunto: false),
    // Cancelada por el propio trabajador, u otro estado que el backend sume
    // después: gris, no rojo. Antes todo lo que no era pendiente ni aprobada
    // se pintaba como rechazada.
    _ => ChipEstado.neutro(nombreDeEstadoSolicitud(estado)),
  };
}
