import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formato.dart';
import '../../core/network/errores.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_forma.dart';
import '../../core/theme/app_theme.dart';
import '../../data/modelos/detalle_obra.dart';
import '../../shared_widgets/panel.dart';
import '../bodega/bodega_providers.dart';
import '../bodega/pantalla_bodega.dart';

/// Aviso de falta de materiales, arriba del catálogo.
///
/// El catálogo es de la empresa y el stock es de cada obra, así que el aviso
/// dice **dónde** falta: "Volcanita ST 10 · Los Almendros". Un "stock bajo"
/// sin la obra obligaría a abrir cada una para saber a cuál mandar material.
///
/// No aparece si no falta nada: un panel verde de "todo bien" encima de cada
/// visita al catálogo se deja de leer a la semana, y entonces tampoco se lee
/// el día que se pone rojo.
class AvisoFaltantes extends ConsumerWidget {
  const AvisoFaltantes({super.key});

  /// Cuántos se listan dentro del panel antes de mandar a la hoja completa.
  static const _visibles = 3;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final faltantes = ref.watch(faltantesProvider);

    return faltantes.when(
      skipLoadingOnRefresh: true,
      loading: () => const SizedBox.shrink(),
      // Un fallo acá no tapa el catálogo, pero tampoco se calla: sin esta
      // línea, "no hay aviso" y "no se pudo revisar" se verían igual.
      error: (e, _) => Padding(
        padding: const EdgeInsets.only(bottom: AppEspacio.md),
        child: Row(
          children: [
            const Icon(
              Icons.sync_problem,
              size: 18,
              color: AppColors.warningDark,
            ),
            const SizedBox(width: AppEspacio.sm),
            Expanded(
              child: Text(
                'No se pudo revisar el stock de las obras. ${mensajeDeError(e)}',
                style: AppTexto.cuerpoChico,
              ),
            ),
            TextButton(
              onPressed: () => ref.invalidate(faltantesProvider),
              child: const Text('Reintentar'),
            ),
          ],
        ),
      ),
      data: (lista) {
        if (lista.isEmpty) return const SizedBox.shrink();
        final criticos = lista.where((f) => f.critico).length;
        final bajos = lista.length - criticos;
        final obras = lista.map((f) => f.obraId).toSet().length;
        final hayCritico = criticos > 0;

        return Padding(
          padding: const EdgeInsets.only(bottom: AppEspacio.lg),
          child: Semantics(
            liveRegion: true,
            child: PanelTocable(
              semanticLabel:
                  'Falta de materiales: ${_resumen(criticos, bajos, obras)}. '
                  'Tocar para ver el detalle por obra',
              color: hayCritico
                  ? AppColors.destructiveTint
                  : AppColors.warningTint,
              borderColor: hayCritico
                  ? AppColors.destructive
                  : AppColors.warning,
              onTap: () => _verTodos(context, lista),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        hayCritico
                            ? Icons.error_outline
                            : Icons.warning_amber_rounded,
                        size: 22,
                        color: hayCritico
                            ? AppColors.destructiveDark
                            : AppColors.warningDark,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Falta de materiales',
                          style: AppTexto.subtitulo.copyWith(
                            color: hayCritico
                                ? AppColors.destructiveDark
                                : AppColors.warningInk,
                          ),
                        ),
                      ),
                      Icon(
                        Icons.chevron_right,
                        color: hayCritico
                            ? AppColors.destructiveDark
                            : AppColors.warningDark,
                      ),
                    ],
                  ),
                  const SizedBox(height: AppEspacio.xs),
                  Text(
                    _resumen(criticos, bajos, obras),
                    style: AppTexto.cuerpoChico.copyWith(
                      color: hayCritico
                          ? AppColors.destructiveDark
                          : AppColors.warningInk,
                    ),
                  ),
                  const SizedBox(height: AppEspacio.sm + 4),
                  for (final f in lista.take(_visibles)) ...[
                    _FilaFaltante(faltante: f, compacta: true),
                    const SizedBox(height: AppEspacio.sm),
                  ],
                  if (lista.length > _visibles)
                    Text(
                      'y ${lista.length - _visibles} más',
                      style: AppTexto.rotulo.copyWith(
                        color: hayCritico
                            ? AppColors.destructiveDark
                            : AppColors.warningInk,
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  static String _resumen(int criticos, int bajos, int obras) {
    final partes = [
      if (criticos > 0) '$criticos bajo el mínimo',
      if (bajos > 0) '$bajos por agotarse',
    ];
    return '${partes.join(' y ')} en $obras ${obras == 1 ? 'obra' : 'obras'}';
  }

  static void _verTodos(BuildContext context, List<MaterialFaltante> lista) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _HojaFaltantes(lista: lista),
    );
  }
}

/// Todos los faltantes, agrupados por obra: es como se reparte la compra.
class _HojaFaltantes extends StatelessWidget {
  const _HojaFaltantes({required this.lista});

