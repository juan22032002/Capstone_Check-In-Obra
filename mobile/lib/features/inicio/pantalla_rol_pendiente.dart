import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_forma.dart';
import '../../core/theme/app_theme.dart';
import '../../data/api/auth_api.dart';
import '../../shared_widgets/panel.dart';
import '../auth/sesion_controller.dart';

/// Lo que ve un rol cuyo flujo todavía no está construido.
///
/// Hoy es el jefe de terreno. Bodeguero, administrador y trabajador tienen su
/// propio shell (`ShellBodega`, `ShellAdmin`, `ShellTrabajador`), y el enrutado de
/// `main.dart` los manda ahí; quien caiga acá es porque su flujo está
/// pendiente.
///
/// Decir eso en pantalla, con los permisos que su rol ya tiene concedidos en
/// el backend, es más útil que una pantalla vacía: la autenticación y la
/// autorización funcionan, lo que falta son las pantallas.
class PantallaRolPendiente extends ConsumerWidget {
  const PantallaRolPendiente({super.key, required this.sesion});

  final SesionUsuario sesion;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final permisos = _permisosDe(sesion.rol);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              nombreDeRol(sesion.rol),
              style: AppTexto.dato.copyWith(color: AppColors.secondary),
            ),
            Text(sesion.nombre, style: AppTexto.titulo.copyWith(fontSize: 19)),
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
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Panel(
                child: Row(
                  children: [
                    Iniciales(sesion.nombre, tamano: 52),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            sesion.nombre,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                              color: AppColors.primary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Empresa #${sesion.empresaId} · usuario #${sesion.usuarioId}',
                            style: const TextStyle(
                              fontFamily: AppTheme.monoFamily,
                              fontSize: 12.5,
                              color: AppColors.secondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    ChipEstado.neutro(nombreDeRol(sesion.rol)),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              const Etiqueta('Lo que habilita tu rol'),
              const SizedBox(height: 8),
              Panel(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (var i = 0; i < permisos.length; i++)
                      Container(
                        decoration: BoxDecoration(
                          border: i < permisos.length - 1
                              ? const Border(
                                  bottom: BorderSide(color: AppColors.border),
                                )
                              : null,
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppEspacio.md,
                          vertical: AppEspacio.sm + 6,
                        ),
                        child: Row(
                          children: [
                            // El visto no aporta nada que el texto no diga: es
                            // una lista de permisos, todos concedidos.
                            const ExcludeSemantics(
                              child: Icon(
                                Icons.check,
                                size: 18,
                                color: AppColors.successDark,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                permisos[i],
                                style: const TextStyle(
                                  fontSize: 13.5,
                                  color: AppColors.primary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Panel(
                color: AppColors.warningTint,
                borderColor: AppColors.warning,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ExcludeSemantics(
                          child: Icon(
                            Icons.construction_outlined,
                            size: 20,
                            color: AppColors.warningDark,
                          ),
                        ),
                        SizedBox(width: 11),
                        Expanded(
                          child: Text(
                            'Tu rol ya está reconocido y el backend te '
                            'autoriza todo lo de arriba. Lo que falta son las '
                            'pantallas.',
                            style: TextStyle(
                              fontSize: 12.5,
                              height: 1.4,
                              color: AppColors.warningInk,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _queFalta(sesion.rol),
                      style: const TextStyle(
                        fontSize: 12.5,
                        height: 1.4,
                        color: AppColors.warningInk,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Qué pantallas faltan por rol, para que no sea un "vuelve después" a secas.
  String _queFalta(String rol) => switch (rol) {
    'JEFE_TERRENO' =>
      'Falta el flujo de cubicación: crear partidas, calcular con el motor de '
          'cubicación, armar y congelar el presupuesto, y ver la desviación de '
          'la obra.',
    'TRABAJADOR' =>
      'Falta el flujo de terreno: solicitar herramienta y material, mostrar la '
          'credencial QR y seguir tus préstamos.',
    _ => 'El flujo de este rol todavía no se construye.',
  };

  /// Refleja la matriz de permisos del README y los `@PreAuthorize` del backend.
  List<String> _permisosDe(String rol) => switch (rol) {
    'TRABAJADOR' => const [
      'Solicitar herramienta o material',
      'Mostrar credencial QR',
      'Ver sus préstamos y devoluciones',
    ],
    'BODEGUERO' => const [
      'Aprobar o rechazar solicitudes',
      'Recepción, despacho y consumo',
      'Autorizar préstamo y registrar devolución',
      'Cerrar turno de bodega',
      'Resolver alertas',
    ],
    'JEFE_TERRENO' => const [
      'Cubicar partidas',
      'Congelar el presupuesto',
      'Ver la desviación de la obra',
      'Resolver alertas',
    ],
    'ADMIN' => const [
      'Crear usuarios y asignar rol',
      'Definir catálogo, precios y mermas',
      'Crear y cerrar obras',
      'Todo lo de bodega y terreno',
    ],
    _ => const ['Rol no reconocido'],
  };
}
