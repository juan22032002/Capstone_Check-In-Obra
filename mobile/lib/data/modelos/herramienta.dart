/// Refleja `HerramientaResponse` del backend.
class Herramienta {
  const Herramienta({
    required this.id,
    required this.codigoQr,
    required this.nombre,
    required this.categoria,
    required this.estado,
    required this.valorReposicion,
    this.tieneValor = true,
  });

  final int id;

  /// Impreso en la herramienta misma: es lo que se escanea.
  final String codigoQr;
  final String nombre;
  final String categoria;

  /// `EstadoHerramienta`: DISPONIBLE, PRESTADA o MANTENCION.
  final String estado;

  /// Lo que cuesta reponerla. El backend **no lo manda** al TRABAJADOR: cuando
  /// falta queda en 0 y [tieneValor] en `false`; no mostrar "$0" como si fuera
  /// un valor.
  final double valorReposicion;

  /// `false` si el servidor no envió `valorReposicion` (rol sin acceso a costos).
  final bool tieneValor;

  bool get disponible => estado == 'DISPONIBLE';

  factory Herramienta.desdeJson(Map<String, dynamic> j) => Herramienta(
    id: j['id'] as int,
    codigoQr: j['codigoQr'] as String,
    nombre: j['nombre'] as String,
    categoria: j['categoria'] as String,
    estado: j['estado'] as String,
    valorReposicion: (j['valorReposicion'] as num?)?.toDouble() ?? 0,
    tieneValor: j['valorReposicion'] != null,
  );
}

/// Refleja `PrestamoHerramientaResponse`.
class Prestamo {
  const Prestamo({
    required this.id,
    required this.fechaPrestamo,
    required this.fechaDevolEsperada,
    required this.fechaDevolReal,
    required this.herramientaId,
    required this.herramientaNombre,
    required this.trabajadorNombre,
    required this.trabajadorRut,
    required this.autorizadoPorNombre,
  });

  final int id;
  final DateTime? fechaPrestamo;
  final DateTime? fechaDevolEsperada;

  /// Nula mientras la herramienta siga fuera de bodega.
  final DateTime? fechaDevolReal;

  final int herramientaId;
  final String herramientaNombre;
  final String trabajadorNombre;
  final String? trabajadorRut;
  final String autorizadoPorNombre;

  /// Quién tiene la herramienta, identificado sin ambigüedad.
  String get quienLaTiene => trabajadorRut == null
      ? trabajadorNombre
      : '$trabajadorNombre · $trabajadorRut';

  bool get abierto => fechaDevolReal == null;

  bool get vencido =>
      abierto &&
      fechaDevolEsperada != null &&
      fechaDevolEsperada!.isBefore(DateTime.now());

  static DateTime? _fecha(Object? v) =>
      v == null ? null : DateTime.parse(v as String);

  factory Prestamo.desdeJson(Map<String, dynamic> j) => Prestamo(
    id: j['id'] as int,
    fechaPrestamo: _fecha(j['fechaPrestamo']),
    fechaDevolEsperada: _fecha(j['fechaDevolEsperada']),
    fechaDevolReal: _fecha(j['fechaDevolReal']),
    herramientaId: j['herramientaId'] as int,
    herramientaNombre: j['herramientaNombre'] as String,
    trabajadorNombre: j['trabajadorNombre'] as String,
    trabajadorRut: j['trabajadorRut'] as String?,
    autorizadoPorNombre: j['autorizadoPorNombre'] as String,
  );
}
