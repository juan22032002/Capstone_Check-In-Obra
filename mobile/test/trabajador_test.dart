import 'dart:async';

import 'package:checkinobra_mobile/core/theme/app_theme.dart';
import 'package:checkinobra_mobile/data/api/auth_api.dart';
import 'package:checkinobra_mobile/data/api/dominio_api.dart';
import 'package:checkinobra_mobile/data/modelos/herramienta.dart';
import 'package:checkinobra_mobile/data/modelos/material.dart';
import 'package:checkinobra_mobile/data/modelos/pedido_especial.dart';
import 'package:checkinobra_mobile/data/modelos/perfil_trabajador.dart';
import 'package:checkinobra_mobile/data/modelos/solicitud.dart';
import 'package:checkinobra_mobile/features/auth/sesion_controller.dart';
import 'package:checkinobra_mobile/features/trabajador/pantalla_pedido_especial.dart';
import 'package:checkinobra_mobile/features/trabajador/pantalla_pedir.dart';
import 'package:checkinobra_mobile/features/trabajador/shell_trabajador.dart';
import 'package:checkinobra_mobile/features/trabajador/trabajador_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
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

final _ahora = DateTime.now();

Prestamo _prestamo(
  int id,
  String nombre, {
  required Duration devuelveEn,
  bool devuelto = false,
}) => Prestamo(
  id: id,
  fechaPrestamo: _ahora.subtract(const Duration(days: 5)),
  fechaDevolEsperada: _ahora.add(devuelveEn),
  fechaDevolReal: devuelto ? _ahora.subtract(const Duration(days: 1)) : null,
  herramientaId: id,
  herramientaNombre: nombre,
  trabajadorNombre: 'Marcelo Sepúlveda',
  trabajadorRut: '17.930.556-9',
  autorizadoPorNombre: 'Jorge Reyes',
);

final _prestamos = [
  _prestamo(1, 'Rotomartillo Bosch GBH', devuelveEn: const Duration(days: -2)),
  _prestamo(2, 'Nivel láser', devuelveEn: const Duration(days: 3)),
  _prestamo(
    3,
    'Esmeril angular',
    devuelveEn: const Duration(days: -10),
    devuelto: true,
  ),
];

final _solicitudes = [
  MiSolicitud(
    id: 1,
    itemId: 2,
    origen: OrigenSolicitud.material,
    nombre: 'Volcanita ST 10 mm',
    cantidad: '12 pl',
    estado: 'PENDIENTE',
    fecha: _ahora.subtract(const Duration(hours: 1)),
    motivoRechazo: null,
    resueltoPorNombre: null,
    descripcion: 'Tabique del baño del 304',
  ),
  MiSolicitud(
    id: 2,
    itemId: 9,
    origen: OrigenSolicitud.herramienta,
    nombre: 'Taladro percutor',
    cantidad: '1 unidad',
    estado: 'RECHAZADA',
    fecha: _ahora.subtract(const Duration(hours: 20)),
    motivoRechazo: 'Están todos en mantención hasta el lunes',
    resueltoPorNombre: 'Jorge Reyes',
  ),
  // Bodega ya se lo pasó: falta que él confirme.
  MiSolicitud(
    id: 7,
    itemId: null,
    origen: OrigenSolicitud.especial,
    nombre: 'Sierra caladora',
    cantidad: '1',
    estado: 'ENTREGADO',
    fecha: _ahora.subtract(const Duration(days: 1)),
    motivoRechazo: null,
    resueltoPorNombre: 'Jorge Reyes',
    descripcion: 'Cortar las placas curvas del hall',
    notaBodega: 'Llegó hoy',
    esHerramientaEspecial: true,
  ),
];

/// Registra lo que se pide, para comprobar que viaja a la obra correcta.
class _SolicitudesFalsas implements SolicitudesApi {
  final pedidos = <(int, int?, double, String)>[];

