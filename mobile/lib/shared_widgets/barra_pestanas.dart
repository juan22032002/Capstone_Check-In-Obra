import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';

/// La barra de pestañas de los dos shells, con la línea fina que la separa del
/// contenido. `NavigationBar` no dibuja borde propio y, sin sombra, el blanco
/// de la barra se fundía con la última tarjeta de la lista.
class BarraDePestanas extends StatelessWidget {
  const BarraDePestanas({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.destinations,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<Widget> destinations;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: onDestinationSelected,
        destinations: destinations,
      ),
    );
  }
}
