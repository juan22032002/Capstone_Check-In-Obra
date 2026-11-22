import 'dart:io';

import 'package:flutter/services.dart';

/// Carga Inter para los tests de layout.
///
/// Con la fuente de prueba de Flutter cada letra mide un cuadrado entero y
/// cualquier fila con texto "desborda". Con Inter los anchos son los del
/// teléfono, y un desborde en el test es un desborde de verdad.
Future<void> cargarInter() async {
  final inter = FontLoader('Inter');
  for (final peso in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    final bytes = File('assets/fonts/Inter-$peso.ttf').readAsBytesSync();
    inter.addFont(Future.value(ByteData.sublistView(bytes)));
  }
  await inter.load();
}
