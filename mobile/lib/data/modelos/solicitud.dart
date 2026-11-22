/// Lo que un trabajador pidió y el bodeguero todavía no resuelve.
///
/// Hay dos solicitudes distintas —material y herramienta— porque terminan en
/// cosas distintas: aprobar una de material genera un despacho en el kardex y
/// aprobar una de herramienta genera un préstamo con fecha de devolución. Se
/// modelan aparte por eso, no por simetría con el backend.
library;

/// Estados de `EstadoSolicitud` en el backend.
const estadoPendiente = 'PENDIENTE';

/// Nombre legible de cada `EstadoSolicitud`. CANCELADA es la que retiró el
/// propio trabajador antes de que la atendieran.
String nombreDeEstadoSolicitud(String estado) => switch (estado) {
  'PENDIENTE' => 'Pendiente',
  'APROBADA' => 'Aprobada',
  'ENTREGADA' => 'Entregada',
  'RECHAZADA' => 'Rechazada',
  'CANCELADA' => 'Cancelada',
  _ => estado,
};

DateTime? _fecha(Object? v) => v == null ? null : DateTime.parse(v as String);

/// Refleja `SolicitudMaterialResponse`.
class SolicitudMaterial {
  const SolicitudMaterial({
    required this.id,
    required this.cantidad,
    required this.estado,
    required this.fechaSolicitud,
    required this.motivoRechazo,
    required this.trabajadorId,
    required this.trabajadorNombre,
    required this.trabajadorRut,
    required this.materialId,
    required this.materialSku,
    required this.materialNombre,
    required this.obraId,
    required this.resueltoPorNombre,
    this.descripcion,
    this.fechaRecepcion,
    this.cantidadEntregada,
  });

  final int id;
  final double cantidad;
  final String estado;
  final DateTime? fechaSolicitud;
  final String? motivoRechazo;
  final int trabajadorId;
  final String trabajadorNombre;
  final String? trabajadorRut;
  final int materialId;
  final String materialSku;
  final String materialNombre;
  final int obraId;
  final String? resueltoPorNombre;

  /// Para qué lo necesita, en palabras de quien pidió. Nula en las anteriores
  /// a que se exigiera.
  final String? descripcion;

  /// Cuándo el trabajador confirmó que lo recibió. Nula hasta entonces.
  final DateTime? fechaRecepcion;

  /// Lo que bodega entregó al aprobar. Puede ser menos de lo pedido: si no
  /// alcanza el stock, el bodeguero aprueba con lo que hay. Nula mientras
  /// no se aprueba, y en las aprobadas antes de que se registrara.
  final double? cantidadEntregada;

  bool get pendiente => estado == estadoPendiente;

  /// Bodega ya lo entregó y falta que el trabajador lo confirme.
  bool get porConfirmar => estado == 'APROBADA';

  /// Le entregaron menos de lo que pidió.
  bool get entregaParcial =>
      cantidadEntregada != null && cantidadEntregada! < cantidad;

  factory SolicitudMaterial.desdeJson(Map<String, dynamic> j) =>
      SolicitudMaterial(
        id: j['id'] as int,
        cantidad: (j['cantidad'] as num).toDouble(),
        estado: j['estado'] as String,
        fechaSolicitud: j['fechaSolicitud'] == null
            ? null
            : DateTime.parse(j['fechaSolicitud'] as String),
        motivoRechazo: j['motivoRechazo'] as String?,
        trabajadorId: j['trabajadorId'] as int,
        trabajadorNombre: j['trabajadorNombre'] as String,
        trabajadorRut: j['trabajadorRut'] as String?,
        materialId: j['materialId'] as int,
        materialSku: j['materialSku'] as String,
        materialNombre: j['materialNombre'] as String,
        obraId: j['obraId'] as int,
        resueltoPorNombre: j['resueltoPorNombre'] as String?,
        descripcion: j['descripcion'] as String?,
        fechaRecepcion: _fecha(j['fechaRecepcion']),
        cantidadEntregada: (j['cantidadEntregada'] as num?)?.toDouble(),
      );
}

/// Refleja `SolicitudHerramientaResponse`.
class SolicitudHerramienta {
  const SolicitudHerramienta({
    required this.id,
    required this.cantidad,
    required this.estado,
    required this.fechaSolicitud,
    required this.motivoRechazo,
    required this.trabajadorId,
    required this.trabajadorNombre,
    required this.trabajadorRut,
    required this.herramientaId,
    required this.herramientaNombre,
    required this.resueltoPorNombre,
    this.descripcion,
    this.fechaRecepcion,
    this.pedidoId,
  });

  final int id;
  final int cantidad;
  final String estado;
  final DateTime? fechaSolicitud;
  final String? motivoRechazo;
  final int trabajadorId;
  final String trabajadorNombre;
  final String? trabajadorRut;
  final int herramientaId;
  final String herramientaNombre;
  final String? resueltoPorNombre;

  /// Para qué lo necesita, en palabras de quien pidió. Nula en las anteriores
  /// a que se exigiera.
  final String? descripcion;

  /// Cuándo el trabajador confirmó que lo recibió. Nula hasta entonces.
  final DateTime? fechaRecepcion;

  /// El pedido con QR que la trajo. Nulo si se pidió sola.
  final int? pedidoId;

  bool get pendiente => estado == estadoPendiente;

  /// Bodega ya lo entregó y falta que el trabajador lo confirme.
  bool get porConfirmar => estado == 'APROBADA';

  factory SolicitudHerramienta.desdeJson(Map<String, dynamic> j) =>
      SolicitudHerramienta(
        id: j['id'] as int,
        cantidad: j['cantidad'] as int,
        estado: j['estado'] as String,
        fechaSolicitud: j['fechaSolicitud'] == null
            ? null
            : DateTime.parse(j['fechaSolicitud'] as String),
        motivoRechazo: j['motivoRechazo'] as String?,
        trabajadorId: j['trabajadorId'] as int,
        trabajadorNombre: j['trabajadorNombre'] as String,
        trabajadorRut: j['trabajadorRut'] as String?,
        herramientaId: j['herramientaId'] as int,
        herramientaNombre: j['herramientaNombre'] as String,
        resueltoPorNombre: j['resueltoPorNombre'] as String?,
        descripcion: j['descripcion'] as String?,
        fechaRecepcion: _fecha(j['fechaRecepcion']),
        pedidoId: j['pedidoId'] as int?,
      );
}
