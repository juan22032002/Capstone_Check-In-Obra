import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formato.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../data/modelos/material.dart';
import '../../shared_widgets/campo_texto.dart';
import '../../shared_widgets/estados.dart';
import '../../shared_widgets/opcion.dart';
import '../../shared_widgets/panel.dart';
import 'bodega_providers.dart';
import 'pantalla_material.dart';

/// Filtro de la lista de bodega.
enum _Filtro {
  todos('Todos'),
  criticos('Críticos'),
  bajos('Bajos');

  const _Filtro(this.rotulo);
  final String rotulo;
}

/// El catálogo con el saldo de la obra. Ordenado por criticidad: lo que hay
/// que reponer va primero, porque eso es lo que se viene a buscar acá.
class PantallaBodega extends ConsumerStatefulWidget {
  const PantallaBodega({super.key});

  @override
  ConsumerState<PantallaBodega> createState() => _PantallaBodegaState();
}

class _PantallaBodegaState extends ConsumerState<PantallaBodega> {
  final _busqueda = TextEditingController();
  _Filtro _filtro = _Filtro.todos;

  @override
  void dispose() {
    _busqueda.dispose();
    super.dispose();
  }

  List<MaterialConStock> _filtrar(List<MaterialConStock> todos) {
    final texto = _busqueda.text.trim().toLowerCase();
    return todos.where((m) {
      final pasaFiltro = switch (_filtro) {
        _Filtro.todos => true,
        _Filtro.criticos => m.critico,
        _Filtro.bajos => m.bajo,
      };
      if (!pasaFiltro) return false;
      if (texto.isEmpty) return true;
      // Se busca por nombre y por SKU: el SKU es lo que viene en la guía de
      // despacho, el nombre es lo que dice quien pide.
      return m.material.nombre.toLowerCase().contains(texto) ||
          m.material.sku.toLowerCase().contains(texto);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final bodega = ref.watch(bodegaProvider);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
          child: Column(
            children: [
              CampoTexto(
                controlador: _busqueda,
                hint: 'Buscar material o SKU',
                icono: Icons.search,
                mono: true,
                alEnviar: (_) => setState(() {}),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  for (final f in _Filtro.values) ...[
                    _Pestana(
                      rotulo: f.rotulo,
                      cantidad: switch (bodega.valueOrNull) {
                        null => null,
                        final lista => switch (f) {
                          _Filtro.todos => lista.length,
                          _Filtro.criticos =>
                            lista.where((m) => m.critico).length,
                          _Filtro.bajos => lista.where((m) => m.bajo).length,
                        },
                      },
                      activa: _filtro == f,
                      onTap: () => setState(() => _filtro = f),
                    ),
                    const SizedBox(width: 8),
                  ],
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(catalogoProvider);
              ref.invalidate(movimientosProvider);
            },
            child: Contenido<List<MaterialConStock>>(
              valor: bodega,
              alReintentar: () {
                ref.invalidate(catalogoProvider);
                ref.invalidate(movimientosProvider);
              },
              estaVacio: (l) => l.isEmpty,
              vacio: const SingleChildScrollView(
                child: Vacio(
                  icono: Icons.inventory_2_outlined,
                  titulo: 'El catálogo está vacío',
                  detalle:
                      'Los materiales los define un administrador. Sin catálogo '
                      'no hay nada que recepcionar ni despachar.',
                ),
              ),
              constructor: (todos) {
                final lista = _filtrar(todos);
                if (lista.isEmpty) {
                  return const SingleChildScrollView(
                    child: Vacio(
                      icono: Icons.search_off,
                      titulo: 'Ningún material coincide',
                      detalle: 'Prueba con otra parte del nombre o del SKU.',
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  itemCount: lista.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (_, i) => FilaMaterial(item: lista[i]),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _Pestana extends StatelessWidget {
  const _Pestana({
    required this.rotulo,
    required this.cantidad,
    required this.activa,
    required this.onTap,
  });

  final String rotulo;
  final int? cantidad;
  final bool activa;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final texto = cantidad == null ? rotulo : '$rotulo · $cantidad';
    return Opcion(texto: texto, elegida: activa, alTocar: onTap);
  }
}

/// Una fila del catálogo con su saldo. También la usa el buscador del
/// registro de movimiento.
class FilaMaterial extends StatelessWidget {
  const FilaMaterial({super.key, required this.item, this.onTap});

  final MaterialConStock item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final m = item.material;
    final unidad = _unidadDe(m.categoria);

    return PanelTocable(
      semanticLabel:
          '${m.nombre}, SKU ${m.sku}, '
          '${Formato.cantidad(item.stock)} $unidad en bodega'
          '${item.critico
              ? ', stock crítico'
              : item.bajo
              ? ', stock bajo'
              : ''}',
      // Franja y no borde completo: tres tarjetas rojas seguidas gritan, y el
      // chip "Crítico" ya dice lo mismo en palabras.
      borderColor: AppColors.border,
      borderIzquierdo: item.critico
          ? AppColors.destructive
          : item.bajo
          ? AppColors.warning
          : null,
      onTap:
          onTap ??
          () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => PantallaMaterial(item: item)),
          ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        m.nombre,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                    if (item.critico) ...[
                      const SizedBox(width: 8),
                      ChipEstado.critico('Crítico'),
                    ] else if (item.bajo) ...[
                      const SizedBox(width: 8),
                      ChipEstado.aviso('Bajo'),
                    ],
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  '${m.sku} · mín. ${Formato.cantidad(m.stockMinimo)} $unidad',
                  style: const TextStyle(
                    fontFamily: AppTheme.monoFamily,
                    fontSize: 12.5,
                    color: AppColors.secondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                Formato.cantidad(item.stock),
                style: TextStyle(
                  fontFeatures: AppTexto.tabulares,
                  fontFamily: AppTheme.monoFamily,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: item.critico
                      ? AppColors.destructiveDark
                      : AppColors.primary,
                ),
              ),
              Text(
                unidad,
                style: const TextStyle(
                  fontSize: 12,
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

/// Unidad de medida según la categoría. El backend no la guarda —`Material` no
/// tiene campo de unidad— así que se deriva del rubro: la volcanita y el OSB
/// van por plancha, el metalcom por unidad, la fijación por kilo.
String _unidadDe(String categoria) => switch (categoria) {
  'VOLCANITA' || 'OSB' => 'pl',
  'FIJACION' => 'kg',
  _ => 'un',
};

/// Expuesta para las demás pantallas de bodega.
String unidadDe(String categoria) => _unidadDe(categoria);

/// Nombre legible de la categoría del catálogo. El backend guarda el valor del
/// enum en mayúsculas; mostrarlo tal cual ("FIJACION", sin tilde) se leía
/// como un código y no como una palabra.
String nombreDeCategoria(String categoria) => switch (categoria) {
  'METALCOM' => 'Metalcom',
  'VOLCANITA' => 'Volcanita',
  'OSB' => 'OSB',
  'FIJACION' => 'Fijación',
  _ =>
    categoria.isEmpty
        ? categoria
        : categoria[0] + categoria.substring(1).toLowerCase(),
};
