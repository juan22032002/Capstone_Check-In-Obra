import 'package:checkinobra_mobile/core/storage/sesion_storage.dart';
import 'package:checkinobra_mobile/data/api/auth_api.dart';
import 'package:checkinobra_mobile/features/inicio/pantalla_rol_pendiente.dart';
import 'package:checkinobra_mobile/shared_widgets/panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Iniciales', () {
    test('toma la primera letra de nombre y apellido', () {
      expect(Iniciales.de('Marcelo Sepúlveda'), 'MS');
    });

    test('con un solo nombre usa una letra', () {
      expect(Iniciales.de('Jorge'), 'J');
    });

    test('ignora los espacios de más', () {
      expect(Iniciales.de('  Camila   Bravo  '), 'CB');
    });

    test('no revienta con texto vacío', () {
      expect(Iniciales.de('   '), '?');
    });
  });

  group('SesionUsuario', () {
    test('sobrevive al viaje de ida y vuelta a JSON', () {
      const original = SesionUsuario(
        token: 'abc.def.ghi',
        usuarioId: 7,
        nombre: 'Jorge Reyes',
        rol: 'BODEGUERO',
        empresaId: 1,
      );
      final copia = SesionUsuario.desdeJson(original.aJson());

      expect(copia.token, original.token);
      expect(copia.usuarioId, original.usuarioId);
      expect(copia.nombre, original.nombre);
      expect(copia.rol, original.rol);
      expect(copia.empresaId, original.empresaId);
    });
  });

  group('UsuarioRecordado', () {
    test('guarda los datos mínimos para el acceso por PIN', () {
      const u = UsuarioRecordado(
        usuarioId: 3,
        empresaId: 1,
        nombre: 'Marcelo Sepúlveda',
        rol: 'TRABAJADOR',
      );
      expect(u.usuarioId, 3);
      expect(Iniciales.de(u.nombre), 'MS');
    });
  });

  testWidgets('el rol pendiente muestra sus permisos y qué falta', (
    tester,
  ) async {
    // El jefe de terreno es uno de los dos roles cuyo flujo no está
    // construido: el bodeguero y el admin ya entran a su propio shell.
    const sesion = SesionUsuario(
      token: 't',
      usuarioId: 1,
      nombre: 'Rodrigo Cárcamo',
      rol: 'JEFE_TERRENO',
      empresaId: 1,
    );

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: PantallaRolPendiente(sesion: sesion)),
      ),
    );
    await tester.pump();

    expect(find.text('Rodrigo Cárcamo'), findsWidgets);
    // Un permiso propio de su rol, y ninguno ajeno.
    expect(find.text('Congelar el presupuesto'), findsOneWidget);
    expect(find.text('Aprobar o rechazar solicitudes'), findsNothing);
    // Y dice qué falta, en vez de dejarlo esperando sin explicación.
    expect(find.textContaining('Falta el flujo de cubicación'), findsOneWidget);
  });
}
