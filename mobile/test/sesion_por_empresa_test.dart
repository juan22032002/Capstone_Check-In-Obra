import 'package:checkinobra_mobile/core/network/api_client.dart';
import 'package:checkinobra_mobile/core/storage/sesion_storage.dart';
import 'package:checkinobra_mobile/data/api/auth_api.dart';
import 'package:checkinobra_mobile/data/modelos/obra.dart';
import 'package:checkinobra_mobile/data/modelos/perfil_trabajador.dart';
import 'package:checkinobra_mobile/features/auth/sesion_controller.dart';
import 'package:checkinobra_mobile/features/obra/obra_activa.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

/// El mismo `usuarioId` en dos empresas: con una base por empresa los ids se
/// repiten, así que nada de lo que guarda el teléfono puede ir solo por id.
const _enEmpresa1 = SesionUsuario(
  token: 'a',
  usuarioId: 4,
  nombre: 'Jorge Reyes',
  rol: 'BODEGUERO',
  empresaId: 1,
);
const _enEmpresa2 = SesionUsuario(
  token: 'b',
  usuarioId: 4,
  nombre: 'Marta Soto',
  rol: 'BODEGUERO',
  empresaId: 2,
);

Obra _obra(int id, String nombre) => Obra(
  id: id,
  nombre: nombre,
  cliente: 'Cliente',
  ubicacion: 'Santiago',
  estado: 'ACTIVA',
  jefeTerrenoNombre: null,
  jefeTerrenoRut: null,
);

PerfilTrabajador _perfil(int usuarioId, String nombre) => PerfilTrabajador(
  id: 1,
  usuarioId: usuarioId,
  nombre: nombre,
  rut: '12.345.678-5',
  cuadrillaId: 1,
  cuadrillaNombre: 'Cuadrilla 1',
  obraId: 3,
  obraNombre: 'Obra',
  obraEstado: 'ACTIVA',
  credencialQr: 'CRED-1',
);

/// Una sesión que el test puede cambiar, como al entrar otra cuenta.
class _SesionCambiante extends SesionController {
  @override
  Future<SesionUsuario?> build() async => null;

  void poner(SesionUsuario? sesion) => state = AsyncValue.data(sesion);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  group('Usuario recordado', () {
    test('guarda la empresa junto al usuario', () async {
      final storage = SesionStorage();
      await storage.guardar(_enEmpresa2);

      final recordado = await storage.leerUsuarioRecordado();

      expect(recordado?.usuarioId, 4);
      expect(recordado?.empresaId, 2);
    });

    test('uno guardado antes de recordar la empresa se descarta', () async {
      // Sin la empresa el PIN no se puede validar en la base correcta: se pide
      // el correo una vez en vez de adivinar.
      FlutterSecureStorage.setMockInitialValues({
        'usuario_recordado':
            '{"usuarioId":4,"nombre":"Jorge Reyes","rol":"BODEGUERO"}',
      });
      final storage = SesionStorage();

      expect(await storage.leerUsuarioRecordado(), isNull);
      expect(
        await const FlutterSecureStorage().read(key: 'usuario_recordado'),
        isNull,
      );
    });
  });

  group('Obra activa por empresa y usuario', () {
    test('el mismo id de usuario en otra empresa no hereda la obra', () async {
      final storage = SesionStorage();
      await storage.guardarObraActiva(empresaId: 1, usuarioId: 4, obraId: 3);

      expect(await storage.leerObraActiva(empresaId: 1, usuarioId: 4), 3);
      expect(await storage.leerObraActiva(empresaId: 2, usuarioId: 4), isNull);
    });

    test('otro usuario de la misma empresa tampoco', () async {
      final storage = SesionStorage();
      await storage.guardarObraActiva(empresaId: 1, usuarioId: 4, obraId: 3);

      expect(await storage.leerObraActiva(empresaId: 1, usuarioId: 5), isNull);
    });

    test('cada cuenta recuerda la suya', () async {
      final storage = SesionStorage();
      await storage.guardarObraActiva(empresaId: 1, usuarioId: 4, obraId: 3);
      await storage.guardarObraActiva(empresaId: 2, usuarioId: 4, obraId: 8);

      expect(await storage.leerObraActiva(empresaId: 1, usuarioId: 4), 3);
      expect(await storage.leerObraActiva(empresaId: 2, usuarioId: 4), 8);
    });

    test('la obra guardada sin empresa se descarta al entrar', () async {
      // No dice de qué empresa era y el id 3 existe en cada una.
      FlutterSecureStorage.setMockInitialValues({
        'obra_activa': '3',
        'perfil_trabajador': '{}',
      });
      final storage = SesionStorage();
      await storage.guardar(_enEmpresa1);

      final todo = await const FlutterSecureStorage().readAll();
      expect(todo.containsKey('obra_activa'), isFalse);
      expect(todo.containsKey('perfil_trabajador'), isFalse);
      expect(await storage.leerObraActiva(empresaId: 1, usuarioId: 4), isNull);
    });

    test('cerrar sesión conserva la obra; "No soy…" las borra todas', () async {
      final storage = SesionStorage();
      await storage.guardar(_enEmpresa1);
      await storage.guardarObraActiva(empresaId: 1, usuarioId: 4, obraId: 3);
      await storage.guardarObraActiva(empresaId: 2, usuarioId: 4, obraId: 8);

      await storage.cerrarSesion();
      expect(await storage.leerObraActiva(empresaId: 1, usuarioId: 4), 3);

      await storage.olvidarTodo();
      expect(await storage.leerObraActiva(empresaId: 1, usuarioId: 4), isNull);
      expect(await storage.leerObraActiva(empresaId: 2, usuarioId: 4), isNull);
    });
  });

