import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Configuración leída desde `mobile/.env`.
///
/// Ese archivo NO está versionado (lo ignora `.gitignore`), porque la URL
/// depende de la máquina de cada quien. Si falta, la app no revienta: arranca
/// igual y lo informa en pantalla, que es más útil que un crash en el arranque.
abstract final class AppConfig {
  static bool _envCargado = false;

  static Future<void> cargar() async {
    try {
      await dotenv.load(fileName: '.env');
      _envCargado = true;
    } catch (_) {
      // Sin .env seguimos con los valores por defecto de abajo.
      _envCargado = false;
    }
  }

  /// `true` si se pudo leer el archivo `.env`.
  static bool get envCargado => _envCargado;

  /// URL fijada al compilar con `--dart-define=API_BASE_URL=...`. Gana sobre
  /// el `.env`: la usa `scripts/levantar.sh --telefono`, que conecta el
  /// teléfono por `adb reverse` y necesita `localhost` sin reescribir el `.env`
  /// de nadie.
  static const _apiDefinidaAlCompilar = String.fromEnvironment('API_BASE_URL');

  /// URL base de la API.
  ///
  /// En desarrollo el valor por defecto apunta al emulador de Android:
  /// 10.0.2.2 es como el emulador alcanza el localhost del computador. En
  /// release no hay valor por defecto y la URL tiene que ser `https://`: ver
  /// [resolverUrl].
  static String get apiBaseUrl => resolverUrl(
    definida: _apiDefinidaAlCompilar,
    delEnv: _envCargado ? dotenv.env['API_BASE_URL'] : null,
    release: kReleaseMode,
  );

  static const _urlDeDesarrollo = 'http://10.0.2.2:8081';

  /// Decide la URL de la API y, en release, la exige `https://` y solo la
  /// toma de `--dart-define`.
  ///
  /// El JWT y el PIN viajan en cada petición: por HTTP quedan en claro para
  /// cualquiera en la misma WiFi (hallazgo S-10). Fuera de desarrollo se
  /// prefiere no arrancar a hacerlo sin cifrar, y tampoco se cae al valor por
  /// defecto del emulador, que es HTTP: una URL ausente en release es un error
  /// de empaquetado, no algo que arreglar adivinando.
  ///
  /// Es pura —recibe el modo— para poder probar el rechazo sin compilar en
  /// release.
  static String resolverUrl({
    required String? definida,
    required String? delEnv,
    required bool release,
  }) {
    // En release la URL entra solo por `--dart-define`. El `.env` es un
    // archivo de desarrollo que viaja empaquetado dentro del APK: dejar que
    // decidiera la URL de producción haría que un `.env` olvidado en la
    // máquina de quien compila cambiara a qué servidor habla la app.
    final delArchivo = release ? null : delEnv;
    final url = (definida != null && definida.isNotEmpty)
        ? definida
        : (delArchivo != null && delArchivo.isNotEmpty)
        ? delArchivo
        : null;

    if (!release) return url ?? _urlDeDesarrollo;

    if (url == null) {
      throw const ConfiguracionInvalida(
        'Falta la dirección del servidor. Compila la app con '
        '--dart-define=API_BASE_URL=https://...',
      );
    }
    final uri = Uri.tryParse(url.trim());
    if (uri == null ||
        uri.scheme.toLowerCase() != 'https' ||
        uri.host.isEmpty) {
      throw const ConfiguracionInvalida(
        'La dirección del servidor tiene que empezar con https://. Por '
        'seguridad la app no se conecta sin cifrar.',
      );
    }
    return url.trim();
  }

  /// Por qué la app no puede arrancar con esta configuración, o `null` si
  /// puede. Se revisa al inicio para mostrarlo en pantalla en vez de fallar
  /// recién en la primera petición.
  static String? get errorDeConfiguracion {
    try {
      apiBaseUrl;
      return null;
    } on ConfiguracionInvalida catch (e) {
      return e.mensaje;
    }
  }
}

/// La configuración con que se compiló la app no permite usarla.
class ConfiguracionInvalida implements Exception {
  const ConfiguracionInvalida(this.mensaje);

  final String mensaje;

  @override
  String toString() => 'ConfiguracionInvalida: $mensaje';
}
