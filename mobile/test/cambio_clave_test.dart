import 'dart:convert';
import 'dart:typed_data';

import 'package:checkinobra_mobile/core/network/api_client.dart';
import 'package:checkinobra_mobile/core/storage/sesion_storage.dart';
import 'package:checkinobra_mobile/core/theme/app_theme.dart';
import 'package:checkinobra_mobile/data/api/auth_api.dart';
import 'package:checkinobra_mobile/features/auth/pantalla_cambiar_clave.dart';
import 'package:checkinobra_mobile/features/auth/sesion_controller.dart';
import 'package:checkinobra_mobile/main.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

const _provisoria = SesionUsuario(
  token: 'provisorio',
  usuarioId: 1,
  nombre: 'Carla Muñoz',
  rol: 'ADMIN',
  empresaId: 1,
  debeCambiarClave: true,
);

const _definitiva = SesionUsuario(
  token: 'definitivo',
  usuarioId: 1,
  nombre: 'Carla Muñoz',
  rol: 'ADMIN',
  empresaId: 1,
);

/// Un servidor falso: guarda lo que le llega y responde lo que se le dice.
class _Servidor implements HttpClientAdapter {
  _Servidor({this.status = 200, this.cuerpo = const {}});

  final int status;
  final Map<String, dynamic> cuerpo;
  final recibidas = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    recibidas.add(options);
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

ApiClient _cliente(
  _Servidor servidor, {
  SesionStorage? storage,
  void Function()? alDebeCambiarClave,
}) {
  final dio = Dio(
    BaseOptions(
      baseUrl: 'https://api.test',
      validateStatus: (s) => s != null && s < 500,
    ),
  )..httpClientAdapter = servidor;
  return ApiClient(
    dio: dio,
    storage: storage,
    alDebeCambiarClave: alDebeCambiarClave,
  );
}

class _SesionFija extends SesionController {
  _SesionFija(this.inicial);

  final SesionUsuario? inicial;

  @override
  Future<SesionUsuario?> build() async => inicial;
}

/// Registra lo que se le pide cambiar, o falla con lo que se le diga.
class _SesionQueCambia extends _SesionFija {
  _SesionQueCambia(super.inicial, {this.falla});

  final Object? falla;
  final cambios = <(String, String)>[];

  @override
  Future<void> cambiarClave({
    required String claveActual,
    required String claveNueva,
  }) async {
    cambios.add((claveActual, claveNueva));
    if (falla != null) throw falla!;
    state = const AsyncValue.data(_definitiva);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() => initializeDateFormatting('es_CL'));
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  group('Sesión con clave provisoria', () {
    test('lee debeCambiarClave del login', () {
      final s = SesionUsuario.desdeJson({
        ..._provisoria.aJson(),
        'debeCambiarClave': true,
      });

      expect(s.debeCambiarClave, isTrue);
    });

    test('sin el campo no hay obligación (sesión antigua o backend viejo)', () {
      final json = {..._definitiva.aJson()}..remove('debeCambiarClave');

      expect(SesionUsuario.desdeJson(json).debeCambiarClave, isFalse);
    });

    test('se guarda y se recupera con la marca', () async {
      final storage = SesionStorage();
      await storage.guardar(_provisoria);

      expect((await storage.leer())?.debeCambiarClave, isTrue);
    });
  });

  group('Cambio de clave en la API', () {
    test(
      'envía PUT /api/auth/pin con la actual y la nueva, con token',
      () async {
        final servidor = _Servidor(cuerpo: _definitiva.aJson());
        final storage = SesionStorage();
        await storage.guardar(_provisoria);

        final sesion = await AuthApi(_cliente(servidor, storage: storage))
            .cambiarClave(
              claveActual: 'provisoria-123',
              claveNueva: 'nueva-clave-456',
            );

        final pedida = servidor.recibidas.single;
        expect(pedida.method, 'PUT');
        expect(pedida.path, '/api/auth/pin');
        expect(pedida.data, {
          'pinActual': 'provisoria-123',
          'pinNuevo': 'nueva-clave-456',
        });
        // Es la única ruta de auth que va autenticada.
        expect(pedida.headers['Authorization'], 'Bearer provisorio');
        expect(sesion.debeCambiarClave, isFalse);
        expect(sesion.token, 'definitivo');
      },
    );

    test('el login sigue sin mandar token', () async {
      final servidor = _Servidor(cuerpo: _definitiva.aJson());
      final storage = SesionStorage();
      await storage.guardar(_provisoria);

      await AuthApi(_cliente(servidor, storage: storage))
          .login(email: 'a@b.cl', pin: 'x' * 8);

      expect(servidor.recibidas.single.headers['Authorization'], isNull);
    });

    test('una clave actual equivocada es un error, no una sesión', () async {
      final servidor = _Servidor(
        status: 400,
        cuerpo: {'mensaje': 'La clave actual no es correcta'},
      );

      await expectLater(
        AuthApi(_cliente(servidor))
            .cambiarClave(claveActual: 'mala', claveNueva: 'nueva-clave-456'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.mensaje,
            'mensaje',
            'La clave actual no es correcta',
          ),
        ),
      );
    });
  });

