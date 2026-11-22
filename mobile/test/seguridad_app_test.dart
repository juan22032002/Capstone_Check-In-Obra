import 'dart:io';

import 'package:checkinobra_mobile/features/auth/pantalla_diagnostico.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

String _leer(String ruta) => File('android/$ruta').readAsStringSync();

void main() {
  group('Respaldo de Android (S-20)', () {
    test('el manifiesto desactiva el respaldo y declara las reglas', () {
      final m = _leer('app/src/main/AndroidManifest.xml');

      expect(m, contains('android:allowBackup="false"'));
      expect(m, contains('android:fullBackupContent="@xml/backup_rules"'));
      expect(
        m,
        contains('android:dataExtractionRules="@xml/data_extraction_rules"'),
      );
    });

    test('las reglas excluyen las preferencias, donde vive el token', () {
      for (final ruta in [
        'app/src/main/res/xml/backup_rules.xml',
        'app/src/main/res/xml/data_extraction_rules.xml',
      ]) {
        final xml = _leer(ruta);
        expect(xml, contains('<exclude domain="sharedpref" />'), reason: ruta);
        expect(xml, contains('<exclude domain="database" />'), reason: ruta);
        expect(xml, isNot(contains('<include')), reason: ruta);
      }
    });

    test('la transferencia a otro teléfono también queda excluida', () {
      final xml = _leer('app/src/main/res/xml/data_extraction_rules.xml');

      expect(xml, contains('<cloud-backup>'));
      expect(xml, contains('<device-transfer>'));
    });
  });

  group('Firma de release (S-20)', () {
    final gradle = _leer('app/build.gradle.kts');

    test('el release no se firma con la clave de debug', () {
      expect(gradle, isNot(contains('signingConfigs.getByName("debug")')));
      expect(gradle, contains('signingConfigs.getByName("release")'));
    });

    test('el keystore sale de variables de entorno o de key.properties', () {
      expect(gradle, contains('CHECKINOBRA_KEYSTORE_FILE'));
      expect(gradle, contains('key.properties'));
    });

    test('un release sin keystore se detiene con un mensaje', () {
      expect(gradle, contains('GradleException'));
      expect(gradle, contains('Falta el keystore de firma'));
    });

    test('el keystore y sus claves no se versionan', () {
      final ignorado = _leer('.gitignore');

      expect(ignorado, contains('key.properties'));
      expect(ignorado, contains('*.jks'));
      expect(ignorado, contains('*.keystore'));
    });
  });

  group('Diagnóstico de conexión (S-29)', () {
    Future<void> montar(WidgetTester tester, {required bool disponible}) =>
        tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: PantallaDiagnostico(disponible: disponible),
            ),
          ),
        );

    testWidgets('en release no muestra nada del servidor ni del token', (
      tester,
    ) async {
      await montar(tester, disponible: false);

      expect(find.text('Esta pantalla no está disponible.'), findsOneWidget);
      expect(find.text('Verificación de conexión'), findsNothing);
    });

    testWidgets('fuera de release sigue disponible para armar el entorno', (
      tester,
    ) async {
      await montar(tester, disponible: true);

      expect(find.text('Verificación de conexión'), findsOneWidget);
    });

    test('la compilación de pruebas no es release', () {
      expect(PantallaDiagnostico.disponibleEnEstaCompilacion, isTrue);
    });
  });
}
