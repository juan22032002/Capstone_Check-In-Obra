import 'package:checkinobra_mobile/data/api/auth_api.dart';
import 'package:checkinobra_mobile/data/modelos/detalle_obra.dart';
import 'package:checkinobra_mobile/data/modelos/material.dart';
import 'package:checkinobra_mobile/features/admin/pantalla_detalle_obra.dart';
import 'package:checkinobra_mobile/features/admin/pantalla_materiales.dart';
import 'package:checkinobra_mobile/features/admin/pantalla_obras.dart';
import 'package:checkinobra_mobile/features/auth/sesion_controller.dart';
import 'package:checkinobra_mobile/features/bodega/bodega_providers.dart';
import 'package:checkinobra_mobile/features/obra/obra_activa.dart';

import 'package:checkinobra_mobile/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'fixtures_obra.dart';
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

final _detalle = DetalleObra.desdeJson(detalleDePrueba());

/// Un teléfono chico con el texto del sistema agrandado: donde se desborda
/// primero una fila con cifras a la derecha.
Future<void> _montar(
  WidgetTester tester,
  Widget pantalla, {
  List<Override> overrides = const [],
  double escalaTexto = 1.3,
}) async {
  tester.view.physicalSize = const Size(360, 780);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sesionProvider.overrideWith(_SesionAdmin.new),
        detalleObraProvider.overrideWith((ref, id) async => _detalle),
        ...overrides,
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

  testWidgets('la ficha muestra jefe, equipo, faltantes y herramientas', (
    tester,
  ) async {
    await _montar(tester, PantallaDetalleObra(obra: _detalle.obra));
    expect(find.text('Ana Rojas'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Tabiques'), 200);
    // Con algo por reponer, la lista arranca filtrada en lo que falta.
    await tester.scrollUntilVisible(find.text('Tornillo'), 200);
    expect(find.text('Tornillo'), findsOneWidget);
    expect(find.text('Volcanita'), findsOneWidget);
    expect(find.text('Montante'), findsNothing);

    await tester.ensureVisible(find.text('Todos (3)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Todos (3)'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Montante'), 200);
    expect(find.text('Montante'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('Esmeril angular'), 200);
    expect(find.text('× 2'), findsOneWidget);
    expect(find.text('Vencida'), findsOneWidget);
  });

  testWidgets('la fila de la obra adelanta materiales y herramientas', (
    tester,
  ) async {
    await _montar(
      tester,
      const Scaffold(body: PantallaObras()),
      overrides: [
        todasLasObrasProvider.overrideWith((ref) async => [_detalle.obra]),
      ],
    );
    expect(find.text('1 trabajador'), findsOneWidget);
    expect(find.text('3 materiales'), findsOneWidget);
    expect(find.text('3 herramientas'), findsOneWidget);
    expect(find.text('1 material bajo el mínimo'), findsOneWidget);
    // Lo crítico va primero en la vista previa, con su cantidad.
    expect(find.text('2 kg'), findsOneWidget);
    expect(find.text('× 2'), findsOneWidget);

    await tester.tap(find.text('Los Almendros'));
    await tester.pumpAndSettle();
    expect(find.byType(PantallaDetalleObra), findsOneWidget);
  });

  testWidgets('el catálogo avisa la falta de materiales y dice el costo', (
    tester,
  ) async {
    await _montar(
      tester,
      const PantallaMateriales(),
      overrides: [
        catalogoProvider.overrideWith(
          (ref) async => [
            const MaterialObra(
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
              sku: 'TOR-6',
              codigoBarra: null,
              nombre: 'Tornillo punta broca',
              categoria: 'FIJACION',
              precioUnitario: 3000,
              stockMinimo: 10,
              ultimoCostoUnitario: 3300,
              fechaUltimoCosto: DateTime.now(),
              costoPromedio: 3150,
            ),
          ],
        ),
        faltantesProvider.overrideWith(
          (ref) async => const [
            MaterialFaltante(
              obraId: 2,
              obraNombre: 'Los Almendros · Torre B',
              materialId: 2,
              sku: 'VOL-ST-10',
              nombre: 'Volcanita ST 10 mm',
              categoria: 'VOLCANITA',
              stock: 24,
              stockMinimo: 40,
              estado: EstadoStock.critico,
            ),
          ],
        ),
      ],
    );
    expect(find.text('Falta de materiales'), findsOneWidget);
    expect(find.text('1 bajo el mínimo en 1 obra'), findsOneWidget);
    expect(find.text('Se agota en 1 obra'), findsOneWidget);

    // Sin compras con costo se dice que es de catálogo; con compra, "costo".
    expect(find.text('catálogo / pl'), findsOneWidget);
    expect(find.text('costo / kg'), findsOneWidget);
    expect(find.text(r'$3.300'), findsOneWidget);
    expect(find.textContaining('10 % sobre catálogo'), findsOneWidget);

    await tester.tap(find.text('Falta de materiales'));
    await tester.pumpAndSettle();
    expect(find.text('Los Almendros · Torre B (1)'), findsOneWidget);
  });
}
