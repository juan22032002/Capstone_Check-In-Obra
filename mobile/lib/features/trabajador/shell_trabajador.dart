import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_forma.dart';
import '../../core/theme/app_theme.dart';
import '../../data/api/auth_api.dart';
import '../../data/modelos/perfil_trabajador.dart';
import '../../shared_widgets/barra_pestanas.dart';
import '../../shared_widgets/estados.dart';
import '../auth/sesion_controller.dart';
import 'pantalla_credencial.dart';
import 'pantalla_historial_trabajador.dart';
import 'pantalla_inicio_trabajador.dart';
import 'trabajador_providers.dart';

/// La app del trabajador: pedir, mostrar la credencial y seguir lo suyo.
///
/// Tres pestañas y no más. La credencial va aparte y no dentro de Inicio
/// porque se abre con el bodeguero esperando al otro lado del mesón: tiene que
/// estar a un toque desde cualquier parte.
class ShellTrabajador extends ConsumerStatefulWidget {
  const ShellTrabajador({super.key});

  @override
  ConsumerState<ShellTrabajador> createState() => _ShellTrabajadorState();
}

class _ShellTrabajadorState extends ConsumerState<ShellTrabajador> {
  int _tab = 0;

  static const _titulos = ['Inicio', 'Mi credencial', 'Historial'];

  @override
  Widget build(BuildContext context) {
    final sesion = ref.watch(sesionProvider).valueOrNull;
    final perfil = ref.watch(perfilTrabajadorProvider);
    // Lo que pide acción de él: devolver lo vencido y confirmar lo recibido.
    final vencidos =
        (ref
                .watch(enMiPoderProvider)
                .valueOrNull
                ?.where((p) => p.vencido)
                .length ??
            0) +
        (ref.watch(porConfirmarProvider).valueOrNull?.length ?? 0);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              sesion?.nombre ?? 'Trabajador',
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
        child: Contenido<PerfilTrabajador>(
          valor: perfil,
          alReintentar: () => ref.invalidate(perfilTrabajadorProvider),
          constructor: (p) => IndexedStack(
            index: _tab,
            children: [
              PantallaInicioTrabajador(perfil: p),
              const PantallaCredencial(),
              const PantallaHistorialTrabajador(),
            ],
          ),
        ).conSinFicha(perfil),
      ),
      bottomNavigationBar: BarraDePestanas(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          NavigationDestination(
            icon: Badge(
              isLabelVisible: vencidos > 0,
              label: Text('$vencidos'),
              child: const Icon(Icons.home_outlined),
            ),
            selectedIcon: const Icon(Icons.home),
            label: 'Inicio',
          ),
          const NavigationDestination(
            icon: Icon(Icons.qr_code_2_outlined),
            selectedIcon: Icon(Icons.qr_code_2),
            label: 'Credencial',
          ),
          const NavigationDestination(
            icon: Icon(Icons.history),
            selectedIcon: Icon(Icons.history),
            label: 'Historial',
          ),
        ],
      ),
    );
  }
}

extension on Widget {
  /// Un 404 en `/trabajadores/yo` no es un fallo de red: es un usuario con rol
  /// Trabajador al que nadie le creó la ficha. Reintentar no lo arregla, así
  /// que se dice qué hacer en vez de mostrar el error genérico.
  Widget conSinFicha(AsyncValue<PerfilTrabajador> perfil) {
    if (perfil case AsyncError(:final error)
        when error is ApiException && error.statusCode == 404) {
      return const _SinFicha();
    }
    return this;
  }
}

class _SinFicha extends StatelessWidget {
  const _SinFicha();

  @override
  Widget build(BuildContext context) {
    return const SingleChildScrollView(
      padding: AppEspacio.pantalla,
      child: Vacio(
        icono: Icons.badge_outlined,
        titulo: 'Tu ficha de trabajador no está creada',
        detalle:
            'Tu usuario tiene el rol Trabajador, pero el administrador todavía '
            'no te registra en una cuadrilla. Sin eso no hay credencial ni '
            'bodega a la que pedir.',
      ),
    );
  }
}
