import 'package:checkinobra_mobile/core/theme/app_theme.dart';
import 'package:checkinobra_mobile/data/modelos/solicitud.dart';
import 'package:checkinobra_mobile/features/trabajador/filas_trabajador.dart';
import 'package:checkinobra_mobile/features/trabajador/trabajador_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'fuentes.dart';

Map<String, dynamic> _json({
  String estado = 'APROBADA',
  double cantidad = 8,
  double? entregada,
}) => {
  'id': 1,
  'cantidad': cantidad,
  'estado': estado,
  'fechaSolicitud': '2026-10-06T09:00:00',
  'motivoRechazo': null,
  'trabajadorId': 1,
  'trabajadorNombre': 'Marcelo Sepúlveda',
  'trabajadorRut': '17.930.556-9',
  'materialId': 3,
  'materialSku': 'VOL-ST-10',
  'materialNombre': 'Volcanita ST 10 mm',
  'obraId': 2,
  'resueltoPorNombre': 'Jorge Reyes',
  'cantidadEntregada': ?entregada,
};

Future<void> _montar(WidgetTester tester, MiSolicitud s) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: SingleChildScrollView(child: FilaMiSolicitud(solicitud: s)),
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

  group('SolicitudMaterial.cantidadEntregada', () {
    test('se lee del backend y marca la entrega parcial', () {
      final s = SolicitudMaterial.desdeJson(_json(entregada: 6));
      expect(s.cantidadEntregada, 6);
      expect(s.entregaParcial, isTrue);
    });

    test('entregar lo pedido no es parcial', () {
      final s = SolicitudMaterial.desdeJson(_json(entregada: 8));
      expect(s.entregaParcial, isFalse);
    });

    test('un backend que todavía no lo manda no rompe nada', () {
      final s = SolicitudMaterial.desdeJson(_json());
      expect(s.cantidadEntregada, isNull);
      expect(s.entregaParcial, isFalse);
    });
  });

  group('Lo que ve el trabajador', () {
    testWidgets('una aprobada con menos de lo pedido lo dice', (tester) async {
      await _montar(
        tester,
        MiSolicitud.deMaterial(
          SolicitudMaterial.desdeJson(_json(entregada: 6)),
          unidad: 'placas',
        ),
      );
      expect(
        find.text('Te entregaron 6 placas de 8 placas que pediste.'),
        findsOneWidget,
      );
      expect(find.text('Lo recibí'), findsOneWidget);
    });

    testWidgets('una aprobada completa muestra lo entregado', (tester) async {
      await _montar(
        tester,
        MiSolicitud.deMaterial(
          SolicitudMaterial.desdeJson(_json(entregada: 8)),
          unidad: 'placas',
        ),
      );
      expect(find.text('Te entregaron 8 placas.'), findsOneWidget);
    });

    testWidgets('una pendiente no muestra entrega', (tester) async {
      await _montar(
        tester,
        MiSolicitud.deMaterial(
          SolicitudMaterial.desdeJson(_json(estado: 'PENDIENTE')),
          unidad: 'placas',
        ),
      );
      expect(find.textContaining('Te entregaron'), findsNothing);
    });

    test('una herramienta aprobada se entrega entera', () {
      final h = SolicitudHerramienta.desdeJson({
        'id': 1,
        'cantidad': 1,
        'estado': 'APROBADA',
        'fechaSolicitud': '2026-10-06T09:00:00',
        'motivoRechazo': null,
        'trabajadorId': 1,
        'trabajadorNombre': 'Marcelo Sepúlveda',
        'trabajadorRut': null,
        'herramientaId': 4,
        'herramientaNombre': 'Nivel láser',
        'herramientaCodigo': 'NIV-01',
        'resueltoPorNombre': 'Jorge Reyes',
      });
      expect(MiSolicitud.deHerramienta(h).entregado, '1 unidad');
    });
  });
}
