import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:checkinobra_mobile/core/network/api_client.dart';
import 'package:checkinobra_mobile/core/network/renovador_sesion.dart';
import 'package:checkinobra_mobile/core/storage/sesion_storage.dart';
import 'package:checkinobra_mobile/data/api/auth_api.dart';
import 'package:checkinobra_mobile/data/api/dominio_api.dart';
import 'package:checkinobra_mobile/features/auth/sesion_controller.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

SesionUsuario _sesion({
  String token = 'viejo',
  String? refresh = 'refresh-1',
  int usuarioId = 4,
  int empresaId = 1,
}) => SesionUsuario(
  token: token,
  refreshToken: refresh,
  usuarioId: usuarioId,
  nombre: 'Jorge Reyes',
  rol: 'BODEGUERO',
  empresaId: empresaId,
);

/// Un servidor falso con el comportamiento que importa: un token de acceso que
/// venció (`viejo`) da 401, el refresh se rota y un refresh ya usado se rechaza.
class _Servidor implements HttpClientAdapter {
  _Servidor({this.demoraRefresh = Duration.zero});

  final Duration demoraRefresh;
  final pedidas = <RequestOptions>[];
  int refrescos = 0;
  int cierres = 0;
  String refreshVigente = 'refresh-1';

  /// Qué responde `/api/auth/refresh`; por defecto, una sesión nueva.
  int statusRefresh = 200;
  Map<String, dynamic>? cuerpoRefresh;
  bool sinRed = false;

  /// Cuántas veces responder 401 aunque el token sea el nuevo.
  bool siempre401 = false;
  Map<String, dynamic> cuerpo401 = const {'mensaje': 'Token vencido'};

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    pedidas.add(options);
    if (options.path == '/api/auth/refresh') {
      refrescos++;
      await Future<void>.delayed(demoraRefresh);
      if (sinRed) {
        throw DioException.connectionError(
          requestOptions: options,
          reason: 'sin red',
        );
      }
      final recibido = (options.data as Map)['refreshToken'];
      if (statusRefresh != 200) {
        return _json(
          cuerpoRefresh ?? {'codigo': 'SESION_INVALIDA', 'mensaje': 'x'},
          statusRefresh,
        );
      }
      if (recibido != refreshVigente) {
        // Reutilizado: el servidor lo rechaza.
        return _json({'codigo': 'SESION_INVALIDA', 'mensaje': 'x'}, 401);
      }
      refreshVigente = 'refresh-${refrescos + 1}';
      return _json(
        _sesion(token: 'nuevo-$refrescos', refresh: refreshVigente).aJson(),
        200,
      );
    }
    if (options.path == '/api/auth/logout') {
      cierres++;
      return ResponseBody.fromString('', 204);
    }
    final token = options.headers['Authorization'];
    final vigente = token != null && token != 'Bearer viejo';
    if (siempre401 || !vigente) {
      return _json(cuerpo401, 401);
    }
    return _json({'ok': true, 'con': token}, 200);
  }

  ResponseBody _json(Map<String, dynamic> cuerpo, int status) =>
      ResponseBody.fromString(
        jsonEncode(cuerpo),
        status,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );

  @override
  void close({bool force = false}) {}
}

Dio _dio(_Servidor servidor) => Dio(
  BaseOptions(
    baseUrl: 'https://api.test',
    validateStatus: (s) => s != null && s < 500,
  ),
)..httpClientAdapter = servidor;

/// Todo cableado como en la app, salvo la red.
class _Montaje {
  _Montaje(this.servidor, this.storage) {
    final auth = AuthApi(ApiClient(dio: _dio(servidor)));
    renovador = RenovadorDeSesion(
      storage: storage,
      pedir: auth.renovar,
      alRenovar: renovadas.add,
    );
    cliente = ApiClient(
      dio: _dio(servidor),
      storage: storage,
      alExpirar: () => expiraciones++,
      alEmpresaSuspendida: () => suspensiones++,
      renovar: (token) => renovador.renovar(tokenQueFallo: token),
    );
  }

  final _Servidor servidor;
  final SesionStorage storage;
  late final RenovadorDeSesion renovador;
  late final ApiClient cliente;
  final renovadas = <SesionUsuario>[];
  int expiraciones = 0;
  int suspensiones = 0;

  Future<Response<dynamic>> pedirObras() =>
      cliente.dio.get<dynamic>('/api/obras');
}

Future<_Montaje> _montar({_Servidor? servidor, SesionUsuario? sesion}) async {
  FlutterSecureStorage.setMockInitialValues({});
  final storage = SesionStorage();
  await storage.guardar(sesion ?? _sesion());
  return _Montaje(servidor ?? _Servidor(), storage);
}

