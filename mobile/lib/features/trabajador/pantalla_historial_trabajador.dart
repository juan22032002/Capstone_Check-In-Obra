import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_forma.dart';
import '../../data/modelos/herramienta.dart';
import '../../shared_widgets/estados.dart';
import 'filas_trabajador.dart';
import 'pantalla_pedido_qr.dart';
import 'trabajador_providers.dart';

/// Todo lo que pidió y todas las herramientas que tuvo. Sirve para responder
/// "¿yo devolví ese esmeril?" sin ir al mesón a preguntar.
class PantallaHistorialTrabajador extends ConsumerStatefulWidget {
  const PantallaHistorialTrabajador({super.key});

  @override
  ConsumerState<PantallaHistorialTrabajador> createState() =>
      _PantallaHistorialTrabajadorState();
}

class _PantallaHistorialTrabajadorState
    extends ConsumerState<PantallaHistorialTrabajador> {
  bool _prestamos = false;

  @override
  Widget build(BuildContext context) {
    final solicitudes = ref.watch(misSolicitudesProvider);
    final prestamos = ref.watch(misPrestamosProvider);
    final porRetirar = ref.watch(pedidosPorRetirarProvider);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: SizedBox(
            width: double.infinity,
            child: SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: false, label: Text('Solicitudes')),
                ButtonSegment(value: true, label: Text('Préstamos')),
              ],
              selected: {_prestamos},
              onSelectionChanged: (s) => setState(() => _prestamos = s.first),
            ),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              recargarTrabajador(ref);
              await ref.read(misSolicitudesProvider.future);
            },
            child: _prestamos
                ? Contenido<List<Prestamo>>(
                    valor: prestamos,
                    alReintentar: () => ref.invalidate(misPrestamosProvider),
                    estaVacio: (l) => l.isEmpty,
                    vacio: const _Vacio(
                      icono: Icons.handyman_outlined,
                      titulo: 'Nunca te han prestado una herramienta',
                      detalle:
                          'Cuando bodega te entregue una, queda registrada '
                          'acá con su fecha de devolución.',
                    ),
                    constructor: (lista) => ListView(
                      padding: AppEspacio.pantalla,
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        for (final p in lista) ...[
                          FilaPrestamo(prestamo: p),
                          const SizedBox(height: AppEspacio.sm),
                        ],
                      ],
                    ),
                  )
                : Contenido<List<MiSolicitud>>(
                    valor: solicitudes,
                    alReintentar: () => ref.invalidate(misSolicitudesProvider),
                    estaVacio: (l) => l.isEmpty,
                    vacio: const _Vacio(
                      icono: Icons.inbox_outlined,
                      titulo: 'Todavía no pides nada',
                      detalle:
                          'Tus solicitudes de material y herramientas '
                          'aparecen acá, con lo que respondió bodega.',
                    ),
                    constructor: (lista) => ListView(
                      padding: AppEspacio.pantalla,
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        for (final pedido in porRetirar) ...[
                          TarjetaPedidoPorRetirar(pedido: pedido),
                          const SizedBox(height: AppEspacio.sm),
                        ],
                        for (final s in lista) ...[
                          FilaMiSolicitud(solicitud: s),
                          const SizedBox(height: AppEspacio.sm),
                        ],
                      ],
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

class _Vacio extends StatelessWidget {
  const _Vacio({
    required this.icono,
    required this.titulo,
    required this.detalle,
  });

  final IconData icono;
  final String titulo;
  final String detalle;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    physics: const AlwaysScrollableScrollPhysics(),
    child: Vacio(icono: icono, titulo: titulo, detalle: detalle),
  );
}
