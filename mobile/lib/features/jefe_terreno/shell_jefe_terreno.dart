import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../auth/sesion_controller.dart';
import '../bodega/bodega_providers.dart';
import '../../shared_widgets/barra_pestanas.dart';
import '../cubicacion/pantalla_partidas.dart';
import '../obra/obra_activa.dart';
import '../obra/pantalla_elegir_obra.dart';
import '../presupuesto/pantalla_presupuesto.dart';

/// La app del jefe de terreno.
///
/// Como la del bodeguero, trabaja sobre una obra: partidas y presupuesto son
/// *de una obra*, así que hay que elegirla antes de mostrar nada.
class ShellJefeTerreno extends ConsumerStatefulWidget {
  const ShellJefeTerreno({super.key});

  @override
  ConsumerState<ShellJefeTerreno> createState() => _ShellJefeTerrenoState();
}

class _ShellJefeTerrenoState extends ConsumerState<ShellJefeTerreno> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final obra = ref.watch(obraActivaProvider);

    if (obra.isLoading && !obra.hasValue) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: AppColors.accentFill),
        ),
      );
    }
    if (obra.valueOrNull == null) return const PantallaElegirObra();

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const _TituloObra(),
        actions: [
          IconButton(
            tooltip: 'Cerrar sesión',
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(sesionProvider.notifier).salir(),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: IndexedStack(
          index: _tab,
          children: const [PantallaPartidas(), PantallaPresupuesto()],
        ),
      ),
      bottomNavigationBar: BarraDePestanas(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.straighten_outlined),
            selectedIcon: Icon(Icons.straighten),
            label: 'Partidas',
          ),
          NavigationDestination(
            icon: Icon(Icons.request_quote_outlined),
            selectedIcon: Icon(Icons.request_quote),
            label: 'Presupuesto',
          ),
        ],
      ),
    );
  }
}

/// Nombre de la obra en curso, tocable para cambiarla.
class _TituloObra extends ConsumerWidget {
  const _TituloObra();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final obra = ref.watch(obraEnCursoProvider);

    return Semantics(
      button: true,
      label: 'Obra ${obra?.nombre ?? ''}. Tocar para cambiar de obra',
      excludeSemantics: true,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const PantallaElegirObra(puedeVolver: true),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Jefe de terreno · Obra',
                    style: AppTexto.dato.copyWith(color: AppColors.secondary),
                  ),
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.unfold_more,
                    size: 14,
                    color: AppColors.secondary,
                  ),
                ],
              ),
              Text(
                obra?.nombre ?? 'Sin obra',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTexto.titulo.copyWith(fontSize: 19),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
