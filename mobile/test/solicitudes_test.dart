import 'package:checkinobra_mobile/data/modelos/solicitud.dart';
import 'package:checkinobra_mobile/features/bodega/bodega_providers.dart';
import 'package:flutter_test/flutter_test.dart';

/// Lo que devuelve `GET /api/solicitudes-material?trabajadorId=`, tal cual.
Map<String, dynamic> _jsonMaterial({
  int id = 1,
  String estado = 'PENDIENTE',
  String? motivo,
  String? resueltoPor,
}) => {
  'id': id,
  'cantidad': 36.0,
  'estado': estado,
  'fechaSolicitud': '2026-09-02T08:14:00',
  'motivoRechazo': motivo,
  'trabajadorId': 5,
  'trabajadorNombre': 'Marcelo Sepúlveda',
  'trabajadorRut': '17.930.556-9',
  'materialId': 2,
  'materialSku': 'VOL-ST-10',
  'materialNombre': 'Volcanita ST 10 mm',
  'obraId': 3,
  'resueltoPorId': resueltoPor == null ? null : 9,
  'resueltoPorNombre': resueltoPor,
};

Map<String, dynamic> _jsonHerramienta({
  int id = 1,
  String estado = 'PENDIENTE',
}) => {
  'id': id,
  'cantidad': 1,
  'estado': estado,
  'fechaSolicitud': '2026-09-02T09:02:00',
  'motivoRechazo': null,
  'trabajadorId': 5,
  'trabajadorNombre': 'Marcelo Sepúlveda',
  'trabajadorRut': '17.930.556-9',
  'herramientaId': 8,
  'herramientaNombre': 'Taladro percutor 800 W',
  'resueltoPorId': null,
  'resueltoPorNombre': null,
};

void main() {
  group('Solicitud de material', () {
    test('una solicitud recién creada está pendiente y sin resolver', () {
      final s = SolicitudMaterial.desdeJson(_jsonMaterial());

      expect(s.pendiente, isTrue);
      expect(s.resueltoPorNombre, isNull);
      expect(s.motivoRechazo, isNull);
    });

    test('una resuelta deja de estar pendiente y dice quién la resolvió', () {
      final s = SolicitudMaterial.desdeJson(
        _jsonMaterial(estado: 'APROBADA', resueltoPor: 'Jorge Reyes'),
      );

      expect(s.pendiente, isFalse);
      expect(s.resueltoPorNombre, 'Jorge Reyes');
    });

    test(
      'una rechazada conserva el motivo, que es lo que ve el trabajador',
      () {
        final s = SolicitudMaterial.desdeJson(
          _jsonMaterial(
            estado: 'RECHAZADA',
            motivo: 'No hay stock suficiente',
            resueltoPor: 'Jorge Reyes',
          ),
        );

        expect(s.pendiente, isFalse);
        expect(s.motivoRechazo, 'No hay stock suficiente');
      },
    );

    test('identifica al solicitante con nombre y RUT', () {
      // Es lo que permite comprobar que la credencial escaneada corresponde a
      // quien está al otro lado del mesón.
      final s = SolicitudMaterial.desdeJson(_jsonMaterial());

      expect(s.trabajadorNombre, 'Marcelo Sepúlveda');
      expect(s.trabajadorRut, '17.930.556-9');
    });
  });

  group('Lo que se muestra tras escanear una credencial', () {
    test('cuenta solo lo pendiente, de los dos tipos juntos', () {
      final datos = SolicitudesDeTrabajador(
        materiales: [
          SolicitudMaterial.desdeJson(_jsonMaterial(id: 1)),
          SolicitudMaterial.desdeJson(_jsonMaterial(id: 2)),
          SolicitudMaterial.desdeJson(
            _jsonMaterial(id: 3, estado: 'APROBADA', resueltoPor: 'Jorge'),
          ),
        ],
        herramientas: [
          SolicitudHerramienta.desdeJson(_jsonHerramienta(id: 4)),
          SolicitudHerramienta.desdeJson(
            _jsonHerramienta(id: 5, estado: 'RECHAZADA'),
          ),
        ],
      );

      expect(datos.materialesPendientes, hasLength(2));
      expect(datos.herramientasPendientes, hasLength(1));
      expect(datos.cuantasPendientes, 3);
      expect(datos.vacio, isFalse);
    });

    test('un trabajador que nunca pidió nada se distingue de uno al día', () {
      // No es lo mismo "todavía no ha pedido nada" que "ya se le resolvió
      // todo": la pantalla dice cosas distintas en cada caso.
      const sinNada = SolicitudesDeTrabajador(materiales: [], herramientas: []);
      final alDia = SolicitudesDeTrabajador(
        materiales: [
          SolicitudMaterial.desdeJson(
            _jsonMaterial(estado: 'APROBADA', resueltoPor: 'Jorge'),
          ),
        ],
        herramientas: const [],
      );

      expect(sinNada.vacio, isTrue);
      expect(sinNada.cuantasPendientes, 0);
      expect(alDia.vacio, isFalse);
      expect(alDia.cuantasPendientes, 0);
    });
  });
}
