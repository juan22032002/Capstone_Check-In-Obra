import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../data/api/auth_api.dart';
import '../../data/modelos/perfil_trabajador.dart';

/// Guarda la sesión en el almacenamiento cifrado del dispositivo
/// (Keystore en Android). Nunca en SharedPreferences: ahí el JWT quedaría
/// legible para cualquiera con acceso al sistema de archivos.
///
/// El PIN NO se guarda jamás — ni aquí ni en ninguna parte del teléfono.
/// Lo único que persiste es el token que devolvió el servidor.
class SesionStorage {
  /// En flutter_secure_storage 11 el cifrado fuerte ya es el comportamiento
  /// por defecto en Android (AES-GCM con la clave envuelta en RSA-OAEP,
  /// respaldada por el Keystore), así que no hace falta configurarlo.
  SesionStorage({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _claveSesion = 'sesion_actual';
  static const _claveUsuarioRecordado = 'usuario_recordado';
  static const _claveObraActiva = 'obra_activa';
  static const _clavePerfilTrabajador = 'perfil_trabajador';

  /// La obra activa y el perfil se guardan **por empresa y usuario**. Con una
  /// base por empresa, los ids se repiten entre empresas: la obra 3 de una
  /// constructora no es la obra 3 de otra, y guardar solo "3" haría que quien
  /// entra con otra cuenta en el mismo teléfono abriera sobre la obra de una
  /// empresa ajena. La clave lleva ambos datos: `obra_activa:<empresa>:<usuario>`.
  static String _clave(String base, int empresaId, int usuarioId) =>
      '$base:$empresaId:$usuarioId';

  /// Borra la clave sin sufijo (formato anterior, que no sabía de qué empresa
  /// era) y todas las que llevan empresa y usuario.
  Future<void> _borrarFamilia(String base) async {
    final todo = await _storage.readAll();
    for (final k in todo.keys.toList()) {
      if (k == base || k.startsWith('$base:')) await _storage.delete(key: k);
    }
  }

  Future<void> guardar(SesionUsuario sesion) async {
    await _storage.write(key: _claveSesion, value: jsonEncode(sesion.aJson()));
    // Se recuerda por separado para poder ofrecer el acceso por PIN aunque
    // la sesión haya expirado o se haya cerrado.
    await _storage.write(
      key: _claveUsuarioRecordado,
      value: jsonEncode({
        'usuarioId': sesion.usuarioId,
        'empresaId': sesion.empresaId,
        'nombre': sesion.nombre,
        'rol': sesion.rol,
      }),
    );
    // Lo que se guardó antes de que fuera por empresa no dice de cuál era, y
    // con ids repetidos no hay forma segura de adivinarlo: se descarta.
    await _storage.delete(key: _claveObraActiva);
    await _storage.delete(key: _clavePerfilTrabajador);
  }

  /// Reemplaza solo la sesión: es lo que hace cada renovación del token, que
  /// ocurre cada ~30 minutos y no tiene por qué tocar al usuario recordado ni
  /// lo demás.
  Future<void> actualizarSesion(SesionUsuario sesion) =>
      _storage.write(key: _claveSesion, value: jsonEncode(sesion.aJson()));

  Future<SesionUsuario?> leer() async {
    final crudo = await _storage.read(key: _claveSesion);
    if (crudo == null) return null;
    try {
      return SesionUsuario.desdeJson(jsonDecode(crudo) as Map<String, dynamic>);
    } catch (_) {
      // Formato viejo o corrupto: se descarta y se pide login de nuevo.
      await _storage.delete(key: _claveSesion);
      return null;
    }
  }

  /// Borra la sesión y la credencial guardada; deja al usuario recordado
  /// para el acceso por PIN. Sin sesión la credencial no se puede mostrar, y
  /// así no queda en un teléfono que se presta o se entrega.
  Future<void> cerrarSesion() async {
    await _storage.delete(key: _claveSesion);
    await _borrarFamilia(_clavePerfilTrabajador);
  }

  /// Olvida también al usuario — "Cambiar" en la pantalla de PIN.
  Future<void> olvidarTodo() async {
    await _storage.delete(key: _claveSesion);
    await _storage.delete(key: _claveUsuarioRecordado);
    await _borrarFamilia(_claveObraActiva);
    await _borrarFamilia(_clavePerfilTrabajador);
  }

  Future<UsuarioRecordado?> leerUsuarioRecordado() async {
    final crudo = await _storage.read(key: _claveUsuarioRecordado);
    if (crudo == null) return null;
    try {
      final json = jsonDecode(crudo) as Map<String, dynamic>;
      // Guardado antes de que se recordara la empresa: sin ella el PIN no se
      // puede validar en la base correcta, así que se pide el correo una vez.
      if (json['empresaId'] == null) {
        await _storage.delete(key: _claveUsuarioRecordado);
        return null;
      }
      return UsuarioRecordado(
        usuarioId: json['usuarioId'] as int,
        empresaId: json['empresaId'] as int,
        nombre: json['nombre'] as String,
        rol: json['rol'] as String,
      );
    } catch (_) {
      await _storage.delete(key: _claveUsuarioRecordado);
      return null;
    }
  }

  Future<String?> leerToken() async => (await leer())?.token;

  /// Obra en la que está trabajando quien usa el teléfono.
  ///
  /// El backend no asocia bodegueros a obras —solo los trabajadores tienen
  /// cuadrilla, y la cuadrilla tiene obra—, así que la elige la persona y el
  /// teléfono la recuerda. Sin esto habría que preguntarla en cada pantalla,
  /// y en una obra el bodeguero trabaja en una sola durante semanas.
  Future<void> guardarObraActiva({
    required int empresaId,
    required int usuarioId,
    required int obraId,
  }) => _storage.write(
    key: _clave(_claveObraActiva, empresaId, usuarioId),
    value: obraId.toString(),
  );

  Future<int?> leerObraActiva({
    required int empresaId,
    required int usuarioId,
  }) async {
    final crudo = await _storage.read(
      key: _clave(_claveObraActiva, empresaId, usuarioId),
    );
    return crudo == null ? null : int.tryParse(crudo);
  }

  Future<void> olvidarObraActiva({
    required int empresaId,
    required int usuarioId,
  }) => _storage.delete(key: _clave(_claveObraActiva, empresaId, usuarioId));

  /// Última copia del perfil del trabajador, para mostrar su credencial sin
  /// conexión. Ver la nota en [PerfilTrabajador].
  Future<void> guardarPerfilTrabajador(
    PerfilTrabajador perfil, {
    required int empresaId,
  }) => _storage.write(
    key: _clave(_clavePerfilTrabajador, empresaId, perfil.usuarioId),
    value: jsonEncode({
      ...perfil.aJson(),
      'guardadoEl': DateTime.now().toIso8601String(),
    }),
  );

  /// La copia guardada, solo si es de este usuario **en esta empresa**: en un
  /// teléfono compartido nadie ve la credencial de otro, y el mismo
  /// `usuarioId` en otra empresa es otra persona.
  Future<PerfilTrabajador?> leerPerfilTrabajador({
    required int empresaId,
    required int usuarioId,
  }) async {
    final clave = _clave(_clavePerfilTrabajador, empresaId, usuarioId);
    final crudo = await _storage.read(key: clave);
    if (crudo == null) return null;
    try {
      return PerfilTrabajador.desdeJson(
        jsonDecode(crudo) as Map<String, dynamic>,
      );
    } catch (_) {
      await _storage.delete(key: clave);
      return null;
    }
  }
}

/// Datos mínimos del último usuario que entró en este teléfono, para
/// ofrecerle el acceso rápido por PIN sin que escriba el correo.
class UsuarioRecordado {
  const UsuarioRecordado({
    required this.usuarioId,
    required this.empresaId,
    required this.nombre,
    required this.rol,
  });

  final int usuarioId;

  /// Los ids de usuario se repiten entre empresas (una base por empresa): el
  /// acceso por PIN necesita las dos cosas para saber de quién es el PIN.
  final int empresaId;
  final String nombre;
  final String rol;
}
