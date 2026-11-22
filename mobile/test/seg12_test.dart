import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:checkinobra_mobile/core/network/api_client.dart';
import 'package:checkinobra_mobile/core/network/errores.dart';
import 'package:checkinobra_mobile/core/theme/app_theme.dart';
import 'package:checkinobra_mobile/data/api/auth_api.dart';
import 'package:checkinobra_mobile/data/api/cliente_rest.dart';
import 'package:checkinobra_mobile/data/api/dominio_api.dart';
import 'package:checkinobra_mobile/data/modelos/kardex.dart';
import 'package:checkinobra_mobile/data/modelos/solicitud.dart';
import 'package:checkinobra_mobile/features/admin/pantalla_importacion.dart';
import 'package:checkinobra_mobile/features/auth/sesion_controller.dart';
import 'package:checkinobra_mobile/features/bodega/solicitudes_acciones.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

/// Responde lo que se le programa y anota cada petición que recibe. Si llega una
/// petición de más, falla: es lo que detecta un reintento que no debía ocurrir.
class _ServidorFalso implements HttpClientAdapter {
  _ServidorFalso(this._respuestas);

  final List<(int, Map<String, dynamic>)> _respuestas;
  final recibidas = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    recibidas.add(options);
    final (status, cuerpo) = _respuestas.removeAt(0);
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

(ClienteRest, _ServidorFalso) _cliente(List<(int, Map<String, dynamic>)> r) {
  final servidor = _ServidorFalso(r);
  final dio = Dio(
    BaseOptions(
      baseUrl: 'http://api.test',
      validateStatus: (s) => s != null && s < 500,
    ),
  )..httpClientAdapter = servidor;
  return (ClienteRest(ApiClient(dio: dio)), servidor);
}

Map<String, dynamic> _error(String codigo, String mensaje, int status) => {
  'status': status,
  'codigo': codigo,
  'mensaje': mensaje,
};

class _SolicitudesQueRegistra implements SolicitudesApi {
  final aprobaciones = <double>[];

