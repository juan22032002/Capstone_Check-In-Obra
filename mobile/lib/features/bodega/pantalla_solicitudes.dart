import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/errores.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../data/modelos/pedido_especial.dart';
import '../../data/modelos/solicitud.dart';
import '../../data/modelos/trabajador.dart';
import '../../shared_widgets/estados.dart';
import '../../shared_widgets/panel.dart';
import 'bodega_providers.dart';
import 'pantalla_escaneo.dart';
import 'pedidos_especiales.dart';
import 'solicitudes_acciones.dart';

/// La cola de la obra: todo lo que espera respuesta del bodeguero.
///
/// Existe además del escaneo porque son dos momentos distintos. Con el
/// trabajador enfrente se escanea su credencial y se resuelve lo suyo; al
/// empezar el turno, lo que se quiere es ver la cola completa y despachar por
/// orden de llegada.
class PantallaSolicitudesObra extends ConsumerWidget {
  const PantallaSolicitudesObra({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final materiales = ref.watch(solicitudesMaterialProvider);
    final herramientas = ref.watch(solicitudesHerramientaProvider);
    final especiales = ref.watch(pedidosEspecialesObraProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Solicitudes pendientes'),
        actions: [
          IconButton(
            tooltip: 'Escanear la credencial o el pedido de un trabajador',
            icon: const Icon(Icons.qr_code_scanner),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const PantallaEscaneoCredencial(),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: () async => recargarBodega(ref),
          child: Contenido<List<SolicitudMaterial>>(
            valor: materiales,
            alReintentar: () => ref.invalidate(solicitudesMaterialProvider),
            constructor: (pedidosMaterial) {
              final pedidosHerramienta =
                  herramientas.valueOrNull ?? const <SolicitudHerramienta>[];
              // Las dos consultas son independientes; si la de herramientas
              // falló, decirlo vale más que mostrar la mitad de la cola como
              // si fuera toda.
              final falloHerramientas = herramientas is AsyncError;
              final pendientesMaterial = pedidosMaterial
                  .where((s) => s.pendiente)
                  .toList();
              final pendientesHerramienta = pedidosHerramienta
                  .where((s) => s.pendiente)
                  .toList();
              // Lo que le toca a bodega primero; lo entregado que el
              // trabajador no confirma, al final.
              final pedidos =
                  [...especiales.valueOrNull ?? const <PedidoEspecial>[]]..sort(
                    (a, b) => (a.siguientePaso == null ? 1 : 0).compareTo(
                      b.siguientePaso == null ? 1 : 0,
                    ),
                  );
              final falloEspeciales = especiales is AsyncError;

              if (pendientesMaterial.isEmpty &&
                  pendientesHerramienta.isEmpty &&
                  pedidos.isEmpty &&
                  !falloHerramientas &&
                  !falloEspeciales) {
                return ListView(
                  children: const [
                    Vacio(
                      icono: Icons.inbox_outlined,
                      titulo: 'Nadie está esperando',
                      detalle:
                          'No hay solicitudes pendientes en esta obra. '
                          'Cuando un trabajador pida material o una '
                          'herramienta, aparece acá.',
                    ),
                  ],
                );
              }

              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (falloHerramientas) ...[
                    MensajeError(
                      mensaje:
                          'No se pudieron traer las solicitudes de '
                          'herramienta: ${mensajeDeError((herramientas as AsyncError).error)}',
                      alReintentar: () =>
                          ref.invalidate(solicitudesHerramientaProvider),
                    ),
                    const SizedBox(height: 14),
                  ],
                  if (pendientesMaterial.isNotEmpty) ...[
                    Etiqueta('Material (${pendientesMaterial.length})'),
                    const SizedBox(height: 8),
                    for (final s in pendientesMaterial) ...[
                      FilaSolicitudMaterial(solicitud: s),
                      const SizedBox(height: 10),
                    ],
                    const SizedBox(height: 10),
                  ],
                  if (pendientesHerramienta.isNotEmpty) ...[
                    Etiqueta('Herramientas (${pendientesHerramienta.length})'),
                    const SizedBox(height: 8),
                    for (final s in pendientesHerramienta) ...[
                      FilaSolicitudHerramienta(solicitud: s),
                      const SizedBox(height: 10),
                    ],
                    const SizedBox(height: 10),
                  ],
                  if (falloEspeciales) ...[
                    MensajeError(
                      mensaje:
                          'No se pudieron traer los pedidos especiales: '
                          '${mensajeDeError((especiales as AsyncError).error)}',
                      alReintentar: () =>
                          ref.invalidate(pedidosEspecialesObraProvider),
                    ),
                    const SizedBox(height: 14),
                  ],
                  if (pedidos.isNotEmpty) ...[
                    Etiqueta('Por conseguir (${pedidos.length})'),
                    const SizedBox(height: 4),
                    Text(
                      'Lo que no está en el catálogo o no había en bodega.',
                      style: AppTexto.cuerpoChico,
                    ),
                    const SizedBox(height: 8),
                    for (final p in pedidos) ...[
                      FilaPedidoEspecial(pedido: p),
                      const SizedBox(height: 10),
                    ],
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Lo que pidió el trabajador cuya credencial se acaba de escanear.
///
/// Es la pantalla a la que lleva el QR. La credencial no autoriza nada por sí
/// sola: identifica a la persona y trae lo suyo a la pantalla; quien aprueba
/// sigue siendo el bodeguero, y queda registrado como tal.
class PantallaSolicitudesTrabajador extends ConsumerWidget {
  const PantallaSolicitudesTrabajador({super.key, required this.trabajador});

  final Trabajador trabajador;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final solicitudes = ref.watch(
      solicitudesDeTrabajadorProvider(trabajador.id),
    );
    // Sus pedidos especiales en esta obra que bodega todavía tiene que
    // mover. Con él enfrente, lo que está listo se le entrega acá mismo.
    final suyos = [
      for (final p
          in ref.watch(pedidosEspecialesObraProvider).valueOrNull ??
              const <PedidoEspecial>[])
        if (p.trabajadorId == trabajador.id && p.siguientePaso != null) p,
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Credencial escaneada')),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(solicitudesDeTrabajadorProvider(trabajador.id));
          },
          child: Contenido<SolicitudesDeTrabajador>(
            valor: solicitudes,
            alReintentar: () =>
                ref.invalidate(solicitudesDeTrabajadorProvider(trabajador.id)),
            constructor: (datos) => ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _Credencial(
                  trabajador: trabajador,
                  pendientes: datos.cuantasPendientes,
                ),
                const SizedBox(height: 20),
                if (suyos.isNotEmpty) ...[
                  Etiqueta('Por conseguir (${suyos.length})'),
                  const SizedBox(height: 8),
                  for (final p in suyos) ...[
                    FilaPedidoEspecial(pedido: p),
                    const SizedBox(height: 10),
                  ],
                  const SizedBox(height: 10),
                ],
                if (datos.cuantasPendientes == 0 && suyos.isEmpty)
                  Vacio(
                    icono: Icons.check_circle_outline,
                    titulo: 'No tiene nada pendiente',
                    detalle: datos.vacio
                        ? '${trabajador.nombre} todavía no ha pedido material '
                              'ni herramientas. Puedes entregarle igual desde '
                              'Movimiento o Préstamo.'
                        : 'Todo lo que ${trabajador.nombre} pidió ya está '
                              'resuelto. Su historial va más abajo.',
                  )
                else ...[
                  if (datos.materialesPendientes.isNotEmpty) ...[
                    Etiqueta(
                      'Material pendiente '
                      '(${datos.materialesPendientes.length})',
                    ),
                    const SizedBox(height: 8),
                    for (final s in datos.materialesPendientes) ...[
                      FilaSolicitudMaterial(
                        solicitud: s,
                        mostrarTrabajador: false,
                      ),
                      const SizedBox(height: 10),
                    ],
                    const SizedBox(height: 10),
                  ],
                  if (datos.herramientasPendientes.isNotEmpty) ...[
                    Etiqueta(
                      'Herramientas pendientes '
                      '(${datos.herramientasPendientes.length})',
                    ),
                    const SizedBox(height: 8),
                    for (final s in datos.herramientasPendientes) ...[
                      FilaSolicitudHerramienta(
                        solicitud: s,
                        mostrarTrabajador: false,
                      ),
                      const SizedBox(height: 10),
                    ],
                  ],
                ],
                const SizedBox(height: 10),
                _Historial(datos: datos),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Quién es la persona que está al otro lado del mesón.
class _Credencial extends StatelessWidget {
  const _Credencial({required this.trabajador, required this.pendientes});

  final Trabajador trabajador;
  final int pendientes;

  @override
  Widget build(BuildContext context) {
    return Panel(
      color: AppColors.surfaceDark,
      borderColor: AppColors.borderOnDark,
      child: Row(
        children: [
          Iniciales(trabajador.nombre, tamano: 46),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  trabajador.nombre,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  trabajador.rut ?? 'sin RUT registrado',
                  style: const TextStyle(
                    fontFamily: AppTheme.monoFamily,
                    fontSize: 12.5,
                    color: AppColors.textOnDark,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  switch (pendientes) {
                    0 => 'Sin solicitudes pendientes',
                    1 => '1 solicitud esperando',
                    final n => '$n solicitudes esperando',
                  },
                  style: TextStyle(
                    fontSize: 12.5,
                    color: pendientes == 0
                        ? AppColors.textOnDark
                        : AppColors.warning,
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

/// Lo ya resuelto, acotado a lo último. Sirve para responder ahí mismo el
/// "pero si te lo entregué ayer" sin salir de la pantalla.
class _Historial extends StatelessWidget {
  const _Historial({required this.datos});

  final SolicitudesDeTrabajador datos;

  @override
  Widget build(BuildContext context) {
    final materiales = datos.materiales.where((s) => !s.pendiente).take(5);
    final herramientas = datos.herramientas.where((s) => !s.pendiente).take(5);
    if (materiales.isEmpty && herramientas.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Etiqueta('Ya resuelto'),
        const SizedBox(height: 8),
        for (final s in materiales) ...[
          FilaSolicitudMaterial(solicitud: s, mostrarTrabajador: false),
          const SizedBox(height: 10),
        ],
        for (final s in herramientas) ...[
          FilaSolicitudHerramienta(solicitud: s, mostrarTrabajador: false),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}
