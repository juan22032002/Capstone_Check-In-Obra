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
import '../../data/modelos/pedido_especial.dart';
import '../../data/modelos/solicitud.dart';
import '../../shared_widgets/globo_texto.dart';
import '../../shared_widgets/panel.dart';
import 'trabajador_providers.dart';

/// Chip del estado de algo que pidió, visto por quien lo pidió.
Widget chipDeSolicitud(MiSolicitud s) => switch (s.estado) {
  'PENDIENTE' => ChipEstado.aviso('Pendiente'),
  'EN_GESTION' => ChipEstado.aviso('Consiguiéndolo'),
  'LISTO_PARA_RETIRO' => ChipEstado.exito('Listo para retirar'),
  // Bodega ya se lo pasó: falta que él lo confirme.
  'APROBADA' || 'ENTREGADO' => ChipEstado.exito('Entregado, por confirmar'),
  'ENTREGADA' || 'RECIBIDO' => ChipEstado.neutro('Recibido'),
  'RECHAZADA' ||
  'RECHAZADO' => ChipEstado.critico('Rechazado', conPunto: false),
  _ => ChipEstado.neutro(
    s.esEspecial
        ? nombreDeEstadoPedido(s.estado)
        : nombreDeEstadoSolicitud(s.estado),
  ),
};

/// Algo que pidió: del catálogo o un pedido especial.
///
/// Mientras nadie lo atiende se puede retirar desde acá —pedir de más o
/// equivocarse de material es común—. Cuando bodega se lo entrega, la fila
/// pide que confirme que lo recibió: hasta entonces, para el sistema sigue en
/// el aire.
class FilaMiSolicitud extends ConsumerStatefulWidget {
  const FilaMiSolicitud({super.key, required this.solicitud});

  final MiSolicitud solicitud;

  @override
  ConsumerState<FilaMiSolicitud> createState() => _FilaMiSolicitudState();
}

class _FilaMiSolicitudState extends ConsumerState<FilaMiSolicitud> {
  bool _enviando = false;
  final _intento = IntentoIdempotente();

  Future<void> _cancelar() async {
    final s = widget.solicitud;
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Retirar la solicitud?'),
        content: Text(
          '${s.nombre} (${s.cantidad}). Bodega ya no la verá en su cola. Si '
          'la necesitas después, tendrás que pedirla de nuevo.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('No, mantenerla'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Retirar'),
          ),
        ],
      ),
    );
    if (confirmado != true) return;
    await _ejecutar(
      accion: 'cancelar',
      llamada: (clave) => switch (s.origen) {
        OrigenSolicitud.material =>
          ref.read(solicitudesApiProvider).cancelarMaterial(s.id, clave: clave),
        OrigenSolicitud.herramienta =>
          ref
              .read(solicitudesApiProvider)
              .cancelarHerramienta(s.id, clave: clave),
        OrigenSolicitud.especial =>
          ref.read(pedidosEspecialesApiProvider).cancelar(s.id, clave: clave),
      },
      exito: 'Retiraste la solicitud de ${s.nombre}',
      // Si bodega se adelantó, no hay nada que corregir: se refresca para
      // que se vea en qué quedó.
      codigosYaResueltos: const {'YA_RESUELTA', 'TRANSICION_INVALIDA'},
    );
  }

  Future<void> _confirmar() async {
    final s = widget.solicitud;
    await _ejecutar(
      accion: 'confirmar',
      llamada: (clave) => switch (s.origen) {
        OrigenSolicitud.material =>
          ref
              .read(solicitudesApiProvider)
              .confirmarRecepcionMaterial(s.id, clave: clave),
        OrigenSolicitud.herramienta =>
          ref
              .read(solicitudesApiProvider)
              .confirmarRecepcionHerramienta(s.id, clave: clave),
        OrigenSolicitud.especial =>
          ref
              .read(pedidosEspecialesApiProvider)
              .confirmarRecepcion(s.id, clave: clave),
      },
      exito: 'Confirmaste que recibiste ${s.nombre}',
      // Un doble toque o un reintento tras un timeout: ya estaba confirmada.
      codigosYaResueltos: const {'NO_ENTREGADA', 'TRANSICION_INVALIDA'},
    );
  }

  Future<void> _ejecutar({
    required String accion,
    required Future<Object?> Function(String clave) llamada,
    required String exito,
    required Set<String> codigosYaResueltos,
  }) async {
    if (_enviando) return;
    final s = widget.solicitud;
    setState(() => _enviando = true);
    try {
      await llamada(_intento.clavePara([accion, s.origen, s.id]));
      recargarTrabajador(ref);
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(exito)));
    } catch (e) {
      if (e is ApiException && codigosYaResueltos.contains(e.codigo)) {
        recargarTrabajador(ref);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(mensajeDeError(e))));
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.solicitud;
    return Panel(
      borderIzquierdo: s.rechazada
          ? AppColors.destructive
          : s.porConfirmar
          ? AppColors.success
          : null,
      color: s.porConfirmar ? AppColors.successTint : AppColors.card,
      borderColor: s.porConfirmar ? AppColors.success : AppColors.border,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _IconoTipo(esHerramienta: s.esHerramienta),
              const SizedBox(width: AppEspacio.sm + 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.nombre,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        s.cantidad,
                        if (s.esEspecial) 'pedido especial',
                        if (s.fecha != null) Formato.relativa(s.fecha!),
                      ].join(' · '),
                      style: AppTexto.dato,
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (s.entregado case final entregado?) ...[
            const SizedBox(height: AppEspacio.sm),
            _Entregado(
              entregado: entregado,
              pedido: s.cantidad,
              parcial: s.entregaParcial,
            ),
          ],
          if (s.descripcion case final para? when para.isNotEmpty) ...[
            const SizedBox(height: AppEspacio.sm),
            GloboTexto(texto: para),
          ],
          if (s.notaBodega case final nota? when nota.isNotEmpty) ...[
            const SizedBox(height: AppEspacio.sm),
            Text(
              '${s.resueltoPorNombre ?? 'Bodega'}: “$nota”',
              style: AppTexto.cuerpoChico.copyWith(color: AppColors.primary),
            ),
          ],
          const SizedBox(height: AppEspacio.sm + 2),
          Row(
            children: [
              chipDeSolicitud(s),
              const Spacer(),
              if (s.cancelable)
                TextButton(
                  onPressed: _enviando ? null : _cancelar,
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.textMuted,
                    minimumSize: const Size(0, 40),
                  ),
                  child: Text(_enviando ? 'Retirando…' : 'Retirar'),
                ),
            ],
          ),
          if (s.porConfirmar) ...[
            const SizedBox(height: AppEspacio.sm + 2),
            FilledButton.icon(
              onPressed: _enviando ? null : _confirmar,
              icon: _enviando
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.check, size: 20),
              label: Text(_enviando ? 'Confirmando…' : 'Lo recibí'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(46),
                backgroundColor: AppColors.successDark,
              ),
            ),
          ],
          if (s.rechazada && s.motivoRechazo != null) ...[
            const SizedBox(height: AppEspacio.sm),
            Text(
              '${s.resueltoPorNombre ?? 'Bodega'}: “${s.motivoRechazo}”',
              style: AppTexto.cuerpoChico.copyWith(
                color: AppColors.destructiveDark,
              ),
            ),
          ] else if (!s.enEspera &&
              !s.porConfirmar &&
              !s.retirada &&
              s.resueltoPorNombre != null) ...[
            const SizedBox(height: AppEspacio.xs),
            Text('Atendió ${s.resueltoPorNombre}', style: AppTexto.dato),
          ],
        ],
      ),
    );
  }
}

