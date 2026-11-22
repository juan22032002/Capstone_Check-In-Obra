import 'dart:convert';
import 'dart:typed_data';

import 'package:checkinobra_mobile/core/network/api_client.dart';
import 'package:checkinobra_mobile/core/network/errores.dart';
import 'package:checkinobra_mobile/core/storage/sesion_storage.dart';
import 'package:checkinobra_mobile/core/theme/app_theme.dart';
import 'package:checkinobra_mobile/data/api/auth_api.dart';
import 'package:checkinobra_mobile/features/auth/pantalla_acceso.dart';
import 'package:checkinobra_mobile/features/auth/sesion_controller.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

const _sesion = SesionUsuario(
  token: 'jwt',
  usuarioId: 4,
  nombre: 'Jorge Reyes',
  rol: 'BODEGUERO',
  empresaId: 1,
);

/// Responde siempre lo mismo y anota cuántas peticiones recibe.
class _Servidor implements HttpClientAdapter {
  _Servidor(this.status, this.cuerpo);

  final int status;
  final Map<String, dynamic> cuerpo;
  int peticiones = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    peticiones++;
    return ResponseBody.fromString(
      jsonEncode(cuerpo),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> _suspendida() => {
  'status': 403,
  'codigo': 'EMPRESA_SUSPENDIDA',
  'mensaje': 'La empresa está suspendida',
};

ApiClient _cliente(
  _Servidor servidor,
  SesionStorage storage,
  void Function() alSuspender,
) {
  final dio = Dio(
    BaseOptions(
      baseUrl: 'https://api.test',
      validateStatus: (s) => s != null && s < 500,
    ),
  )..httpClientAdapter = servidor;
  return ApiClient(
    dio: dio,
    storage: storage,
    alEmpresaSuspendida: alSuspender,
  );
}

class _AuthQueEntra implements AuthApi {
  @override
  Future<SesionUsuario> login({
    required String email,
    required String pin,
  }) async => _sesion;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  group('Reconocer la suspensión', () {
    test('solo el 403 con el código la distingue', () {
      expect(
        const ApiException(
          403,
          'x',
          codigo: 'EMPRESA_SUSPENDIDA',
        ).empresaSuspendida,
        isTrue,
      );
    });

    test('un 403 por falta de permiso no es una suspensión', () {
      expect(const ApiException(403, 'x').empresaSuspendida, isFalse);
    });

    test('ni uno de cambio de clave pendiente', () {
      expect(
        const ApiException(
          403,
          'x',
          codigo: 'DEBE_CAMBIAR_PIN',
        ).empresaSuspendida,
        isFalse,
      );
    });

    test('el código con otro estado tampoco', () {
      expect(
        const ApiException(
          409,
          'x',
          codigo: 'EMPRESA_SUSPENDIDA',
        ).empresaSuspendida,
        isFalse,
      );
    });

    test('el mensaje es el aviso, no el del servidor ni "sin permiso"', () {
      const e = ApiException(
        403,
        'La empresa está suspendida',
        codigo: 'EMPRESA_SUSPENDIDA',
      );

      expect(
        mensajeDeError(e),
        'Tu empresa está suspendida. Habla con la plataforma.',
      );
    });

    test('un 403 sin el código conserva su mensaje, como hoy', () {
      const e = ApiException(403, 'Tu rol no permite esta acción.');

      expect(mensajeDeError(e), 'Tu rol no permite esta acción.');
    });
  });

  group('Interceptor', () {
    Future<(int, int)> pedir(
      Map<String, dynamic> cuerpo, {
      int status = 403,
      String ruta = '/api/obras',
    }) async {
      var avisos = 0;
      final storage = SesionStorage();
      await storage.guardar(_sesion);
      final servidor = _Servidor(status, cuerpo);
      final cliente = _cliente(servidor, storage, () => avisos++);

      await cliente.dio.get<dynamic>(ruta);
      return (avisos, servidor.peticiones);
    }

    test('un 403 EMPRESA_SUSPENDIDA avisa una vez y no reintenta', () async {
      final (avisos, peticiones) = await pedir(_suspendida());

      expect(avisos, 1);
      expect(peticiones, 1);
    });

    test('un 403 sin código no avisa', () async {
      final (avisos, _) = await pedir({'mensaje': 'sin permiso'});

      expect(avisos, 0);
    });

    test('un 403 DEBE_CAMBIAR_PIN no avisa', () async {
      final (avisos, _) = await pedir({'codigo': 'DEBE_CAMBIAR_PIN'});

      expect(avisos, 0);
    });

    test('un 200 no avisa', () async {
      final (avisos, _) = await pedir({'ok': true}, status: 200);

      expect(avisos, 0);
    });

    test(
      'en el login no cierra nada: el error se muestra donde está',
      () async {
        var avisos = 0;
        final storage = SesionStorage();
        final cliente = _cliente(
          _Servidor(403, _suspendida()),
          storage,
          () => avisos++,
        );

        Object? fallo;
        try {
          await AuthApi(cliente).login(email: 'a@b.cl', pin: 'x' * 8);
        } catch (e) {
          fallo = e;
        }

        expect(avisos, 0);
        expect((fallo as ApiException).empresaSuspendida, isTrue);
        expect(mensajeDeError(fallo), contains('suspendida'));
      },
    );
  });

  group('Controlador de sesión', () {
    Future<(ProviderContainer, SesionStorage)> contenedor() async {
      final storage = SesionStorage();
      await storage.guardar(_sesion);
      final c = ProviderContainer(
        overrides: [sesionStorageProvider.overrideWithValue(storage)],
      );
      addTearDown(c.dispose);
      await c.read(sesionProvider.future);
      return (c, storage);
    }

    test('cierra la sesión local y deja el aviso', () async {
      final (c, storage) = await contenedor();

      await c.read(sesionProvider.notifier).suspenderPorEmpresa();

      expect(c.read(sesionProvider).valueOrNull, isNull);
      expect(await storage.leer(), isNull);
      expect(
        c.read(avisoDeAccesoProvider),
        'Tu empresa está suspendida. Habla con la plataforma.',
      );
    });

    test('sin sesión no hace nada ni deja aviso', () async {
      final c = ProviderContainer(
        overrides: [sesionStorageProvider.overrideWithValue(SesionStorage())],
      );
      addTearDown(c.dispose);
      await c.read(sesionProvider.future);

      await c.read(sesionProvider.notifier).suspenderPorEmpresa();

      expect(c.read(avisoDeAccesoProvider), isNull);
    });

    test('varias peticiones a la vez cierran una sola vez', () async {
      final (c, _) = await contenedor();

      await Future.wait([
        c.read(sesionProvider.notifier).suspenderPorEmpresa(),
        c.read(sesionProvider.notifier).suspenderPorEmpresa(),
        c.read(sesionProvider.notifier).suspenderPorEmpresa(),
      ]);

      expect(c.read(sesionProvider).valueOrNull, isNull);
      expect(c.read(avisoDeAccesoProvider), isNotNull);
    });

    test(
      'de punta a punta: el 403 del cliente real cierra la sesión',
      () async {
        // Con el cliente HTTP que arma la app, solo cambiando la red por una falsa.
        final (c, storage) = await contenedor();
        final servidor = _Servidor(403, _suspendida());
        c.read(apiClientProvider).dio.httpClientAdapter = servidor;

        final respuesta = await c
            .read(apiClientProvider)
            .dio
            .get<dynamic>('/api/obras');
        await Future<void>.delayed(Duration.zero);

        expect(respuesta.statusCode, 403);
        expect(servidor.peticiones, 1);
        expect(c.read(sesionProvider).valueOrNull, isNull);
        expect(await storage.leer(), isNull);
        expect(c.read(avisoDeAccesoProvider), contains('suspendida'));
      },
    );

    test('un 403 por falta de permiso deja la sesión como está', () async {
      final (c, storage) = await contenedor();
      c.read(apiClientProvider).dio.httpClientAdapter = _Servidor(403, {
        'mensaje': 'Tu rol no permite esta acción',
      });

      await c.read(apiClientProvider).dio.get<dynamic>('/api/obras');
      await Future<void>.delayed(Duration.zero);

      expect(c.read(sesionProvider).valueOrNull?.token, 'jwt');
      expect((await storage.leer())?.token, 'jwt');
      expect(c.read(avisoDeAccesoProvider), isNull);
    });
  });

  group('Pantalla de acceso', () {
    Future<ProviderContainer> abrir(WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sesionStorageProvider.overrideWithValue(SesionStorage()),
            usuarioRecordadoProvider.overrideWith((ref) async => null),
            authApiProvider.overrideWithValue(_AuthQueEntra()),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            home: const PantallaAcceso(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return ProviderScope.containerOf(
        tester.element(find.byType(PantallaAcceso)),
      );
    }

    testWidgets('muestra el aviso de empresa suspendida', (tester) async {
      final c = await abrir(tester);

      c.read(avisoDeAccesoProvider.notifier).state = mensajeEmpresaSuspendida;
      await tester.pumpAndSettle();

      expect(
        find.text('Tu empresa está suspendida. Habla con la plataforma.'),
        findsOneWidget,
      );
    });

    testWidgets('sin aviso no muestra nada extra', (tester) async {
      await abrir(tester);

      expect(find.textContaining('suspendida'), findsNothing);
      expect(find.text('Entendido'), findsNothing);
    });

    testWidgets('se puede descartar', (tester) async {
      final c = await abrir(tester);
      c.read(avisoDeAccesoProvider.notifier).state = mensajeEmpresaSuspendida;
      await tester.pumpAndSettle();

      await tester.tap(find.text('Entendido'));
      await tester.pumpAndSettle();

      expect(find.textContaining('suspendida'), findsNothing);
      expect(c.read(avisoDeAccesoProvider), isNull);
    });

    testWidgets('al entrar bien el aviso se borra', (tester) async {
      final c = await abrir(tester);
      c.read(avisoDeAccesoProvider.notifier).state = mensajeEmpresaSuspendida;

      await tester.runAsync(
        () => c
            .read(sesionProvider.notifier)
            .entrarConCorreo(email: 'a@b.cl', pin: 'clave-larga-1'),
      );

      expect(c.read(avisoDeAccesoProvider), isNull);
    });
  });
}