/// Un `AuthApi` que registra el cierre de sesión.
class _AuthQueRegistra implements AuthApi {
  _AuthQueRegistra({this.falla = false});

  final bool falla;
  final revocados = <String>[];

  @override
  Future<void> cerrarSesion(String refreshToken) async {
    revocados.add(refreshToken);
    if (falla) {
      throw DioException.connectionError(
        requestOptions: RequestOptions(),
        reason: 'sin red',
      );
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Sesión con refresh token', () {
    test('se guarda y se lee junto al token', () async {
      FlutterSecureStorage.setMockInitialValues({});
      final storage = SesionStorage();
      await storage.guardar(_sesion(refresh: 'abc.def'));

      expect((await storage.leer())?.refreshToken, 'abc.def');
    });

    test('una sesión guardada antes de que existiera no lo tiene', () {
      final json = _sesion().aJson()..remove('refreshToken');

      expect(SesionUsuario.desdeJson(json).refreshToken, isNull);
    });

    test('marcar el cambio de clave pendiente no pierde el refresh', () {
      expect(_sesion().conCambioPendiente().refreshToken, 'refresh-1');
    });
  });

  group('Un 401 renueva y reintenta', () {
    test('la petición que falló sale bien con el token nuevo', () async {
      final m = await _montar();

      final respuesta = await m.pedirObras();

      expect(respuesta.statusCode, 200);
      expect((respuesta.data as Map)['con'], 'Bearer nuevo-1');
      expect(m.servidor.refrescos, 1);
      expect(m.expiraciones, 0);
    });

    test(
      'el refresh nuevo reemplaza al anterior en el almacenamiento',
      () async {
        final m = await _montar();

        await m.pedirObras();

        final guardada = await m.storage.leer();
        expect(guardada?.token, 'nuevo-1');
        expect(guardada?.refreshToken, 'refresh-2');
        expect(m.renovadas.single.refreshToken, 'refresh-2');
      },
    );

    test(
      'el siguiente vencimiento usa el refresh nuevo, no el viejo',
      () async {
        final m = await _montar();
        await m.pedirObras();

        // Vence otra vez: se vuelve a guardar un token que el servidor rechaza.
        await m.storage.actualizarSesion(
          _sesion(token: 'viejo', refresh: m.servidor.refreshVigente),
        );
        final respuesta = await m.pedirObras();

        expect(respuesta.statusCode, 200);
        expect(m.servidor.refrescos, 2);
        expect(m.expiraciones, 0);
      },
    );

    test(
      'se reintenta una sola vez: si el token nuevo también falla, cierra',
      () async {
        final servidor = _Servidor()..siempre401 = true;
        final m = await _montar(servidor: servidor);

        final respuesta = await m.pedirObras();

        expect(respuesta.statusCode, 401);
        expect(m.servidor.refrescos, 1);
        expect(m.expiraciones, 1);
        // Dos peticiones a /api/obras (la original y un reintento), no más.
        expect(
          m.servidor.pedidas.where((p) => p.path == '/api/obras'),
          hasLength(2),
        );
      },
    );
  });

  group('Peticiones simultáneas', () {
    test(
      'tres 401 a la vez refrescan una sola vez y todas salen bien',
      () async {
        // Con demora para que las tres se superpongan.
        final servidor = _Servidor(
          demoraRefresh: const Duration(milliseconds: 50),
        );
        final m = await _montar(servidor: servidor);

        final respuestas = await Future.wait([
          m.pedirObras(),
          m.pedirObras(),
          m.pedirObras(),
        ]);

        expect(servidor.refrescos, 1);
        expect(respuestas.map((r) => r.statusCode), [200, 200, 200]);
        expect(m.expiraciones, 0);
      },
    );

    test('una que llega tarde con el token viejo no gasta otro refresh', () async {
      final m = await _montar();
      await m.pedirObras();
      expect(m.servidor.refrescos, 1);

      // Una petición salió con el token viejo y recién ahora recibe su 401: el
      // guardado ya es otro, así que solo se reintenta.
      final resultado = await m.renovador.renovar(tokenQueFallo: 'viejo');

      expect(resultado, ResultadoRenovacion.renovada);
      expect(m.servidor.refrescos, 1);
    });
  });

