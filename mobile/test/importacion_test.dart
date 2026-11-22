import 'package:checkinobra_mobile/data/modelos/importacion.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Informe de importación', () {
    test('una planilla sin errores queda lista para importar', () {
      final informe = ResultadoImportacion.desdeJson({
        'confirmado': false,
        'filasLeidas': 34,
        'filasValidas': 34,
        'importadas': 0,
        'errores': <dynamic>[],
      });

      expect(informe.listaParaImportar, isTrue);
      // La simulación no guarda nada: la cifra de importadas es 0 hasta que
      // el administrador confirma.
      expect(informe.importadas, 0);
      expect(informe.confirmado, isFalse);
    });

    test('con una sola fila mala no se importa nada', () {
      // La importación es todo o nada: 33 filas válidas no se guardan si la
      // 34 está mal. La app tiene que reflejar eso y no ofrecer el botón.
      final informe = ResultadoImportacion.desdeJson({
        'confirmado': false,
        'filasLeidas': 34,
        'filasValidas': 33,
        'importadas': 0,
        'errores': [
          {'fila': 12, 'detalle': "La categoría 'PLANCHA' no existe"},
        ],
      });

      expect(informe.listaParaImportar, isFalse);
      expect(informe.importadas, 0);
      expect(informe.errores.single.fila, 12);
      expect(informe.errores.single.detalle, contains('PLANCHA'));
    });

    test('tras confirmar, lo importado coincide con lo válido', () {
      final informe = ResultadoImportacion.desdeJson({
        'confirmado': true,
        'filasLeidas': 34,
        'filasValidas': 34,
        'importadas': 34,
        'errores': <dynamic>[],
      });

      expect(informe.confirmado, isTrue);
      expect(informe.importadas, informe.filasValidas);
    });

    test('un informe sin la lista de errores no revienta', () {
      // Defensa barata contra un backend que omita el campo al serializar una
      // lista vacía.
      final informe = ResultadoImportacion.desdeJson({
        'confirmado': true,
        'filasLeidas': 2,
        'filasValidas': 2,
        'importadas': 2,
      });

      expect(informe.errores, isEmpty);
    });
  });
}
