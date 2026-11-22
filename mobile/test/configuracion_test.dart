import 'dart:io';

import 'package:checkinobra_mobile/core/network/app_config.dart';
import 'package:flutter_test/flutter_test.dart';

String _url({String? definida, String? delEnv, bool release = true}) =>
    AppConfig.resolverUrl(definida: definida, delEnv: delEnv, release: release);

void main() {
  group('URL de la API en release', () {
    test('acepta una URL https', () {
      expect(
        _url(definida: 'https://api.checkinobra.cl'),
        'https://api.checkinobra.cl',
      );
    });

    test('acepta https con puerto, ruta y mayúsculas en el esquema', () {
      expect(
        _url(definida: 'HTTPS://api.checkinobra.cl:8443/v1'),
        'HTTPS://api.checkinobra.cl:8443/v1',
      );
    });

    test('rechaza http aunque sea la del emulador', () {
      expect(
        () => _url(definida: 'http://10.0.2.2:8081'),
        throwsA(isA<ConfiguracionInvalida>()),
      );
    });

    test('rechaza http en cualquier mayúscula y sin esquema', () {
      for (final url in [
        'HTTP://api.checkinobra.cl',
        'api.checkinobra.cl',
        'ftp://api.checkinobra.cl',
        'https://',
        'https:api.checkinobra.cl',
      ]) {
        expect(
          () => _url(definida: url),
          throwsA(isA<ConfiguracionInvalida>()),
          reason: url,
        );
      }
    });

    test('sin URL no cae al valor del emulador: falla', () {
      expect(() => _url(), throwsA(isA<ConfiguracionInvalida>()));
      expect(
        () => _url(definida: '', delEnv: ''),
        throwsA(isA<ConfiguracionInvalida>()),
      );
    });

    test('la URL compilada gana sobre la del .env, y también se valida', () {
      expect(
        () => _url(
          definida: 'http://inseguro.cl',
          delEnv: 'https://api.checkinobra.cl',
        ),
        throwsA(isA<ConfiguracionInvalida>()),
      );
    });

    test('en release el .env no decide la URL, ni siquiera si es https', () {
      // El .env viaja dentro del APK y es de desarrollo: un archivo olvidado en
      // la máquina de quien compila no debe cambiar a qué servidor habla la app.
      expect(
        () => _url(delEnv: 'https://api.checkinobra.cl'),
        throwsA(isA<ConfiguracionInvalida>()),
      );
      expect(
        _url(definida: 'https://api.checkinobra.cl', delEnv: 'https://otro.cl'),
        'https://api.checkinobra.cl',
      );
    });

    test('el mensaje dice qué hacer', () {
      expect(
        () => _url(definida: 'http://api.checkinobra.cl'),
        throwsA(
          isA<ConfiguracionInvalida>().having(
            (e) => e.mensaje,
            'mensaje',
            contains('https://'),
          ),
        ),
      );
    });
  });

  group('URL de la API en desarrollo', () {
    test('sin configurar apunta al emulador', () {
      expect(_url(release: false), 'http://10.0.2.2:8081');
    });

    test('el .env sigue valiendo en desarrollo', () {
      expect(
        _url(release: false, delEnv: 'http://localhost:8081'),
        'http://localhost:8081',
      );
      expect(
        _url(
          release: false,
          definida: 'http://10.0.2.2:9000',
          delEnv: 'http://localhost:8081',
        ),
        'http://10.0.2.2:9000',
      );
    });

    test('permite http, que es lo que usa el emulador', () {
      expect(
        _url(release: false, delEnv: 'http://192.168.1.50:8081'),
        'http://192.168.1.50:8081',
      );
    });
  });

  group('Android: sin tráfico en claro', () {
    String leer(String ruta) =>
        File('android/app/src/$ruta').readAsStringSync();

    test(
      'el config principal prohíbe el tráfico en claro y no abre excepciones',
      () {
        final xml = leer('main/res/xml/network_security_config.xml');

        expect(xml, contains('cleartextTrafficPermitted="false"'));
        expect(xml, isNot(contains('cleartextTrafficPermitted="true"')));
        expect(xml, isNot(contains('<domain')));
      },
    );

    test('solo debug abre HTTP, y solo hacia el computador de desarrollo', () {
      final xml = leer('debug/res/xml/network_security_config.xml');

      expect(xml, contains('<base-config cleartextTrafficPermitted="false"'));
      final dominios = RegExp(r'<domain[^>]*>([^<]+)</domain>')
          .allMatches(xml)
          .map((m) => m.group(1))
          .toList();
      expect(dominios, ['10.0.2.2', 'localhost', '127.0.0.1']);
    });

    test('el manifiesto principal usa el config y declara INTERNET', () {
      final manifiesto = leer('main/AndroidManifest.xml');

      expect(
        manifiesto,
        contains(
          'android:networkSecurityConfig="@xml/network_security_config"',
        ),
      );
      expect(
        manifiesto,
        contains(
          '<uses-permission android:name="android.permission.INTERNET" />',
        ),
      );
    });

    test('los comentarios XML no llevan "--", que Android no puede leer', () {
      // Un "--" dentro de un comentario rompe el parseo de recursos y recién
      // se ve al compilar el APK, no en `flutter test`.
      for (final ruta in [
        'main/res/xml/network_security_config.xml',
        'debug/res/xml/network_security_config.xml',
        'main/AndroidManifest.xml',
      ]) {
        final comentarios = RegExp(
          r'<!--(.*?)-->',
          dotAll: true,
        ).allMatches(leer(ruta)).map((m) => m.group(1)!);
        for (final c in comentarios) {
          expect(c, isNot(contains('--')), reason: ruta);
        }
      }
    });

    test('ninguna variante que no sea debug abre tráfico en claro', () {
      final perfil = File('android/app/src/profile/res');
      expect(perfil.existsSync(), isFalse);
    });
  });
}
