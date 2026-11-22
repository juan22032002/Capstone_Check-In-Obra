import 'package:flutter/services.dart';

/// Brillo de la pantalla mientras se muestra la credencial.
///
/// El lector del bodeguero no lee un QR en una pantalla oscura, y en obra
/// el trabajador tiene guantes: no va a ir a buscar el ajuste de brillo. Se
/// sube solo en la ventana de la app (ver `MainActivity`) y se devuelve al
/// salir de la credencial.
class Pantalla {
  const Pantalla._();

  static const _canal = MethodChannel('checkinobra/pantalla');

  static Future<void> brilloMaximo() => _invocar('brilloMaximo');

  static Future<void> brilloNormal() => _invocar('brilloNormal');

  /// Sin el lado nativo (pruebas, otra plataforma) la credencial se muestra
  /// igual: el brillo es una ayuda, no una condición.
  static Future<void> _invocar(String metodo) async {
    try {
      await _canal.invokeMethod<void>(metodo);
    } on MissingPluginException {
      // Sin canal nativo.
    } on PlatformException {
      // La ventana no aceptó el cambio.
    }
  }
}
