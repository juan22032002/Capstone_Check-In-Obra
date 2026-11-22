import 'dart:async';

import 'package:checkinobra_mobile/core/theme/app_theme.dart';
import 'package:checkinobra_mobile/data/api/dominio_api.dart';
import 'package:checkinobra_mobile/data/modelos/obra.dart';
import 'package:checkinobra_mobile/data/modelos/partida.dart';
import 'package:checkinobra_mobile/features/bodega/bodega_providers.dart';
import 'package:checkinobra_mobile/features/cubicacion/cubicacion_providers.dart';
import 'package:checkinobra_mobile/features/cubicacion/pantalla_detalle_partida.dart';
import 'package:checkinobra_mobile/features/cubicacion/pantalla_nueva_partida.dart';
import 'package:checkinobra_mobile/features/cubicacion/pantalla_partidas.dart';
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

Map<String, dynamic> _jsonPartida({int id = 7, String tipo = 'TABIQUE'}) => {
  'id': id,
  'tipo': tipo,
  'anchoM': 4.8,
  'altoM': 2.4,
  'separacionMontantes': 0.6,
  'obraId': 3,
};

Map<String, dynamic> _jsonItem({
  int id = 1,
  String nombre = 'Montante 60×38',
  double calculada = 9,
  double conMerma = 10,
}) => {
  'id': id,
  'partidaId': 7,
  'materialId': id,
  'materialSku': 'MET-M60',
  'materialNombre': nombre,
  'cantidadCalculada': calculada,
  'cantidadConMerma': conMerma,
};

class _PartidasFalsas implements PartidasApi {
  _PartidasFalsas({
    this.partidas = const [],
    this.items = const [],
    this.alCubicar,
  });

  final List<Partida> partidas;
  List<ItemCubicado> items;
  final List<ItemCubicado> Function()? alCubicar;

  final creadas = <Map<String, Object?>>[];
  final clavesDeCubicar = <String?>[];

  @override
  Future<List<Partida>> porObra(int obraId) async => partidas;

  @override
  Future<Partida> crear({
    required int obraId,
    required String tipo,
    required double anchoM,
    required double altoM,
    required double separacionMontantes,
    String? clave,
  }) async {
    creadas.add({
      'obraId': obraId,
      'tipo': tipo,
      'anchoM': anchoM,
      'altoM': altoM,
      'separacionMontantes': separacionMontantes,
    });
    return Partida.desdeJson(_jsonPartida());
  }

  @override
  Future<List<ItemCubicado>> cubicar(int partidaId, {String? clave}) async {
    clavesDeCubicar.add(clave);
    items = alCubicar?.call() ?? items;
    return items;
  }

  @override
  Future<List<ItemCubicado>> itemsCubicados(int partidaId) async => items;
}

