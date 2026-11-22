import 'package:checkinobra_mobile/data/modelos/herramienta.dart';
import 'package:checkinobra_mobile/data/modelos/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Lo que el backend manda a un ADMIN o JEFE_TERRENO.
Map<String, dynamic> _materialConCostos() => {
  'id': 2,
  'sku': 'VOL-ST-10',
  'codigoBarra': null,
  'nombre': 'Volcanita ST 10 mm',
  'categoria': 'VOLCANITA',
  'precioUnitario': 5980,
  'stockMinimo': 40,
  'ultimoCostoUnitario': 5400,
  'fechaUltimoCosto': '2026-09-01T10:00:00',
  'costoPromedio': 5500.5,
};

/// Lo que recibe un TRABAJADOR: sin ningún campo de precio ni de costo.
Map<String, dynamic> _materialParaTrabajador() => {
  'id': 2,
  'sku': 'VOL-ST-10',
  'codigoBarra': null,
  'nombre': 'Volcanita ST 10 mm',
  'categoria': 'VOLCANITA',
  'stockMinimo': 40,
};

Map<String, dynamic> _herramientaParaTrabajador() => {
  'id': 8,
  'codigoQr': 'HER-8',
  'nombre': 'Taladro percutor 800 W',
  'categoria': 'ELECTRICA',
  'estado': 'DISPONIBLE',
};

void main() {
  group('Material sin costos (TRABAJADOR)', () {
    test('se lee sin precio, costos ni fecha, sin fallar', () {
      final m = MaterialObra.desdeJson(_materialParaTrabajador());

      expect(m.nombre, 'Volcanita ST 10 mm');
      expect(m.stockMinimo, 40);
      expect(m.ultimoCostoUnitario, isNull);
      expect(m.fechaUltimoCosto, isNull);
      expect(m.costoPromedio, isNull);
    });

    test('dice que no tiene precio, en vez de pasar por uno de \$0', () {
      final m = MaterialObra.desdeJson(_materialParaTrabajador());

      expect(m.tienePrecio, isFalse);
      expect(m.tieneCostoReal, isFalse);
      expect(m.variacionCosto, isNull);
    });

    test('con costos sigue leyéndose igual que antes', () {
      final m = MaterialObra.desdeJson(_materialConCostos());

      expect(m.tienePrecio, isTrue);
      expect(m.precioUnitario, 5980);
      expect(m.ultimoCostoUnitario, 5400);
      expect(m.costoPromedio, 5500.5);
      expect(m.costoVigente, 5400);
      expect(m.fechaUltimoCosto, DateTime(2026, 9, 1, 10));
    });

    test('un precio de 0 enviado por el servidor sí es un precio', () {
      final m = MaterialObra.desdeJson({
        ..._materialParaTrabajador(),
        'precioUnitario': 0,
      });

      expect(m.tienePrecio, isTrue);
    });

    test('un material armado a mano conserva su precio', () {
      const m = MaterialObra(
        id: 1,
        sku: 'X',
        codigoBarra: null,
        nombre: 'X',
        categoria: 'OSB',
        precioUnitario: 1000,
        stockMinimo: 1,
      );

      expect(m.tienePrecio, isTrue);
    });

    test('el material con stock tampoco depende de los costos', () {
      final conStock = MaterialConStock(
        material: MaterialObra.desdeJson(_materialParaTrabajador()),
        stock: 10,
      );

      expect(conStock.critico, isTrue);
    });
  });

  group('Herramienta sin valor de reposición (TRABAJADOR)', () {
    test('se lee sin valorReposicion, sin fallar', () {
      final h = Herramienta.desdeJson(_herramientaParaTrabajador());

      expect(h.nombre, 'Taladro percutor 800 W');
      expect(h.disponible, isTrue);
    });

    test('dice que no tiene valor, en vez de pasar por uno de \$0', () {
      final h = Herramienta.desdeJson(_herramientaParaTrabajador());

      expect(h.tieneValor, isFalse);
    });

    test('con valor sigue leyéndose igual que antes', () {
      final h = Herramienta.desdeJson({
        ..._herramientaParaTrabajador(),
        'valorReposicion': 189990,
      });

      expect(h.tieneValor, isTrue);
      expect(h.valorReposicion, 189990);
    });
  });
}
