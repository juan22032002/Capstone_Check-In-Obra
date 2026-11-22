import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_forma.dart';
import '../core/theme/app_theme.dart';
import 'panel.dart';

/// Una tarjeta que lleva a otra pantalla: ícono, qué es, para qué sirve y la
/// flecha que dice que se entra.
///
/// El ícono va en tinta sobre un cuadro hundido y la flecha en gris. Antes los
/// dos iban en naranjo, y con dos o tres de estas tarjetas seguidas el acento
/// dejaba de marcar la acción principal de la pantalla.
class FilaAccion extends StatelessWidget {
  const FilaAccion({
    super.key,
    required this.icono,
    required this.titulo,
    required this.detalle,
    required this.onTap,
    this.semanticLabel,
  });

  final IconData icono;
  final String titulo;
  final String detalle;
  final VoidCallback? onTap;

  /// Si falta, se anuncia el título y el detalle.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return PanelTocable(
      semanticLabel: semanticLabel ?? '$titulo. $detalle',
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(
              color: AppColors.sunken,
              borderRadius: AppForma.borde,
            ),
            child: Icon(icono, size: 21, color: AppColors.primary),
          ),
          const SizedBox(width: AppEspacio.sm + 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titulo, style: AppTexto.subtitulo.copyWith(fontSize: 15)),
                const SizedBox(height: 2),
                Text(
                  detalle,
                  style: AppTexto.cuerpoChico.copyWith(
                    fontSize: 12.5,
                    color: AppColors.secondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppEspacio.sm),
          const Icon(Icons.chevron_right, size: 22, color: AppColors.secondary),
        ],
      ),
    );
  }
}
