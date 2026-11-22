/// Refleja `MaterialResponse` del backend.
class MaterialObra {
  const MaterialObra({
    required this.id,
    required this.sku,
    required this.codigoBarra,
    required this.nombre,
    required this.categoria,
    required this.precioUnitario,
    required this.stockMinimo,
    this.ultimoCostoUnitario,
    this.fechaUltimoCosto,
    this.costoPromedio,
    this.tienePrecio = true,
  });

  final int id;
  final String sku;

  /// El código impreso de fábrica en el envase — lo que lee el escáner de
  /// código de barras. Nulo en los materiales que no traen etiqueta, que se
  /// siguen encontrando por SKU.
  final String? codigoBarra;

  final String nombre;

  /// `CategoriaMaterial`: METALCOM, VOLCANITA, OSB, FIJACION.
  final String categoria;

  /// Precio de catálogo. El backend **no lo manda** al TRABAJADOR (ni los costos
  /// de abajo): un trabajador pide material, no ve cuánto cuesta. Cuando falta
  /// queda en 0 y [tienePrecio] en `false`; una pantalla que muestre precios
  /// tiene que mirar [tienePrecio] antes de mostrar "$0", que no es un precio.
  final double precioUnitario;

  /// `false` si el servidor no envió `precioUnitario` (rol sin acceso a costos).
  final bool tienePrecio;
  final double stockMinimo;

  /// Lo que se pagó por unidad en la última recepción que trajo costo. Nulo
  /// mientras ninguna recepción lo haya registrado: ahí solo existe el precio
  /// de catálogo, que es una estimación y no lo que costó.
  final double? ultimoCostoUnitario;
  final DateTime? fechaUltimoCosto;

  /// Promedio ponderado por cantidad de las recepciones con costo.
  final double? costoPromedio;

  bool get tieneCostoReal => ultimoCostoUnitario != null;

  /// El costo con que se valoriza el stock: el real si existe, el de catálogo
  /// si no.
  double get costoVigente => ultimoCostoUnitario ?? precioUnitario;

  /// Cuánto se alejó la última compra del precio de catálogo, en proporción.
  /// Positivo: se pagó más caro de lo presupuestado.
  double? get variacionCosto =>
      ultimoCostoUnitario == null || precioUnitario == 0
      ? null
      : (ultimoCostoUnitario! - precioUnitario) / precioUnitario;

  factory MaterialObra.desdeJson(Map<String, dynamic> j) => MaterialObra(
    id: j['id'] as int,
    sku: j['sku'] as String,
    codigoBarra: j['codigoBarra'] as String?,
    nombre: j['nombre'] as String,
    categoria: j['categoria'] as String,
    precioUnitario: (j['precioUnitario'] as num?)?.toDouble() ?? 0,
    tienePrecio: j['precioUnitario'] != null,
    stockMinimo: (j['stockMinimo'] as num).toDouble(),
    ultimoCostoUnitario: (j['ultimoCostoUnitario'] as num?)?.toDouble(),
    fechaUltimoCosto: j['fechaUltimoCosto'] == null
        ? null
        : DateTime.parse(j['fechaUltimoCosto'] as String),
    costoPromedio: (j['costoPromedio'] as num?)?.toDouble(),
  );
}

/// Refleja `ParametroMermaResponse`.
class ParametroMerma {
  const ParametroMerma({required this.porcentaje, required this.materialId});

  final double porcentaje;
  final int materialId;

  factory ParametroMerma.desdeJson(Map<String, dynamic> j) => ParametroMerma(
    porcentaje: (j['porcentaje'] as num).toDouble(),
    materialId: j['materialId'] as int,
  );
}

/// Un material junto con su saldo en una obra. El stock no viene en
/// `MaterialResponse` porque no es del material: es la suma de los movimientos
/// de kardex de ese material **en esa obra**.
class MaterialConStock {
  const MaterialConStock({required this.material, required this.stock});

  final MaterialObra material;
  final double stock;

  bool get critico => stock < material.stockMinimo;

  /// Bajo, pero todavía no bajo el mínimo: el margen es del 25 %.
  bool get bajo => !critico && stock < material.stockMinimo * 1.25;

  /// Orden de la pantalla de bodega: primero lo que hay que reponer.
  int get criticidad => critico ? 0 : (bajo ? 1 : 2);
}
