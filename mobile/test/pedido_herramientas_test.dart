import 'package:checkinobra_mobile/core/network/errores.dart';
import 'package:checkinobra_mobile/core/theme/app_theme.dart';
import 'package:checkinobra_mobile/data/api/auth_api.dart';
import 'package:checkinobra_mobile/data/api/dominio_api.dart';
import 'package:checkinobra_mobile/data/modelos/herramienta.dart';
import 'package:checkinobra_mobile/data/modelos/pedido_herramienta.dart';
import 'package:checkinobra_mobile/data/modelos/perfil_trabajador.dart';
import 'package:checkinobra_mobile/features/auth/sesion_controller.dart';
import 'package:checkinobra_mobile/features/bodega/pantalla_entrega_pedido.dart';
import 'package:checkinobra_mobile/features/trabajador/pantalla_credencial.dart';
import 'package:checkinobra_mobile/features/trabajador/pantalla_pedido_qr.dart';
import 'package:checkinobra_mobile/features/trabajador/pantalla_pedir.dart';
import 'package:checkinobra_mobile/features/trabajador/shell_trabajador.dart';
import 'package:checkinobra_mobile/features/trabajador/trabajador_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

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

const _uuid = '3f1c2a9e-7b44-4d0a-9c3e-5a6b7c8d9e0f';

Herramienta _herramienta(
  int id,
  String nombre, {
  String estado = 'DISPONIBLE',
}) => Herramienta(
  id: id,
  codigoQr: 'HER-$id',
  nombre: nombre,
  categoria: 'ELECTRICA',
  estado: estado,
  valorReposicion: 90000,
);

/// Dos taladros iguales, un esmeril, una sierra que no está y un nivel que ya
/// tiene pedido.
final _herramientas = [
  _herramienta(1, 'Taladro percutor'),
  _herramienta(2, 'Taladro percutor'),
  _herramienta(3, 'Esmeril angular'),
  _herramienta(4, 'Sierra circular', estado: 'PRESTADA'),
  _herramienta(5, 'Nivel láser'),
];

final _nivelYaPedido = MiSolicitud(
  id: 30,
  itemId: 5,
  origen: OrigenSolicitud.herramienta,
  nombre: 'Nivel láser',
  cantidad: '1 unidad',
  estado: 'PENDIENTE',
  fecha: DateTime.now().subtract(const Duration(hours: 1)),
  motivoRechazo: null,
  resueltoPorNombre: null,
);

/// Lo que responde el backend al crear, tal cual.
Map<String, dynamic> _jsonPedido({
  String estado = 'PENDIENTE',
  List<(int, String)> herramientas = const [
    (1, 'Taladro percutor'),
    (3, 'Esmeril angular'),
  ],
}) => {
  'id': 12,
  'codigoQr': _uuid,
  'estado': estado,
  'fechaSolicitud': '2026-10-19T08:14:00',
  'descripcion': 'Perforar la losa del 5º piso',
  'trabajador': {'id': 1, 'nombre': 'Marcelo Sepúlveda', 'rut': '17.930.556-9'},
  'solicitudes': [
    for (final (i, (id, nombre)) in herramientas.indexed)
      {
        'id': 40 + i,
        'cantidad': 1,
        'estado': estado == 'ENTREGADO' ? 'APROBADA' : estado,
        'fechaSolicitud': '2026-10-19T08:14:00',
        'motivoRechazo': null,
        'trabajadorId': 1,
        'trabajadorNombre': 'Marcelo Sepúlveda',
        'trabajadorRut': '17.930.556-9',
        'herramientaId': id,
        'herramientaNombre': nombre,
        'resueltoPorNombre': null,
        'descripcion': 'Perforar la losa del 5º piso',
        'pedidoId': 12,
      },
  ],
  'fechaEntrega': null,
  'entregadoPorId': null,
  'entregadoPorNombre': null,
};

/// Registra lo que se pide, entrega y cancela.
class _PedidosFalsos implements PedidosHerramientaApi {
  _PedidosFalsos({
    this.errorAlCrear,
    this.errorAlEntregar,
    this.estadoAlReleer = 'ENTREGADO',
  });

  final Object? errorAlCrear;
  final Object? errorAlEntregar;

