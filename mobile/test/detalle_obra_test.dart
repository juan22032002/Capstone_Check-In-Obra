import 'package:checkinobra_mobile/data/modelos/detalle_obra.dart';
import 'package:checkinobra_mobile/data/modelos/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures_obra.dart';

Map<String, dynamic> _material({
  int id = 1,
  double? ultimoCosto,
  String? fecha,
}) => {
  'id': id,
  'sku': 'VOL-ST-10',
  'codigoBarra': null,
  'nombre': 'Volcanita ST 10 mm',
  'categoria': 'VOLCANITA',
  'precioUnitario': 5980,
  'stockMinimo': 40,
  'ultimoCostoUnitario': ultimoCosto,
  'fechaUltimoCosto': fecha,
  'costoPromedio': ultimoCosto,
};

void main() {
  group('MaterialObra', () {
    test('sin recepciones con costo, el costo vigente es el de catálogo', () {
      final m = MaterialObra.desdeJson(_material());
      expect(m.tieneCostoReal, isFalse);
      expect(m.costoVigente, 5980);
      expect(m.variacionCosto, isNull);
    });

    test('con costo real, lo usa y calcula la variación contra catálogo', () {
      final m = MaterialObra.desdeJson(
        _material(ultimoCosto: 6578, fecha: '2026-09-28T10:15:30'),
      );
      expect(m.tieneCostoReal, isTrue);
      expect(m.costoVigente, 6578);
      expect(m.fechaUltimoCosto, DateTime(2026, 9, 28, 10, 15, 30));
      expect(m.variacionCosto, closeTo(0.10, 0.001));
    });

    test('un backend sin los campos nuevos sigue leyéndose', () {
      final json = _material()
        ..remove('ultimoCostoUnitario')
        ..remove('fechaUltimoCosto')
        ..remove('costoPromedio');
      expect(MaterialObra.desdeJson(json).costoVigente, 5980);
    });
  });

  group('DetalleObra', () {
    final json = detalleDePrueba();

    test('lee el contrato completo', () {
      final d = DetalleObra.desdeJson(json);
      expect(d.obra.nombre, 'Los Almendros');
      expect(d.jefes.single.rol, 'JEFE_TERRENO');
      expect(d.trabajadores.single.cuadrillaNombre, 'Tabiques');
      expect(d.materiales, hasLength(3));
      expect(d.herramientas.first.prestamoId, 10);
      expect(
        d.herramientas.first.prestadaA,
        'Marcelo Sepúlveda · 17.930.556-9',
      );
      expect(d.resumen.materialesPorReponer, 2);
    });

    test(
      'los faltantes van con lo crítico primero y sin los que están bien',
      () {
        final d = DetalleObra.desdeJson(json);
        expect(d.faltantes.map((m) => m.nombre), ['Tornillo', 'Volcanita']);
      },
    );

    test('las herramientas se agrupan por nombre, las vencidas arriba', () {
      final grupos = DetalleObra.desdeJson(json).herramientasAgrupadas;
      expect(grupos.map((g) => g.nombre), [
        'Esmeril angular',
        'Taladro percutor',
      ]);
      expect(grupos.last.cantidad, 2);
      expect(grupos.last.valor, 200000);
      expect(grupos.first.vencidas, 1);
    });

    test('sin valorStock lo calcula con el costo vigente y no valoriza saldo negativo', () {
      final m = MaterialDeObra.desdeJson({
        'materialId': 1,
        'sku': 'A',
        'nombre': 'X',
        'categoria': 'OSB',
        'stock': -3,
        'stockMinimo': 1,
        'precioUnitario': 1000,
        'estado': 'CRITICO',
      });
      expect(m.valorStock, 0);
      expect(m.estado, EstadoStock.critico);
    });
  });
}
