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
import '../../data/modelos/pedido_herramienta.dart';
import '../../shared_widgets/estados.dart';
import '../../shared_widgets/globo_texto.dart';
import '../../shared_widgets/panel.dart';
import '../../shared_widgets/presion.dart';
import 'bodega_providers.dart';
import 'solicitudes_acciones.dart';

/// El pedido de herramientas que el trabajador mostró en su teléfono.
///
/// Primero quién es —nombre y RUT en grande— porque el QR se puede
/// fotografiar: el bodeguero mira a la persona antes de entregar. Después lo
/// que se lleva y hasta cuándo. Entregar crea un préstamo por herramienta,
/// todos con la misma devolución esperada.
class PantallaEntregaPedido extends ConsumerStatefulWidget {
  const PantallaEntregaPedido({super.key, required this.pedido});

  final PedidoHerramienta pedido;

  @override
  ConsumerState<PantallaEntregaPedido> createState() =>
      _PantallaEntregaPedidoState();
}

class _PantallaEntregaPedidoState extends ConsumerState<PantallaEntregaPedido> {
  // Fin del turno, igual que al aprobar una solicitud suelta.
  late DateTime _devolucion = devolucionPorDefecto(DateTime.now());

  bool _enviando = false;
  String? _error;

  /// El pedido como se ve ahora. Cambia si al entregar el backend responde
  /// que ya estaba resuelto: se vuelve a leer para decir si se entregó o se
  /// canceló.
  late PedidoHerramienta _pedido = widget.pedido;

  /// Ya estaba resuelto y no se pudo volver a leer cómo: sin más datos, lo
  /// más probable es que otro bodeguero se adelantara, o que un reintento
  /// llegara después de un éxito cuya respuesta se perdió.
  bool _yaEntregado = false;
  final _intento = IntentoIdempotente();

  Future<void> _entregar() async {
    if (_enviando) return;
    // Una devolución en el pasado haría nacer los préstamos vencidos.
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
    final p = _pedido;
    try {
      final entrega = await ref
          .read(pedidosHerramientaApiProvider)
          .entregar(
            p.codigoQr,
            fechaDevolEsperada: _devolucion,
            clave: _intento.clavePara([p.codigoQr, _devolucion]),
          );
      recargarBodega(ref);
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      final n = entrega.prestamos.length;
      final mensajero = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      mensajero.showSnackBar(
        SnackBar(
          content: Text(
            '${n == 1 ? '1 herramienta entregada' : '$n herramientas entregadas'}'
            ' a ${p.trabajador.nombre}',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      if (e is ApiException && e.yaEstabaHecho) {
        recargarBodega(ref);
        await _releer();
        return;
      }
      setState(() => _error = mensajeDeError(e));
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  /// YA_RESUELTA llega tanto si se entregó como si el trabajador lo canceló
  /// mientras esperaba en el mesón: se pregunta cuál fue.
  Future<void> _releer() async {
    try {
      final fresco = await ref
          .read(pedidosHerramientaApiProvider)
          .porQr(_pedido.codigoQr);
      if (!mounted) return;
      setState(() {
        _pedido = fresco;
        _yaEntregado = fresco.pendiente;
      });
    } catch (_) {
      if (mounted) setState(() => _yaEntregado = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _pedido;
    final n = p.solicitudes.length;
    final entregable = p.pendiente && !_yaEntregado;

    return PopScope(
      canPop: !_enviando,
      child: Scaffold(
        appBar: AppBar(title: const Text('Pedido de herramientas')),
        body: SafeArea(
          top: false,
          child: ListView(
            padding: AppEspacio.pantalla,
            children: [
              _Persona(pedido: p),
              const SizedBox(height: AppEspacio.lg),
              Etiqueta(n == 1 ? '1 herramienta' : '$n herramientas'),
              const SizedBox(height: AppEspacio.sm),
              for (final s in p.solicitudes) ...[
                Panel(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.handyman_outlined,
                        size: 20,
                        color: AppColors.secondary,
                      ),
                      const SizedBox(width: AppEspacio.sm + 4),
                      Expanded(
                        child: Text(
                          s.herramientaNombre,
                          style: AppTexto.cuerpo.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppEspacio.sm),
              ],
              if (p.descripcion case final d? when d.trim().isNotEmpty) ...[
                const SizedBox(height: AppEspacio.sm),
                GloboTexto(texto: d),
              ],
              const SizedBox(height: AppEspacio.lg),
              if (entregable) ...[
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
                  texto: 'Entregar ($n)',
                  textoEnviando: 'Entregando…',
                  enviando: _enviando,
                  alPresionar: _entregar,
                ),
              ] else
                _NoEntregable(pedido: p, yaEntregado: _yaEntregado),
            ],
          ),
        ),
      ),
    );
  }
}

class _Persona extends StatelessWidget {
  const _Persona({required this.pedido});

  final PedidoHerramienta pedido;

  @override
  Widget build(BuildContext context) {
    final t = pedido.trabajador;
    return Panel(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      child: Column(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: const BoxDecoration(
              color: AppColors.sunken,
              borderRadius: AppForma.borde,
            ),
            child: const Icon(Icons.badge_outlined, color: AppColors.secondary),
          ),
          const SizedBox(height: AppEspacio.sm + 4),
          Text(
            t.nombre,
            textAlign: TextAlign.center,
            style: AppTexto.titulo.copyWith(fontSize: 22),
          ),
          if (t.rut != null) ...[
            const SizedBox(height: 2),
            Text(
              t.rut!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFeatures: AppTexto.tabulares,
                fontSize: 17,
                fontWeight: FontWeight.w500,
                color: AppColors.textMuted,
              ),
            ),
          ],
          const SizedBox(height: AppEspacio.sm),
          Text(
            'Confirma que es la persona que tienes enfrente.',
            textAlign: TextAlign.center,
            style: AppTexto.cuerpoChico,
          ),
          if (pedido.fechaSolicitud != null) ...[
            const SizedBox(height: 4),
            Text(
              'Pedido ${Formato.relativa(pedido.fechaSolicitud!)}',
              textAlign: TextAlign.center,
              style: AppTexto.dato,
            ),
          ],
        ],
      ),
    );
  }
}

/// Por qué no se ofrece entregar.
class _NoEntregable extends StatelessWidget {
  const _NoEntregable({required this.pedido, required this.yaEntregado});

  final PedidoHerramienta pedido;
  final bool yaEntregado;

  @override
  Widget build(BuildContext context) {
    final String texto;
    if (yaEntregado || pedido.entregado) {
      final quien = pedido.entregadoPorNombre;
      final cuando = pedido.fechaEntrega;
      texto =
          'Este pedido ya se entregó'
          '${cuando == null ? '' : ' ${Formato.relativa(cuando)}'}'
          '${quien == null ? '' : ' por $quien'}. '
          'Las herramientas ya están a nombre del trabajador.';
    } else if (pedido.cancelado) {
      texto =
          'El trabajador canceló este pedido. Si todavía las necesita, '
          'tiene que volver a pedirlas.';
    } else {
      texto = 'Este pedido no se puede entregar: está ${pedido.estado}.';
    }
    return Semantics(
      liveRegion: true,
      child: Panel(
        color: AppColors.warningTint,
        borderColor: AppColors.warning,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.info_outline, color: AppColors.warningDark),
            const SizedBox(width: AppEspacio.sm + 4),
            Expanded(
              child: Text(
                texto,
                style: AppTexto.cuerpoChico.copyWith(
                  fontSize: 14,
                  color: AppColors.warningInk,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
