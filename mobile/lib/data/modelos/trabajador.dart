/// Refleja `TrabajadorResponse` del backend.
///
/// El RUT ya no vive en `Trabajador` sino en su `Usuario` — identifica a la
/// persona, no al rol— pero la API lo sigue entregando aplanado acá, que es
/// como se necesita para mostrarlo.
class Trabajador {
  const Trabajador({
    required this.id,
    required this.rut,
    required this.nombre,
    required this.cuadrillaId,
  });

  final int id;
  final String? rut;
  final String nombre;
  final int? cuadrillaId;

  /// "Marcelo Sepúlveda · 17.930.556-9", que es como se identifica a alguien
  /// en obra cuando hay dos con el mismo nombre de pila.
  String get identificacion => rut == null ? nombre : '$nombre · $rut';

  factory Trabajador.desdeJson(Map<String, dynamic> j) => Trabajador(
    id: j['id'] as int,
    rut: j['rut'] as String?,
    nombre: j['nombre'] as String,
    cuadrillaId: j['cuadrillaId'] as int?,
  );
}
