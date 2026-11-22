import 'package:checkinobra_mobile/core/theme/app_theme.dart';
import 'package:checkinobra_mobile/data/api/auth_api.dart';
import 'package:checkinobra_mobile/data/api/cliente_rest.dart';
import 'package:checkinobra_mobile/data/api/dominio_api.dart';
import 'package:checkinobra_mobile/data/modelos/material.dart';
import 'package:checkinobra_mobile/data/modelos/obra.dart';
import 'package:checkinobra_mobile/data/modelos/partida.dart';
import 'package:checkinobra_mobile/data/modelos/presupuesto.dart';
import 'package:checkinobra_mobile/features/bodega/bodega_providers.dart';
import 'package:checkinobra_mobile/features/presupuesto/pantalla_agregar_item.dart';
import 'package:checkinobra_mobile/features/presupuesto/pantalla_agregar_partida.dart';
import 'package:checkinobra_mobile/features/presupuesto/pantalla_presupuesto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'fuentes.dart';

const _obra = Obra(
  id: 3,
  nombre: 'Los Almendros',
  cliente: 'Inmobiliaria Aconcagua',
  ubicacion: 'Ñuñoa',
  estado: 'ACTIVA',
  jefeTerrenoNombre: 'Ana Rojas',
  jefeTerrenoRut: '12.345.678-5',
);

Map<String, dynamic> _json({
  String estado = 'BORRADOR',
  double total = 0,
  String? fechaCongelado,
}) => {
  'id': 11,
  'estado': estado,
  'fechaCongelado': fechaCongelado,
  'total': total,
  'obraId': 3,
  'obraNombre': 'Los Almendros',
};

Presupuesto _presupuesto({String estado = 'BORRADOR', double total = 0}) =>
    Presupuesto.desdeJson(_json(estado: estado, total: total));

PresupuestoItem _item({
  int id = 1,
  String nombre = 'Montante 60×38',
  double cantidad = 10,
  double precio = 2500,
}) => PresupuestoItem.desdeJson({
  'id': id,
  'materialId': id,
  'materialSku': 'MET-M60',
  'materialNombre': nombre,
  'cantidad': cantidad,
  'precioUnitario': precio,
  'subtotal': cantidad * precio,
  'presupuestoId': 11,
});

/// Un presupuesto que cambia de estado como el del backend: BORRADOR →
/// APROBADO → CONGELADO, y 409 fuera de ese orden.
class _PresupuestosFalsos implements PresupuestosApi {
  _PresupuestosFalsos({this.actual, List<PresupuestoItem>? lista})
    : lista = lista ?? [];

  Presupuesto? actual;
  final List<PresupuestoItem> lista;

  int creaciones = 0;
  final agregados = <Map<String, Object?>>[];
  final desdePartida = <int>[];
  ApiException? falla;

  @override
  Future<Presupuesto?> porObra(int obraId) async => actual;

  @override
  Future<Presupuesto> crear(int obraId, {String? clave}) async {
    creaciones++;
    return actual = _presupuesto();
  }

  @override
  Future<List<PresupuestoItem>> items(int presupuestoId) async => lista;

  @override
  Future<PresupuestoItem> agregarItem(
    int presupuestoId, {
    required int materialId,
    required double cantidad,
    String? clave,
  }) async {
    agregados.add({'materialId': materialId, 'cantidad': cantidad});
    return _item(id: materialId, cantidad: cantidad);
  }

  @override
  Future<List<PresupuestoItem>> agregarDesdePartida(
    int presupuestoId, {
    required int partidaId,
    String? clave,
  }) async {
    if (falla != null) throw falla!;
    desdePartida.add(partidaId);
    return [_item(id: 1), _item(id: 2, nombre: 'Volcanita')];
  }

  @override
  Future<Presupuesto> aprobar(int presupuestoId, {String? clave}) async {
    if (falla != null) throw falla!;
    return actual = _presupuesto(estado: 'APROBADO');
  }

  @override
  Future<Presupuesto> congelar(int presupuestoId, {String? clave}) async {
    if (falla != null) throw falla!;
    return actual = _presupuesto(estado: 'CONGELADO');
  }
}

class _PartidasFalsas implements PartidasApi {
  @override
  Future<List<Partida>> porObra(int obraId) async => [
    Partida.desdeJson({
      'id': 7,
      'tipo': 'TABIQUE',
      'anchoM': 4.8,
      'altoM': 2.4,
      'separacionMontantes': 0.6,
      'obraId': 3,
    }),
  ];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Un `ClienteRest` cuya lectura de un presupuesto responde lo que se le diga.
class _RestQueFalla implements ClienteRest {
  _RestQueFalla(this.error);

