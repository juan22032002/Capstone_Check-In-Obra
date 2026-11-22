import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api/auth_api.dart';
import '../storage/sesion_storage.dart';
import '../../features/auth/sesion_controller.dart';
import 'app_config.dart';
import 'renovador_sesion.dart';

/// Cliente HTTP contra la API de Check-In-Obra.
///
/// Los timeouts son cortos a propósito: en terreno, esperar 30 segundos a que
/// una petición muera es peor que fallar rápido y reintentar.
class ApiClient {
  ApiClient({
    Dio? dio,
    SesionStorage? storage,
    void Function()? alExpirar,
    void Function()? alDebeCambiarClave,
    void Function()? alEmpresaSuspendida,
    Future<ResultadoRenovacion> Function(String tokenQueFallo)? renovar,
  }) : dio = dio ?? _crearDio() {
    if (storage != null) {
      this.dio.interceptors.add(
        _InterceptorToken(
          this.dio,
          storage,
          alExpirar,
          alDebeCambiarClave,
          renovar,
          alEmpresaSuspendida,
        ),
      );
    }
  }

  static Dio _crearDio() => Dio(
    BaseOptions(
      baseUrl: AppConfig.apiBaseUrl,
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 8),
      sendTimeout: const Duration(seconds: 8),
      contentType: Headers.jsonContentType,
      // No lanzar excepción por 4xx: los manejamos nosotros para
      // distinguir "credenciales malas" de "no hay red".
      validateStatus: (status) => status != null && status < 500,
    ),
  );

  final Dio dio;

  String get baseUrl => dio.options.baseUrl;
}

/// Adjunta el JWT a cada petición, salvo a las de `/api/auth` — pedir el
/// token mandando el token no tiene sentido.
///
/// También se ocupa del token vencido. El de acceso dura 30 minutos; ante un
/// 401 fuera de `/api/auth` se intenta **renovarlo** con el refresh token y
/// reintentar la petición **una vez**, sin que quien está en bodega note nada.
/// Solo se cierra la sesión si el servidor dice que ya no vale (`SESION_INVALIDA`,
/// o el refresh rechazado): ahí vuelve a la pantalla de acceso con su usuario
/// recordado. Sin señal no se cierra nada: no poder renovar no es lo mismo que
/// no poder seguir.
class _InterceptorToken extends Interceptor {
  _InterceptorToken(
    this._dio,
    this._storage,
    this._alExpirar,
    this._alDebeCambiarClave,
    this._renovar,
    this._alEmpresaSuspendida,
  );

  final Dio _dio;
  final SesionStorage _storage;
  final void Function()? _alExpirar;
  final void Function()? _alDebeCambiarClave;
  final Future<ResultadoRenovacion> Function(String tokenQueFallo)? _renovar;
  final void Function()? _alEmpresaSuspendida;

  static const _marcaReintento = 'reintentado_tras_renovar';

