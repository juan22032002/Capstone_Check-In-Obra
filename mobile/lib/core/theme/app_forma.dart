import 'package:flutter/widgets.dart';

/// Forma y espacio del sistema.
///
/// Dos radios, nunca uno intermedio: 12 para todo lo que se toca o agrupa
/// —botón, campo, tarjeta, hoja— y 6 para lo que solo rotula —chips—. Un
/// radio "de compromiso" de 8 o 10 en un solo componente se ve como un error
/// al lado de los demás.
abstract final class AppForma {
  static const radio = 12.0;
  static const radioChip = 6.0;

  static const borde = BorderRadius.all(Radius.circular(radio));
  static const bordeChip = BorderRadius.all(Radius.circular(radioChip));

  /// Solo arriba: las hojas que suben desde el borde inferior.
  static const bordeHoja = BorderRadius.vertical(top: Radius.circular(radio));
}

/// Escala de espacio sobre una base de 4. Los nombres dicen para qué es cada
/// uno, así una pantalla no inventa un 14 o un 18 por su cuenta.
abstract final class AppEspacio {
  /// Entre un rótulo y su dato, entre un ícono y su texto.
  static const xs = 4.0;

  /// Entre elementos de un mismo grupo.
  static const sm = 8.0;

  /// Relleno de tarjeta y separación entre tarjetas de una lista.
  static const md = 16.0;

  /// Entre grupos dentro de una pantalla.
  static const lg = 24.0;

  /// Entre secciones.
  static const xl = 32.0;

  /// Margen lateral de toda pantalla.
  static const pantalla = EdgeInsets.all(md);
}
