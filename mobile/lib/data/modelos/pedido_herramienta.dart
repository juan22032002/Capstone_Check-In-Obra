import 'herramienta.dart';
import 'solicitud.dart';
import 'trabajador.dart';

/// Varias herramientas pedidas de una vez, que se retiran con un QR.
///
/// El trabajador marca lo que necesita, la app le muestra el código y el
/// bodeguero lo escanea para entregar todo junto. Por debajo cada herramienta
/// sigue siendo una `SolicitudHerramienta`: el pedido solo las agrupa y les da
/// un código que se pueda mostrar en el mesón.
///
/// Refleja `PedidoHerramientaResponse`.
class PedidoHerramienta {
  const PedidoHerramienta({
    required this.id,
    required this.codigoQr,
    required this.estado,
    required this.fechaSolicitud,
    required this.descripcion,
    required this.trabajador,
    required this.solicitudes,
    this.fechaEntrega,
    this.entregadoPorNombre,
  });

  final int id;

  /// El UUID del pedido, sin prefijo. Es lo que reciben los endpoints.
  final String codigoQr;

  /// PENDIENTE, ENTREGADO o CANCELADO.
  final String estado;
  final DateTime? fechaSolicitud;

  /// Para qué las necesita: uno solo para todo el pedido.
  final String? descripcion;
  final Trabajador trabajador;
  final List<SolicitudHerramienta> solicitudes;

  /// Cuándo y quién de bodega lo entregó. Nulos mientras no se entrega.
  final DateTime? fechaEntrega;
  final String? entregadoPorNombre;

  /// Lo que se lee en el QR lleva el prefijo para que el escáner de bodega
  /// sepa que es un pedido y no una credencial, que también es un UUID.
  static const prefijoQr = 'PEDIDO:';

  /// Lo más que acepta el backend en un pedido; con más responde 400.
  static const maximoHerramientas = 20;

  /// El código a dibujar en el QR.
  String get contenidoQr => '$prefijoQr$codigoQr';

  bool get pendiente => estado == 'PENDIENTE';
  bool get entregado => estado == 'ENTREGADO';
  bool get cancelado => estado == 'CANCELADO';

  /// El UUID de un QR de pedido, o `null` si lo leído no es un pedido.
  static String? codigoDesdeQr(String leido) {
    final t = leido.trim();
    if (t.length <= prefijoQr.length ||
        t.substring(0, prefijoQr.length).toUpperCase() != prefijoQr) {
      return null;
    }
    return t.substring(prefijoQr.length).trim();
  }

  factory PedidoHerramienta.desdeJson(Map<String, dynamic> j) =>
      PedidoHerramienta(
        id: j['id'] as int,
        codigoQr: j['codigoQr'] as String,
        estado: j['estado'] as String,
        fechaSolicitud: j['fechaSolicitud'] == null
            ? null
            : DateTime.parse(j['fechaSolicitud'] as String),
        descripcion: j['descripcion'] as String?,
        trabajador: Trabajador.desdeJson(
          j['trabajador'] as Map<String, dynamic>,
        ),
        solicitudes: [
          for (final s in (j['solicitudes'] as List<dynamic>? ?? const []))
            SolicitudHerramienta.desdeJson(s as Map<String, dynamic>),
        ],
        fechaEntrega: j['fechaEntrega'] == null
            ? null
            : DateTime.parse(j['fechaEntrega'] as String),
        entregadoPorNombre: j['entregadoPorNombre'] as String?,
      );
}

/// Nombre legible de cada estado del pedido.
String nombreDeEstadoPedido(String estado) => switch (estado) {
  'PENDIENTE' => 'Por retirar',
  'ENTREGADO' => 'Entregado',
  'CANCELADO' => 'Cancelado',
  _ => estado,
};

/// Lo que devuelve entregar un pedido: el pedido ya entregado y un préstamo
/// por herramienta, cada uno con su fecha de devolución.
class EntregaPedido {
  const EntregaPedido({required this.pedido, required this.prestamos});

  final PedidoHerramienta pedido;
  final List<Prestamo> prestamos;

  factory EntregaPedido.desdeJson(Map<String, dynamic> j) => EntregaPedido(
    pedido: PedidoHerramienta.desdeJson(j['pedido'] as Map<String, dynamic>),
    prestamos: [
      for (final p in (j['prestamos'] as List<dynamic>? ?? const []))
        Prestamo.desdeJson(p as Map<String, dynamic>),
    ],
  );
}
