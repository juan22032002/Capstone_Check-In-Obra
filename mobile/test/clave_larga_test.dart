import 'package:checkinobra_mobile/core/formato.dart';
import 'package:checkinobra_mobile/core/network/api_client.dart';
import 'package:checkinobra_mobile/core/network/errores.dart';
import 'package:checkinobra_mobile/core/politica_clave.dart';
import 'package:checkinobra_mobile/core/theme/app_theme.dart';
import 'package:checkinobra_mobile/data/api/auth_api.dart';
import 'package:checkinobra_mobile/data/api/dominio_api.dart';
import 'package:checkinobra_mobile/data/modelos/usuario.dart';
import 'package:checkinobra_mobile/features/admin/pantalla_usuarios.dart';
import 'package:checkinobra_mobile/features/auth/pantalla_acceso.dart';
import 'package:checkinobra_mobile/features/auth/sesion_controller.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

/// Un `AuthApi` real sobre un `Dio` que responde lo que se le diga.
AuthApi _authQueResponde(
  int status, {
  Map<String, dynamic>? cuerpo,
  Map<String, String>? cabeceras,
}) {
  final dio = Dio(BaseOptions(baseUrl: 'https://api.test'))
    ..interceptors.add(
      InterceptorsWrapper(
        onRequest: (opciones, handler) => handler.resolve(
          Response(
            requestOptions: opciones,
            statusCode: status,
            data: cuerpo,
            headers: Headers.fromMap({
              for (final e in (cabeceras ?? {}).entries) e.key: [e.value],
            }),
          ),
        ),
      ),
    );
  return AuthApi(ApiClient(dio: dio));
}

class _AuthQueRegistra implements AuthApi {
  final claves = <String>[];

