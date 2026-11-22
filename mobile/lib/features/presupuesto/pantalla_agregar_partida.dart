import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/errores.dart';
import '../../core/network/idempotencia.dart';
import '../../core/theme/app_colors.dart';
import '../../data/api/dominio_api.dart';
import '../../data/modelos/partida.dart';
import '../../data/modelos/presupuesto.dart';
import '../../shared_widgets/estados.dart';
import '../cubicacion/cubicacion_providers.dart';
import '../cubicacion/pantalla_partidas.dart';
import 'presupuesto_providers.dart';

/// Agrega al presupuesto todos los ítems cubicados de una partida (D5).
///
/// Se elige la partida y el backend hace el resto en una sola transacción:
/// copia la cantidad con merma y toma el precio vigente de cada material. La
/// partida tiene que estar cubicada; si no, el backend lo dice con un 409.
///
/// Agregar dos veces la misma partida duplica los ítems —el backend no
/// deduplica—, por eso un solo envío a la vez y una confirmación que nombra la
/// partida antes de enviar.
class PantallaAgregarPartida extends ConsumerStatefulWidget {
  const PantallaAgregarPartida({super.key, required this.presupuesto});

  final Presupuesto presupuesto;

  @override
  ConsumerState<PantallaAgregarPartida> createState() =>
      _PantallaAgregarPartidaState();
}

class _PantallaAgregarPartidaState
    extends ConsumerState<PantallaAgregarPartida> {
  final _intento = IntentoIdempotente();
  bool _enviando = false;
  String? _error;

  Future<void> _agregar(Partida partida) async {
    if (_enviando) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Agregar ${partida.nombreDelTipo} #${partida.id}'),
        content: const Text(
          'Se agregan todos sus materiales con la cantidad con merma y el '
          'precio vigente del catálogo. Si ya la agregaste antes, quedará '
          'duplicada.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.accentFill,
            ),
            child: const Text('Agregar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() {
      _enviando = true;
      _error = null;
    });
    final presupuestoId = widget.presupuesto.id;
    try {
      final agregados = await ref
          .read(presupuestosApiProvider)
          .agregarDesdePartida(
            presupuestoId,
            partidaId: partida.id,
            clave: _intento.clavePara([presupuestoId, partida.id]),
          );
      _intento.reiniciar();
      ref.invalidate(itemsPresupuestoProvider(presupuestoId));
      ref.invalidate(presupuestoDeObraProvider(widget.presupuesto.obraId));
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      final mensajero = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      mensajero.showSnackBar(
        SnackBar(
          content: Text(
            '${agregados.length} '
            '${agregados.length == 1 ? 'ítem agregado' : 'ítems agregados'} '
            'al presupuesto',
          ),
        ),
      );
    } catch (e) {
      // Un 409 por congelado cambia lo que ofrece la pantalla anterior.
      ref.invalidate(presupuestoDeObraProvider(widget.presupuesto.obraId));
      if (mounted) setState(() => _error = mensajeDeError(e));
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final obraId = widget.presupuesto.obraId;
    final partidas = ref.watch(partidasDeObraProvider(obraId));

    return PopScope(
      canPop: !_enviando,
      child: Scaffold(
        appBar: AppBar(title: const Text('Agregar una partida')),
        body: SafeArea(
          top: false,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'Elige una partida ya cubicada: sus materiales entran al '
                'presupuesto de una vez.',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.45,
                  color: AppColors.textMuted,
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 14),
                MensajeError(mensaje: _error!),
              ],
              const SizedBox(height: 16),
              Contenido<List<Partida>>(
                valor: partidas,
                alReintentar: () =>
                    ref.invalidate(partidasDeObraProvider(obraId)),
                estaVacio: (l) => l.isEmpty,
                vacio: const Vacio(
                  icono: Icons.straighten,
                  titulo: 'Esta obra no tiene partidas',
                  detalle:
                      'Crea y cubica una partida desde la pestaña Partidas.',
                ),
                constructor: (lista) => Column(
                  children: [
                    for (final p in lista) ...[
                      IgnorePointer(
                        ignoring: _enviando,
                        child: Opacity(
                          opacity: _enviando ? 0.5 : 1,
                          child: FilaPartida(
                            partida: p,
                            alTocar: () => _agregar(p),
                            etiqueta: 'Agregar al presupuesto',
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