  @override
  Future<void> onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) async {
    final pedida = response.requestOptions;
    final esAuth = pedida.path.startsWith('/api/auth');
    final autorizacion = pedida.headers['Authorization'];
    final llevabaToken = autorizacion is String;

    if (response.statusCode == 401 && !esAuth && llevabaToken) {
      await _alRecibir401(response, handler, autorizacion);
      return;
    }
    if (response.statusCode == 403 && !esAuth && llevabaToken) {
      final cuerpo = response.data;
      final codigo = cuerpo is Map ? cuerpo['codigo'] : null;
      // Cuenta con clave provisoria: el servidor responde 403 a todo salvo al
      // cambio de clave. No es un "sin permiso" que mostrar como error, sino una
      // orden de llevar a la persona a cambiarla.
      if (codigo == 'DEBE_CAMBIAR_PIN') _alDebeCambiarClave?.call();
      // Empresa suspendida: el servidor responde 403 con este código a todo, y
      // seguir con la sesión no sirve. Se distingue solo por el código; un 403
      // por falta de permiso pasa de largo y se muestra como siempre.
      if (codigo == codigoEmpresaSuspendida) _alEmpresaSuspendida?.call();
    }
    handler.next(response);
  }

  Future<void> _alRecibir401(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
    String autorizacion,
  ) async {
    final pedida = response.requestOptions;
    final cuerpo = response.data;
    final sesionInvalida =
        cuerpo is Map && cuerpo['codigo'] == 'SESION_INVALIDA';
    final yaReintentada = pedida.extra[_marcaReintento] == true;
    final renovar = _renovar;

    // El servidor dijo que la sesión no vale, o ya se reintentó con un token
    // recién renovado y igual falló: no hay más que intentar.
    if (sesionInvalida || yaReintentada || renovar == null) {
      _alExpirar?.call();
      handler.next(response);
      return;
    }

    final resultado = await renovar(autorizacion.replaceFirst('Bearer ', ''));
    switch (resultado) {
      case ResultadoRenovacion.renovada:
        try {
          // `onRequest` vuelve a leer el token del almacenamiento: el
          // reintento sale con el nuevo.
          final reintento = await _dio.fetch<dynamic>(
            pedida.copyWith(
              data: pedida.data is FormData
                  ? (pedida.data as FormData).clone()
                  : pedida.data,
              extra: {...pedida.extra, _marcaReintento: true},
            ),
          );
          handler.resolve(reintento);
        } on DioException catch (e) {
          handler.reject(e);
        }
      case ResultadoRenovacion.sesionInvalida:
        _alExpirar?.call();
        handler.next(response);
      case ResultadoRenovacion.empresaSuspendida:
        _alEmpresaSuspendida?.call();
        handler.next(response);
      case ResultadoRenovacion.noDisponible:
        // La petición falla con su 401, pero la sesión sigue: se puede
        // reintentar cuando vuelva la señal.
        handler.next(response);
    }
  }

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    // `/api/auth/pin` es la única ruta de auth que va autenticada: cambia la
    // clave de quien tiene la sesión.
    if (!options.path.startsWith('/api/auth') ||
        options.path == '/api/auth/pin') {
      final token = await _storage.leerToken();
      if (token != null) {
        options.headers['Authorization'] = 'Bearer $token';
      }
    }
    handler.next(options);
  }
}

final sesionStorageProvider = Provider<SesionStorage>((ref) => SesionStorage());

final apiClientProvider = Provider<ApiClient>(
  (ref) => ApiClient(
    storage: ref.watch(sesionStorageProvider),
    // Se lee al momento del 401, no al construir: el controlador de sesión
    // depende de este cliente para el login.
    alExpirar: () => ref.read(sesionProvider.notifier).expirar(),
    alDebeCambiarClave: () =>
        ref.read(sesionProvider.notifier).exigirCambioDeClave(),
    renovar: (tokenQueFallo) => ref
        .read(renovadorDeSesionProvider)
        .renovar(tokenQueFallo: tokenQueFallo),
    alEmpresaSuspendida: () =>
        ref.read(sesionProvider.notifier).suspenderPorEmpresa(),
  ),
);

/// Renueva el token de acceso. Usa un cliente **sin** el interceptor del token:
/// renovar no lleva token, y con él un 401 del propio refresh intentaría
/// renovar de nuevo, sin fin.
final renovadorDeSesionProvider = Provider<RenovadorDeSesion>((ref) {
  return RenovadorDeSesion(
    storage: ref.watch(sesionStorageProvider),
    pedir: (refresh) => ref.read(authApiSinTokenProvider).renovar(refresh),
    alRenovar: (nueva) =>
        ref.read(sesionProvider.notifier).aplicarRenovada(nueva),
  );
});

/// El cliente de auth **sin** interceptor de token, para renovar la sesión.
final authApiSinTokenProvider = Provider<AuthApi>(
  (ref) => AuthApi(ApiClient()),
);

final authApiProvider = Provider<AuthApi>(
  (ref) => AuthApi(ref.watch(apiClientProvider)),
);