  @override
  Future<SesionUsuario> login({
    required String email,
    required String pin,
  }) async {
    claves.add(pin);
    return const SesionUsuario(
      token: 't',
      usuarioId: 1,
      nombre: 'Ana',
      rol: 'JEFE_TERRENO',
      empresaId: 1,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UsuariosQueRegistra implements UsuariosApi {
  final creados = <Map<String, String>>[];

  @override
  Future<UsuarioEmpresa> crear({
    required String nombre,
    required String email,
    required String rut,
    required String rol,
    required String pinInicial,
    String? clave,
  }) async {
    creados.add({'rol': rol, 'pinInicial': pinInicial});
    return UsuarioEmpresa(
      id: 1,
      nombre: nombre,
      email: email,
      rut: rut,
      rol: rol,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SinSesion extends SesionController {
  @override
  Future<SesionUsuario?> build() async => null;
}

void main() {
  group('PoliticaClave', () {
    test('el trabajador usa un PIN de exactamente 4 dígitos', () {
      expect(PoliticaClave.error('1234', rol: 'TRABAJADOR'), isNull);
      expect(PoliticaClave.error('123', rol: 'TRABAJADOR'), isNotNull);
      expect(PoliticaClave.error('12345', rol: 'TRABAJADOR'), isNotNull);
      expect(PoliticaClave.error('12a4', rol: 'TRABAJADOR'), isNotNull);
    });

    test('los demás roles usan una clave de 8 a 72 caracteres', () {
      for (final rol in ['ADMIN', 'JEFE_TERRENO', 'BODEGUERO']) {
        expect(PoliticaClave.error('1234', rol: rol), isNotNull, reason: rol);
        expect(PoliticaClave.error('1234567', rol: rol), isNotNull);
        expect(PoliticaClave.error('12345678', rol: rol), isNull);
        expect(PoliticaClave.error('a' * 72, rol: rol), isNull);
        expect(PoliticaClave.error('a' * 73, rol: rol), isNotNull);
      }
    });

    test('cuenta caracteres, no unidades de texto', () {
      // Siete letras y un emoji son ocho caracteres, aunque el emoji ocupe dos
      // unidades UTF-16.
      expect(PoliticaClave.error('abcdefg😀', rol: 'ADMIN'), isNull);
    });

    test('al entrar acepta una clave antigua de 4 dígitos', () {
      expect(PoliticaClave.errorAlEntrar('0000'), isNull);
      expect(PoliticaClave.errorAlEntrar('una clave larga y buena'), isNull);
      expect(PoliticaClave.errorAlEntrar('123'), isNotNull);
    });
  });

  group('Espera por demasiados intentos (429)', () {
    test('lee Retry-After en segundos', () {
      expect(AuthApi.segundosDeEspera('75'), 75);
      expect(AuthApi.segundosDeEspera(' 60 '), 60);
    });

    test('ignora lo que no es una espera en segundos', () {
      expect(AuthApi.segundosDeEspera(null), isNull);
      expect(AuthApi.segundosDeEspera(''), isNull);
      expect(AuthApi.segundosDeEspera('0'), isNull);
      expect(AuthApi.segundosDeEspera('Wed, 21 Oct 2026 07:28:00 GMT'), isNull);
    });

    test('dice cuánto esperar, en palabras', () {
      const e = ApiException(
        429,
        'x',
        codigo: 'DEMASIADOS_INTENTOS',
        reintentarEnSegundos: 90,
      );

      expect(mensajeDeError(e), contains('1 min 30 s'));
      expect(mensajeDeError(e), startsWith('Demasiados intentos'));
    });

    test('sin cabecera igual avisa que hay que esperar', () {
      const e = ApiException(429, 'x', codigo: 'DEMASIADOS_INTENTOS');

      expect(mensajeDeError(e), contains('Espera un momento'));
    });

    test('un 429 sin código también se reconoce', () {
      expect(const ApiException(429, 'x').demasiadosIntentos, isTrue);
      expect(const ApiException(400, 'x').demasiadosIntentos, isFalse);
    });

    test('el login lee Retry-After y el código del cuerpo', () async {
      final api = _authQueResponde(
        429,
        cuerpo: {'mensaje': 'bloqueado', 'codigo': 'DEMASIADOS_INTENTOS'},
        cabeceras: {'retry-after': '75'},
      );

      await expectLater(
        api.login(email: 'a@b.cl', pin: 'clave-larga-1'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.reintentarEnSegundos, 'espera', 75)
              .having((e) => e.codigo, 'codigo', 'DEMASIADOS_INTENTOS'),
        ),
      );
    });

    test('un PIN equivocado (400) no es un bloqueo', () async {
      final api = _authQueResponde(400, cuerpo: {'mensaje': 'Credenciales'});

      await expectLater(
        api.login(email: 'a@b.cl', pin: '1234'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.demasiadosIntentos,
            'bloqueo',
            isFalse,
          ),
        ),
      );
    });

    test('las esperas se dicen como se hablan', () {
      expect(Formato.espera(1), '1 segundo');
      expect(Formato.espera(45), '45 segundos');
      expect(Formato.espera(60), '1 minuto');
      expect(Formato.espera(120), '2 minutos');
      expect(Formato.espera(150), '2 min 30 s');
      expect(Formato.espera(3600), '1 h');
      expect(Formato.espera(3660), '1 h 1 min');
    });
  });

  group('Login por correo con clave larga', () {
    Future<_AuthQueRegistra> abrir(WidgetTester tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      final auth = _AuthQueRegistra();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            usuarioRecordadoProvider.overrideWith((ref) async => null),
            authApiProvider.overrideWithValue(auth),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            home: const PantallaAcceso(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return auth;
    }

    testWidgets('envía la clave completa, más larga que 4 dígitos', (
      tester,
    ) async {
      final auth = await abrir(tester);

      await tester.enterText(find.byType(TextField).at(0), 'ana@empresa.cl');
      await tester.enterText(find.byType(TextField).at(1), 'Clave-Larga-2026');
      await tester.tap(find.text('Entrar'));
      await tester.pumpAndSettle();

      expect(auth.claves, ['Clave-Larga-2026']);
    });

    testWidgets('una clave de 4 dígitos sigue entrando (cuentas antiguas)', (
      tester,
    ) async {
      final auth = await abrir(tester);

      await tester.enterText(find.byType(TextField).at(0), 'ana@empresa.cl');
      await tester.enterText(find.byType(TextField).at(1), '0000');
      await tester.tap(find.text('Entrar'));
      await tester.pumpAndSettle();

      expect(auth.claves, ['0000']);
    });

    testWidgets('una clave demasiado corta no se envía', (tester) async {
      final auth = await abrir(tester);

      await tester.enterText(find.byType(TextField).at(0), 'ana@empresa.cl');
      await tester.enterText(find.byType(TextField).at(1), '123');
      await tester.tap(find.text('Entrar'));
      await tester.pumpAndSettle();

      expect(find.text('Escribe tu PIN o tu clave'), findsOneWidget);
      expect(auth.claves, isEmpty);
    });
  });

  group('Alta de usuario', () {
    Future<_UsuariosQueRegistra> abrir(WidgetTester tester) async {
      tester.view.physicalSize = const Size(400, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final api = _UsuariosQueRegistra();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sesionProvider.overrideWith(_SinSesion.new),
            usuariosApiProvider.overrideWithValue(api),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            home: const PantallaNuevoUsuario(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return api;
    }

    Future<void> llenar(WidgetTester tester, String clave) async {
      final campos = find.byType(TextField);
      await tester.enterText(campos.at(0), 'Ana Rojas');
      await tester.enterText(campos.at(1), 'ana@empresa.cl');
      await tester.enterText(campos.at(2), '12.345.678-5');
      await tester.enterText(campos.at(3), clave);
      await tester.tap(find.text('Registrar usuario'));
      await tester.pumpAndSettle();
    }

    testWidgets('un bodeguero exige clave de 8 caracteres o más', (
      tester,
    ) async {
      final api = await abrir(tester);

      await llenar(tester, '1234');
      expect(find.textContaining('al menos 8 caracteres'), findsOneWidget);
      expect(api.creados, isEmpty);

      await tester.enterText(find.byType(TextField).at(3), 'clave-larga-1');
      await tester.tap(find.text('Registrar usuario'));
      await tester.pumpAndSettle();
      expect(api.creados, [
        {'rol': 'BODEGUERO', 'pinInicial': 'clave-larga-1'},
      ]);
    });

    testWidgets('un trabajador sigue con PIN de 4 dígitos', (tester) async {
      final api = await abrir(tester);

      await tester.tap(find.text('Trabajador'));
      await tester.pumpAndSettle();
      expect(find.text('PIN inicial'), findsOneWidget);

      await llenar(tester, '4821');
      expect(api.creados, [
        {'rol': 'TRABAJADOR', 'pinInicial': '4821'},
      ]);
    });

    testWidgets('el rótulo y la ayuda siguen al rol elegido', (tester) async {
      await abrir(tester);

      expect(find.text('Clave inicial'), findsOneWidget);
      await tester.tap(find.text('Trabajador'));
      await tester.pumpAndSettle();
      expect(find.text('PIN inicial'), findsOneWidget);
      expect(find.text('Clave inicial'), findsNothing);
    });
  });
}
