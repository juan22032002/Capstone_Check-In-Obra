/// Refleja `PedidoEspecialResponse`: algo que el trabajador necesita y que
/// bodega no puede entregar de inmediato —no está en el catálogo, o está pero
/// no hay— y hay que conseguir.
///
/// No es una solicitud de catálogo con otro nombre: no descuenta stock al
/// aprobarse porque no hay stock que descontar. Es un encargo que avanza por
/// estados hasta que el trabajador confirma que lo recibió.
class PedidoEspecial {
  const PedidoEspecial({
    required this.id,
    required this.tipo,
    required this.nombre,
    required this.cantidad,
    required this.unidad,
    required this.descripcion,
    required this.materialId,
    required this.herramientaId,
    required this.estado,
    required this.obraId,
    required this.obraNombre,
    required this.trabajadorId,
    required this.trabajadorNombre,
    required this.trabajadorRut,
    required this.fechaSolicitud,
    required this.fechaActualizacion,
    required this.notaBodega,
    required this.motivoRechazo,
    required this.gestionadoPorNombre,
    required this.fechaEntrega,
    required this.fechaRecepcion,
  });

  final int id;

  /// MATERIAL o HERRAMIENTA.
  final String tipo;

  /// Lo que se pide, en palabras de quien pide.
  final String nombre;
  final double cantidad;
  final String? unidad;

  /// Para qué lo necesita.
  final String descripcion;

  /// Si lo pedido existe en el catálogo pero no había, apunta a él.
  final int? materialId;
  final int? herramientaId;

  /// `EstadoPedidoEspecial`.
  final String estado;
  final int obraId;
  final String obraNombre;
  final int trabajadorId;
  final String trabajadorNombre;
  final String? trabajadorRut;
  final DateTime? fechaSolicitud;
  final DateTime? fechaActualizacion;

  /// Lo que bodega le dice al trabajador mientras lo consigue ("llega el
  /// jueves").
  final String? notaBodega;
  final String? motivoRechazo;
  final String? gestionadoPorNombre;
  final DateTime? fechaEntrega;
  final DateTime? fechaRecepcion;

  bool get esHerramienta => tipo == 'HERRAMIENTA';

  /// Todavía no termina: bodega tiene algo que hacer, o el trabajador tiene
  /// que confirmar.
  bool get abierto => const {
    'PENDIENTE',
    'EN_GESTION',
    'LISTO_PARA_RETIRO',
    'ENTREGADO',
  }.contains(estado);

  /// El trabajador todavía puede retirarlo: nadie lo consiguió.
  bool get cancelable => estado == 'PENDIENTE' || estado == 'EN_GESTION';

  /// Bodega lo entregó y falta la confirmación del trabajador.
  bool get porConfirmar => estado == 'ENTREGADO';

  String get cantidadConUnidad {
    final n = cantidad == cantidad.roundToDouble()
        ? cantidad.toStringAsFixed(0)
        : cantidad.toString().replaceAll('.', ',');
    return unidad == null || unidad!.isEmpty ? n : '$n $unidad';
  }

  /// El siguiente paso que puede dar bodega, o nulo si no le toca a bodega.
  PasoPedido? get siguientePaso => switch (estado) {
    'PENDIENTE' => PasoPedido.gestionar,
    'EN_GESTION' => PasoPedido.listo,
    'LISTO_PARA_RETIRO' => PasoPedido.entregar,
    _ => null,
  };

  static DateTime? _fecha(Object? v) =>
      v == null ? null : DateTime.parse(v as String);

  factory PedidoEspecial.desdeJson(Map<String, dynamic> j) => PedidoEspecial(
    id: j['id'] as int,
    tipo: j['tipo'] as String,
    nombre: j['nombre'] as String,
    cantidad: (j['cantidad'] as num).toDouble(),
    unidad: j['unidad'] as String?,
    descripcion: j['descripcion'] as String? ?? '',
    materialId: j['materialId'] as int?,
    herramientaId: j['herramientaId'] as int?,
    estado: j['estado'] as String,
    obraId: j['obraId'] as int,
    obraNombre: j['obraNombre'] as String? ?? '',
    trabajadorId: j['trabajadorId'] as int,
    trabajadorNombre: j['trabajadorNombre'] as String,
    trabajadorRut: j['trabajadorRut'] as String?,
    fechaSolicitud: _fecha(j['fechaSolicitud']),
    fechaActualizacion: _fecha(j['fechaActualizacion']),
    notaBodega: j['notaBodega'] as String?,
    motivoRechazo: j['motivoRechazo'] as String?,
    gestionadoPorNombre: j['gestionadoPorNombre'] as String?,
    fechaEntrega: _fecha(j['fechaEntrega']),
    fechaRecepcion: _fecha(j['fechaRecepcion']),
  );
}

/// Lo que bodega hace con un pedido especial, en orden.
enum PasoPedido {
  gestionar('Lo estoy consiguiendo', 'gestionar'),
  listo('Ya llegó: avisar para retirar', 'listo'),
  entregar('Entregar al trabajador', 'entregar');

  const PasoPedido(this.rotulo, this.ruta);

  final String rotulo;

  /// Segmento del endpoint: `/api/pedidos-especiales/{id}/<ruta>`.
  final String ruta;
}

/// Nombre legible de cada estado, para el trabajador y para bodega.
String nombreDeEstadoPedido(String estado) => switch (estado) {
  'PENDIENTE' => 'Pendiente',
  'EN_GESTION' => 'Consiguiéndolo',
  'LISTO_PARA_RETIRO' => 'Listo para retirar',
  'ENTREGADO' => 'Entregado',
  'RECIBIDO' => 'Recibido',
  'RECHAZADO' => 'Rechazado',
  'CANCELADO' => 'Cancelado',
  _ => estado,
};