  @override
  Future<SolicitudMaterial> pedirMaterial({
    required int materialId,
    int? obraId,
    required double cantidad,
    required String descripcion,
    String? clave,
  }) async {
    pedidos.add((materialId, obraId, cantidad, descripcion));
    return Completer<SolicitudMaterial>().future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Responde como el backend cuando ya hay una solicitud pendiente del mismo
/// material: 409 `SOLICITUD_DUPLICADA` con el mensaje listo para mostrar.
class _SolicitudesDuplicadas implements SolicitudesApi {
  int intentos = 0;

  @override
  Future<SolicitudMaterial> pedirMaterial({
    required int materialId,
    int? obraId,
    required double cantidad,
    required String descripcion,
    String? clave,
  }) async {
    intentos++;
    throw const ApiException(
      409,
      'Ya pediste Montante 90 y tu solicitud sigue pendiente',
      codigo: 'SOLICITUD_DUPLICADA',
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

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
        misPrestamosProvider.overrideWith((ref) async => _prestamos),
        misSolicitudesProvider.overrideWith((ref) async => _solicitudes),
        misPedidosHerramientaProvider.overrideWith((ref) async => const []),
        ...overrides,
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

void main() {
  setUpAll(() async {
    await initializeDateFormatting('es_CL');
    await cargarInter();
  });

  testWidgets('inicio muestra obra, lo vencido primero y lo pendiente', (
    tester,
  ) async {
    await _montar(tester, const ShellTrabajador());
    expect(find.text('Los Almendros · Torre B'), findsOneWidget);
    expect(find.text('Pedir material'), findsOneWidget);
    expect(find.text('Pedir herramienta'), findsOneWidget);
    // Solo lo abierto está "en tu poder", y lo vencido va arriba.
    expect(find.text('En tu poder (2)'), findsOneWidget);
    final vencida = tester.getTopLeft(find.text('Rotomartillo Bosch GBH'));
    final alDia = tester.getTopLeft(find.text('Nivel láser'));
    expect(vencida.dy, lessThan(alDia.dy));
    expect(find.text('Esmeril angular'), findsNothing);

    await tester.scrollUntilVisible(find.text('Volcanita ST 10 mm'), 200);
    expect(find.text('Esperando a bodega (1)'), findsOneWidget);
    expect(find.text('Retirar'), findsOneWidget);

    // Lo rechazado hace poco se ve con el motivo, para que no desaparezca sin
    // explicación.
    await tester.scrollUntilVisible(find.text('Taladro percutor'), 200);
    expect(find.textContaining('mantención hasta el lunes'), findsOneWidget);
  });

  testWidgets('la credencial dibuja el QR con nombre y RUT', (tester) async {
    await _montar(tester, const ShellTrabajador());
    await tester.tap(find.text('Credencial'));
    await tester.pumpAndSettle();

    expect(find.byType(QrImageView), findsOneWidget);
    expect(find.text('17.930.556-9'), findsOneWidget);
    expect(find.text('Perdí el teléfono: renovar'), findsOneWidget);
  });

  testWidgets('sin cuadrilla no deja pedir y dice por qué', (tester) async {
    await _montar(
      tester,
      const ShellTrabajador(),
      overrides: [
        perfilTrabajadorProvider.overrideWith(
          (ref) async => const PerfilTrabajador(
            id: 1,
            usuarioId: 6,
            nombre: 'Marcelo Sepúlveda',
            rut: null,
            cuadrillaId: null,
            cuadrillaNombre: null,
            obraId: null,
            obraNombre: null,
            obraEstado: null,
            credencialQr: 'X',
          ),
        ),
      ],
    );

    expect(
      find.textContaining('no estás en ninguna cuadrilla'),
      findsOneWidget,
    );
    await tester.tap(find.text('Pedir material'));
    await tester.pumpAndSettle();
    expect(find.byType(PantallaPedirMaterial), findsNothing);
  });

  testWidgets('un pedido repetido muestra el mensaje del servidor y recarga', (
    tester,
  ) async {
    // Otro teléfono ya pidió este material, o la lista no estaba al día: el
    // servidor responde 409 SOLICITUD_DUPLICADA. Se ve su mensaje —no uno
    // genérico— y la lista se recarga para marcarlo como ya pedido.
    final api = _SolicitudesDuplicadas();
    var cargas = 0;
    await _montar(
      tester,
      const PantallaPedirMaterial(perfil: _perfil),
      overrides: [
        solicitudesApiProvider.overrideWithValue(api),
        misSolicitudesProvider.overrideWith((ref) async {
          cargas++;
          return _solicitudes;
        }),
        catalogoTrabajadorProvider.overrideWith(
          (ref) async => const [
            MaterialObra(
              id: 3,
              sku: 'MET-MONT-90',
              codigoBarra: null,
              nombre: 'Montante 90',
              categoria: 'METALCOM',
              precioUnitario: 3100,
              stockMinimo: 40,
            ),
          ],
        ),
      ],
    );
    await tester.tap(find.text('Montante 90'));
    await tester.pumpAndSettle();
    final campos = find.descendant(
      of: find.byType(BottomSheet),
      matching: find.byType(TextField),
    );
    await tester.enterText(campos.first, '24');
    await tester.enterText(campos.last, 'Tabiquería del piso 5');
    final antes = cargas;

    await tester.tap(find.text('Solicitar material'));
    await tester.pumpAndSettle();

    expect(api.intentos, 1);
    expect(
      find.text('Ya pediste Montante 90 y tu solicitud sigue pendiente'),
      findsOneWidget,
    );
    expect(find.textContaining('error inesperado'), findsNothing);
    // La lista de solicitudes se volvió a pedir al servidor.
    expect(cargas, greaterThan(antes));
    // La hoja sigue abierta: el mensaje es lo que hay que leer.
    expect(find.byType(BottomSheet), findsOneWidget);
  });

  testWidgets('pedir material lo manda a la obra de su cuadrilla', (
    tester,
  ) async {
    final api = _SolicitudesFalsas();
    await _montar(
      tester,
      const PantallaPedirMaterial(perfil: _perfil),
      overrides: [
        solicitudesApiProvider.overrideWithValue(api),
        catalogoTrabajadorProvider.overrideWith(
          (ref) async => const [
            MaterialObra(
              id: 2,
              sku: 'VOL-ST-10',
              codigoBarra: null,
              nombre: 'Volcanita ST 10 mm',
              categoria: 'VOLCANITA',
              precioUnitario: 5980,
              stockMinimo: 40,
            ),
            MaterialObra(
              id: 3,
              sku: 'MET-MONT-90',
              codigoBarra: null,
              nombre: 'Montante 90',
              categoria: 'METALCOM',
              precioUnitario: 3100,
              stockMinimo: 40,
            ),
          ],
        ),
      ],
    );
    // Ya tiene pedida la volcanita: se le advierte en la fila.
    expect(find.text('Ya lo pediste'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'mont');
    await tester.pumpAndSettle();
    expect(find.text('Volcanita ST 10 mm'), findsNothing);

    await tester.tap(find.text('Montante 90'));
    await tester.pumpAndSettle();
    // Sin decir para qué, no sale.
    final campos = find.descendant(
      of: find.byType(BottomSheet),
      matching: find.byType(TextField),
    );
    await tester.enterText(campos.first, '24');
    await tester.tap(find.text('Solicitar material'));
    await tester.pumpAndSettle();
    expect(
      find.text('Cuéntale a bodega para qué lo necesitas'),
      findsOneWidget,
    );
    expect(api.pedidos, isEmpty);

    await tester.enterText(campos.last, '  Tabiquería del piso 5  ');
    await tester.tap(find.text('Solicitar material'));
    await tester.pump();

    expect(api.pedidos, [(3, 2, 24.0, 'Tabiquería del piso 5')]);
  });

  testWidgets('lo entregado pide confirmar y muestra el para qué', (
    tester,
  ) async {
    await _montar(tester, const ShellTrabajador());

    // Arriba de todo, porque es lo único que espera algo de él.
    expect(find.text('Confirma que lo recibiste (1)'), findsOneWidget);
    expect(find.text('Lo recibí'), findsOneWidget);
    expect(find.text('Cortar las placas curvas del hall'), findsOneWidget);
    expect(find.textContaining('Llegó hoy'), findsOneWidget);
    final confirmar = tester.getTopLeft(find.text('Sierra caladora'));
    final obra = tester.getTopLeft(find.text('Los Almendros · Torre B'));
    expect(confirmar.dy, lessThan(obra.dy));
  });

  testWidgets('el pedido especial sale con tipo, nombre y para qué', (
    tester,
  ) async {
    final api = _PedidosFalsos();
    await _montar(
      tester,
      const PantallaPedidoEspecial(
        esHerramienta: false,
        nombreInicial: 'perfil omega',
      ),
      overrides: [pedidosEspecialesApiProvider.overrideWithValue(api)],
    );
    expect(find.text('No está en la lista'), findsOneWidget);
    final campos = find.byType(TextField);
    await tester.enterText(campos.at(1), '20');
    await tester.enterText(campos.at(2), 'tiras');
    // Los campos de texto también son desplazables: se nombra la lista.
    await tester.scrollUntilVisible(
      find.text('¿Para qué lo necesitas?'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(campos.last, 'Terminar el cielo del hall');
    await tester.ensureVisible(find.text('Enviar pedido de material'));
    await tester.tap(find.text('Enviar pedido de material'));
    await tester.pump();

    expect(api.creados, [
      ('MATERIAL', 'perfil omega', 20.0, 'tiras', 'Terminar el cielo del hall'),
    ]);
  });
}

class _PedidosFalsos implements PedidosEspecialesApi {
  final creados = <(String, String, double, String?, String)>[];

  @override
  Future<PedidoEspecial> crear({
    required String tipo,
    required String nombre,
    required double cantidad,
    String? unidad,
    required String descripcion,
    int? materialId,
    int? herramientaId,
    String? clave,
  }) {
    creados.add((tipo, nombre, cantidad, unidad, descripcion));
    return Completer<PedidoEspecial>().future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