  group('403 DEBE_CAMBIAR_PIN', () {
    Future<int> llamadasTras(
      WidgetTester? _, {
      required int status,
      required Map<String, dynamic> cuerpo,
      String ruta = '/api/obras',
    }) async {
      var llamadas = 0;
      final storage = SesionStorage();
      await storage.guardar(_provisoria);
      final cliente = _cliente(
        _Servidor(status: status, cuerpo: cuerpo),
        storage: storage,
        alDebeCambiarClave: () => llamadas++,
      );

      await cliente.dio.get<dynamic>(ruta);
      return llamadas;
    }

    test('avisa cuando el servidor lo pide', () async {
      expect(
        await llamadasTras(
          null,
          status: 403,
          cuerpo: {'codigo': 'DEBE_CAMBIAR_PIN', 'mensaje': 'x'},
        ),
        1,
      );
    });

    test('un 403 por falta de permiso no es lo mismo', () async {
      expect(
        await llamadasTras(
          null,
          status: 403,
          cuerpo: {'mensaje': 'sin permiso'},
        ),
        0,
      );
    });

    test('un 403 con otro código tampoco', () async {
      expect(
        await llamadasTras(null, status: 403, cuerpo: {'codigo': 'OTRO'}),
        0,
      );
    });

    test('ni uno que llegue de las rutas de auth', () async {
      expect(
        await llamadasTras(
          null,
          status: 403,
          cuerpo: {'codigo': 'DEBE_CAMBIAR_PIN'},
          ruta: '/api/auth/login',
        ),
        0,
      );
    });
  });

