import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../data/modelos/obra.dart';
import '../../shared_widgets/estados.dart';
import '../../shared_widgets/panel.dart';
import 'obra_activa.dart';

/// Primera pregunta al entrar: en qué obra se está.
///
/// Nada del sistema —stock, herramientas, alertas— existe fuera de una obra,
/// así que no hay una pantalla útil que mostrar antes de responderla.
class PantallaElegirObra extends ConsumerWidget {
  const PantallaElegirObra({super.key, this.puedeVolver = false});

  /// `true` cuando se llega desde el selector, con una obra ya elegida.
  final bool puedeVolver;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final obras = ref.watch(obrasActivasProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Elige la obra'),
        automaticallyImplyLeading: puedeVolver,
      ),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: () async => ref.refresh(obrasActivasProvider.future),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'Todo lo que registres —stock, préstamos, alertas— queda '
                'asociado a esta obra. Puedes cambiarla desde el encabezado.',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.45,
                  color: AppColors.textMuted,
                ),
              ),
              const SizedBox(height: 18),
              Contenido<List<Obra>>(
                valor: obras,
                alReintentar: () => ref.invalidate(obrasActivasProvider),
                estaVacio: (lista) => lista.isEmpty,
                vacio: const Vacio(
                  icono: Icons.domain_disabled_outlined,
                  titulo: 'No hay obras activas',
                  detalle:
                      'Un administrador tiene que crear la obra antes de que '
                      'se pueda registrar movimiento en ella.',
                ),
                constructor: (lista) => Column(
                  children: [
                    for (final obra in lista) ...[
                      _FilaObra(obra: obra),
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

class _FilaObra extends ConsumerWidget {
  const _FilaObra({required this.obra});

  final Obra obra;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PanelTocable(
      semanticLabel: 'Trabajar en ${obra.nombre}, cliente ${obra.cliente}',
      onTap: () async {
        await ref.read(obraActivaProvider.notifier).elegir(obra);
        if (context.mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      },
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  obra.nombre,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  obra.cliente,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.textMuted,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  obra.ubicacion,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.secondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          const Icon(Icons.chevron_right, size: 22, color: AppColors.secondary),
        ],
      ),
    );
  }
}
