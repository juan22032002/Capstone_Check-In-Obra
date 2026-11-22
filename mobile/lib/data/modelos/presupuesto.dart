/// Refleja `PresupuestoResponse` del backend.
class Presupuesto {
  const Presupuesto({
    required this.id,
    required this.estado,
    required this.fechaCongelado,
    required this.total,
    required this.obraId,
    required this.obraNombre,
  });

  final int id;

  /// `EstadoPresupuesto`: BORRADOR → APROBADO → CONGELADO. No retrocede.
  final String estado;

  /// Solo existe una vez congelado.
  final DateTime? fechaCongelado;
  final double total;
  final int obraId;
  final String obraNombre;

  bool get esBorrador => estado == 'BORRADOR';
  bool get aprobado => estado == 'APROBADO';
  bool get congelado => estado == 'CONGELADO';

  /// Un presupuesto congelado es la referencia contra la que se mide la
  /// desviación: no admite más ítems (RN-12).
  bool get editable => !congelado;

  factory Presupuesto.desdeJson(Map<String, dynamic> j) => Presupuesto(
    id: j['id'] as int,
    estado: j['estado'] as String,
    fechaCongelado: j['fechaCongelado'] == null
        ? null
        : DateTime.parse(j['fechaCongelado'] as String),
    total: (j['total'] as num).toDouble(),
    obraId: j['obraId'] as int,
    obraNombre: j['obraNombre'] as String,
  );
}

/// Refleja `PresupuestoItemResponse`. El precio es el que tenía el catálogo
/// **al agregar el ítem** (RN-13): no cambia si el catálogo sube después.
class PresupuestoItem {
  const PresupuestoItem({
    required this.id,
    required this.materialId,
    required this.materialSku,
    required this.materialNombre,
    required this.cantidad,
    required this.precioUnitario,
    required this.subtotal,
  });

  final int id;
  final int materialId;
  final String materialSku;
  final String materialNombre;
  final double cantidad;
  final double precioUnitario;
  final double subtotal;

  factory PresupuestoItem.desdeJson(Map<String, dynamic> j) => PresupuestoItem(
    id: j['id'] as int,
    materialId: j['materialId'] as int,
    materialSku: j['materialSku'] as String,
    materialNombre: j['materialNombre'] as String,
    cantidad: (j['cantidad'] as num).toDouble(),
    precioUnitario: (j['precioUnitario'] as num).toDouble(),
    subtotal: (j['subtotal'] as num).toDouble(),
  );
}