  group('Controlador de sesión', () {
    ProviderContainer contenedor(SesionStorage storage, [AuthApi? api]) {
      final c = ProviderContainer(
        overrides: [
          sesionStorageProvider.overrideWithValue(storage),
          if (api != null) authApiProvider.overrideWithValue(api),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    test('exigirCambioDeClave marca la sesión y la guarda', () async {
      final storage = SesionStorage();
      await storage.guardar(_definitiva);
      final c = contenedor(storage);
      await c.read(sesionProvider.future);

      await c.read(sesionProvider.notifier).exigirCambioDeClave();

      expect(c.read(sesionProvider).valueOrNull?.debeCambiarClave, isTrue);
      expect((await storage.leer())?.debeCambiarClave, isTrue);
    });

    test('sin sesión no hace nada', () async {
      final c = contenedor(SesionStorage());
      await c.read(sesionProvider.future);

      await c.read(sesionProvider.notifier).exigirCambioDeClave();

      expect(c.read(sesionProvider).valueOrNull, isNull);
    });

    test('cambiar la clave reemplaza la sesión por la nueva', () async {
      final servidor = _Servidor(cuerpo: _definitiva.aJson());
      final storage = SesionStorage();
      await storage.guardar(_provisoria);
      final c = contenedor(
        storage,
        AuthApi(_cliente(servidor, storage: storage)),
      );
      await c.read(sesionProvider.future);

      await c
          .read(sesionProvider.notifier)
          .cambiarClave(
            claveActual: 'provisoria-123',
            claveNueva: 'nueva-clave-456',
          );

      final sesion = c.read(sesionProvider).valueOrNull;
      expect(sesion?.debeCambiarClave, isFalse);
      expect(sesion?.token, 'definitivo');
      expect((await storage.leer())?.token, 'definitivo');
    });

    test('si el cambio falla, la sesión sigue siendo la provisoria', () async {
      final servidor = _Servidor(
        status: 400,
        cuerpo: {'mensaje': 'La clave actual no es correcta'},
      );
      final storage = SesionStorage();
      await storage.guardar(_provisoria);
      final c = contenedor(
        storage,
        AuthApi(_cliente(servidor, storage: storage)),
      );
      await c.read(sesionProvider.future);

      await expectLater(
        c
            .read(sesionProvider.notifier)
            .cambiarClave(claveActual: 'mala', claveNueva: 'nueva-clave-456'),
        throwsA(isA<ApiException>()),
      );

      expect(c.read(sesionProvider).valueOrNull?.debeCambiarClave, isTrue);
      expect((await storage.leer())?.token, 'provisorio');
    });
  });

  group('Pantalla de cambio de clave', () {
    Future<_SesionQueCambia> abrir(
      WidgetTester tester, {
      Object? falla,
      SesionUsuario sesion = _provisoria,
    }) async {
      tester.view.physicalSize = const Size(400, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final controlador = _SesionQueCambia(sesion, falla: falla);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [sesionProvider.overrideWith(() => controlador)],
          child: MaterialApp(
            theme: AppTheme.light,
            home: PantallaCambiarClave(sesion: sesion),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return controlador;
    }

    Future<void> llenar(
      WidgetTester tester, {
      String actual = 'provisoria-123',
      String nueva = 'nueva-clave-456',
      String? repetida,
      String boton = 'Cambiar clave',
    }) async {
      final campos = find.byType(TextField);
      await tester.enterText(campos.at(0), actual);
      await tester.enterText(campos.at(1), nueva);
      await tester.enterText(campos.at(2), repetida ?? nueva);
      await tester.tap(find.text(boton));
      await tester.pumpAndSettle();
    }

    testWidgets('explica por qué y ofrece cerrar sesión, no omitir', (
      tester,
    ) async {
      await abrir(tester);

      expect(find.text('Cambia tu clave'), findsOneWidget);
      expect(find.textContaining('provisoria'), findsWidgets);
      expect(find.text('Cerrar sesión'), findsOneWidget);
      expect(find.textContaining('Omitir'), findsNothing);
    });

    testWidgets('envía la actual y la nueva', (tester) async {
      final c = await abrir(tester);

      await llenar(tester);

      expect(c.cambios, [('provisoria-123', 'nueva-clave-456')]);
    });

    testWidgets('no acepta la misma clave que la actual', (tester) async {
      final c = await abrir(tester);

      await llenar(tester, actual: 'provisoria-123', nueva: 'provisoria-123');

      expect(find.text('Elige una distinta de la actual'), findsOneWidget);
      expect(c.cambios, isEmpty);
    });

    testWidgets('exige 8 caracteres a un administrador', (tester) async {
      final c = await abrir(tester);

      await llenar(tester, nueva: '1234');

      expect(find.textContaining('al menos 8 caracteres'), findsOneWidget);
      expect(c.cambios, isEmpty);
    });

    testWidgets('las dos nuevas tienen que coincidir', (tester) async {
      final c = await abrir(tester);

      await llenar(tester, repetida: 'otra-clave-distinta');

      expect(find.text('No coincide con la nueva'), findsOneWidget);
      expect(c.cambios, isEmpty);
    });

    testWidgets('un trabajador cambia su PIN de 4 dígitos', (tester) async {
      const trabajador = SesionUsuario(
        token: 't',
        usuarioId: 6,
        nombre: 'Marcelo',
        rol: 'TRABAJADOR',
        empresaId: 1,
        debeCambiarClave: true,
      );
      final c = await abrir(tester, sesion: trabajador);

      expect(find.text('Cambia tu PIN'), findsOneWidget);
      await llenar(tester, actual: '0000', nueva: '4821', boton: 'Cambiar PIN');
      expect(c.cambios, [('0000', '4821')]);
    });

    testWidgets('un error del servidor se muestra y se puede reintentar', (
      tester,
    ) async {
      await abrir(
        tester,
        falla: const ApiException(400, 'La clave actual no es correcta'),
      );

      await llenar(tester);

      expect(find.text('La clave actual no es correcta'), findsOneWidget);
      expect(find.text('Cambiar clave'), findsOneWidget);
    });

    testWidgets('un bloqueo por intentos dice cuánto esperar', (tester) async {
      await abrir(
        tester,
        falla: const ApiException(
          429,
          'x',
          codigo: 'DEMASIADOS_INTENTOS',
          reintentarEnSegundos: 60,
        ),
      );

      await llenar(tester);

      expect(find.textContaining('Espera 1 minuto'), findsOneWidget);
    });
  });

  group('La raíz de la app', () {
    testWidgets('con clave provisoria muestra el cambio, no la app', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sesionProvider.overrideWith(() => _SesionFija(_provisoria)),
          ],
          child: const CheckInObraApp(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(PantallaCambiarClave), findsOneWidget);
    });
  });
}