Future<void> _montar(
  WidgetTester tester,
  Widget pantalla,
  PartidasApi api, {
  double escalaTexto = 1.3,
}) async {
  tester.view.physicalSize = const Size(360, 780);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        obraEnCursoProvider.overrideWithValue(_obra),
        partidasApiProvider.overrideWithValue(api),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: MediaQuery(
          data: MediaQueryData(
            size: const Size(360, 780),
            textScaler: TextScaler.linear(escalaTexto),
          ),
          child: pantalla,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('es_CL');
    await cargarInter();
  });

  group('Modelos', () {
    test('una partida calcula su superficie y nombra su tipo', () {
      final p = Partida.desdeJson(_jsonPartida(tipo: 'CIELO'));

      expect(p.superficieM2, closeTo(11.52, 1e-9));
      expect(p.nombreDelTipo, 'Cielo');
    });

    test('un ítem cubicado distingue lo calculado de lo con merma', () {
      final i = ItemCubicado.desdeJson(_jsonItem(calculada: 9, conMerma: 10));

      expect(i.merma, 1);
      expect(i.materialNombre, 'Montante 60×38');
    });

    test('un ítem sin parámetro de merma no suma nada', () {
      final i = ItemCubicado.desdeJson(_jsonItem(calculada: 12, conMerma: 12));

      expect(i.merma, 0);
    });
  });

  group('MedidasPartida', () {
    test('acepta una medida con coma o con punto decimal', () {
      expect(MedidasPartida.error('2,4', 'el alto'), isNull);
      expect(MedidasPartida.error('0.6', 'la separación'), isNull);
    });

    test('rechaza vacío, cero, negativo y texto', () {
      expect(MedidasPartida.error('', 'el ancho'), 'Falta el ancho');
      expect(MedidasPartida.error('  ', 'el ancho'), 'Falta el ancho');
      expect(
        MedidasPartida.error('0', 'la separación'),
        'Escribe la separación mayor que cero',
      );
      expect(
        MedidasPartida.error('-1', 'el alto'),
        'Escribe el alto mayor que cero',
      );
      expect(MedidasPartida.error('abc', 'el ancho'), contains('como número'));
    });
  });

  group('Lista de partidas', () {
    testWidgets('muestra cada partida con sus medidas', (tester) async {
      final api = _PartidasFalsas(
        partidas: [
          Partida.desdeJson(_jsonPartida()),
          Partida.desdeJson(_jsonPartida(id: 8, tipo: 'CIELO')),
        ],
      );
      await _montar(tester, const Scaffold(body: PantallaPartidas()), api);

      expect(find.text('Tabique #7'), findsOneWidget);
      expect(find.text('Cielo #8'), findsOneWidget);
      expect(find.textContaining('4,8 × 2,4 m'), findsNWidgets(2));
    });

    testWidgets('sin partidas dice qué hacer', (tester) async {
      await _montar(
        tester,
        const Scaffold(body: PantallaPartidas()),
        _PartidasFalsas(),
      );

      expect(find.text('Esta obra no tiene partidas'), findsOneWidget);
      expect(find.text('Nueva partida'), findsOneWidget);
    });
  });

  group('Nueva partida', () {
    testWidgets('con medidas en cero no llama al servidor', (tester) async {
      final api = _PartidasFalsas();
      await _montar(tester, const PantallaNuevaPartida(), api);

      final campos = find.byType(TextField);
      await tester.enterText(campos.at(0), '4,8');
      await tester.enterText(campos.at(1), '2,4');
      await tester.enterText(campos.at(2), '0');
      await tester.tap(find.text('Crear partida'));
      await tester.pumpAndSettle();

      expect(find.textContaining('mayor que cero'), findsOneWidget);
      expect(api.creadas, isEmpty);
    });

    testWidgets('con campos vacíos señala los tres', (tester) async {
      final api = _PartidasFalsas();
      await _montar(tester, const PantallaNuevaPartida(), api);

      await tester.tap(find.text('Crear partida'));
      await tester.pumpAndSettle();

      expect(find.text('Falta el ancho'), findsOneWidget);
      expect(find.text('Falta el alto'), findsOneWidget);
      expect(find.text('Falta la separación'), findsOneWidget);
      expect(api.creadas, isEmpty);
    });

    testWidgets('envía tipo y medidas tal como se tipearon', (tester) async {
      final api = _PartidasFalsas();
      await _montar(tester, const PantallaNuevaPartida(), api);

      await tester.tap(find.text('Cielo'));
      await tester.pumpAndSettle();
      final campos = find.byType(TextField);
      await tester.enterText(campos.at(0), '4,8');
      await tester.enterText(campos.at(1), '2,4');
      await tester.enterText(campos.at(2), '0,6');
      await tester.tap(find.text('Crear partida'));
      await tester.pumpAndSettle();

      expect(api.creadas, [
        {
          'obraId': 3,
          'tipo': 'CIELO',
          'anchoM': 4.8,
          'altoM': 2.4,
          'separacionMontantes': 0.6,
        },
      ]);
      // Termina en la partida creada, lista para cubicar.
      expect(find.text('Cubicar partida'), findsOneWidget);
    });
  });

  group('Detalle y cubicación', () {
    final partida = Partida.desdeJson(_jsonPartida());

    testWidgets('una partida sin cubicar ofrece cubicar', (tester) async {
      await _montar(
        tester,
        PantallaDetallePartida(partida: partida),
        _PartidasFalsas(),
      );

      expect(find.text('Todavía no se cubica'), findsOneWidget);
      expect(find.text('Cubicar partida'), findsOneWidget);
    });

    testWidgets('lista cada material con su cantidad calculada y con merma', (
      tester,
    ) async {
      final api = _PartidasFalsas(
        items: [
          ItemCubicado.desdeJson(_jsonItem()),
          ItemCubicado.desdeJson(
            _jsonItem(
              id: 2,
              nombre: 'Volcanita ST 10 mm',
              calculada: 11.52,
              conMerma: 12.67,
            ),
          ),
        ],
      );
      await _montar(tester, PantallaDetallePartida(partida: partida), api);

      expect(find.text('Montante 60×38'), findsOneWidget);
      expect(find.text('10'), findsOneWidget);
      expect(find.text('calculada 9'), findsOneWidget);
      expect(find.text('12,67'), findsOneWidget);
      expect(find.text('calculada 11,52'), findsOneWidget);
      // Con ítems, volver a cubicar avisa que reemplaza (RN-21).
      expect(find.text('Cubicar de nuevo'), findsOneWidget);
      expect(find.textContaining('reemplaza el cálculo'), findsOneWidget);
    });

    testWidgets('cubicar muestra el resultado', (tester) async {
      final api = _PartidasFalsas(
        alCubicar: () => [ItemCubicado.desdeJson(_jsonItem(conMerma: 10))],
      );
      await _montar(tester, PantallaDetallePartida(partida: partida), api);

      await tester.tap(find.text('Cubicar partida'));
      await tester.pumpAndSettle();

      expect(api.clavesDeCubicar, hasLength(1));
      expect(find.text('Montante 60×38'), findsOneWidget);
      expect(find.text('Cubicar de nuevo'), findsOneWidget);
    });

    testWidgets('dos cubicaciones son dos intenciones, con claves distintas', (
      tester,
    ) async {
      final api = _PartidasFalsas(
        alCubicar: () => [ItemCubicado.desdeJson(_jsonItem())],
      );
      await _montar(tester, PantallaDetallePartida(partida: partida), api);

      await tester.tap(find.text('Cubicar partida'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cubicar de nuevo'));
      await tester.pumpAndSettle();

      expect(api.clavesDeCubicar, hasLength(2));
      expect(api.clavesDeCubicar[0], isNot(api.clavesDeCubicar[1]));
    });

    testWidgets('dos toques seguidos cubican una sola vez', (tester) async {
      final respuesta = Completer<List<ItemCubicado>>();
      final api = _CubicarLento(respuesta);
      await _montar(tester, PantallaDetallePartida(partida: partida), api);

      await tester.tap(find.text('Cubicar partida'));
      await tester.pump();
      await tester.tap(find.byType(FilledButton), warnIfMissed: false);
      await tester.pump();

      expect(api.llamadas, 1);
      respuesta.complete([]);
      await tester.pumpAndSettle();
    });
  });
}

class _CubicarLento extends _PartidasFalsas {
  _CubicarLento(this._respuesta);

  final Completer<List<ItemCubicado>> _respuesta;
  int llamadas = 0;

  @override
  Future<List<ItemCubicado>> cubicar(int partidaId, {String? clave}) {
    llamadas++;
    return _respuesta.future;
  }
}
