import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formato.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_forma.dart';
import '../../core/theme/app_theme.dart';
import '../../data/api/dominio_api.dart';
import '../../data/modelos/obra.dart';
import '../../data/modelos/pedido_especial.dart';
import '../../data/modelos/solicitud.dart';
import '../../shared_widgets/estados.dart';
import '../../shared_widgets/globo_texto.dart';
import '../../shared_widgets/panel.dart';
import '../bodega/bodega_providers.dart';
import '../bodega/pantalla_solicitudes.dart';
import '../bodega/pedidos_especiales.dart';
import '../obra/obra_activa.dart';

/// Lo que piden los trabajadores de una obra y sigue sin resolver.
class _PendientesDeObra {
  const _PendientesDeObra(this.materiales, this.herramientas);

  final List<SolicitudMaterial> materiales;
  final List<SolicitudHerramienta> herramientas;

  int get total => materiales.length + herramientas.length;
}

final _pendientesDeObraProvider = FutureProvider.family<_PendientesDeObra, int>(
  (ref, obraId) async {
    final api = ref.watch(solicitudesApiProvider);
    final (m, h) = await (
      api.materialesPorObra(obraId),
      api.herramientasPorObra(obraId),
    ).wait;
    return _PendientesDeObra(
      m.where((s) => s.pendiente).toList(),
      h.where((s) => s.pendiente).toList(),
    );
  },
);

/// Solicitudes de toda la empresa, para el administrador.
///
/// Arriba van los pedidos especiales, que el administrador sí resuelve desde
/// acá: conseguir algo suele ser una compra, y la compra es suya. Abajo, lo
/// pedido del catálogo en cada obra; eso se entrega en el mesón con el stock
/// de esa obra a la vista, así que el botón lleva a su bodega en vez de
/// aprobar a ciegas desde una lista general.
class PantallaSolicitudesAdmin extends ConsumerWidget {
  const PantallaSolicitudesAdmin({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final especiales = ref.watch(pedidosEspecialesEmpresaProvider);
    final obras = ref.watch(obrasActivasProvider).valueOrNull ?? const [];

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(_pendientesDeObraProvider);
        ref.invalidate(pedidosEspecialesEmpresaProvider);
        await ref.read(pedidosEspecialesEmpresaProvider.future);
      },
      child: ListView(
        padding: AppEspacio.pantalla,
        children: [
          const Etiqueta('Por conseguir'),
          const SizedBox(height: 4),
          Text(
            'Lo que no está en el catálogo o no había en bodega. Pasa por '
            'tus manos o las de bodega hasta que el trabajador confirme que '
            'lo recibió.',
            style: AppTexto.cuerpoChico,
          ),
          const SizedBox(height: AppEspacio.sm + 4),
          Contenido<List<PedidoEspecial>>(
            valor: especiales,
            alReintentar: () =>
                ref.invalidate(pedidosEspecialesEmpresaProvider),
            estaVacio: (l) => l.isEmpty,
            vacio: Panel(
              child: Text(
                'Nadie está esperando que le consigan algo.',
                style: AppTexto.cuerpoChico,
              ),
            ),
            constructor: (lista) {
              final porObra = <String, List<PedidoEspecial>>{};
              for (final p in lista) {
                porObra.putIfAbsent(p.obraNombre, () => []).add(p);
              }
              for (final l in porObra.values) {
                l.sort(
                  (a, b) => (a.siguientePaso == null ? 1 : 0).compareTo(
                    b.siguientePaso == null ? 1 : 0,
                  ),
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final e in porObra.entries) ...[
                    Text(
                      e.key,
                      style: AppTexto.rotulo.copyWith(color: AppColors.primary),
                    ),
                    const SizedBox(height: AppEspacio.sm),
                    for (final p in e.value) ...[
                      FilaPedidoEspecial(pedido: p),
                      const SizedBox(height: AppEspacio.sm),
                    ],
                    const SizedBox(height: AppEspacio.sm),
                  ],
                ],
              );
            },
          ),
          const SizedBox(height: AppEspacio.lg),
          const Etiqueta('Del catálogo, por obra'),
          const SizedBox(height: AppEspacio.sm + 4),
          if (obras.isEmpty)
            Panel(
              child: Text('No hay obras activas.', style: AppTexto.cuerpoChico),
            )
          else
            for (final o in obras) ...[
              _ObraConPendientes(obra: o),
              const SizedBox(height: AppEspacio.sm),
            ],
          const SizedBox(height: AppEspacio.lg),
        ],
      ),
    );
  }
}

class _ObraConPendientes extends ConsumerWidget {
  const _ObraConPendientes({required this.obra});

  final Obra obra;

  /// Se atiende desde la bodega de la obra: ahí se ve el stock que alcanza y
  /// se registra el despacho contra la obra correcta.
  Future<void> _atender(BuildContext context, WidgetRef ref) async {
    await ref.read(obraActivaProvider.notifier).elegir(obra);
    if (!context.mounted) return;
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const PantallaSolicitudesObra()));
    ref.invalidate(_pendientesDeObraProvider(obra.id));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pendientes = ref.watch(_pendientesDeObraProvider(obra.id));

    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  obra.nombre,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
              ),
              switch (pendientes) {
                AsyncData(:final value) when value.total == 0 =>
                  ChipEstado.neutro('Al día'),
                AsyncData(:final value) => ChipEstado.aviso(
                  value.total == 1
                      ? '1 pendiente'
                      : '${value.total} pendientes',
                ),
                AsyncError() => ChipEstado.critico('Sin datos'),
                _ => const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              },
            ],
          ),
          if (pendientes.valueOrNull case final p? when p.total > 0) ...[
            const SizedBox(height: AppEspacio.sm),
            for (final s in p.materiales.take(3))
              _Linea(
                nombre: s.materialNombre,
                cantidad: Formato.cantidad(s.cantidad),
                quien: s.trabajadorNombre,
                para: s.descripcion,
              ),
            for (final s in p.herramientas.take(3))
              _Linea(
                nombre: s.herramientaNombre,
                cantidad: '1',
                quien: s.trabajadorNombre,
                para: s.descripcion,
              ),
            if (p.total > 6)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('y ${p.total - 6} más', style: AppTexto.dato),
              ),
            const SizedBox(height: AppEspacio.sm),
            OutlinedButton(
              onPressed: () => _atender(context, ref),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(44),
                side: const BorderSide(color: AppColors.borderControl),
                foregroundColor: AppColors.primary,
              ),
              child: const Text('Atender en la bodega de esta obra'),
            ),
          ],
        ],
      ),
    );
  }
}

class _Linea extends StatelessWidget {
  const _Linea({
    required this.nombre,
    required this.cantidad,
    required this.quien,
    required this.para,
  });

  final String nombre;
  final String cantidad;
  final String quien;
  final String? para;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppEspacio.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '$nombre × $cantidad',
                  style: AppTexto.cuerpoChico.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Text(quien, style: AppTexto.dato),
            ],
          ),
          if (para != null && para!.isNotEmpty) ...[
            const SizedBox(height: 4),
            GloboTexto(texto: para!),
          ],
        ],
      ),
    );
  }
}
