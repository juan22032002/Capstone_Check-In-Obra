import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_forma.dart';
import '../core/theme/app_theme.dart';

/// El "para qué" de una solicitud, como globo de mensaje: se lee como lo que
/// dijo quien pidió, no como un dato del sistema.
class GloboTexto extends StatelessWidget {
  const GloboTexto({super.key, required this.texto, this.autor});

  final String texto;

  /// Quién lo dijo, cuando no es obvio (en la cola de bodega).
  final String? autor;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Para qué: $texto',
      excludeSemantics: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(12, 9, 12, 10),
        decoration: const BoxDecoration(
          color: AppColors.sunken,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(3),
            topRight: Radius.circular(AppForma.radio),
            bottomLeft: Radius.circular(AppForma.radio),
            bottomRight: Radius.circular(AppForma.radio),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (autor != null)
              Text(
                autor!,
                style: AppTexto.dato.copyWith(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            Text(
              texto,
              style: AppTexto.cuerpoChico.copyWith(
                fontSize: 13.5,
                color: AppColors.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
