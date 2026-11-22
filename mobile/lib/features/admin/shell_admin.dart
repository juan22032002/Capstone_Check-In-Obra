import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_forma.dart';
import '../../core/theme/app_theme.dart';
import '../../data/api/dominio_api.dart';
import '../../data/modelos/usuario.dart';
import '../../shared_widgets/barra_pestanas.dart';
import '../../shared_widgets/estados.dart';
import '../../shared_widgets/fila_accion.dart';
import '../../shared_widgets/panel.dart';
import '../auth/sesion_controller.dart';
import '../bodega/bodega_providers.dart';
import '../bodega/shell_bodega.dart';
import '../obra/obra_activa.dart';
import 'pantalla_importacion.dart';
import 'pantalla_materiales.dart';
import 'pantalla_obras.dart';
import 'pantalla_solicitudes_admin.dart';
import 'pantalla_usuarios.dart';

final empresaProvider = FutureProvider<Empresa>(
  (ref) => ref.watch(empresaApiProvider).mia(),
);

/// La app del administrador: configura la empresa y entra a bodega cuando hace
/// falta.
///
/// El admin no tiene obra activa como el bodeguero — trabaja sobre la empresa
/// entera— así que su shell no exige elegir una. La elige recién al abrir la
/// vista de bodega.
class ShellAdmin extends ConsumerStatefulWidget {
  const ShellAdmin({super.key});

  @override
  ConsumerState<ShellAdmin> createState() => _ShellAdminState();
}

class _ShellAdminState extends ConsumerState<ShellAdmin> {
  int _tab = 0;

  static const _titulos = [
    'Obras',
    'Materiales',
    'Solicitudes',
    'Usuarios',
    'Empresa',
  ];

  @override
  Widget build(BuildContext context) {
    // Pedidos especiales que esperan algo de bodega o del administrador.
    final porAtender =
        ref
            .watch(pedidosEspecialesEmpresaProvider)
            .valueOrNull
            ?.where((p) => p.siguientePaso != null)
            .length ??
        0;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Administración',
              style: AppTexto.dato.copyWith(color: AppColors.secondary),
            ),
            Text(_titulos[_tab], style: AppTexto.titulo.copyWith(fontSize: 19)),
          ],
        ),
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
          children: const [
            PantallaObras(),
            PantallaMateriales(),
            PantallaSolicitudesAdmin(),
            PantallaUsuarios(),
            _PantallaEmpresa(),
          ],
        ),
      ),
      bottomNavigationBar: BarraDePestanas(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.domain_outlined),
            selectedIcon: Icon(Icons.domain),
            label: 'Obras',
          ),
          const NavigationDestination(
            icon: Icon(Icons.category_outlined),
            selectedIcon: Icon(Icons.category),
            label: 'Materiales',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: porAtender > 0,
              label: Text('$porAtender'),
              child: const Icon(Icons.inbox_outlined),
            ),
            selectedIcon: const Icon(Icons.inbox),
            label: 'Solicitudes',
          ),
          const NavigationDestination(
            icon: Icon(Icons.people_outline),
            selectedIcon: Icon(Icons.people),
            label: 'Usuarios',
          ),
          const NavigationDestination(
            icon: Icon(Icons.business_outlined),
            selectedIcon: Icon(Icons.business),
            label: 'Empresa',
          ),
        ],
      ),
    );
  }
}

class _PantallaEmpresa extends ConsumerWidget {
  const _PantallaEmpresa();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final empresa = ref.watch(empresaProvider);
    final sesion = ref.watch(sesionProvider).valueOrNull;
    final obras = ref.watch(todasLasObrasProvider).valueOrNull;
    final materiales = ref.watch(catalogoProvider).valueOrNull;
    final usuarios = ref.watch(usuariosProvider).valueOrNull;

    return RefreshIndicator(
      onRefresh: () async => ref.refresh(empresaProvider.future),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Contenido<Empresa>(
            valor: empresa,
            alReintentar: () => ref.invalidate(empresaProvider),
            constructor: (e) => Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(e.nombre, style: AppTexto.titulo),
                  const SizedBox(height: AppEspacio.xs),
                  Text(e.rut, style: AppTexto.dato.copyWith(fontSize: 13.5)),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppEspacio.sm + 4),
          Panel(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Contador(
                    valor: '${obras?.where((o) => o.activa).length ?? 0}',
                    rotulo: 'Obras\nactivas',
                  ),
                ),
                Expanded(
                  child: Contador(
                    valor: '${usuarios?.length ?? 0}',
                    rotulo: 'Usuarios',
                  ),
                ),
                Expanded(
                  child: Contador(
                    valor: '${materiales?.length ?? 0}',
                    rotulo: 'Materiales',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppEspacio.lg),
          const Etiqueta('Operación'),
          const SizedBox(height: AppEspacio.sm + 4),
          FilaAccion(
            icono: Icons.inventory_2_outlined,
            titulo: 'Vista de bodega',
            detalle:
                'Kardex, herramientas y alertas de una obra. Tu rol incluye '
                'todo lo de bodega.',
            semanticLabel:
                'Abrir la vista de bodega. El administrador puede registrar '
                'movimientos y préstamos igual que un bodeguero',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const ShellBodega(comoAdmin: true),
              ),
            ),
          ),
          const SizedBox(height: AppEspacio.sm + 2),
          FilaAccion(
            icono: Icons.table_view_outlined,
            titulo: 'Importación masiva',
            detalle:
                'Cargar materiales y herramientas nuevos desde una planilla '
                'Excel, en vez de uno por uno.',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const PantallaImportacion()),
            ),
          ),
          const SizedBox(height: AppEspacio.lg),
          const Etiqueta('Sesión'),
          const SizedBox(height: AppEspacio.sm + 4),
          Panel(
            child: Row(
              children: [
                Iniciales(sesion?.nombre ?? '?', tamano: 44),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        sesion?.nombre ?? '',
                        style: AppTexto.subtitulo.copyWith(fontSize: 15),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        nombreDeRol(sesion?.rol ?? ''),
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.secondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