  group('Cuándo se cierra la sesión', () {
    test(
      'SESION_INVALIDA en la petición cierra sin intentar renovar',
      () async {
        final servidor = _Servidor()
          ..cuerpo401 = {'codigo': 'SESION_INVALIDA', 'mensaje': 'x'};
        final m = await _montar(servidor: servidor);

        final respuesta = await m.pedirObras();

        expect(respuesta.statusCode, 401);
        expect(m.expiraciones, 1);
        expect(servidor.refrescos, 0);
      },
    );

    test('el refresh rechazado cierra la sesión', () async {
      final servidor = _Servidor()..statusRefresh = 401;
      final m = await _montar(servidor: servidor);

      await m.pedirObras();

      expect(m.expiraciones, 1);
      expect(servidor.refrescos, 1);
    });

    test('un refresh ya usado (reutilizado) cierra la sesión', () async {
      final servidor = _Servidor()..refreshVigente = 'otro-distinto';
      final m = await _montar(servidor: servidor);

      await m.pedirObras();

      expect(m.expiraciones, 1);
    });

    test('sin refresh guardado (sesión antigua) cierra como antes', () async {
      final servidor = _Servidor();
      final m = await _montar(
        servidor: servidor,
        sesion: _sesion(refresh: null),
      );

      await m.pedirObras();

      expect(m.expiraciones, 1);
      expect(servidor.refrescos, 0);
    });

    test('sin señal para renovar NO cierra la sesión', () async {
      final servidor = _Servidor()..sinRed = true;
      final m = await _montar(servidor: servidor);

      final respuesta = await m.pedirObras();

      expect(respuesta.statusCode, 401);
      expect(m.expiraciones, 0);
      // Sigue guardada tal cual, para reintentar cuando vuelva la señal.
      final guardada = await m.storage.leer();
      expect(guardada?.token, 'viejo');
      expect(guardada?.refreshToken, 'refresh-1');
    });

    test('una empresa suspendida al renovar cierra con su aviso, no con el de expirada', () async {
      final servidor = _Servidor()
        ..statusRefresh = 403
        ..cuerpoRefresh = {
          'codigo': 'EMPRESA_SUSPENDIDA',
          'mensaje': 'La empresa está suspendida',
        };
      final m = await _montar(servidor: servidor);

      final respuesta = await m.pedirObras();

      expect(respuesta.statusCode, 401);
      expect(m.suspensiones, 1);
      // Es el aviso de suspensión, no el de "tu sesión expiró".
      expect(m.expiraciones, 0);
      expect(servidor.refrescos, 1);
    });

    test(
      'el renovador lo informa como suspendida, no como fallo pasajero',
      () async {
        final servidor = _Servidor()
          ..statusRefresh = 403
          ..cuerpoRefresh = {'codigo': 'EMPRESA_SUSPENDIDA', 'mensaje': 'x'};
        final m = await _montar(servidor: servidor);

        expect(
          await m.renovador.renovar(tokenQueFallo: 'viejo'),
          ResultadoRenovacion.empresaSuspendida,
        );
      },
    );

    test(
      'un 403 del refresh sin ese código sigue sin cerrar la sesión',
      () async {
        final servidor = _Servidor()
          ..statusRefresh = 403
          ..cuerpoRefresh = {'mensaje': 'sin permiso'};
        final m = await _montar(servidor: servidor);

        await m.pedirObras();

        expect(m.suspensiones, 0);
        expect(m.expiraciones, 0);
      },
    );

    test('un bloqueo temporal (429) del refresh tampoco la cierra', () async {
      final servidor = _Servidor()
        ..statusRefresh = 429
        ..cuerpoRefresh = {'codigo': 'DEMASIADOS_INTENTOS', 'mensaje': 'x'};
      final m = await _montar(servidor: servidor);

      await m.pedirObras();

      expect(m.expiraciones, 0);
    });
  });