  @override
  Future<MovimientoKardex> aprobarMaterial(
    int solicitudId, {
    required double cantidadAEntregar,
    String? clave,
  }) {
    aprobaciones.add(cantidadAEntregar);
    return Completer<MovimientoKardex>().future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SesionBodeguero extends SesionController {
  @override
  Future<SesionUsuario?> build() async => const SesionUsuario(
    token: 't',
    usuarioId: 1,
    nombre: 'Jorge Reyes',
    rol: 'BODEGUERO',
    empresaId: 1,
  );
}

SolicitudMaterial _pidio36() => SolicitudMaterial.desdeJson({
  'id': 1,
  'cantidad': 36.0,
  'estado': 'PENDIENTE',
  'fechaSolicitud': '2026-09-02T08:14:00',
  'motivoRechazo': null,
  'trabajadorId': 5,
  'trabajadorNombre': 'Marcelo Sepúlveda',
  'trabajadorRut': '17.930.556-9',
  'materialId': 2,
  'materialSku': 'VOL-ST-10',
  'materialNombre': 'Volcanita ST 10 mm',
  'obraId': 3,
  'resueltoPorId': null,
  'resueltoPorNombre': null,
});

void main() {
  setUpAll(() => initializeDateFormatting('es_CL'));

  group('Importación: solo .xlsx (S-21)', () {
    test('el selector solo ofrece xlsx', () {
      expect(extensionesDePlanilla, ['xlsx']);
    });

    test('acepta un .xlsx en cualquier mayúscula', () {
      expect(esPlanillaXlsx('materiales.xlsx'), isTrue);
      expect(esPlanillaXlsx('MATERIALES.XLSX'), isTrue);
    });

    test('rechaza .xls, .csv, otros y nombres que solo lo parecen', () {
      for (final nombre in [
        'materiales.xls',
        'materiales.csv',
        'materiales.pdf',
        'materiales.xlsx.exe',
        'materiales.xlsm',
        'xlsx',
        '',
      ]) {
        expect(esPlanillaXlsx(nombre), isFalse, reason: nombre);
      }
    });

    test('el aviso dice cómo convertirla', () {
      expect(mensajePlanillaNoXlsx, contains('.xlsx'));
      expect(mensajePlanillaNoXlsx, contains('guárdala'));
    });
  });

  group('Pantallas del trabajador (S-19)', () {
    // El backend dejó sin acceso al TRABAJADOR a /api/trabajadores (lista y
    // ficha), /api/alertas, /api/partidas y /api/cuadrillas. Esta revisión
    // falla si una pantalla suya empieza a llamar algo de eso, y obliga a
    // mirar si la ruta está permitida a su rol.
    final fuentes = Directory('lib/features/trabajador')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .map((f) => f.readAsStringSync())
        .join('\n');

    Set<String> metodosDe(String api) =>
        RegExp('${api}ApiProvider\\)\\s*\\.(\\w+)\\(')
            .allMatches(fuentes)
            .map((m) => m.group(1)!)
            .toSet();

    test('hay código del trabajador que revisar', () {
      expect(fuentes, contains('trabajadoresApiProvider'));
    });

    test('no usa las APIs de alertas ni de partidas', () {
      expect(fuentes, isNot(contains('alertasApiProvider')));
      expect(fuentes, isNot(contains('partidasApiProvider')));
      expect(fuentes, isNot(contains('presupuestosApiProvider')));
    });

    test('de trabajadores solo usa lo propio: su ficha y su credencial', () {
      // `porObra` es `GET /api/trabajadores` y `porCredencial` es de bodega.
      expect(metodosDe('trabajadores'), {'yo', 'renovarMiCredencial'});
    });

    test('de préstamos solo usa los suyos', () {
      expect(metodosDe('prestamos'), {'mios'});
    });

    test('las rutas que usa están entre las que no cambian', () {
      final rutas = RegExp(r"'(/api/[^']+)'")
          .allMatches(File('lib/data/api/dominio_api.dart').readAsStringSync())
          .map((m) => m.group(1)!)
          .toSet();
      // Las rutas propias del trabajador siguen existiendo en la API de la app.
      expect(
        rutas,
        containsAll([
          '/api/trabajadores/yo',
          '/api/trabajadores/yo/credencial',
          '/api/solicitudes-material/mias',
          '/api/prestamos-herramienta/mios',
        ]),
      );
    });
  });

  group('Rechazos de negocio del servidor (S-26)', () {
    const sinObra =
        'Marcelo Sepúlveda no está asignado a esta obra: pertenece a otra.';
    const sinCuadrilla = 'Marcelo Sepúlveda no tiene cuadrilla asignada.';

    test('un despacho a un trabajador de otra obra muestra el mensaje y no se reintenta', () async {
      final (rest, servidor) = _cliente([
        (409, _error('OBRA_NO_ASIGNADA', sinObra, 409)),
      ]);

      Object? fallo;
      try {
        await KardexApi(rest).registrar(
          obraId: 3,
          materialId: 2,
          trabajadorId: 5,
          tipo: 'DESPACHO',
          cantidad: 10,
          clave: 'k',
        );
      } catch (e) {
        fallo = e;
      }

      expect(fallo, isA<ApiException>());
      expect((fallo as ApiException).codigo, 'OBRA_NO_ASIGNADA');
      expect(mensajeDeError(fallo), sinObra);
      // Una sola petición: la respuesta no cambia hasta elegir a otro trabajador.
      expect(servidor.recibidas, hasLength(1));
    });

    test('un consumo igual', () async {
      final (rest, servidor) = _cliente([
        (409, _error('OBRA_NO_ASIGNADA', sinObra, 409)),
      ]);

      await expectLater(
        KardexApi(rest).registrar(
          obraId: 3,
          materialId: 2,
          trabajadorId: 5,
          tipo: 'CONSUMO',
          cantidad: 10,
        ),
        throwsA(
          isA<ApiException>().having((e) => e.mensaje, 'mensaje', sinObra),
        ),
      );
      expect(servidor.recibidas, hasLength(1));
    });

    test('un préstamo directo a un trabajador sin cuadrilla', () async {
      final (rest, servidor) = _cliente([
        (409, _error('SIN_CUADRILLA', sinCuadrilla, 409)),
      ]);

      Object? fallo;
      try {
        await PrestamosApi(rest).prestar(
          herramientaId: 8,
          trabajadorId: 5,
          obraId: 3,
          fechaDevolEsperada: DateTime(2026, 9, 30),
          clave: 'k',
        );
      } catch (e) {
        fallo = e;
      }

      expect((fallo as ApiException).codigo, 'SIN_CUADRILLA');
      expect(mensajeDeError(fallo), sinCuadrilla);
      expect(servidor.recibidas, hasLength(1));
    });

    test('solo los 409 reintentables se reintentan, no estos', () async {
      // Contraste: CONFLICTO_CONCURRENTE sí se reintenta; OBRA_NO_ASIGNADA no.
      final (rest, servidor) = _cliente([
        (409, _error('CONFLICTO_CONCURRENTE', 'x', 409)),
        (
          200,
          {
            'id': 1,
            'tipo': 'DESPACHO',
            'cantidad': 1.0,
            'fecha': '2026-09-02T08:14:00',
            'obraId': 3,
            'materialId': 2,
            'materialNombre': 'Volcanita',
            'materialSku': 'V',
            'trabajadorId': 5,
            'trabajadorNombre': 'M',
            'trabajadorRut': null,
            'costoUnitario': null,
            'registradoPorNombre': 'J',
          },
        ),
      ]);

      try {
        await KardexApi(rest)
            .registrar(obraId: 3, materialId: 2, tipo: 'DESPACHO', cantidad: 1);
      } catch (_) {}

      expect(servidor.recibidas.length, greaterThan(1));
    });

    test('aprobar de más responde 400 y el mensaje llega tal cual', () async {
      const mensaje = 'La cantidad a entregar no puede superar lo pedido (36).';
      final (rest, servidor) = _cliente([
        (400, _error('VALIDACION', mensaje, 400)),
      ]);

      await expectLater(
        SolicitudesApi(rest).aprobarMaterial(1, cantidadAEntregar: 40),
        throwsA(
          isA<ApiException>()
              .having((e) => e.statusCode, 'status', 400)
              .having((e) => e.mensaje, 'mensaje', mensaje),
        ),
      );
      expect(servidor.recibidas, hasLength(1));
    });
  });

  group('Aprobar material: cantidad a entregar (S-17)', () {
    Future<_SolicitudesQueRegistra> abrir(WidgetTester tester) async {
      tester.view.physicalSize = const Size(400, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final api = _SolicitudesQueRegistra();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sesionProvider.overrideWith(_SesionBodeguero.new),
            solicitudesApiProvider.overrideWithValue(api),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () => aprobarMaterial(context, _pidio36()),
                    child: const Text('abrir'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      // En la app la sesión ya está cargada porque la observa la raíz; acá nadie
      // la observa, así que se espera a que cargue.
      final contenedor = ProviderScope.containerOf(
        tester.element(find.text('abrir')),
      );
      await tester.runAsync(() => contenedor.read(sesionProvider.future));
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      return api;
    }

    Future<void> aprobarCon(WidgetTester tester, String cantidad) async {
      await tester.enterText(find.byType(TextField).first, cantidad);
      await tester.pump();
      final boton = find.widgetWithText(FilledButton, 'Aprobar y despachar');
      await tester.ensureVisible(boton);
      await tester.tap(boton);
      await tester.pump();
    }

    testWidgets('más de lo pedido no se envía', (tester) async {
      final api = await abrir(tester);

      await aprobarCon(tester, '40');

      expect(
        find.textContaining('No puedes entregar más de lo pedido'),
        findsOneWidget,
      );
      expect(find.textContaining('(36)'), findsOneWidget);
      expect(api.aprobaciones, isEmpty);
    });

    testWidgets('cero no se envía', (tester) async {
      final api = await abrir(tester);

      await aprobarCon(tester, '0');

      expect(find.text('Escribe una cantidad mayor a cero.'), findsOneWidget);
      expect(api.aprobaciones, isEmpty);
    });

    testWidgets('una entrega parcial sí se envía', (tester) async {
      final api = await abrir(tester);

      await aprobarCon(tester, '30');

      expect(api.aprobaciones, [30.0]);
    });

    testWidgets('lo pedido completo sí se envía', (tester) async {
      final api = await abrir(tester);

      await aprobarCon(tester, '36');

      expect(api.aprobaciones, [36.0]);
    });
  });
}
