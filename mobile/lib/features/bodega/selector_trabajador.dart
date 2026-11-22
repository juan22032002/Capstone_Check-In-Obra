import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../data/modelos/trabajador.dart';
import '../../shared_widgets/estados.dart';
import '../../shared_widgets/panel.dart';
import 'bodega_providers.dart';

/// Elegir a quién se le entrega o se le presta.
///
/// Muestra siempre nombre **y** RUT: en una obra hay dos Marcelos y el nombre
/// solo no basta para firmar una entrega.
class SelectorTrabajador extends ConsumerWidget {
  const SelectorTrabajador({
    super.key,
    required this.elegido,
    required this.alElegir,
    this.habilitado = true,
    this.obligatorio = true,
  });

  final Trabajador? elegido;
  final void Function(Trabajador?) alElegir;
  final bool habilitado;
  final bool obligatorio;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trabajadores = ref.watch(trabajadoresDeObraProvider);

    if (elegido != null) {
      return PanelTocable(
        semanticLabel: 'Recibe ${elegido!.identificacion}. Tocar para cambiar',
        onTap: habilitado ? () => _abrir(context, ref) : null,
        borderColor: AppColors.accentFill,
        child: Row(
          children: [
            Iniciales(elegido!.nombre, tamano: 38),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    elegido!.nombre,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    elegido!.rut ?? 'sin RUT registrado',
                    style: TextStyle(
                      fontFamily: AppTheme.monoFamily,
                      fontSize: 12,
                      color: elegido!.rut == null
                          ? AppColors.warningDark
                          : AppColors.secondary,
                    ),
                  ),
                ],
              ),
            ),
            const Text(
              'Cambiar',
              style: TextStyle(fontSize: 12.5, color: AppColors.accentFill),
            ),
          ],
        ),
      );
    }

    return Contenido<List<Trabajador>>(
      valor: trabajadores,
      alReintentar: () => ref.invalidate(trabajadoresDeObraProvider),
      estaVacio: (l) => l.isEmpty,
      vacio: const Panel(
        color: AppColors.warningTint,
        borderColor: AppColors.warning,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExcludeSemantics(
              child: Icon(
                Icons.groups_outlined,
                size: 20,
                color: AppColors.warningDark,
              ),
            ),
            SizedBox(width: 11),
            Expanded(
              child: Text(
                'Esta obra no tiene trabajadores con cuadrilla asignada. Un '
                'administrador debe crearles la cuadrilla antes de poder '
                'entregarles material o herramientas.',
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.4,
                  color: AppColors.warningInk,
                ),
              ),
            ),
          ],
        ),
      ),
      constructor: (_) => PanelTocable(
        semanticLabel: 'Elegir el trabajador que recibe',
        onTap: habilitado ? () => _abrir(context, ref) : null,
        borderColor: obligatorio ? AppColors.borderControl : AppColors.border,
        child: Row(
          children: [
            const Icon(
              Icons.person_search_outlined,
              size: 22,
              color: AppColors.secondary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                obligatorio
                    ? 'Elegir quién recibe'
                    : 'Elegir quién recibe (opcional)',
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.textMuted,
                ),
              ),
            ),
            const Icon(
              Icons.chevron_right,
              size: 22,
              color: AppColors.secondary,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _abrir(BuildContext context, WidgetRef ref) async {
    final lista = ref.read(trabajadoresDeObraProvider).valueOrNull ?? const [];
    if (lista.isEmpty) return;

    final elegido = await showModalBottomSheet<Trabajador>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 18, 16, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '¿Quién recibe?',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: lista.length,
                separatorBuilder: (_, _) =>
                    const Divider(height: 1, color: AppColors.border),
                itemBuilder: (_, i) {
                  final t = lista[i];
                  return ListTile(
                    leading: Iniciales(t.nombre, tamano: 38),
                    title: Text(t.nombre),
                    subtitle: Text(
                      t.rut ?? 'sin RUT registrado',
                      style: TextStyle(
                        fontFamily: AppTheme.monoFamily,
                        fontSize: 12,
                        color: t.rut == null
                            ? AppColors.warningDark
                            : AppColors.secondary,
                      ),
                    ),
                    onTap: () => Navigator.of(context).pop(t),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (elegido != null) alElegir(elegido);
  }
}
