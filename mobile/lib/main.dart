import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'core/navegacion.dart';
import 'core/network/app_config.dart';
import 'core/theme/app_colors.dart';
import 'core/theme/app_theme.dart';
import 'data/api/auth_api.dart';
import 'features/admin/shell_admin.dart';
import 'features/auth/pantalla_acceso.dart';
import 'features/auth/pantalla_cambiar_clave.dart';
import 'features/auth/pantalla_configuracion_invalida.dart';
import 'features/auth/sesion_controller.dart';
import 'features/bodega/shell_bodega.dart';
import 'features/inicio/pantalla_rol_pendiente.dart';
import 'features/jefe_terreno/shell_jefe_terreno.dart';
import 'features/trabajador/shell_trabajador.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppConfig.cargar();
  // En release, una URL que no sea https:// impide arrancar (S-10).
  final errorDeConfiguracion = AppConfig.errorDeConfiguracion;
  if (errorDeConfiguracion != null) {
    runApp(PantallaConfiguracionInvalida(mensaje: errorDeConfiguracion));
    return;
  }
  // Sin esto, `DateFormat` con locale 'es_CL' lanza LocaleDataException y
  // revienta cualquier pantalla que muestre una fecha — que en esta app son
  // casi todas: el kardex, las alertas y el cierre de turno.
  await initializeDateFormatting('es_CL');
  runApp(const ProviderScope(child: CheckInObraApp()));
}

class CheckInObraApp extends StatelessWidget {
  const CheckInObraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Check-In-Obra',
      debugShowCheckedModeBanner: false,
      navigatorKey: navegadorRaiz,
      scaffoldMessengerKey: mensajeroRaiz,
      theme: AppTheme.light,
      // Decisión explícita, no un descuido: ver la nota en AppTheme.
      themeMode: ThemeMode.light,
      home: const _Raiz(),
    );
  }
}

/// Cada rol entra a su propia app. No es una preferencia de diseño: el
/// bodeguero trabaja sobre una obra y necesita elegirla antes de ver nada,
/// mientras que el administrador trabaja sobre la empresa entera y no tiene
/// obra activa. Un shell común tendría que negar la mitad de sí mismo en cada
/// caso.
Widget _paraElRol(SesionUsuario sesion) => switch (sesion.rol) {
  'BODEGUERO' => const ShellBodega(),
  'ADMIN' => const ShellAdmin(),
  'TRABAJADOR' => const ShellTrabajador(),
  'JEFE_TERRENO' => const ShellJefeTerreno(),
  // Un rol que la app no conoce (uno nuevo del backend, por ejemplo).
  _ => PantallaRolPendiente(sesion: sesion),
};

/// Decide qué mostrar según haya sesión guardada o no.
///
/// Al abrir la app se lee el token del almacenamiento cifrado: si sigue ahí,
/// se entra directo. Pedir credenciales cada vez que se abre la app sería
/// inaceptable en obra.
class _Raiz extends ConsumerWidget {
  const _Raiz();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sesion = ref.watch(sesionProvider);

    return switch (sesion) {
      // Primera carga: aún no sabemos si hay sesión guardada.
      AsyncLoading() when !sesion.hasValue => const _Cargando(),
      // Con clave provisoria no hay app que mostrar: el servidor rechaza todo
      // salvo el cambio de clave.
      AsyncValue(value: final s?) when s.debeCambiarClave =>
        PantallaCambiarClave(sesion: s),
      AsyncValue(value: final s?) => _paraElRol(s),
      _ => const PantallaAcceso(),
    };
  }
}

class _Cargando extends StatelessWidget {
  const _Cargando();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppColors.primary,
      body: Center(child: CircularProgressIndicator(color: Colors.white)),
    );
  }
}