  group('Perfil del trabajador por empresa', () {
    test('el mismo usuarioId en otra empresa no ve la credencial', () async {
      final storage = SesionStorage();
      await storage.guardarPerfilTrabajador(_perfil(4, 'Pedro'), empresaId: 1);

      expect(
        (await storage.leerPerfilTrabajador(
          empresaId: 1,
          usuarioId: 4,
        ))?.nombre,
        'Pedro',
      );
      expect(
        await storage.leerPerfilTrabajador(empresaId: 2, usuarioId: 4),
        isNull,
      );
    });

    test('cerrar sesión borra la credencial de todas las empresas', () async {
      final storage = SesionStorage();
      await storage.guardarPerfilTrabajador(_perfil(4, 'Pedro'), empresaId: 1);
      await storage.guardarPerfilTrabajador(_perfil(4, 'Pablo'), empresaId: 2);

      await storage.cerrarSesion();

      expect(
        await storage.leerPerfilTrabajador(empresaId: 1, usuarioId: 4),
        isNull,
      );
      expect(
        await storage.leerPerfilTrabajador(empresaId: 2, usuarioId: 4),
        isNull,
      );
    });
  });

  group('Login por PIN', () {
    test('envía la empresa junto al usuario', () async {
      Map<String, dynamic>? cuerpo;
      final dio = Dio(BaseOptions(baseUrl: 'https://api.test'))
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (opciones, handler) {
              cuerpo = opciones.data as Map<String, dynamic>;
              handler.resolve(
                Response(
                  requestOptions: opciones,
                  statusCode: 200,
                  data: _enEmpresa2.aJson(),
                ),
              );
            },
          ),
        );

      final sesion = await AuthApi(ApiClient(dio: dio))
          .loginPorPin(usuarioId: 4, empresaId: 2, pin: '1234');

      expect(cuerpo, {'usuarioId': 4, 'empresaId': 2, 'pin': '1234'});
      expect(sesion.empresaId, 2);
    });
  });

  group('Cambiar de cuenta en el mismo teléfono', () {
    ProviderContainer contenedor(SesionStorage storage) {
      final c = ProviderContainer(
        overrides: [
          sesionStorageProvider.overrideWithValue(storage),
          sesionProvider.overrideWith(_SesionCambiante.new),
          // La misma obra 3 existe en las dos empresas, con otro nombre.
          obrasActivasProvider.overrideWith((ref) async {
            final empresa = ref.read(sesionProvider).valueOrNull?.empresaId;
            return [_obra(3, empresa == 1 ? 'Torre Norte' : 'Edificio Sur')];
          }),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    _SesionCambiante sesion(ProviderContainer c) =>
        c.read(sesionProvider.notifier) as _SesionCambiante;

    test(
      'la obra de la cuenta anterior no se muestra ni se reutiliza',
      () async {
        final c = contenedor(SesionStorage());
        await c.read(sesionProvider.future);

        sesion(c).poner(_enEmpresa1);
        await c.read(obraActivaProvider.future);
        await c
            .read(obraActivaProvider.notifier)
            .elegir(_obra(3, 'Torre Norte'));
        expect(c.read(obraActivaProvider).valueOrNull?.nombre, 'Torre Norte');

        // Entra otra cuenta con el mismo id de usuario y otra empresa.
        sesion(c).poner(_enEmpresa2);
        final tras = await c.read(obraActivaProvider.future);

        expect(tras, isNull);
      },
    );

    test('al volver la primera cuenta recupera su obra', () async {
      final c = contenedor(SesionStorage());
      await c.read(sesionProvider.future);

      sesion(c).poner(_enEmpresa1);
      await c.read(obraActivaProvider.future);
      await c.read(obraActivaProvider.notifier).elegir(_obra(3, 'Torre Norte'));

      sesion(c).poner(_enEmpresa2);
      await c.read(obraActivaProvider.future);
      sesion(c).poner(_enEmpresa1);
      final vuelta = await c.read(obraActivaProvider.future);

      expect(vuelta?.nombre, 'Torre Norte');
    });

    test('sin sesión no hay obra activa', () async {
      final c = contenedor(SesionStorage());
      await c.read(sesionProvider.future);

      sesion(c).poner(_enEmpresa1);
      await c.read(obraActivaProvider.future);
      await c.read(obraActivaProvider.notifier).elegir(_obra(3, 'Torre Norte'));
      sesion(c).poner(null);

      expect(await c.read(obraActivaProvider.future), isNull);
    });
  });
}
