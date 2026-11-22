import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formato.dart';
import '../../core/network/errores.dart';
import '../../core/network/idempotencia.dart';
import '../../core/theme/app_colors.dart';
import '../../data/api/dominio_api.dart';
import '../../data/modelos/alerta.dart';
import '../../shared_widgets/estados.dart';
import '../../shared_widgets/panel.dart';
import 'bodega_providers.dart';

/// Alertas de la obra.
///
/// Al abrirla se dispara la detección en el backend: no hay tareas
/// programadas, así que las alertas nacen cuando alguien mira. Es una decisión
/// del sistema, no un descuido — pero significa que esta pantalla es la que
/// las crea, y por eso tarda un poco más en cargar que las demás.
class PantallaAlertas extends ConsumerWidget {
  const PantallaAlertas({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alertas = ref.watch(alertasProvider);

    return RefreshIndicator(
      onRefresh: () async => ref.refresh(alertasProvider.future),
      child: Contenido<List<Alerta>>(
        valor: alertas,
        alReintentar: () => ref.invalidate(alertasProvider),
        estaVacio: (l) => l.isEmpty,
        vacio: const SingleChildScrollView(
          child: Vacio(
            icono: Icons.notifications_none,
            titulo: 'Sin alertas',
            detalle:
                'No hay herramientas sin devolver ni materiales bajo el '
                'mínimo en esta obra.',
          ),
        ),
        constructor: (lista) {
          final sinResolver = lista.where((a) => !a.resuelto).toList();
          final resueltas = lista.where((a) => a.resuelto).toList();

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (sinResolver.isEmpty)
                const Panel(
                  color: AppColors.successTint,
                  borderColor: AppColors.success,
                  child: Row(
                    children: [
                      ExcludeSemantics(
                        child: Icon(
                          Icons.check_circle_outline,
                          size: 20,
                          color: AppColors.successDark,
                        ),
                      ),
                      SizedBox(width: 11),
                      Expanded(
                        child: Text(
                          'Todo resuelto en esta obra.',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.successDark,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              else
                for (final a in sinResolver) ...[
                  _FilaAlerta(alerta: a),
                  const SizedBox(height: 10),
                ],
              if (resueltas.isNotEmpty) ...[
                const SizedBox(height: 14),
                Etiqueta('Resueltas · ${resueltas.length}'),
                const SizedBox(height: 8),
                for (final a in resueltas.take(10)) ...[
                  _FilaAlerta(alerta: a),
                  const SizedBox(height: 8),
                ],
              ],
            ],
          );
        },
      ),
    );
  }
}

class _FilaAlerta extends ConsumerStatefulWidget {
  const _FilaAlerta({required this.alerta});

  final Alerta alerta;

  @override
  ConsumerState<_FilaAlerta> createState() => _FilaAlertaState();
}

class _FilaAlertaState extends ConsumerState<_FilaAlerta> {
  bool _enviando = false;
  final _intento = IntentoIdempotente();

  Future<void> _resolver() async {
    if (_enviando) return;
    setState(() => _enviando = true);
    try {
      await ref
          .read(alertasApiProvider)
          .resolver(
            widget.alerta.id,
            clave: _intento.clavePara([widget.alerta.id]),
          );
      ref.invalidate(alertasProvider);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(mensajeDeError(e))));
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.alerta;
    final color = switch (a.tipo) {
      'NO_DEVUELTA' => AppColors.destructive,
      'STOCK_CRITICO' => AppColors.warning,
      _ => AppColors.secondary,
    };

    return Panel(
      color: a.resuelto ? AppColors.background : AppColors.card,
      borderIzquierdo: a.resuelto ? null : color,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (a.resuelto)
                ChipEstado.neutro(nombreDeAlerta(a.tipo))
              else
                switch (a.tipo) {
                  'NO_DEVUELTA' => ChipEstado.critico(nombreDeAlerta(a.tipo)),
                  'STOCK_CRITICO' => ChipEstado.aviso(nombreDeAlerta(a.tipo)),
                  _ => ChipEstado.neutro(nombreDeAlerta(a.tipo)),
                },
              const Spacer(),
              Text(
                Formato.antiguedad(a.fecha),
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.secondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Text(
            a.mensaje,
            style: TextStyle(
              fontSize: 14.5,
              height: 1.45,
              color: a.resuelto ? AppColors.secondary : AppColors.primary,
            ),
          ),
          if (!a.resuelto) ...[
            const SizedBox(height: 12),
            // Compacto y a la derecha: con tres alertas seguidas, tres botones
            // de ancho completo pesaban más que las alertas. 44 px de alto
            // sigue siendo el mínimo para acertar con guantes.
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                onPressed: _enviando ? null : _resolver,
                icon: _enviando
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.done, size: 18),
                label: Text(
                  _enviando ? 'Resolviendo…' : 'Marcar como resuelta',
                ),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 44),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  textStyle: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.1,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
