import 'package:flutter/material.dart';

/// El navegador y el mensajero de la raíz de la app.
///
/// Existen para lo que ocurre fuera de una pantalla: cuando el servidor
/// rechaza el token, la sesión se cierra desde el cliente HTTP, que no tiene
/// `BuildContext`, y hay que sacar a la persona de las rutas que tenga
/// apiladas encima.
final navegadorRaiz = GlobalKey<NavigatorState>();
final mensajeroRaiz = GlobalKey<ScaffoldMessengerState>();