  /// Lo que responde `porQr` después de un YA_RESUELTA.
  final String estadoAlReleer;

  final creados = <(List<int>, String)>[];
  final claves = <String?>[];
  final entregas = <(String, DateTime)>[];
  final cancelados = <int>[];

  @override
  Future<PedidoHerramienta> crear({
    required List<int> herramientaIds,
    required String descripcion,
    String? clave,
  }) async {
    creados.add((herramientaIds, descripcion));
    claves.add(clave);
    if (errorAlCrear != null) throw errorAlCrear!;
    return PedidoHerramienta.desdeJson(_jsonPedido());
  }

  @override
  Future<EntregaPedido> entregar(
    String codigoQr, {
    required DateTime fechaDevolEsperada,
    String? clave,
  }) async {
    entregas.add((codigoQr, fechaDevolEsperada));
    claves.add(clave);
    if (errorAlEntregar != null) throw errorAlEntregar!;
    return EntregaPedido.desdeJson({
      'pedido': _jsonPedido(estado: 'ENTREGADO'),
      'prestamos': [
        for (final (id, nombre) in [
          (1, 'Taladro percutor'),
          (3, 'Esmeril angular'),
        ])
          {
            'id': id,
            'fechaPrestamo': '2026-10-19T09:00:00',
            'fechaDevolEsperada': fechaDevolEsperada.toIso8601String(),
            'fechaDevolReal': null,
            'herramientaId': id,
            'herramientaNombre': nombre,
            'trabajadorNombre': 'Marcelo Sepúlveda',
            'trabajadorRut': '17.930.556-9',
            'autorizadoPorNombre': 'Jorge Reyes',
          },
      ],
    });
  }

  @override
  Future<PedidoHerramienta> porQr(String codigoQr) async =>
      PedidoHerramienta.desdeJson(_jsonPedido(estado: estadoAlReleer));

