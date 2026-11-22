import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formato.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../data/modelos/kardex.dart';
import '../../data/modelos/material.dart';
import '../../shared_widgets/estados.dart';
import '../../shared_widgets/panel.dart';
import 'bodega_providers.dart';
import 'pantalla_bodega.dart';
import 'pantalla_movimiento.dart';

/// Un material visto desde la obra: cuánto queda, y cómo se llegó a esa cifra.
///
/// El kardex completo va en la pantalla porque el saldo no es un dato que el
/// sistema guarde: es el resultado de esta lista. Mostrar el número sin los
/// movimientos que lo producen obligaría a creerle al sistema en vez de poder
/// revisarlo, que es lo contrario de lo que este proyecto vino a resolver.
class PantallaMaterial extends ConsumerWidget {
  const PantallaMaterial({super.key, required this.item});

  final MaterialConStock item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Se relee del provider para que el saldo se actualice al volver de
    // registrar un movimiento, en vez de quedar con el valor de la entrada.
    final actual =
        ref
            .watch(bodegaProvider)
            .valueOrNull
            ?.where((m) => m.material.id == item.material.id)
            .firstOrNull ??
        item;

    final m = actual.material;
    final unidad = unidadDe(m.categoria);
    final movimientos = ref
        .watch(movimientosProvider)
        .whenData((lista) => lista.where((x) => x.materialId == m.id).toList());

    return Scaffold(
      appBar: AppBar(title: const Text('Material')),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    m.nombre,
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w600,
                      height: 1.25,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    // El código de barras al lado del SKU: son los dos códigos
                    // con los que este material se puede encontrar escaneando,
                    // y verlos acá permite comprobar contra la etiqueta real
                    // cuando el escáner no lo reconoce.
                    m.codigoBarra == null
                        ? m.sku
                        : '${m.sku} · ${m.codigoBarra}',
                    style: const TextStyle(
                      fontFamily: AppTheme.monoFamily,
                      fontSize: 12.5,
                      color: AppColors.secondary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      ChipEstado.neutro(nombreDeCategoria(m.categoria)),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          // Dice de dónde sale la cifra: lo que se pagó en la
                          // última recepción, o el precio estimado del catálogo.
                          m.tieneCostoReal
                              ? 'Costó ${Formato.pesos(m.ultimoCostoUnitario!)} / $unidad'
                              : '${Formato.pesos(m.precioUnitario)} / $unidad · catálogo',
                          style: const TextStyle(
                            fontFeatures: AppTexto.tabulares,
                            fontSize: 12.5,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Panel(
              color: actual.critico
                  ? AppColors.destructiveTint
                  : AppColors.card,
              borderColor: actual.critico
                  ? AppColors.destructive
                  : AppColors.border,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        Formato.cantidad(actual.stock),
                        style: TextStyle(
                          fontFeatures: AppTexto.tabulares,
                          fontFamily: AppTheme.monoFamily,
                          fontSize: 38,
                          fontWeight: FontWeight.w600,
                          height: 1,
                          color: actual.critico
                              ? AppColors.destructiveDark
                              : AppColors.primary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          '$unidad en bodega',
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ),
                      const Spacer(),
                      if (actual.critico)
                        ChipEstado.critico('Stock crítico')
                      else if (actual.bajo)
                        ChipEstado.aviso('Stock bajo')
                      else
                        ChipEstado.exito('Sobre el mínimo'),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Stock mínimo de obra: ${Formato.cantidad(m.stockMinimo)} $unidad',
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const Etiqueta('Kardex del material'),
            const SizedBox(height: 8),
            Contenido<List<MovimientoKardex>>(
              valor: movimientos,
              alReintentar: () => ref.invalidate(movimientosProvider),
              estaVacio: (l) => l.isEmpty,
              vacio: const Vacio(
                icono: Icons.receipt_long_outlined,
                titulo: 'Sin movimientos',
                detalle:
                    'Este material todavía no entra ni sale en esta obra. '
                    'Su saldo es cero por eso, no por un error.',
              ),
              constructor: (lista) => Panel(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (var i = 0; i < lista.length; i++)
                      _FilaKardex(
                        movimiento: lista[i],
                        // El saldo se reconstruye hacia atrás desde el actual:
                        // así cada fila muestra cómo quedó la bodega justo
                        // después de ese movimiento.
                        saldoDespues: _saldoTras(lista, i, actual.stock),
                        unidad: unidad,
                        ultima: i == lista.length - 1,
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => PantallaMovimiento(item: actual),
                ),
              ),
              icon: const Icon(Icons.add),
              label: const Text('Registrar movimiento'),
            ),
          ],
        ),
      ),
    );
  }

  /// Los movimientos vienen del más nuevo al más viejo. El saldo tras el
  /// movimiento `i` es el saldo actual menos todo lo que pasó después de él.
  static double _saldoTras(
    List<MovimientoKardex> lista,
    int i,
    double saldoActual,
  ) {
    var saldo = saldoActual;
    for (var j = 0; j < i; j++) {
      saldo -= lista[j].cantidadConSigno;
    }
    return saldo;
  }
}

class _FilaKardex extends StatelessWidget {
  const _FilaKardex({
    required this.movimiento,
    required this.saldoDespues,
    required this.unidad,
    required this.ultima,
  });

  final MovimientoKardex movimiento;
  final double saldoDespues;
  final String unidad;
  final bool ultima;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        border: ultima
            ? null
            : const Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  switch (movimiento.tipo) {
                    'RECEPCION' => 'Recepción',
                    'DESPACHO' => 'Despacho',
                    _ => 'Consumo',
                  },
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  Formato.relativa(movimiento.fecha),
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textMuted,
                  ),
                ),
                const SizedBox(height: 2),
                // Quién recibió es el dato que se busca cuando aparece un
                // descuadre; quién lo anotó va después, en gris.
                if (movimiento.receptor case final quien?)
                  Text(
                    'Entregado a $quien',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: AppColors.primary,
                    ),
                  ),
                Text(
                  'Registró ${movimiento.usuarioNombre}',
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.secondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                Formato.cantidadConSigno(movimiento.cantidadConSigno),
                style: TextStyle(
                  fontFeatures: AppTexto.tabulares,
                  fontFamily: AppTheme.monoFamily,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: movimiento.entra
                      ? AppColors.successDark
                      : AppColors.primary,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                '${Formato.cantidad(saldoDespues)} $unidad',
                style: const TextStyle(
                  fontFeatures: AppTexto.tabulares,
                  fontFamily: AppTheme.monoFamily,
                  fontSize: 12.5,
                  color: AppColors.secondary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
