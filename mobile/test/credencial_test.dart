import 'package:checkinobra_mobile/core/storage/sesion_storage.dart';
import 'package:checkinobra_mobile/core/theme/app_theme.dart';
import 'package:checkinobra_mobile/data/api/auth_api.dart';
import 'package:checkinobra_mobile/data/api/dominio_api.dart';
import 'package:checkinobra_mobile/data/modelos/perfil_trabajador.dart';
import 'package:checkinobra_mobile/features/auth/sesion_controller.dart';
import 'package:checkinobra_mobile/features/trabajador/pantalla_credencial.dart';
import 'package:checkinobra_mobile/features/trabajador/trabajador_providers.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'fuentes.dart';

class _SesionTrabajador extends SesionController {
  @override
  Future<SesionUsuario?> build() async => const SesionUsuario(
    token: 't',
    usuarioId: 6,
    nombre: 'Marcelo Sepúlveda',
    rol: 'TRABAJADOR',
    empresaId: 1,
  );
}

const _perfil = PerfilTrabajador(
  id: 1,
  usuarioId: 6,
  nombre: 'Marcelo Sepúlveda',
  rut: '17.930.556-9',
  cuadrillaId: 1,
  cuadrillaNombre: 'Cuadrilla 2',
  obraId: 2,
  obraNombre: 'Los Almendros · Torre B',
  obraEstado: 'ACTIVA',
  credencialQr: 'CRED-7f3a9c2e-1b44',
);

/// Responde con [respuesta] o lanza [error], según cuál se le dé.
class _TrabajadoresFalsos implements TrabajadoresApi {
  _TrabajadoresFalsos({this.respuesta, this.error});

  final PerfilTrabajador? respuesta;
  final Object? error;

  @override
  Future<PerfilTrabajador> yo() async {
    if (error != null) throw error!;
    return respuesta!;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final _sinRed = DioException(
  requestOptions: RequestOptions(path: '/api/trabajadores/yo'),
  type: DioExceptionType.connectionError,
);

ProviderContainer _contenedor(TrabajadoresApi api) {
  final c = ProviderContainer(
    overrides: [
      sesionProvider.overrideWith(_SesionTrabajador.new),
      trabajadoresApiProvider.overrideWithValue(api),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('es_CL');
    await cargarInter();
  });

  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  group('Sin conexión', () {
    test('muestra la última credencial guardada', () async {
      // Con señal: se guarda la copia.
      final conRed = _contenedor(_TrabajadoresFalsos(respuesta: _perfil));
      await conRed.read(sesionProvider.future);
      final fresco = await conRed.read(perfilTrabajadorProvider.future);
      expect(fresco.sinConexion, isFalse);

      // Sin señal: se muestra esa copia, marcada como guardada.
      final sinRed = _contenedor(_TrabajadoresFalsos(error: _sinRed));
      await sinRed.read(sesionProvider.future);
      final guardado = await sinRed.read(perfilTrabajadorProvider.future);
      expect(guardado.credencialQr, 'CRED-7f3a9c2e-1b44');
      expect(guardado.sinConexion, isTrue);
    });

    test('sin copia guardada, el error de red sube', () async {
      final c = _contenedor(_TrabajadoresFalsos(error: _sinRed));
      await c.read(sesionProvider.future);
      await expectLater(
        c.read(perfilTrabajadorProvider.future),
        throwsA(isA<DioException>()),
      );
    });

    test(
      'si el servidor responde, su respuesta manda sobre la copia',
      () async {
        await SesionStorage().guardarPerfilTrabajador(_perfil, empresaId: 1);
        final c = _contenedor(
          _TrabajadoresFalsos(
            error: const ApiException(404, 'No se encontró lo que buscabas.'),
          ),
        );
        await c.read(sesionProvider.future);
        await expectLater(
          c.read(perfilTrabajadorProvider.future),
          throwsA(isA<ApiException>()),
        );
      },
    );

    test('nadie ve la credencial guardada de otro usuario', () async {
      final storage = SesionStorage();
      await storage.guardarPerfilTrabajador(_perfil, empresaId: 1);
      expect(
        await storage.leerPerfilTrabajador(empresaId: 1, usuarioId: 99),
        isNull,
      );
      expect(
        await storage.leerPerfilTrabajador(empresaId: 1, usuarioId: 6),
        isNotNull,
      );
    });

    test('cerrar sesión borra la credencial guardada', () async {
      final storage = SesionStorage();
      await storage.guardarPerfilTrabajador(_perfil, empresaId: 1);
      await storage.cerrarSesion();
      expect(
        await storage.leerPerfilTrabajador(empresaId: 1, usuarioId: 6),
        isNull,
      );
    });
  });

  group('Pantalla completa', () {
    late List<String> llamadas;

    setUp(() {
      llamadas = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('checkinobra/pantalla'),
            (call) async {
              llamadas.add(call.method);
              return null;
            },
          );
    });

    tearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('checkinobra/pantalla'),
            null,
          ),
    );

    Future<void> montar(WidgetTester tester, PerfilTrabajador perfil) async {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sesionProvider.overrideWith(_SesionTrabajador.new),
            perfilTrabajadorProvider.overrideWith((ref) async => perfil),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            home: const Scaffold(body: PantallaCredencial()),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('abre con el brillo al máximo y lo devuelve al cerrar', (
      tester,
    ) async {
      await montar(tester, _perfil);
      await tester.tap(find.text('Mostrar en bodega'));
      await tester.pumpAndSettle();

      expect(find.byType(PantallaCredencialCompleta), findsOneWidget);
      expect(find.byType(QrImageView), findsOneWidget);
      expect(llamadas, ['brilloMaximo']);
      // El QR ocupa el ancho de la pantalla, no el tope de 300 de la tarjeta.
      expect(tester.getSize(find.byType(QrImageView)).width, greaterThan(300));

      // Un toque en cualquier parte la cierra.
      await tester.tap(find.text('Toca para cerrar'));
      await tester.pumpAndSettle();
      expect(find.byType(PantallaCredencialCompleta), findsNothing);
      expect(llamadas, ['brilloMaximo', 'brilloNormal']);
    });

    testWidgets('sin conexión avisa y no ofrece renovar', (tester) async {
      await montar(
        tester,
        PerfilTrabajador.desdeJson({
          ..._perfil.aJson(),
          'guardadoEl': DateTime.now().toIso8601String(),
        }),
      );
      expect(find.textContaining('Sin conexión'), findsOneWidget);
      expect(find.byType(QrImageView), findsOneWidget);
      expect(find.text('Perdí el teléfono: renovar'), findsNothing);
      expect(find.text('Mostrar en bodega'), findsOneWidget);
    });
  });
}