  @override
  Future<PedidoHerramienta> cancelar(int id, {String? clave}) async {
    cancelados.add(id);
    return PedidoHerramienta.desdeJson(_jsonPedido(estado: 'CANCELADO'));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Abre [pantalla] sobre una ruta vacía, para que pueda cerrarse.
Future<void> _montar(
  WidgetTester tester,
  Widget pantalla, {
  List<Override> overrides = const [],
}) async {
  tester.view.physicalSize = const Size(360, 780);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sesionProvider.overrideWith(_SesionTrabajador.new),
        perfilTrabajadorProvider.overrideWith((ref) async => _perfil),
        misPrestamosProvider.overrideWith((ref) async => const []),
        misSolicitudesProvider.overrideWith((ref) async => [_nivelYaPedido]),
        misPedidosHerramientaProvider.overrideWith((ref) async => const []),
        ...overrides,
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.3)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(context)
                    .push(MaterialPageRoute<void>(builder: (_) => pantalla)),
                child: const Text('Abrir'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Abrir'));
  await tester.pumpAndSettle();
}

FilledButton _botonSolicitar(WidgetTester tester) => tester.widget(
  find.ancestor(
    of: find.textContaining('Solicitar ('),
    matching: find.byWidgetPredicate((w) => w is FilledButton),
  ),
);

void main() {
  setUpAll(() async {
    await initializeDateFormatting('es_CL');
    await cargarInter();
  });

  group('QR del pedido', () {
    test('lleva el prefijo y los endpoints reciben el UUID sin él', () {
      final p = PedidoHerramienta.desdeJson(_jsonPedido());
      expect(p.contenidoQr, 'PEDIDO:$_uuid');
      expect(PedidoHerramienta.codigoDesdeQr(p.contenidoQr), _uuid);
      // El lector puede devolver espacios o el prefijo en minúsculas.
      expect(PedidoHerramienta.codigoDesdeQr(' pedido:$_uuid '), _uuid);
    });

    test('una credencial o un código de barras no son un pedido', () {
      // La credencial también es un UUID: sin prefijo, va al otro camino.
      expect(PedidoHerramienta.codigoDesdeQr(_uuid), isNull);
      expect(PedidoHerramienta.codigoDesdeQr('7801234567890'), isNull);
      expect(PedidoHerramienta.codigoDesdeQr('PEDIDO:'), isNull);
    });

    test('trae a quien pidió y una solicitud por herramienta', () {
      final p = PedidoHerramienta.desdeJson(_jsonPedido());
      expect(p.pendiente, isTrue);
      expect(p.trabajador.identificacion, 'Marcelo Sepúlveda · 17.930.556-9');
      expect(p.solicitudes.map((s) => s.herramientaId), [1, 3]);
      expect(p.solicitudes.first.pedidoId, 12);
    });

    test('resolver una de sus solicitudes sola dice qué hacer', () {
      const e = ApiException(
        409,
        'Esta solicitud es parte de un pedido con QR: se entrega o se cancela '
        'el pedido completo',
        codigo: 'EN_PEDIDO',
      );
      expect(mensajeDeError(e), contains('pedido completo'));
      expect(mensajeDeError(e), startsWith('Esta herramienta va en un pedido'));
    });

    test('sus herramientas no se retiran una a una, solo el pedido', () {
      final p = PedidoHerramienta.desdeJson(_jsonPedido());
      final suelta = MiSolicitud.deHerramienta(p.solicitudes.first);
      expect(suelta.enEspera, isTrue);
      expect(suelta.cancelable, isFalse);
    });
  });

  group('Pedir varias herramientas', () {
    testWidgets('se marcan varias y sale un solo pedido con su QR', (
      tester,
    ) async {
      final api = _PedidosFalsos();
      await _montar(
        tester,
        const PantallaPedirHerramienta(),
        overrides: [
          pedidosHerramientaApiProvider.overrideWithValue(api),
          herramientasParaPedirProvider.overrideWith(
            (ref) async => _herramientas,
          ),
        ],
      );

      // Sin nada marcado no se puede enviar.
      expect(find.text('Solicitar (0)'), findsOneWidget);
      expect(_botonSolicitar(tester).onPressed, isNull);
      // La sierra no está en bodega: no se marca, ofrece conseguirla.
      expect(find.text('Pedir que\nla consigan'), findsOneWidget);
      // El nivel ya lo tiene pedido: se ve, pero no se puede marcar.
      expect(find.text('Ya la pediste'), findsOneWidget);
      final casillas = tester.widgetList<Checkbox>(find.byType(Checkbox));
      expect(casillas.length, 3);
      expect(casillas.where((c) => c.onChanged == null).length, 1);

      await tester.tap(find.text('Taladro percutor'));
      await tester.tap(find.text('Esmeril angular'));
      await tester.tap(find.text('Nivel láser'));
      await tester.pump();
      expect(find.text('Solicitar (2)'), findsOneWidget);

      // Desmarcar y volver a marcar, ahora desde la casilla. Van primero las
      // disponibles por nombre: el esmeril es la primera.
      await tester.tap(find.text('Esmeril angular'));
      await tester.pump();
      expect(find.text('Solicitar (1)'), findsOneWidget);
      await tester.tap(find.byType(Checkbox).first);
      await tester.pump();
      expect(find.text('Solicitar (2)'), findsOneWidget);

      await tester.tap(find.text('Solicitar (2)'));
      await tester.pumpAndSettle();
      expect(find.text('Pedir 2 herramientas'), findsOneWidget);

      // Un solo "para qué" para todo, y sin él no sale.
      await tester.tap(find.text('Pedir y generar QR'));
      await tester.pumpAndSettle();
      expect(
        find.text('Cuéntale a bodega para qué lo necesitas'),
        findsOneWidget,
      );
      expect(api.creados, isEmpty);

      await tester.enterText(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.byType(TextField),
        ),
        '  Perforar la losa del 5º piso ',
      );
      await tester.tap(find.text('Pedir y generar QR'));
      await tester.pumpAndSettle();

      // Del taladro, la primera unidad disponible.
      final (ids, paraQue) = api.creados.single;
      expect(ids, [1, 3]);
      expect(paraQue, 'Perforar la losa del 5º piso');
      expect(api.claves.single, isNotNull);

      // Y el QR del pedido, en lugar de la lista.
      expect(find.byType(PantallaPedidoQr), findsOneWidget);
      expect(find.byType(PantallaPedirHerramienta), findsNothing);
      expect(
        tester.widget<CodigoQr>(find.byType(CodigoQr)).codigo,
        'PEDIDO:$_uuid',
      );
      expect(find.text('Muéstralo en bodega para retirarlas'), findsOneWidget);
      // Escrito bajo el QR, para ingresarlo a mano si no se deja leer.
      expect(find.text('PEDIDO:$_uuid'), findsOneWidget);
      expect(find.text('Taladro percutor'), findsOneWidget);
      expect(find.text('Esmeril angular'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('no deja marcar más de las que acepta un pedido', (
      tester,
    ) async {
      final muchas = [
        for (var i = 1; i <= PedidoHerramienta.maximoHerramientas + 1; i++)
          _herramienta(100 + i, 'Herramienta ${i.toString().padLeft(2, '0')}'),
      ];
      await _montar(
        tester,
        const PantallaPedirHerramienta(),
        overrides: [
          pedidosHerramientaApiProvider.overrideWithValue(_PedidosFalsos()),
          herramientasParaPedirProvider.overrideWith((ref) async => muchas),
        ],
      );

      for (final h in muchas) {
        await tester.scrollUntilVisible(
          find.text(h.nombre),
          120,
          scrollable: find.byType(Scrollable).last,
        );
        await tester.tap(find.text(h.nombre));
        await tester.pump();
      }
      expect(
        find.text('Solicitar (${PedidoHerramienta.maximoHerramientas})'),
        findsOneWidget,
      );
      expect(find.textContaining('Hasta 20 herramientas'), findsOneWidget);
    });

    testWidgets('si otro se llevó una, no pide ninguna y recarga la lista', (
      tester,
    ) async {
      final api = _PedidosFalsos(
        errorAlCrear: const ApiException(
          409,
          'La herramienta no está DISPONIBLE (estado actual: PRESTADA).',
          codigo: 'HERRAMIENTA_NO_DISPONIBLE',
        ),
      );
      var cargas = 0;
      await _montar(
        tester,
        const PantallaPedirHerramienta(),
        overrides: [
          pedidosHerramientaApiProvider.overrideWithValue(api),
          herramientasParaPedirProvider.overrideWith((ref) async {
            cargas++;
            return _herramientas;
          }),
        ],
      );
      expect(cargas, 1);

      await tester.tap(find.text('Esmeril angular'));
      await tester.pump();
      await tester.tap(find.text('Solicitar (1)'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.byType(TextField),
        ),
        'Cortar perfiles',
      );
      await tester.tap(find.text('Pedir y generar QR'));
      await tester.pumpAndSettle();

      expect(api.creados, hasLength(1));
      expect(find.byType(PantallaPedidoQr), findsNothing);
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.textContaining('no está DISPONIBLE'), findsOneWidget);
      expect(cargas, 2);
    });
  });

  group('QR pendiente', () {
    testWidgets('se abre desde Inicio y se puede cancelar', (tester) async {
      final api = _PedidosFalsos();
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sesionProvider.overrideWith(_SesionTrabajador.new),
            perfilTrabajadorProvider.overrideWith((ref) async => _perfil),
            misPrestamosProvider.overrideWith((ref) async => const []),
            misSolicitudesProvider.overrideWith((ref) async => const []),
            misPedidosHerramientaProvider.overrideWith(
              (ref) async => [
                PedidoHerramienta.desdeJson(_jsonPedido()),
                // Lo ya entregado no tiene QR que mostrar.
                PedidoHerramienta.desdeJson(_jsonPedido(estado: 'ENTREGADO')),
              ],
            ),
            pedidosHerramientaApiProvider.overrideWithValue(api),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            home: const ShellTrabajador(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Herramientas por retirar'), findsOneWidget);
      expect(find.text('Taladro percutor, Esmeril angular'), findsOneWidget);

      await tester.tap(find.text('Herramientas por retirar'));
      await tester.pumpAndSettle();
      expect(find.byType(PantallaPedidoQr), findsOneWidget);

      // El código escrito bajo el QR también es desplazable: se nombra la
      // lista.
      await tester.scrollUntilVisible(
        find.text('Cancelar pedido'),
        200,
        scrollable: find
            .descendant(
              of: find.byType(PantallaPedidoQr),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(find.text('Cancelar pedido'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Cancelar pedido'));
      await tester.pumpAndSettle();

      expect(api.cancelados, [12]);
      expect(find.byType(PantallaPedidoQr), findsNothing);
      expect(find.textContaining('Pedido cancelado'), findsOneWidget);
    });
  });

  group('Entrega en bodega', () {
    testWidgets('muestra a quién y qué, y entrega con la devolución', (
      tester,
    ) async {
      final api = _PedidosFalsos();
      await _montar(
        tester,
        PantallaEntregaPedido(
          pedido: PedidoHerramienta.desdeJson(_jsonPedido()),
        ),
        overrides: [pedidosHerramientaApiProvider.overrideWithValue(api)],
      );

      // Quién es, para confirmarlo con la persona enfrente.
      expect(find.text('Marcelo Sepúlveda'), findsOneWidget);
      expect(find.text('17.930.556-9'), findsOneWidget);
      expect(find.text('Taladro percutor'), findsOneWidget);
      expect(find.text('Esmeril angular'), findsOneWidget);
      expect(find.text('Devolución esperada'), findsOneWidget);

      await tester.scrollUntilVisible(find.text('Entregar (2)'), 200);
      await tester.tap(find.text('Entregar (2)'));
      await tester.pumpAndSettle();

      expect(api.entregas, hasLength(1));
      final (codigo, devolucion) = api.entregas.single;
      expect(codigo, _uuid);
      expect(devolucion.isAfter(DateTime.now()), isTrue);
      expect(api.claves.single, isNotNull);
      expect(find.byType(PantallaEntregaPedido), findsNothing);
      expect(
        find.text('2 herramientas entregadas a Marcelo Sepúlveda'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('si ya se entregó lo dice en vez de un error', (tester) async {
      final api = _PedidosFalsos(
        errorAlEntregar: const ApiException(
          409,
          'El pedido ya fue entregado.',
          codigo: 'YA_RESUELTA',
        ),
      );
      await _montar(
        tester,
        PantallaEntregaPedido(
          pedido: PedidoHerramienta.desdeJson(_jsonPedido()),
        ),
        overrides: [pedidosHerramientaApiProvider.overrideWithValue(api)],
      );

      await tester.scrollUntilVisible(find.text('Entregar (2)'), 200);
      await tester.tap(find.text('Entregar (2)'));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.textContaining('ya se entregó'),
        200,
      );
      expect(find.textContaining('ya se entregó'), findsOneWidget);
      expect(find.text('Entregar (2)'), findsNothing);
      expect(find.byType(PantallaEntregaPedido), findsOneWidget);
    });

    testWidgets('si lo cancelaron mientras esperaba, dice que se canceló', (
      tester,
    ) async {
      // El backend da el mismo YA_RESUELTA para entregado y cancelado.
      final api = _PedidosFalsos(
        errorAlEntregar: const ApiException(
          409,
          'El pedido ya está resuelto.',
          codigo: 'YA_RESUELTA',
        ),
        estadoAlReleer: 'CANCELADO',
      );
      await _montar(
        tester,
        PantallaEntregaPedido(
          pedido: PedidoHerramienta.desdeJson(_jsonPedido()),
        ),
        overrides: [pedidosHerramientaApiProvider.overrideWithValue(api)],
      );

      await tester.scrollUntilVisible(find.text('Entregar (2)'), 200);
      await tester.tap(find.text('Entregar (2)'));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.textContaining('canceló este pedido'),
        200,
      );
      expect(find.textContaining('canceló este pedido'), findsOneWidget);
      expect(find.textContaining('ya se entregó'), findsNothing);
    });

    testWidgets('un pedido cancelado no se ofrece para entregar', (
      tester,
    ) async {
      await _montar(
        tester,
        PantallaEntregaPedido(
          pedido: PedidoHerramienta.desdeJson(_jsonPedido(estado: 'CANCELADO')),
        ),
        overrides: [
          pedidosHerramientaApiProvider.overrideWithValue(_PedidosFalsos()),
        ],
      );
      await tester.scrollUntilVisible(
        find.textContaining('canceló este pedido'),
        200,
      );
      expect(find.textContaining('canceló este pedido'), findsOneWidget);
      expect(find.textContaining('Entregar'), findsNothing);
    });
  });
}
