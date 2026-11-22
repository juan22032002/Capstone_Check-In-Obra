import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formato.dart';
import '../../data/api/dominio_api.dart';
import '../../data/modelos/partida.dart';

/// Las partidas de una obra. Es por id de obra y no por la obra activa: el
/// provider no debe cambiar de contenido por debajo de una pantalla abierta si
/// el jefe cambia de obra desde el encabezado.
final partidasDeObraProvider = FutureProvider.family<List<Partida>, int>(
  (ref, obraId) => ref.watch(partidasApiProvider).porObra(obraId),
);

/// Lo que quedó de la última cubicación de una partida.
final itemsCubicadosProvider = FutureProvider.family<List<ItemCubicado>, int>(
  (ref, partidaId) => ref.watch(partidasApiProvider).itemsCubicados(partidaId),
);

/// Las tres medidas de una partida tal como las teclea el jefe.
///
/// El backend aún no las valida (con separación 0 el motor divide por cero), y
/// aunque lo haga, avisar en el formulario ahorra el viaje. Es una regla de
/// forma —mayor que cero y finita— y no de negocio: cuánto mide una pared real
/// lo sabe quien está en la obra.
abstract final class MedidasPartida {
  /// Por qué la medida no sirve, o `null` si sirve. `rotulo` lleva su artículo
  /// ("el ancho", "la separación") para que el mensaje se lea natural.
  static String? error(String texto, String rotulo) {
    if (texto.trim().isEmpty) return 'Falta $rotulo';
    final valor = Formato.numero(texto);
    if (valor == null || !valor.isFinite) {
      return 'Escribe $rotulo como número, por ejemplo 2,4';
    }
    if (valor <= 0) return 'Escribe $rotulo mayor que cero';
    return null;
  }
}
