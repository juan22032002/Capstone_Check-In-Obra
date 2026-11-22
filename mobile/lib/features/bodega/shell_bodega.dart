import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../shared_widgets/barra_pestanas.dart';
import '../../shared_widgets/panel.dart';
import '../auth/sesion_controller.dart';
import '../obra/obra_activa.dart';
import '../obra/pantalla_elegir_obra.dart';
import 'bodega_providers.dart';
import 'pantalla_alertas.dart';
import 'pantalla_bodega.dart';
import 'pantalla_escaneo.dart';
import 'pantalla_herramientas.dart';
import 'pantalla_inicio_bodega.dart';

/// La app del bodeguero: cuatro pestañas y una obra.
///
/// Antes de mostrarlas hay que saber en qué obra se está — stock, herramientas
/// y alertas son todos *de una obra*, así que sin ella no hay nada que dibujar.
class ShellBodega extends ConsumerStatefulWidget {
  const ShellBodega({super.key, this.comoAdmin = false});

  /// El ADMIN también puede operar bodega (matriz de permisos del README).
  /// Cuando entra por acá, la pantalla se lo recuerda y le deja volver.
  final bool comoAdmin;

  @override
  ConsumerState<ShellBodega> createState() => _ShellBodegaState();
}

class _ShellBodegaState extends ConsumerState<ShellBodega> {
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
    if (obra.valueOrNull == null) {
      return PantallaElegirObra(puedeVolver: widget.comoAdmin);
    }

    final sinResolver =
        ref.watch(alertasSinResolverProvider).valueOrNull?.length ?? 0;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: widget.comoAdmin,
        title: _TituloObra(comoAdmin: widget.comoAdmin),
        actions: [
          // El escaneo de credencial está en el encabezado y no solo en el
          // inicio: es la acción que se dispara con el trabajador enfrente, y
          // puede pasar estando en cualquier pestaña.
          IconButton(
            tooltip: 'Escanear la credencial o el pedido de un trabajador',
            icon: const Icon(Icons.qr_code_scanner),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const PantallaEscaneoCredencial(),
              ),
            ),
          ),
          if (!widget.comoAdmin)
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
          children: [
            PantallaInicioBodega(alIrA: (i) => setState(() => _tab = i)),
            const PantallaBodega(),
            const PantallaHerramientas(),
            const PantallaAlertas(),
          ],
        ),
      ),
      bottomNavigationBar: BarraDePestanas(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Inicio',
          ),
          const NavigationDestination(
            icon: Icon(Icons.inventory_2_outlined),
            selectedIcon: Icon(Icons.inventory_2),
            label: 'Bodega',
          ),
          const NavigationDestination(
            icon: Icon(Icons.handyman_outlined),
            selectedIcon: Icon(Icons.handyman),
            label: 'Herram.',
          ),
          NavigationDestination(
            // El número va en el badge y no como texto suelto para que el
            // lector de pantalla lo anuncie junto a "Alertas" y no aparte.
            icon: Badge(
              isLabelVisible: sinResolver > 0,
              label: Text('$sinResolver'),
              backgroundColor: AppColors.destructive,
              child: const Icon(Icons.notifications_none),
            ),
            selectedIcon: Badge(
              isLabelVisible: sinResolver > 0,
              label: Text('$sinResolver'),
              backgroundColor: AppColors.destructive,
              child: const Icon(Icons.notifications),
            ),
            label: 'Alertas',
          ),
        ],
      ),
    );
  }
}

/// Nombre de la obra en curso, tocable para cambiarla.
class _TituloObra extends ConsumerWidget {
  const _TituloObra({required this.comoAdmin});

  final bool comoAdmin;

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
                    comoAdmin ? 'Bodega, vista de administrador' : 'Obra',
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

/// Encabezado de sección reutilizado por las pantallas del shell.
class TituloDeSeccion extends StatelessWidget {
  const TituloDeSeccion(this.texto, {super.key});

  final String texto;

  @override
  Widget build(BuildContext context) => Etiqueta(texto);
}
