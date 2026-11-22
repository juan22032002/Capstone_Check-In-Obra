import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../data/api/dominio_api.dart';
import '../../data/modelos/detalle_obra.dart';
import '../../data/modelos/obra.dart';
import '../auth/sesion_controller.dart';

/// Obras activas de la empresa. Las cerradas no se ofrecen: no se puede
/// registrar nada contra una obra cerrada, que es el punto de cerrarla.
final obrasActivasProvider = FutureProvider<List<Obra>>((ref) async {
  final obras = await ref.watch(obrasApiProvider).listar();
  return obras.where((o) => o.activa).toList();
});

/// Todas las obras, incluidas las cerradas — la vista de admin.
final todasLasObrasProvider = FutureProvider<List<Obra>>(
  (ref) => ref.watch(obrasApiProvider).listar(),
);

/// El detalle completo de una obra, para su ficha y para el resumen de su fila
/// en la lista. Es por id y no por la obra activa: el admin mira cualquiera.
final detalleObraProvider = FutureProvider.family<DetalleObra, int>(
  (ref, obraId) => ref.watch(obrasApiProvider).detalle(obraId),
);

/// De quién es lo que se guarda en el teléfono: empresa y usuario.
typedef _Identidad = ({int empresaId, int usuarioId});

/// La obra en la que se está trabajando.
///
/// `null` significa que todavía no se elige ninguna, y ese es un estado real:
/// al entrar por primera vez hay que preguntarla antes de poder mostrar stock,
/// herramientas o alertas, porque todas esas cosas son *de una obra*.
///
/// Se recuerda **por empresa y usuario**, y el controlador se reconstruye
/// cuando cambia quien tiene la sesión. Sin eso, quien entraba con otra cuenta
/// en el mismo teléfono veía la obra de la anterior: en memoria, porque el
/// estado seguía vivo, y en disco, porque el id 3 existe en cada empresa.
class ObraActivaController extends AsyncNotifier<Obra?> {
  _Identidad? get _identidad {
    final s = ref.read(sesionProvider).valueOrNull;
    return s == null ? null : (empresaId: s.empresaId, usuarioId: s.usuarioId);
  }

  @override
  Future<Obra?> build() async {
    final identidad = ref.watch(
      sesionProvider.select((s) {
        final v = s.valueOrNull;
        return v == null
            ? null
            : (empresaId: v.empresaId, usuarioId: v.usuarioId);
      }),
    );
    if (identidad == null) return null;

    final guardada = await ref
        .read(sesionStorageProvider)
        .leerObraActiva(
          empresaId: identidad.empresaId,
          usuarioId: identidad.usuarioId,
        );
    if (guardada == null) return null;

    final obras = await ref.watch(obrasActivasProvider.future);
    // Si la obra guardada se cerró o dejó de existir, se descarta en silencio
    // y se vuelve a preguntar: es preferible a fallar con un 404 opaco.
    return obras.where((o) => o.id == guardada).firstOrNull;
  }

  Future<void> elegir(Obra obra) async {
    final identidad = _identidad;
    if (identidad != null) {
      await ref
          .read(sesionStorageProvider)
          .guardarObraActiva(
            empresaId: identidad.empresaId,
            usuarioId: identidad.usuarioId,
            obraId: obra.id,
          );
    }
    state = AsyncValue.data(obra);
  }

  Future<void> limpiar() async {
    final identidad = _identidad;
    if (identidad != null) {
      await ref
          .read(sesionStorageProvider)
          .olvidarObraActiva(
            empresaId: identidad.empresaId,
            usuarioId: identidad.usuarioId,
          );
    }
    state = const AsyncValue.data(null);
  }
}

final obraActivaProvider = AsyncNotifierProvider<ObraActivaController, Obra?>(
  ObraActivaController.new,
);