/// Cuánto le entregó bodega. Si fue menos de lo pedido se dice junto a lo
/// que pidió, para que no confirme "lo recibí" creyendo que llegó todo.
class _Entregado extends StatelessWidget {
  const _Entregado({
    required this.entregado,
    required this.pedido,
    required this.parcial,
  });

  final String entregado;
  final String pedido;
  final bool parcial;

  @override
  Widget build(BuildContext context) {
    final color = parcial ? AppColors.warningDark : AppColors.successDark;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          parcial ? Icons.info_outline : Icons.check_circle_outline,
          size: 18,
          color: color,
        ),
        const SizedBox(width: AppEspacio.sm),
        Expanded(
          child: Text(
            parcial
                ? 'Te entregaron $entregado de $pedido que pediste.'
                : 'Te entregaron $entregado.',
            style: AppTexto.cuerpoChico.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _IconoTipo extends StatelessWidget {
  const _IconoTipo({required this.esHerramienta});

  final bool esHerramienta;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: esHerramienta ? 'Herramienta' : 'Material',
      child: Container(
        width: 36,
        height: 36,
        decoration: const BoxDecoration(
          color: AppColors.sunken,
          borderRadius: AppForma.borde,
        ),
        child: Icon(
          esHerramienta ? Icons.handyman_outlined : Icons.inventory_2_outlined,
          size: 19,
          color: AppColors.secondary,
        ),
      ),
    );
  }
}

/// Un préstamo propio: qué herramienta, desde cuándo y hasta cuándo.
///
/// El vencido se dice con todas sus letras y en rojo: es el que genera la
/// alerta en bodega y el que hay que devolver hoy.
class FilaPrestamo extends StatelessWidget {
  const FilaPrestamo({super.key, required this.prestamo});

  final Prestamo prestamo;

  @override
  Widget build(BuildContext context) {
    final p = prestamo;
    final devuelve = p.fechaDevolEsperada;

    final (Widget chip, String detalle) = switch (p) {
      Prestamo(abierto: false) => (
        ChipEstado.neutro('Devuelta'),
        p.fechaDevolReal == null
            ? 'Devuelta'
            : 'Devuelta ${Formato.relativa(p.fechaDevolReal!)}',
      ),
      Prestamo(vencido: true) => (
        ChipEstado.critico('Vencida'),
        'Debías devolverla ${Formato.relativa(devuelve!)}',
      ),
      _ => (
        ChipEstado.exito('En tu poder'),
        devuelve == null
            ? 'Sin fecha de devolución'
            : 'Devuélvela ${Formato.relativa(devuelve)}',
      ),
    };

    return Panel(
      borderIzquierdo: p.vencido ? AppColors.destructive : null,
      color: p.abierto ? AppColors.card : AppColors.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _IconoTipo(esHerramienta: true),
              const SizedBox(width: AppEspacio.sm + 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.herramientaNombre,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      detalle,
                      style: AppTexto.dato.copyWith(
                        color: p.vencido
                            ? AppColors.destructiveDark
                            : AppColors.secondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppEspacio.sm + 2),
          // El chip va abajo y no junto al nombre: ahí le quitaba ancho y
          // "Rotomartillo Bosch GBH" se partía en dos líneas.
          Row(
            children: [
              chip,
              const SizedBox(width: AppEspacio.sm),
              if (p.fechaPrestamo != null)
                Expanded(
                  child: Text(
                    'Entregó ${p.autorizadoPorNombre} · '
                    '${Formato.relativa(p.fechaPrestamo!)}',
                    textAlign: TextAlign.end,
                    style: AppTexto.dato.copyWith(fontSize: 11.5),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
