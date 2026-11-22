import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_forma.dart';
import '../core/theme/movimiento.dart';
import 'presion.dart';

/// Una opción de un grupo excluyente: el tipo de movimiento, el filtro de la
/// bodega, la categoría del catálogo, el catálogo a importar.
///
/// Antes había cuatro copias de este control, cada una con su relleno y su
/// borde. La elegida se rellena en pizarra y no en naranjo: el acento queda
/// para el botón que confirma, que suele estar en la misma pantalla.
///
/// El color lo pone el `Material` —que lo funde solo al cambiar— y no una
/// decoración encima del `InkWell`, que taparía el splash.
class Opcion extends StatelessWidget {
  const Opcion({
    super.key,
    required this.texto,
    required this.elegida,
    required this.alTocar,
    this.semanticLabel,
    this.expandida = false,
  });

  final String texto;
  final bool elegida;
  final VoidCallback? alTocar;
  final String? semanticLabel;

  /// Ocupa el ancho que le den y centra el texto (segmentos de igual ancho).
  /// Si no, mide lo que su texto (chips de filtro en una fila desplazable).
  final bool expandida;

  @override
  Widget build(BuildContext context) {
    final duracion = Movimiento.de(context, Movimiento.estado);
    return Semantics(
      button: true,
      selected: elegida,
      enabled: alTocar != null,
      label: semanticLabel ?? texto,
      excludeSemantics: true,
      child: Presionable(
        habilitado: alTocar != null,
        child: Material(
          color: elegida ? AppColors.primary : AppColors.card,
          animationDuration: duracion,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: AppForma.borde,
            side: BorderSide(
              color: elegida ? AppColors.primary : AppColors.borderControl,
            ),
          ),
          child: InkWell(
            onTap: alTocar,
            child: ConstrainedBox(
              // 44 px: el mínimo para acertar con guantes.
              constraints: const BoxConstraints(minHeight: 44),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Align(
                  alignment: Alignment.center,
                  widthFactor: expandida ? null : 1,
                  heightFactor: 1,
                  child: AnimatedDefaultTextStyle(
                    duration: duracion,
                    curve: Movimiento.salida,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.2,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.15,
                      color: elegida ? Colors.white : AppColors.textMuted,
                    ),
                    child: Text(texto, softWrap: false),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