  group('Controlador de sesión', () {
    Future<(ProviderContainer, _AuthQueRegistra, SesionStorage)> contenedor({
      bool fallaElCierre = false,
    }) async {
      FlutterSecureStorage.setMockInitialValues({});
      final storage = SesionStorage();
      await storage.guardar(_sesion());
      final auth = _AuthQueRegistra(falla: fallaElCierre);
      final c = ProviderContainer(
        overrides: [
          sesionStorageProvider.overrideWithValue(storage),
          authApiProvider.overrideWithValue(auth),
        ],
      );
      addTearDown(c.dispose);
      await c.read(sesionProvider.future);
      return (c, auth, storage);
    }

    test('cerrar sesión borra token y refresh, y revoca el refresh', () async {
      final (c, auth, storage) = await contenedor();

      await c.read(sesionProvider.notifier).salir();
      await Future<void>.delayed(Duration.zero);

      expect(await storage.leer(), isNull);
      expect(c.read(sesionProvider).valueOrNull, isNull);
      expect(auth.revocados, ['refresh-1']);
    });

    test(
      'si avisar al servidor falla, la sesión local igual se cierra',
      () async {
        final (c, auth, storage) = await contenedor(fallaElCierre: true);

        await c.read(sesionProvider.notifier).salir();
        await Future<void>.delayed(Duration.zero);

        expect(await storage.leer(), isNull);
        expect(c.read(sesionProvider).valueOrNull, isNull);
        expect(auth.revocados, ['refresh-1']);
      },
    );

    test(
      'expirar no intenta revocar: el servidor ya dijo que no vale',
      () async {
        final (c, auth, storage) = await contenedor();

        await c.read(sesionProvider.notifier).expirar();

        expect(await storage.leer(), isNull);
        expect(auth.revocados, isEmpty);
      },
    );

    test('una renovación reemplaza la sesión sin cerrarla', () async {
      final (c, _, _) = await contenedor();

      c
          .read(sesionProvider.notifier)
          .aplicarRenovada(_sesion(token: 'nuevo', refresh: 'refresh-2'));

      final s = c.read(sesionProvider).valueOrNull;
      expect(s?.token, 'nuevo');
      expect(s?.refreshToken, 'refresh-2');
    });

    test(
      'una renovación de otra cuenta no le pisa la sesión a quien entró',
      () async {
        final (c, _, _) = await contenedor();

        c
            .read(sesionProvider.notifier)
            .aplicarRenovada(
              _sesion(token: 'ajeno', refresh: 'x', usuarioId: 99),
            );
        c
            .read(sesionProvider.notifier)
            .aplicarRenovada(
              _sesion(token: 'ajeno', refresh: 'x', empresaId: 2),
            );

        expect(c.read(sesionProvider).valueOrNull?.token, 'viejo');
      },
    );

    test('renovar el token no reconstruye el cliente ni recarga los datos', () async {
      final (c, _, _) = await contenedor();
      final antes = c.read(clienteRestProvider);

      c
          .read(sesionProvider.notifier)
          .aplicarRenovada(_sesion(token: 'nuevo', refresh: 'refresh-2'));

      // Cada renovación (cada ~30 minutos) no debe tirar el caché de todas las
      // pantallas: es la misma persona.
      expect(identical(c.read(clienteRestProvider), antes), isTrue);
    });
  });

  group('Empresa suspendida al renovar, con la app cableada', () {
    test('cierra la sesión local y deja el aviso de suspensión', () async {
      FlutterSecureStorage.setMockInitialValues({});
      final storage = SesionStorage();
      await storage.guardar(_sesion());
      final servidor = _Servidor()
        ..statusRefresh = 403
        ..cuerpoRefresh = {'codigo': 'EMPRESA_SUSPENDIDA', 'mensaje': 'x'};
      final c = ProviderContainer(
        overrides: [
          sesionStorageProvider.overrideWithValue(storage),
          authApiSinTokenProvider.overrideWithValue(
            AuthApi(ApiClient(dio: _dio(servidor))),
          ),
        ],
      );
      addTearDown(c.dispose);
      await c.read(sesionProvider.future);
      c.read(apiClientProvider).dio.httpClientAdapter = servidor;

      // El token vence (401) y al renovar el servidor dice que la empresa está
      // suspendida.
      await c.read(apiClientProvider).dio.get<dynamic>('/api/obras');
      await Future<void>.delayed(Duration.zero);

      expect(c.read(sesionProvider).valueOrNull, isNull);
      expect(await storage.leer(), isNull);
      expect(c.read(avisoDeAccesoProvider), contains('suspendida'));
    });
  });

  group('Cableado de la app', () {
    test('renovar desde el proveedor guarda y actualiza la sesión', () async {
      FlutterSecureStorage.setMockInitialValues({});
      final storage = SesionStorage();
      await storage.guardar(_sesion());
      final servidor = _Servidor();
      final c = ProviderContainer(
        overrides: [
          sesionStorageProvider.overrideWithValue(storage),
          authApiSinTokenProvider.overrideWithValue(
            AuthApi(ApiClient(dio: _dio(servidor))),
          ),
        ],
      );
      addTearDown(c.dispose);
      await c.read(sesionProvider.future);

      final resultado = await c
          .read(renovadorDeSesionProvider)
          .renovar(tokenQueFallo: 'viejo');

      expect(resultado, ResultadoRenovacion.renovada);
      expect(c.read(sesionProvider).valueOrNull?.token, 'nuevo-1');
      expect((await storage.leer())?.refreshToken, 'refresh-2');
    });
  });
}