  final ApiException error;

  @override
  Future<T> uno<T>(
    String ruta,
    T Function(Map<String, dynamic>) desde, {
    Map<String, dynamic>? params,
  }) async => throw error;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _montante = MaterialObra(
  id: 1,
  sku: 'MET-M60',
  codigoBarra: null,
  nombre: 'Montante 60×38',
  categoria: 'METALCOM',
  precioUnitario: 2500,
  stockMinimo: 10,
);

Future<void> _montar(
  WidgetTester tester,
  Widget pantalla,
  _PresupuestosFalsos api,
) async {
  tester.view.physicalSize = const Size(360, 780);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        obraEnCursoProvider.overrideWithValue(_obra),
        presupuestosApiProvider.overrideWithValue(api),
        partidasApiProvider.overrideWithValue(_PartidasFalsas()),
        catalogoProvider.overrideWith((ref) async => [_montante]),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(360, 780),
            textScaler: TextScaler.linear(1.3),
          ),
          child: pantalla,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tocar(WidgetTester tester, String texto) async {
  await tester.ensureVisible(find.text(texto));
  await tester.tap(find.text(texto));
  await tester.pumpAndSettle();
}

const _pantalla = Scaffold(body: PantallaPresupuesto());

void main() {
  setUpAll(() async {
    await initializeDateFormatting('es_CL');
    await cargarInter();
  });

  group('Modelo', () {
    test('solo un presupuesto congelado deja de ser editable', () {
      expect(_presupuesto().editable, isTrue);
      expect(_presupuesto(estado: 'APROBADO').editable, isTrue);
      expect(_presupuesto(estado: 'CONGELADO').editable, isFalse);
    });

    test('lee la fecha en que se congeló', () {
      final p = Presupuesto.desdeJson(
        _json(estado: 'CONGELADO', fechaCongelado: '2026-09-05'),
      );

      expect(p.fechaCongelado, DateTime(2026, 9, 5));
    });

    test('una obra sin presupuesto (404) no es un error', () async {
      final api = PresupuestosApi(
        _RestQueFalla(const ApiException(404, 'La obra no tiene presupuesto')),
      );

      expect(await api.porObra(3), isNull);
    });

    test('cualquier otro fallo sí se propaga', () {
      final api = PresupuestosApi(
        _RestQueFalla(const ApiException(403, 'Tu rol no permite esta acción')),
      );

      expect(api.porObra(3), throwsA(isA<ApiException>()));
    });
  });

  group('Crear (D4)', () {
    testWidgets('sin presupuesto ofrece crearlo y nace en borrador', (
      tester,
    ) async {
      final api = _PresupuestosFalsos();
      await _montar(tester, _pantalla, api);

      expect(find.text('Esta obra no tiene presupuesto'), findsOneWidget);
      await _tocar(tester, 'Crear presupuesto');

      expect(api.creaciones, 1);
      expect(find.text('Borrador'), findsOneWidget);
      expect(find.text('Crear presupuesto'), findsNothing);
    });
  });

  group('Ciclo de vida (D6 y D7)', () {
    testWidgets('en borrador se agrega y se aprueba, pero no se congela', (
      tester,
    ) async {
      await _montar(
        tester,
        _pantalla,
        _PresupuestosFalsos(actual: _presupuesto()),
      );

      expect(find.text('Agregar ítem'), findsOneWidget);
      expect(find.text('Aprobar presupuesto'), findsOneWidget);
      expect(find.text('Congelar presupuesto'), findsNothing);
    });

    testWidgets('aprobar pide confirmación y pasa a aprobado', (tester) async {
      final api = _PresupuestosFalsos(actual: _presupuesto());
      await _montar(tester, _pantalla, api);

      await _tocar(tester, 'Aprobar presupuesto');
      // Cancelar no aprueba.
      await _tocar(tester, 'Cancelar');
      expect(api.actual!.estado, 'BORRADOR');

      await _tocar(tester, 'Aprobar presupuesto');
      await _tocar(tester, 'Aprobar');

      expect(api.actual!.estado, 'APROBADO');
      expect(find.text('Aprobado'), findsOneWidget);
      expect(find.text('Aprobar presupuesto'), findsNothing);
      expect(find.text('Congelar presupuesto'), findsOneWidget);
    });

    testWidgets('congelar oculta todas las acciones de edición', (
      tester,
    ) async {
      final api = _PresupuestosFalsos(actual: _presupuesto(estado: 'APROBADO'));
      await _montar(tester, _pantalla, api);

      await _tocar(tester, 'Congelar presupuesto');
      await _tocar(tester, 'Congelar');

      expect(api.actual!.estado, 'CONGELADO');
      expect(find.text('Congelado'), findsOneWidget);
      expect(find.text('Agregar ítem'), findsNothing);
      expect(find.text('Agregar una partida cubicada'), findsNothing);
      expect(find.text('Aprobar presupuesto'), findsNothing);
      expect(find.text('Congelar presupuesto'), findsNothing);
    });

    testWidgets('un 409 se muestra y la pantalla se refresca', (tester) async {
      // Otro teléfono ya lo aprobó: el backend responde 409.
      final api = _PresupuestosFalsos(actual: _presupuesto())
        ..falla = const ApiException(
          409,
          'Solo se aprueba un presupuesto en BORRADOR',
        );
      await _montar(tester, _pantalla, api);

      await _tocar(tester, 'Aprobar presupuesto');
      await _tocar(tester, 'Aprobar');

      expect(
        find.text('Solo se aprueba un presupuesto en BORRADOR'),
        findsOneWidget,
      );
    });
  });

  group('Ítems (D5)', () {
    testWidgets('cada ítem muestra cantidad, precio y subtotal', (
      tester,
    ) async {
      final api = _PresupuestosFalsos(
        actual: _presupuesto(total: 25000),
        lista: [_item()],
      );
      await _montar(tester, _pantalla, api);

      expect(find.text('Montante 60×38'), findsOneWidget);
      expect(find.text('10 × \$2.500'), findsOneWidget);
      expect(find.text('\$25.000'), findsWidgets);
    });

    testWidgets('con cantidad en cero no se agrega nada', (tester) async {
      final api = _PresupuestosFalsos(actual: _presupuesto());
      await _montar(
        tester,
        PantallaAgregarItem(presupuesto: _presupuesto()),
        api,
      );

      await tester.enterText(find.byType(TextField).last, '0');
      await _tocar(tester, 'Agregar al presupuesto');

      expect(api.agregados, isEmpty);
    });

    testWidgets('sin elegir material pide elegirlo', (tester) async {
      final api = _PresupuestosFalsos(actual: _presupuesto());
      await _montar(
        tester,
        PantallaAgregarItem(presupuesto: _presupuesto()),
        api,
      );

      await tester.enterText(find.byType(TextField).last, '5');
      await _tocar(tester, 'Agregar al presupuesto');

      expect(find.text('Elige un material.'), findsOneWidget);
      expect(api.agregados, isEmpty);
    });

    testWidgets('muestra el precio vigente y envía material y cantidad', (
      tester,
    ) async {
      final api = _PresupuestosFalsos(actual: _presupuesto());
      await _montar(
        tester,
        PantallaAgregarItem(presupuesto: _presupuesto()),
        api,
      );

      await tester.tap(find.byType(DropdownMenu<MaterialObra>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Montante 60×38').last);
      await tester.pumpAndSettle();
      expect(find.textContaining('precio vigente \$2.500'), findsOneWidget);

      await tester.enterText(find.byType(TextField).last, '12');
      await tester.pumpAndSettle();
      expect(find.text('\$30.000'), findsOneWidget);

      await _tocar(tester, 'Agregar al presupuesto');
      expect(api.agregados, [
        {'materialId': 1, 'cantidad': 12.0},
      ]);
    });

    testWidgets('agregar una partida cubicada envía su id tras confirmar', (
      tester,
    ) async {
      final api = _PresupuestosFalsos(actual: _presupuesto());
      await _montar(
        tester,
        PantallaAgregarPartida(presupuesto: _presupuesto()),
        api,
      );

      await _tocar(tester, 'Tabique #7');
      expect(find.textContaining('quedará duplicada'), findsOneWidget);
      await _tocar(tester, 'Cancelar');
      expect(api.desdePartida, isEmpty);

      await _tocar(tester, 'Tabique #7');
      await _tocar(tester, 'Agregar');

      expect(api.desdePartida, [7]);
    });

    testWidgets('si la partida no está cubicada muestra el 409', (
      tester,
    ) async {
      final api = _PresupuestosFalsos(
        actual: _presupuesto(),
      )..falla = const ApiException(409, 'La partida no tiene ítems cubicados');
      await _montar(
        tester,
        PantallaAgregarPartida(presupuesto: _presupuesto()),
        api,
      );

      await _tocar(tester, 'Tabique #7');
      await _tocar(tester, 'Agregar');

      expect(find.text('La partida no tiene ítems cubicados'), findsOneWidget);
      expect(api.desdePartida, isEmpty);
    });
  });
}
