import 'dart:async';

import 'package:checkinobra_mobile/data/api/auth_api.dart';
import 'package:checkinobra_mobile/data/api/dominio_api.dart';
import 'package:checkinobra_mobile/data/modelos/kardex.dart';
import 'package:checkinobra_mobile/data/modelos/material.dart';
import 'package:checkinobra_mobile/data/modelos/obra.dart';
import 'package:checkinobra_mobile/features/auth/sesion_controller.dart';
import 'package:checkinobra_mobile/features/bodega/bodega_providers.dart';
import 'package:checkinobra_mobile/features/bodega/pantalla_movimiento.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

const _item = MaterialConStock(
  material: MaterialObra(
    id: 1,
    sku: 'VOL-ST-10',
    codigoBarra: null,
    nombre: 'Volcanita ST 10 mm',
    categoria: 'VOLCANITA',
    precioUnitario: 5980,
    stockMinimo: 40,
  ),
  stock: 60,
);

/// Registra cada envío y lo deja colgado hasta que el test lo suelte: así el
/// segundo toque llega con el primero todavía en vuelo, como en la obra.
class _KardexLento implements KardexApi {
  final envios = <String?>[];
  final respuesta = Completer<MovimientoKardex>();

  @override
  Future<MovimientoKardex> registrar({
    required int obraId,
    required int materialId,
    required String tipo,
    required double cantidad,
    int? trabajadorId,
    double? costoUnitario,
    String? clave,
  }) {
    envios.add(clave);
    return respuesta.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SesionFija extends SesionController {
  @override
  Future<SesionUsuario?> build() async => const SesionUsuario(
    token: 't',
    usuarioId: 1,
    nombre: 'Jorge Reyes',
    rol: 'BODEGUERO',
    empresaId: 1,
  );
}

Future<void> _abrir(WidgetTester tester, {KardexApi? kardex}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        trabajadoresDeObraProvider.overrideWith((ref) async => []),
        sesionProvider.overrideWith(_SesionFija.new),
        obraEnCursoProvider.overrideWithValue(
          const Obra(
            id: 1,
            nombre: 'Edificio Los Robles',
            cliente: 'Inmobiliaria',
            ubicacion: 'Temuco',
            estado: 'ACTIVA',
            jefeTerrenoNombre: null,
            jefeTerrenoRut: null,
          ),
        ),
        if (kardex != null) kardexApiProvider.overrideWithValue(kardex),
      ],
      child: const MaterialApp(home: PantallaMovimiento(item: _item)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => initializeDateFormatting('es_CL'));

  testWidgets('el saldo resultante sigue a lo que se escribe', (tester) async {
    // Antes el saldo se calculaba al abrir y no se movía mientras se tecleaba:
    // la advertencia de "quedarás bajo el mínimo" nunca aparecía a tiempo.
    await _abrir(tester);
    await tester.tap(find.text('Consumo'));
    await tester.pumpAndSettle();

    final cantidad = find.byType(TextField).last;
    await tester.enterText(cantidad, '10');
    await tester.pumpAndSettle();
    expect(find.text('50 pl'), findsOneWidget);
    expect(find.textContaining('bajo el stock mínimo'), findsNothing);

    await tester.enterText(cantidad, '30');
    await tester.pumpAndSettle();
    expect(find.text('30 pl'), findsOneWidget);
    expect(find.textContaining('bajo el stock mínimo'), findsOneWidget);

    await tester.enterText(cantidad, '70');
    await tester.pumpAndSettle();
    expect(find.textContaining('No hay tanto en bodega'), findsOneWidget);
  });

  testWidgets('dos toques seguidos envían un solo movimiento', (tester) async {
    // El botón recién se deshabilita en el build siguiente; sin el guard al
    // entrar, el segundo toque del mismo cuadro también llegaba al servidor.
    final kardex = _KardexLento();
    await _abrir(tester, kardex: kardex);
    // En la app la sesión ya está cargada: la observa la raíz. Acá nadie la
    // observa, así que se espera a que cargue; si no, el primer toque sale
    // antes de enviar y el test no ejercita la carrera.
    final contenedor = ProviderScope.containerOf(
      tester.element(find.byType(PantallaMovimiento)),
    );
    await tester.runAsync(() => contenedor.read(sesionProvider.future));
    // En una recepción la cantidad es el primer campo: debajo va el costo.
    await tester.enterText(find.byType(TextField).first, '12');
    await tester.pump();

    final boton = find.text('Registrar recepción');
    await tester.tap(boton);
    await tester.tap(boton, warnIfMissed: false);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(kardex.envios, hasLength(1));
    expect(kardex.envios.single, isNotNull);
    expect(find.text('Registrando…'), findsOneWidget);
  });
}
