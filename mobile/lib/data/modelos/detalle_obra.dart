import 'obra.dart';

/// Refleja `ObraDetalleResponse`: todo lo que hay que saber de una obra en una
/// sola respuesta — quién la dirige, quién trabaja en ella y qué hay en su
/// bodega.
///
/// Viene armado del backend y no se reconstruye acá con cinco llamadas porque
/// el stock es la suma del kardex entero de la obra: pedirlo por partes sería
/// traer cientos de movimientos para mostrar una tarjeta.
class DetalleObra {
  const DetalleObra({
    required this.obra,
    required this.jefes,
    required this.cuadrillas,
    required this.trabajadores,
    required this.materiales,
    required this.herramientas,
    required this.resumen,
  });

  final Obra obra;
  final List<PersonaACargo> jefes;
  final List<CuadrillaDeObra> cuadrillas;
  final List<TrabajadorDeObra> trabajadores;
  final List<MaterialDeObra> materiales;
  final List<HerramientaDeObra> herramientas;
  final ResumenObra resumen;

  /// Lo que hay que reponer, primero lo crítico.
  List<MaterialDeObra> get faltantes =>
      materiales.where((m) => m.estado != EstadoStock.ok).toList()
        ..sort((a, b) => a.estado.index.compareTo(b.estado.index));

  /// Las herramientas se muestran agrupadas por nombre —"Taladro percutor × 3"—
  /// porque en obra se piensa en cuántas hay de cada una, no en cada QR.
  List<GrupoHerramientas> get herramientasAgrupadas {
    final grupos = <String, List<HerramientaDeObra>>{};
    for (final h in herramientas) {
      grupos.putIfAbsent(h.nombre, () => []).add(h);
    }
    return [
      for (final e in grupos.entries)
        GrupoHerramientas(nombre: e.key, unidades: e.value),
    ]..sort((a, b) {
      final porVencidas = b.vencidas.compareTo(a.vencidas);
      return porVencidas != 0 ? porVencidas : a.nombre.compareTo(b.nombre);
    });
  }

  factory DetalleObra.desdeJson(Map<String, dynamic> j) => DetalleObra(
    obra: Obra.desdeJson(j['obra'] as Map<String, dynamic>),
    jefes: _lista(j['jefes'], PersonaACargo.desdeJson),
    cuadrillas: _lista(j['cuadrillas'], CuadrillaDeObra.desdeJson),
    trabajadores: _lista(j['trabajadores'], TrabajadorDeObra.desdeJson),
    materiales: _lista(j['materiales'], MaterialDeObra.desdeJson),
    herramientas: _lista(j['herramientas'], HerramientaDeObra.desdeJson),
    resumen: ResumenObra.desdeJson(
      (j['resumen'] as Map<String, dynamic>?) ?? const {},
    ),
  );
}

class PersonaACargo {
  const PersonaACargo({
    required this.usuarioId,
    required this.nombre,
    required this.rut,
    required this.rol,
  });

  final int usuarioId;
  final String nombre;
  final String? rut;

  /// `RolUsuario`: JEFE_TERRENO, BODEGUERO o ADMIN.
  final String rol;

  factory PersonaACargo.desdeJson(Map<String, dynamic> j) => PersonaACargo(
    usuarioId: j['usuarioId'] as int,
    nombre: j['nombre'] as String,
    rut: j['rut'] as String?,
    rol: j['rol'] as String,
  );
}

class CuadrillaDeObra {
  const CuadrillaDeObra({
    required this.id,
    required this.nombre,
    required this.cantidadTrabajadores,
  });

  final int id;
  final String nombre;
  final int cantidadTrabajadores;

  factory CuadrillaDeObra.desdeJson(Map<String, dynamic> j) => CuadrillaDeObra(
    id: j['id'] as int,
    nombre: j['nombre'] as String,
    cantidadTrabajadores: (j['cantidadTrabajadores'] as num?)?.toInt() ?? 0,
  );
}

class TrabajadorDeObra {
  const TrabajadorDeObra({
    required this.id,
    required this.nombre,
    required this.rut,
    required this.cuadrillaId,
    required this.cuadrillaNombre,
  });

