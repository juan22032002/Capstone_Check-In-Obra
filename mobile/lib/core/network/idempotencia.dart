import 'dart:math';

/// La clave `Idempotency-Key` de **una** intención del usuario.
///
/// El problema que resuelve: el timeout de la app es de ocho segundos, y en la
/// red de la obra pasa que el servidor alcanza a guardar el despacho pero la
/// respuesta no alcanza a volver. El bodeguero ve "el servidor no respondió",
/// toca de nuevo y el kardex queda con dos despachos. Con la clave, el segundo
/// envío le devuelve al teléfono la respuesta del primero en vez de repetirlo.
///
/// La clave vive en la pantalla u hoja que registra la acción, no en el cliente
/// HTTP, porque lo que se deduplica es la *intención*, no el cuerpo: dos
/// recepciones idénticas de 10 planchas son dos entregas del proveedor, se
/// registran desde dos pantallas distintas y llevan dos claves distintas.
///
/// Dentro de la misma pantalla, la clave se reutiliza mientras el cuerpo no
/// cambie —eso es "reintentar"— y se renueva si el usuario corrige algo tras un
/// fallo, porque el backend rechaza con 422 una clave repetida con otro cuerpo.
class IntentoIdempotente {
  String? _clave;
  List<Object?>? _huella;

  /// La clave para enviar estos datos. `huella` son los valores que forman el
  /// cuerpo: si difieren de los del envío anterior, es otra intención.
  String clavePara(List<Object?> huella) {
    final anterior = _huella;
    if (_clave == null || anterior == null || !_mismos(anterior, huella)) {
      _clave = uuidV4();
      _huella = List.unmodifiable(huella);
    }
    return _clave!;
  }

  /// Para las pantallas que siguen abiertas tras un éxito y pueden registrar
  /// otra cosa: la siguiente acción es una intención nueva.
  void reiniciar() {
    _clave = null;
    _huella = null;
  }

  static bool _mismos(List<Object?> a, List<Object?> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

final _aleatorio = Random.secure();

/// UUID versión 4 (RFC 9562), que es lo que el backend valida en la cabecera.
/// Son dieciséis bytes: no justifica sumar una dependencia.
String uuidV4() {
  final b = List<int>.generate(16, (_) => _aleatorio.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40; // versión 4
  b[8] = (b[8] & 0x3f) | 0x80; // variante RFC
  String hex(int desde, int hasta) => b
      .sublist(desde, hasta)
      .map((x) => x.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex(0, 4)}-${hex(4, 6)}-${hex(6, 8)}-${hex(8, 10)}-${hex(10, 16)}';
}
