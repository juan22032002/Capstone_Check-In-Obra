/// Qué clave se le puede definir a cada rol — la misma regla que aplica el
/// backend (`Usuario.definirPin`), para avisar en el formulario en vez de
/// esperar el 400.
///
/// El TRABAJADOR entra con un PIN de 4 dígitos, porque lo teclea con guantes en
/// un teclado propio. ADMIN, JEFE_TERRENO y BODEGUERO tienen acceso a datos de
/// toda la empresa y entran con correo y una clave de 8 a 72 caracteres: 4
/// dígitos son diez mil combinaciones.
abstract final class PoliticaClave {
  static const largoPin = 4;
  static const minimoClave = 8;
  static const maximoClave = 72;

  static bool esPin(String rol) => rol == 'TRABAJADOR';

  /// Por qué la clave no sirve para ese rol, o `null` si sirve.
  static String? error(String clave, {required String rol}) {
    // Se cuentan caracteres y no unidades UTF-16: "ñ" o un emoji son uno.
    final largo = clave.runes.length;
    if (esPin(rol)) {
      return RegExp(r'^\d{4}$').hasMatch(clave) ? null : 'El PIN son 4 dígitos';
    }
    if (largo < minimoClave) {
      return 'La clave necesita al menos $minimoClave caracteres';
    }
    if (largo > maximoClave) {
      return 'La clave admite hasta $maximoClave caracteres';
    }
    return null;
  }

  /// Para el login: no se vuelven a exigir las reglas de definición (una clave
  /// antigua de 4 dígitos todavía entra), solo que haya algo razonable.
  static String? errorAlEntrar(String clave) {
    final largo = clave.runes.length;
    if (largo < largoPin) return 'Escribe tu PIN o tu clave';
    if (largo > maximoClave) {
      return 'La clave admite hasta $maximoClave caracteres';
    }
    return null;
  }

  static String etiqueta(String rol) => esPin(rol) ? 'PIN' : 'clave';

  /// Lo que cuenta el campo de definición, para que se vea cuánto falta.
  static String progreso(String clave, {required String rol}) {
    final largo = clave.runes.length;
    return esPin(rol)
        ? '$largo de $largoPin dígitos'
        : '$largo de $minimoClave caracteres como mínimo';
  }
}
