import 'package:checkinobra_mobile/core/network/api_client.dart';
import 'package:checkinobra_mobile/core/storage/sesion_storage.dart';
import 'package:checkinobra_mobile/data/api/auth_api.dart';
import 'package:checkinobra_mobile/features/auth/sesion_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

/// Responde el login con la sesión que se le dé, sin red.
class _AuthFalsa implements AuthApi {
  _AuthFalsa(this.respuesta);

  final SesionUsuario respuesta;

  @override
  Future<SesionUsuario> login({
    required String email,
    required String pin,
  }) async => respuesta;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _sesion = SesionUsuario(
  token: 't',
  usuarioId: 4,
  nombre: 'Jorge Reyes',
  rol: 'BODEGUERO',
  empresaId: 1,
);

Future<ProviderContainer> _conSesionGuardada() async {
  FlutterSecureStorage.setMockInitialValues({});
  final storage = SesionStorage();
  await storage.guardar(_sesion);
  final contenedor = ProviderContainer(
    overrides: [sesionStorageProvider.overrideWithValue(storage)],
  );
  await contenedor.read(sesionProvider.future);
  return contenedor;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'un token vencido cierra la sesión pero recuerda a la persona',
    () async {
      // Lo que pasa de un día para otro: el JWT vence, el primer 401 cierra la
      // sesión, y al abrir la app tiene que aparecer "Hola de nuevo, Jorge", no
      // el formulario de correo.
      final c = await _conSesionGuardada();
      await c.read(sesionProvider.notifier).expirar();

      final storage = c.read(sesionStorageProvider);
      expect(await storage.leer(), isNull);
      expect((await storage.leerUsuarioRecordado())?.nombre, 'Jorge Reyes');
    },
  );

  test('cerrar sesión también recuerda a la persona', () async {
    final c = await _conSesionGuardada();
    await c.read(sesionProvider.notifier).salir();

    expect(
      await c.read(sesionStorageProvider).leerUsuarioRecordado(),
      isNotNull,
    );
  });

  test('"No soy…" es lo único que la olvida', () async {
    final c = await _conSesionGuardada();
    await c.read(sesionProvider.notifier).cambiarDeUsuario();

    expect(await c.read(sesionStorageProvider).leerUsuarioRecordado(), isNull);
  });

  test(
    'tras "No soy…", la persona que entra después queda recordada',
    () async {
      // El bug: el recordado quedaba en caché en null tras olvidar al anterior,
      // y al cerrar sesión la pantalla mostraba el formulario de correo en vez
      // de "Hola de nuevo, Jorge". Solo reiniciar la app lo arreglaba.
      FlutterSecureStorage.setMockInitialValues({});
      final storage = SesionStorage();
      await storage.guardar(
        const SesionUsuario(
          token: 'a',
          usuarioId: 1,
          nombre: 'Administrador',
          rol: 'ADMIN',
          empresaId: 1,
        ),
      );
      final c = ProviderContainer(
        overrides: [
          sesionStorageProvider.overrideWithValue(storage),
          authApiProvider.overrideWithValue(_AuthFalsa(_sesion)),
        ],
      );
      // La pantalla de acceso lo observa todo el tiempo.
      c.listen(usuarioRecordadoProvider, (_, _) {});
      await c.read(sesionProvider.future);

      await c.read(sesionProvider.notifier).salir();
      expect(
        (await c.read(usuarioRecordadoProvider.future))?.nombre,
        'Administrador',
      );

      await c.read(sesionProvider.notifier).cambiarDeUsuario();
      expect(await c.read(usuarioRecordadoProvider.future), isNull);

      await c
          .read(sesionProvider.notifier)
          .entrarConCorreo(email: 'jorge.reyes@arauco-ltda.cl', pin: '2222');
      await c.read(sesionProvider.notifier).salir();

      expect(
        (await c.read(usuarioRecordadoProvider.future))?.nombre,
        'Jorge Reyes',
      );
    },
  );
}
