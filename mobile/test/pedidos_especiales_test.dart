import 'package:checkinobra_mobile/core/theme/app_theme.dart';
import 'package:checkinobra_mobile/data/api/auth_api.dart';
import 'package:checkinobra_mobile/data/api/dominio_api.dart';
import 'package:checkinobra_mobile/data/modelos/obra.dart';
import 'package:checkinobra_mobile/data/modelos/pedido_especial.dart';
import 'package:checkinobra_mobile/data/modelos/solicitud.dart';
import 'package:checkinobra_mobile/features/admin/pantalla_solicitudes_admin.dart';
import 'package:checkinobra_mobile/features/auth/sesion_controller.dart';
import 'package:checkinobra_mobile/features/bodega/bodega_providers.dart';
import 'package:checkinobra_mobile/features/bodega/pedidos_especiales.dart';
import 'package:checkinobra_mobile/features/obra/obra_activa.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'fuentes.dart';

class _SesionAdmin extends SesionController {
  @override
  Future<SesionUsuario?> build() async => const SesionUsuario(
    token: 't',
    usuarioId: 1,
    nombre: 'Carla Muñoz',
    rol: 'ADMIN',
    empresaId: 1,
  );
}

/// La cola de catálogo de cada obra, vacía: este test mira los pedidos
/// especiales.
class _SolicitudesVacias implements SolicitudesApi {
  @override
  Future<List<SolicitudMaterial>> materialesPorObra(
    int obraId, {
    bool soloPendientes = true,
  }) async => const [];

  @override
  Future<List<SolicitudHerramienta>> herramientasPorObra(
    int obraId, {
    bool soloPendientes = true,
  }) async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Map<String, dynamic> _json({
  int id = 1,
  String estado = 'PENDIENTE',
  String tipo = 'MATERIAL',
  int? materialId,
  String? nota,
}) => {
  'id': id,
  'tipo': tipo,
  'nombre': tipo == 'MATERIAL' ? 'Perfil omega 0,85 mm' : 'Sierra caladora',
  'cantidad': tipo == 'MATERIAL' ? 20 : 1,
  'unidad': tipo == 'MATERIAL' ? 'tiras' : null,
  'descripcion': 'Terminar el cielo del hall',
  'materialId': materialId,
  'herramientaId': null,
  'estado': estado,
  'obraId': 2,
  'obraNombre': 'Los Almendros · Torre B',
  'trabajadorId': 1,
  'trabajadorNombre': 'Marcelo Sepúlveda',
  'trabajadorRut': '17.930.556-9',
  'fechaSolicitud': DateTime.now()
      .subtract(const Duration(hours: 3))
      .toIso8601String(),
  'fechaActualizacion': null,
  'notaBodega': nota,
  'motivoRechazo': null,
  'gestionadoPorNombre': nota == null ? null : 'Jorge Reyes',
  'fechaEntrega': null,
  'fechaRecepcion': null,
};

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
      overrides: [sesionProvider.overrideWith(_SesionAdmin.new), ...overrides],
      child: MaterialApp(
        theme: AppTheme.light,
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(360, 780),
            textScaler: TextScaler.linear(1.3),
          ),
          child: Scaffold(body: pantalla),
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

  test('el siguiente paso sigue el orden del pedido', () {
    PasoPedido? paso(String e) =>
        PedidoEspecial.desdeJson(_json(estado: e)).siguientePaso;
    expect(paso('PENDIENTE'), PasoPedido.gestionar);
    expect(paso('EN_GESTION'), PasoPedido.listo);
    expect(paso('LISTO_PARA_RETIRO'), PasoPedido.entregar);
    // Entregado espera al trabajador, no a bodega.
    expect(paso('ENTREGADO'), isNull);
    expect(
      PedidoEspecial.desdeJson(_json(estado: 'ENTREGADO')).porConfirmar,
      isTrue,
    );
  });

  testWidgets('bodega ve el para qué, quién lo pidió y el paso siguiente', (
    tester,
  ) async {
    await _montar(
      tester,
      ListView(
        padding: const EdgeInsets.all(16),
        children: [
          FilaPedidoEspecial(pedido: PedidoEspecial.desdeJson(_json())),
          const SizedBox(height: 10),
          FilaPedidoEspecial(
            pedido: PedidoEspecial.desdeJson(
              _json(
                id: 2,
                estado: 'LISTO_PARA_RETIRO',
                tipo: 'HERRAMIENTA',
                nota: 'Está en el mesón',
              ),
            ),
          ),
        ],
      ),
    );
    expect(find.text('Terminar el cielo del hall'), findsNWidgets(2));
    expect(find.text('Marcelo Sepúlveda · 17.930.556-9'), findsNWidgets(2));
    expect(find.text('Lo estoy consiguiendo'), findsOneWidget);
    expect(find.text('Entregar ahora'), findsOneWidget);
    expect(find.text('Entregar al trabajador'), findsOneWidget);
    expect(find.textContaining('Está en el mesón'), findsOneWidget);
  });

  testWidgets('el admin ve los pedidos de la empresa y lo de cada obra', (
    tester,
  ) async {
    await _montar(
      tester,
      const PantallaSolicitudesAdmin(),
      overrides: [
        solicitudesApiProvider.overrideWithValue(_SolicitudesVacias()),
        pedidosEspecialesEmpresaProvider.overrideWith(
          (ref) async => [
            PedidoEspecial.desdeJson(_json()),
            PedidoEspecial.desdeJson(_json(id: 3, estado: 'ENTREGADO')),
          ],
        ),
        obrasActivasProvider.overrideWith(
          (ref) async => const [
            Obra(
              id: 2,
              nombre: 'Los Almendros · Torre B',
              cliente: 'Inmobiliaria Aconcagua',
              ubicacion: 'Ñuñoa',
              estado: 'ACTIVA',
              jefeTerrenoNombre: null,
              jefeTerrenoRut: null,
            ),
          ],
        ),
      ],
    );
    expect(find.text('Por conseguir'), findsOneWidget);
    // Lo que espera a bodega va antes que lo que espera al trabajador.
    final nuevo = tester.getTopLeft(find.text('Nuevo'));
    final entregado = tester.getTopLeft(find.text('Entregado, sin confirmar'));
    expect(nuevo.dy, lessThan(entregado.dy));
  });
}
