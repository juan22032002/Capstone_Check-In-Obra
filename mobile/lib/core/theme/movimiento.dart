import 'package:flutter/widgets.dart';

/// Tiempos y curvas de la app. Pocos y cortos a propósito.
///
/// La app se usa decenas de veces por turno para lo mismo —aprobar, despachar,
/// recibir—, así que nada de lo que se repite puede demorar al bodeguero. La
/// animación acá tiene dos trabajos y ninguno decorativo: confirmar que el
/// toque llegó (la presión) y evitar que un cambio de estado se lea como un
/// salto o un parpadeo (el saldo que pasa a rojo, la lista que se refresca).
abstract final class Movimiento {
  /// Respuesta a la presión de un dedo.
  static const presion = Duration(milliseconds: 110);

  /// Cambio de estado dentro de una pantalla: color de un panel, un aviso que
  /// aparece, el texto de un botón que pasa a "Registrando…".
  static const estado = Duration(milliseconds: 180);

  /// Salida fuerte: arranca rápido, que es cuando el ojo está mirando. Las
  /// curvas de fábrica (`Curves.easeOut`) son demasiado tibias para esto.
  static const salida = Cubic(0.23, 1, 0.32, 1);

  /// Cuánto se hunde lo que se aprieta. Sutil: se siente más de lo que se ve.
  static const escalaPresion = 0.97;

  /// `Duration.zero` si la persona pidió reducir las animaciones en Android.
  /// Reducir no es anular el cambio: el estado final se muestra igual, solo
  /// que sin transición.
  static Duration de(BuildContext context, Duration normal) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false
      ? Duration.zero
      : normal;
}
