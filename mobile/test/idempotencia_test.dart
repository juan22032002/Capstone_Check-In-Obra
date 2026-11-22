import 'dart:convert';
import 'dart:typed_data';

import 'package:checkinobra_mobile/core/network/api_client.dart';
import 'package:checkinobra_mobile/core/network/idempotencia.dart';
import 'package:checkinobra_mobile/data/api/auth_api.dart';
import 'package:checkinobra_mobile/data/api/cliente_rest.dart';
import 'package:checkinobra_mobile/features/bodega/solicitudes_acciones.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// Responde lo que se le programa y anota cada petición que recibe.
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

void main() {
  group('Clave por intención', () {
    test('reintentar lo mismo reutiliza la clave', () {
      // Es lo que hace que el reintento tras un timeout reciba la respuesta
      // del primer envío en vez de registrar un segundo despacho.
      final intento = IntentoIdempotente();
      final primera = intento.clavePara([1, 7, 'DESPACHO', 36.0]);
      expect(intento.clavePara([1, 7, 'DESPACHO', 36.0]), primera);
    });

    test('corregir el cuerpo tras un fallo da una clave nueva', () {
      // El backend responde 422 a una clave repetida con otro cuerpo.
      final intento = IntentoIdempotente();
      final primera = intento.clavePara([1, 7, 'DESPACHO', 36.0]);
      expect(intento.clavePara([1, 7, 'DESPACHO', 30.0]), isNot(primera));
    });

    test('reiniciar empieza otra intención aunque el cuerpo sea igual', () {
      final intento = IntentoIdempotente();
      final primera = intento.clavePara(['x']);
      intento.reiniciar();
      expect(intento.clavePara(['x']), isNot(primera));
    });

    test('dos pantallas nunca comparten clave', () {
      // Dos recepciones idénticas de 10 planchas son dos entregas del
      // proveedor, no un duplicado.
      expect(
        IntentoIdempotente().clavePara([10.0]),
        isNot(IntentoIdempotente().clavePara([10.0])),
      );
    });

    test('la clave es un UUID v4 que el backend acepta', () {
      final v4 = RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      );
      for (var i = 0; i < 200; i++) {
        expect(uuidV4(), matches(v4));
      }
    });
  });

  group('Escrituras contra el servidor', () {
    test('la clave viaja en la cabecera Idempotency-Key', () async {
      final (rest, servidor) = _cliente([
        (201, {'id': 1}),
      ]);
      await rest.crear('/api/kardex', {'x': 1}, (j) => j, clave: 'abc');
      expect(servidor.recibidas.single.headers['Idempotency-Key'], 'abc');
    });

    test('sin clave no se inventa una', () async {
      final (rest, servidor) = _cliente([
        (201, {'id': 1}),
      ]);
      await rest.crear('/api/obras', {'x': 1}, (j) => j);
      expect(
        servidor.recibidas.single.headers.containsKey('Idempotency-Key'),
        isFalse,
      );
    });

    test(
      '"en curso" se reintenta con la misma clave hasta el resultado',
      () async {
        final (rest, servidor) = _cliente([
          (409, {'mensaje': 'en curso', 'codigo': 'IDEMPOTENCIA_EN_CURSO'}),
          (201, {'id': 42}),
        ]);
        final r = await rest.crear(
          '/api/kardex',
          {'x': 1},
          (j) => j,
          clave: 'abc',
        );
        expect(r['id'], 42);
        expect(servidor.recibidas, hasLength(2));
        expect(
          servidor.recibidas.map((o) => o.headers['Idempotency-Key']),
          everyElement('abc'),
        );
      },
    );

    test('un choque concurrente se reintenta con la misma clave', () async {
      final (rest, servidor) = _cliente([
        (409, {'mensaje': 'choque', 'codigo': 'CONFLICTO_CONCURRENTE'}),
        (201, {'id': 7}),
      ]);
      final r = await rest.crear('/api/kardex', {}, (j) => j, clave: 'k');
      expect(r['id'], 7);
      expect(servidor.recibidas, hasLength(2));
    });

    test('un dato duplicado no se reintenta', () async {
      final (rest, servidor) = _cliente([
        (409, {'mensaje': 'El SKU ya existe', 'codigo': 'DATO_DUPLICADO'}),
      ]);
      await expectLater(
        rest.crear('/api/materiales', {}, (j) => j, clave: 'k'),
        throwsA(isA<ApiException>()),
      );
      expect(servidor.recibidas, hasLength(1));
    });

    test('otro 409 no se reintenta y trae su código', () async {
      final (rest, servidor) = _cliente([
        (
          409,
          {'mensaje': 'Stock insuficiente', 'codigo': 'STOCK_INSUFICIENTE'},
        ),
      ]);
      await expectLater(
        rest.crear('/api/kardex', {'x': 1}, (j) => j, clave: 'abc'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.codigo, 'codigo', 'STOCK_INSUFICIENTE')
              .having((e) => e.yaEstabaHecho, 'yaEstabaHecho', isFalse),
        ),
      );
      expect(servidor.recibidas, hasLength(1));
    });

    test('"ya resuelta" se reconoce como algo ya hecho', () async {
      final (rest, _) = _cliente([
        (
          409,
          {'mensaje': 'La solicitud ya fue aprobada', 'codigo': 'YA_RESUELTA'},
        ),
      ]);
      await expectLater(
        rest.actualizar('/api/solicitudes-material/1/aprobar', {}, (j) => j),
        throwsA(
          isA<ApiException>().having(
            (e) => e.yaEstabaHecho,
            'yaEstabaHecho',
            isTrue,
          ),
        ),
      );
    });

    test('un cuerpo de error sin código sigue funcionando', () async {
      // El campo `codigo` es aditivo: un backend anterior no lo manda.
      final (rest, _) = _cliente([
        (409, {'mensaje': 'Conflicto'}),
      ]);
      await expectLater(
        rest.crear('/api/kardex', {}, (j) => j),
        throwsA(
          isA<ApiException>()
              .having((e) => e.codigo, 'codigo', isNull)
              .having((e) => e.mensaje, 'mensaje', 'Conflicto'),
        ),
      );
    });
  });

  group('Devolución propuesta', () {
    test('antes de las 18:00 es hoy al cierre', () {
      expect(
        devolucionPorDefecto(DateTime(2026, 9, 27, 9, 30)),
        DateTime(2026, 9, 27, 18),
      );
    });

    test('pasadas las 18:00 es mañana, no un préstamo ya vencido', () {
      // Antes se proponía hoy a las 18:00 a cualquier hora, y un préstamo
      // aprobado a las 19:00 nacía vencido y con alerta.
      expect(
        devolucionPorDefecto(DateTime(2026, 9, 27, 19, 5)),
        DateTime(2026, 9, 28, 18),
      );
      expect(
        devolucionPorDefecto(DateTime(2026, 9, 27, 18)),
        DateTime(2026, 9, 28, 18),
      );
    });

    test('el último día del mes pasa al mes siguiente', () {
      expect(
        devolucionPorDefecto(DateTime(2026, 9, 30, 20)),
        DateTime(2026, 10, 1, 18),
      );
    });
  });
}