  final int id;
  final String nombre;
  final String? rut;
  final int? cuadrillaId;
  final String? cuadrillaNombre;

  factory TrabajadorDeObra.desdeJson(Map<String, dynamic> j) =>
      TrabajadorDeObra(
        id: j['id'] as int,
        nombre: j['nombre'] as String,
        rut: j['rut'] as String?,
        cuadrillaId: j['cuadrillaId'] as int?,
        cuadrillaNombre: j['cuadrillaNombre'] as String?,
      );
}

/// El orden del enum es el de la pantalla: lo crítico arriba.
enum EstadoStock {
  critico,
  bajo,
  ok;

  static EstadoStock desde(String? v) => switch (v) {
    'CRITICO' => critico,
    'BAJO' => bajo,
    _ => ok,
  };
}

class MaterialDeObra {
  const MaterialDeObra({
    required this.materialId,
    required this.sku,
    required this.nombre,
    required this.categoria,
    required this.stock,
    required this.stockMinimo,
    required this.precioUnitario,
    required this.ultimoCostoUnitario,
    required this.costoPromedio,
    required this.valorStock,
    required this.estado,
  });

  final int materialId;
  final String sku;
  final String nombre;
  final String categoria;
  final double stock;
  final double stockMinimo;
  final double precioUnitario;
  final double? ultimoCostoUnitario;
  final double? costoPromedio;

  /// Stock valorizado al último costo real, o al de catálogo si no hay.
  final double valorStock;
  final EstadoStock estado;

  double get costoVigente => ultimoCostoUnitario ?? precioUnitario;

  factory MaterialDeObra.desdeJson(Map<String, dynamic> j) {
    final stock = (j['stock'] as num).toDouble();
    final precio = (j['precioUnitario'] as num).toDouble();
    final ultimo = (j['ultimoCostoUnitario'] as num?)?.toDouble();
    return MaterialDeObra(
      materialId: j['materialId'] as int,
      sku: j['sku'] as String,
      nombre: j['nombre'] as String,
      categoria: j['categoria'] as String,
      stock: stock,
      stockMinimo: (j['stockMinimo'] as num).toDouble(),
      precioUnitario: precio,
      ultimoCostoUnitario: ultimo,
      costoPromedio: (j['costoPromedio'] as num?)?.toDouble(),
      valorStock:
          (j['valorStock'] as num?)?.toDouble() ??
          (stock < 0 ? 0 : stock) * (ultimo ?? precio),
      estado: EstadoStock.desde(j['estado'] as String?),
    );
  }
}

/// Una herramienta que está en la obra. Hoy el backend no asigna herramientas
/// a obras: las que "están" en una son las que tienen un préstamo abierto en
/// ella, así que siempre hay alguien que la tiene.
class HerramientaDeObra {
  const HerramientaDeObra({
    required this.prestamoId,
    required this.herramientaId,
    required this.codigoQr,
    required this.nombre,
    required this.categoria,
    required this.estado,
    required this.valorReposicion,
    required this.prestadaA,
    required this.fechaDevolEsperada,
    required this.vencida,
  });

  final int? prestamoId;
  final int herramientaId;
  final String codigoQr;
  final String nombre;
  final String categoria;

  /// `EstadoHerramienta`: DISPONIBLE, PRESTADA o MANTENCION.
  final String estado;
  final double valorReposicion;

  /// "Nombre · RUT" de quien la tiene. Nula solo si algún día el backend
  /// asigna herramientas a la obra sin préstamo.
  final String? prestadaA;
  final DateTime? fechaDevolEsperada;
  final bool vencida;

