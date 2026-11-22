import 'package:intl/intl.dart';

/// Formato chileno para todo lo que se muestra: punto como separador de miles,
/// coma decimal. Un "1,240" en una pantalla de bodega chilena se lee como mil
/// doscientos cuarenta, no como uno coma dos.
abstract final class Formato {
  /// El símbolo se antepone a mano. `NumberFormat.currency` con `es_CL`
  /// devuelve "5.980 $" —símbolo al final, con espacio— y en Chile los precios
  /// se escriben "$5.980". El separador de miles sí lo pone el locale.
  static final _enteros = NumberFormat('#,##0', 'es_CL');

  static final _cantidad = NumberFormat('#,##0.##', 'es_CL');
  static final _hora = DateFormat('HH:mm', 'es_CL');
  static final _fechaCorta = DateFormat('dd MMM', 'es_CL');
  static final _fechaHora = DateFormat('dd MMM HH:mm', 'es_CL');
  static final _fechaCompleta = DateFormat('dd MMM yyyy', 'es_CL');

  static String pesos(double v) => '\$${_enteros.format(v)}';

  /// Cantidades de material: se muestran sin decimales cuando son enteras,
  /// porque "36 pl" se lee más rápido que "36,00 pl".
  static String cantidad(double v) => _cantidad.format(v);

  static String cantidadConSigno(double v) =>
      '${v > 0
          ? '+'
          : v < 0
          ? '−'
          : ''}${_cantidad.format(v.abs())}';

  static String hora(DateTime d) => _hora.format(d);

  /// "45 segundos", "1 minuto", "2 min 30 s", "1 h": una espera como se dice,
  /// redondeada hacia arriba (esperar de menos vuelve a bloquear).
  static String espera(int segundos) {
    if (segundos < 60) {
      return '$segundos ${segundos == 1 ? 'segundo' : 'segundos'}';
    }
    final minutos = segundos ~/ 60;
    final resto = segundos % 60;
    if (minutos < 60) {
      if (resto == 0) return '$minutos ${minutos == 1 ? 'minuto' : 'minutos'}';
      return '$minutos min $resto s';
    }
    final horas = minutos ~/ 60;
    final m = minutos % 60;
    return m == 0 ? '$horas h' : '$horas h $m min';
  }

  static String fechaHora(DateTime d) => _fechaHora.format(d);

  /// "05 sep 2026" — una fecha sin hora, con el año.
  static String fecha(DateTime d) => _fechaCompleta.format(d);

  /// "hoy 09:02", "ayer 15:41" o "22 ago" — como en el mockup del kardex.
  static String relativa(DateTime d) {
    final ahora = DateTime.now();
    final dia = DateTime(d.year, d.month, d.day);
    final hoy = DateTime(ahora.year, ahora.month, ahora.day);
    final diferencia = hoy.difference(dia).inDays;
    if (diferencia == 0) return 'hoy ${_hora.format(d)}';
    if (diferencia == 1) return 'ayer ${_hora.format(d)}';
    return _fechaCorta.format(d);
  }

  /// Lee un número **tal como lo teclea alguien en Chile**.
  ///
  /// El caso difícil es el punto: en "5.980" separa miles y en "0.75" es
  /// decimal, y el teclado numérico de Android ofrece los dos signos sin
  /// distinguirlos. La regla es la misma que aplica el backend al leer una
  /// planilla ({@code Numeros.decimal}), para que el mismo texto signifique lo
  /// mismo tecleado que importado:
  ///
  /// - con coma, la coma es el decimal y el punto separa miles ("12.500,75");
  /// - con punto solo, separa miles **si** el número tiene forma de miles —la
  ///   parte entera no empieza en cero y cada grupo tras un punto tiene tres
  ///   dígitos ("5.980" → 5980, "1.234.567")— y es decimal en cualquier otro
  ///   caso ("0.75" → 0,75; "0.750" → 0,75).
  ///
  /// Mirar solo "tres dígitos detrás" no basta: "0.750" se leía como 750. Nadie
  /// escribe setecientos cincuenta como "0.750", pero sí tres cuartos de metro.
  ///
  /// Antes cada pantalla tenía su propia regla: la de movimiento leía "1.200"
  /// como 1,2 y la de aprobación leía "0.5" como 5. Son cantidades que van al
  /// kardex, así que un factor de mil o de diez ahí no se nota hasta el
  /// descuadre.
  static final _conMiles = RegExp(r'^[1-9]\d{0,2}(\.\d{3})+$');

  static double? numero(String texto) {
    var limpio = texto.replaceAll(' ', '').replaceAll('\u00A0', '').trim();
    if (limpio.isEmpty) return null;

    if (limpio.contains(',')) {
      limpio = limpio.replaceAll('.', '').replaceAll(',', '.');
    } else {
      if (_conMiles.hasMatch(limpio)) limpio = limpio.replaceAll('.', '');
    }

    return double.tryParse(limpio);
  }

  /// Por qué un RUT no sirve, o `null` si sirve.
  ///
  /// Es la misma regla que aplica el backend al crear un usuario, para avisar
  /// en el formulario en vez de esperar el 400: se quitan puntos, guion y
  /// espacios, se pasa a mayúscula, el cuerpo tiene de 1 a 8 dígitos y el
  /// dígito verificador (0-9 o K) sale del módulo 11.
  static String? errorDeRut(String texto) {
    final limpio = _limpiarRut(texto);
    if (limpio.isEmpty) return 'El RUT es obligatorio';
    if (!RegExp(r'^\d{1,8}[0-9K]$').hasMatch(limpio)) {
      return 'Escribe el RUT con su dígito verificador, por ejemplo 12.345.678-5';
    }
    final cuerpo = limpio.substring(0, limpio.length - 1);
    if (_digitoVerificador(cuerpo) != limpio[limpio.length - 1]) {
      return 'El RUT no es válido: revisa el dígito verificador';
    }
    return null;
  }

  /// El RUT en el formato que guarda el backend: 12.345.678-5, con K
  /// mayúscula. Solo para un RUT que ya pasó `errorDeRut`.
  static String rutCanonico(String texto) {
    final limpio = _limpiarRut(texto);
    final cuerpo = limpio.substring(0, limpio.length - 1);
    final dv = limpio[limpio.length - 1];
    return '${_enteros.format(int.parse(cuerpo))}-$dv';
  }

  static String _limpiarRut(String texto) =>
      texto.replaceAll(RegExp(r'[.\-\s]'), '').toUpperCase();

  static String _digitoVerificador(String cuerpo) {
    var suma = 0;
    var factor = 2;
    for (var i = cuerpo.length - 1; i >= 0; i--) {
      suma += int.parse(cuerpo[i]) * factor;
      factor = factor == 7 ? 2 : factor + 1;
    }
    final resto = 11 - suma % 11;
    return switch (resto) {
      11 => '0',
      10 => 'K',
      _ => '$resto',
    };
  }

  /// "hace 2 h", "hace 14 h", "hace 3 d" — para la antigüedad de una alerta.
  static String antiguedad(DateTime d) {
    final minutos = DateTime.now().difference(d).inMinutes;
    if (minutos < 1) return 'recién';
    if (minutos < 60) return 'hace $minutos min';
    final horas = minutos ~/ 60;
    if (horas < 24) return 'hace $horas h';
    return 'hace ${horas ~/ 24} d';
  }
}
