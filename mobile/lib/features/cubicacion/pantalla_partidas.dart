import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formato.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../data/modelos/partida.dart';
import '../../shared_widgets/estados.dart';
import '../../shared_widgets/panel.dart';
import '../bodega/bodega_providers.dart';
import 'cubicacion_providers.dart';
import 'pantalla_detalle_partida.dart';
import 'pantalla_nueva_partida.dart';

/// Las partidas de la obra en curso (D1) — de acá se entra a cubicar cada una.
class PantallaPartidas extends ConsumerWidget {
  const PantallaPartidas({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final obra = ref.watch(obraEnCursoProvider);
    if (obra == null) return const SizedBox.shrink();
    final partidas = ref.watch(partidasDeObraProvider(obra.id));

    return RefreshIndicator(
      onRefresh: () async =>
          ref.refresh(partidasDeObraProvider(obra.id).future),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Cada partida es un paño de obra con sus medidas. Al cubicarla, '
            'la app calcula qué materiales lleva y cuántos, con merma.',
            style: TextStyle(
              fontSize: 13,
              height: 1.45,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const PantallaNuevaPartida()),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.accentFill,
              ),
              icon: const Icon(Icons.add),
              label: const Text('Nueva partida'),
            ),
          ),
          const SizedBox(height: 18),
          Contenido<List<Partida>>(
            valor: partidas,
            alReintentar: () => ref.invalidate(partidasDeObraProvider(obra.id)),
            estaVacio: (l) => l.isEmpty,
            vacio: const Vacio(
              icono: Icons.straighten,
              titulo: 'Esta obra no tiene partidas',
              detalle:
                  'Crea la primera con sus medidas para poder cubicarla y '
                  'armar el presupuesto.',
            ),
            constructor: (lista) => Column(
              children: [
                for (final p in lista) ...[
                  FilaPartida(partida: p),
                  const SizedBox(height: 10),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class FilaPartida extends StatelessWidget {
  const FilaPartida({
    super.key,
    required this.partida,
    this.alTocar,
    this.etiqueta = 'Ver y cubicar',
  });

  final Partida partida;

  /// Por defecto abre el detalle de la partida; otras pantallas (agregar al
  /// presupuesto) reusan la fila con su propia acción.
  final VoidCallback? alTocar;
  final String etiqueta;

  String get medidas =>
      '${Formato.cantidad(partida.anchoM)} × ${Formato.cantidad(partida.altoM)} m'
      ' · montantes cada ${Formato.cantidad(partida.separacionMontantes)} m';

  @override
  Widget build(BuildContext context) {
    return PanelTocable(
      semanticLabel: '${partida.nombreDelTipo}, $medidas. $etiqueta',
      onTap:
          alTocar ??
          () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => PantallaDetallePartida(partida: partida),
            ),
          ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${partida.nombreDelTipo} #${partida.id}',
                  style: AppTexto.subtitulo,
                ),
                const SizedBox(height: 4),
                Text(
                  medidas,
                  style: AppTexto.cuerpoChico.copyWith(
                    color: AppColors.textMuted,
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
