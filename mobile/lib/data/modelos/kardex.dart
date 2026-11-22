/// Refleja `KardexMovimientoResponse` del backend.
class MovimientoKardex {
  const MovimientoKardex({
    required this.id,
    required this.tipo,
    required this.cantidad,
    required this.fecha,
    required this.materialId,
    required this.materialSku,
    required this.materialNombre,
    required this.usuarioNombre,
    required this.trabajadorNombre,
    required this.trabajadorRut,
    this.costoUnitario,
  });

  final int id;

  /// `TipoMovimiento`: RECEPCION, DESPACHO o CONSUMO.
  final String tipo;
  final double cantidad;
  final DateTime fecha;
  final int materialId;
  final String materialSku;
  final String materialNombre;

  /// Quién ANOTÓ el movimiento.
  final String usuarioNombre;

  /// Quién lo RECIBIÓ. Son dos personas distintas en un despacho: el bodeguero
  /// registra y el trabajador se lleva. Nulos en una recepción.
  final String? trabajadorNombre;
  final String? trabajadorRut;

  /// Lo que se pagó por unidad. Solo lo trae una recepción, y solo si quien
  /// la registró tenía la factura o la guía a mano.
  final double? costoUnitario;

  String? get receptor => trabajadorNombre == null
      ? null
      : trabajadorRut == null
      ? trabajadorNombre
      : '$trabajadorNombre · $trabajadorRut';

  /// La recepción suma al saldo; despacho y consumo restan.
  bool get entra => tipo == 'RECEPCION';

  /// Cantidad con el signo que tiene sobre el stock, para mostrarla.
  double get cantidadConSigno => entra ? cantidad : -cantidad;

  factory MovimientoKardex.desdeJson(Map<String, dynamic> j) =>
      MovimientoKardex(
        id: j['id'] as int,
        tipo: j['tipoMovimiento'] as String,
        cantidad: (j['cantidad'] as num).toDouble(),
        fecha: DateTime.parse(j['fecha'] as String),
        materialId: j['materialId'] as int,
        materialSku: j['materialSku'] as String,
        materialNombre: j['materialNombre'] as String,
        usuarioNombre: j['usuarioNombre'] as String,
        trabajadorNombre: j['trabajadorNombre'] as String?,
        trabajadorRut: j['trabajadorRut'] as String?,
        costoUnitario: (j['costoUnitario'] as num?)?.toDouble(),
      );
}