  factory HerramientaDeObra.desdeJson(Map<String, dynamic> j) {
    final quien = j['prestadaA'] as Map<String, dynamic>?;
    final nombre = quien?['nombre'] as String?;
    final rut = quien?['rut'] as String?;
    return HerramientaDeObra(
      prestamoId: j['prestamoId'] as int?,
      herramientaId: j['herramientaId'] as int,
      codigoQr: j['codigoQr'] as String,
      nombre: j['nombre'] as String,
      categoria: j['categoria'] as String,
      estado: j['estado'] as String,
      valorReposicion: (j['valorReposicion'] as num).toDouble(),
      prestadaA: nombre == null
          ? null
          : (rut == null ? nombre : '$nombre · $rut'),
      fechaDevolEsperada: j['fechaDevolEsperada'] == null
          ? null
          : DateTime.parse(j['fechaDevolEsperada'] as String),
      vencida: j['vencida'] as bool? ?? false,
    );
  }
}

class GrupoHerramientas {
  const GrupoHerramientas({required this.nombre, required this.unidades});

  final String nombre;
  final List<HerramientaDeObra> unidades;

  int get cantidad => unidades.length;
  int get prestadas => unidades.where((h) => h.prestadaA != null).length;
  int get vencidas => unidades.where((h) => h.vencida).length;
  double get valor => unidades.fold(0, (t, h) => t + h.valorReposicion);
}

class ResumenObra {
  const ResumenObra({
    required this.cantidadTrabajadores,
    required this.cantidadJefes,
    required this.materialesCriticos,
    required this.materialesBajos,
    required this.valorMateriales,
    required this.herramientasEnObra,
    required this.herramientasVencidas,
    required this.valorHerramientas,
    required this.alertasPendientes,
  });

  final int cantidadTrabajadores;
  final int cantidadJefes;
  final int materialesCriticos;
  final int materialesBajos;
  final double valorMateriales;
  final int herramientasEnObra;
  final int herramientasVencidas;
  final double valorHerramientas;
  final int alertasPendientes;

  int get materialesPorReponer => materialesCriticos + materialesBajos;

  factory ResumenObra.desdeJson(Map<String, dynamic> j) => ResumenObra(
    cantidadTrabajadores: _entero(j['cantidadTrabajadores']),
    cantidadJefes: _entero(j['cantidadJefes']),
    materialesCriticos: _entero(j['materialesCriticos']),
    materialesBajos: _entero(j['materialesBajos']),
    valorMateriales: (j['valorMateriales'] as num?)?.toDouble() ?? 0,
    herramientasEnObra: _entero(j['herramientasEnObra']),
    herramientasVencidas: _entero(j['herramientasVencidas']),
    valorHerramientas: (j['valorHerramientas'] as num?)?.toDouble() ?? 0,
    alertasPendientes: _entero(j['alertasPendientes']),
  );
}

/// Refleja `MaterialFaltanteResponse`: un material que se está agotando en una
/// obra activa. Es lo que alimenta el aviso de la pestaña Materiales, que es de
/// la empresa entera y no de una obra.
class MaterialFaltante {
  const MaterialFaltante({
    required this.obraId,
    required this.obraNombre,
    required this.materialId,
    required this.sku,
    required this.nombre,
    required this.categoria,
    required this.stock,
    required this.stockMinimo,
    required this.estado,
  });

  final int obraId;
  final String obraNombre;
  final int materialId;
  final String sku;
  final String nombre;
  final String categoria;
  final double stock;
  final double stockMinimo;
  final EstadoStock estado;

  bool get critico => estado == EstadoStock.critico;

  factory MaterialFaltante.desdeJson(Map<String, dynamic> j) =>
      MaterialFaltante(
        obraId: j['obraId'] as int,
        obraNombre: j['obraNombre'] as String,
        materialId: j['materialId'] as int,
        sku: j['sku'] as String,
        nombre: j['nombre'] as String,
        categoria: j['categoria'] as String,
        stock: (j['stock'] as num).toDouble(),
        stockMinimo: (j['stockMinimo'] as num).toDouble(),
        estado: EstadoStock.desde(j['estado'] as String?),
      );
}

int _entero(Object? v) => (v as num?)?.toInt() ?? 0;

List<T> _lista<T>(Object? v, T Function(Map<String, dynamic>) desde) => [
  for (final e in (v as List?) ?? const []) desde(e as Map<String, dynamic>),
];