  final List<MaterialFaltante> lista;

  @override
  Widget build(BuildContext context) {
    final porObra = <String, List<MaterialFaltante>>{};
    for (final f in lista) {
      porObra.putIfAbsent(f.obraNombre, () => []).add(f);
    }

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.92,
      builder: (context, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
        children: [
          Text('Falta de materiales', style: AppTexto.titulo),
          const SizedBox(height: AppEspacio.xs),
          Text(
            'Materiales bajo el mínimo o a menos de un 25 % de llegar a él, '
            'en cada obra activa.',
            style: AppTexto.cuerpoChico,
          ),
          for (final e in porObra.entries) ...[
            const SizedBox(height: AppEspacio.lg),
            Etiqueta('${e.key} (${e.value.length})'),
            const SizedBox(height: AppEspacio.sm + 4),
            for (final f in e.value) ...[
              Panel(
                borderIzquierdo: f.critico
                    ? AppColors.destructive
                    : AppColors.warning,
                child: _FilaFaltante(faltante: f, compacta: false),
              ),
              const SizedBox(height: AppEspacio.sm),
            ],
          ],
        ],
      ),
    );
  }
}

class _FilaFaltante extends StatelessWidget {
  const _FilaFaltante({required this.faltante, required this.compacta});

  final MaterialFaltante faltante;

  /// Dentro del aviso va la obra en la misma línea; en la hoja ya está en el
  /// encabezado del grupo.
  final bool compacta;

  @override
  Widget build(BuildContext context) {
    final f = faltante;
    final unidad = unidadDe(f.categoria);
    final tinta = f.critico ? AppColors.destructiveDark : AppColors.warningInk;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                f.nombre,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: compacta ? tinta : AppColors.primary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                compacta ? f.obraNombre : f.sku,
                style: AppTexto.dato.copyWith(
                  color: compacta ? tinta : AppColors.secondary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: AppEspacio.sm),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '${Formato.cantidad(f.stock)} $unidad',
              style: TextStyle(
                fontFeatures: AppTexto.tabulares,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: compacta ? tinta : AppColors.primary,
              ),
            ),
            const SizedBox(height: 2),
            if (compacta)
              Text(
                'mín. ${Formato.cantidad(f.stockMinimo)}',
                style: AppTexto.dato.copyWith(color: tinta),
              )
            else
              _ChipFaltante(critico: f.critico, minimo: f.stockMinimo),
          ],
        ),
      ],
    );
  }
}

class _ChipFaltante extends StatelessWidget {
  const _ChipFaltante({required this.critico, required this.minimo});

  final bool critico;
  final double minimo;

  @override
  Widget build(BuildContext context) {
    final texto = 'mín. ${Formato.cantidad(minimo)}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: critico ? AppColors.destructiveTint : AppColors.warningTint,
        borderRadius: AppForma.bordeChip,
      ),
      child: Text(
        texto,
        style: AppTexto.dato.copyWith(
          fontSize: 11.5,
          color: critico ? AppColors.destructiveDark : AppColors.warningDark,
        ),
      ),
    );
  }
}
