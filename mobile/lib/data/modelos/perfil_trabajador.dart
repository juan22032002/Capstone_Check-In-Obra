/// Refleja `TrabajadorPerfilResponse` (`GET /api/trabajadores/yo`): el
/// trabajador que entró, con su obra y su credencial.
///
/// Es la única respuesta en la que la credencial viaja sin que alguien la
/// acabe de emitir, y es porque se la pide su dueño para mostrarla. El código
/// es portador —quien lo tiene se presenta como este trabajador en el mesón
/// de bodega—, pero tiene que verse sin señal (RF-B9): en obra el mesón suele
/// estar donde no llega. Por eso la última copia se guarda en el
/// almacenamiento cifrado, junto al token y con la misma protección, y se
/// borra al cerrar sesión. Si se pierde el teléfono, renovar la anula.
class PerfilTrabajador {
  const PerfilTrabajador({
    required this.id,
    required this.usuarioId,
    required this.nombre,
    required this.rut,
    required this.cuadrillaId,
    required this.cuadrillaNombre,
    required this.obraId,
    required this.obraNombre,
    required this.obraEstado,
    required this.credencialQr,
    this.guardadoEl,
  });

  final int id;
  final int usuarioId;
  final String nombre;
  final String? rut;

  /// Nulos mientras no lo asignen a una cuadrilla. Es un estado real: sin
  /// cuadrilla no tiene obra, y sin obra no hay a qué bodega pedirle material.
  final int? cuadrillaId;
  final String? cuadrillaNombre;
  final int? obraId;
  final String? obraNombre;

  /// `EstadoObra`: ACTIVA o CERRADA.
  final String? obraEstado;

  final String? credencialQr;

  /// Cuándo se guardó la copia que se está mostrando. Nulo si viene recién
  /// del servidor; con fecha, el teléfono estaba sin conexión y puede que la
  /// credencial ya no sea la vigente.
  final DateTime? guardadoEl;

  bool get sinConexion => guardadoEl != null;

  bool get tieneObra => obraId != null;

  bool get obraActiva => obraEstado == 'ACTIVA';

  /// Puede pedir material: una solicitud de material es contra la bodega de
  /// una obra, y a una obra cerrada ya no entra ni sale nada.
  bool get puedePedirMaterial => tieneObra && obraActiva;

  String get identificacion => rut == null ? nombre : '$nombre · $rut';

  factory PerfilTrabajador.desdeJson(Map<String, dynamic> j) =>
      PerfilTrabajador(
        id: j['id'] as int,
        usuarioId: j['usuarioId'] as int,
        nombre: j['nombre'] as String,
        rut: j['rut'] as String?,
        cuadrillaId: j['cuadrillaId'] as int?,
        cuadrillaNombre: j['cuadrillaNombre'] as String?,
        obraId: j['obraId'] as int?,
        obraNombre: j['obraNombre'] as String?,
        obraEstado: j['obraEstado'] as String?,
        credencialQr: j['credencialQr'] as String?,
        guardadoEl: j['guardadoEl'] == null
            ? null
            : DateTime.tryParse(j['guardadoEl'] as String),
      );

  /// Para guardar la copia sin conexión. `guardadoEl` lo pone quien guarda.
  Map<String, dynamic> aJson() => {
    'id': id,
    'usuarioId': usuarioId,
    'nombre': nombre,
    'rut': rut,
    'cuadrillaId': cuadrillaId,
    'cuadrillaNombre': cuadrillaNombre,
    'obraId': obraId,
    'obraNombre': obraNombre,
    'obraEstado': obraEstado,
    'credencialQr': credencialQr,
  };
}
