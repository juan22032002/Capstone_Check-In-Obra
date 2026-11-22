import 'package:dio/dio.dart';

import '../../data/api/auth_api.dart';
import '../storage/sesion_storage.dart';

/// Cómo terminó un intento de renovar la sesión.
enum ResultadoRenovacion {
  /// Hay un token de acceso nuevo guardado: se puede reintentar lo que falló.
  renovada,

  /// El servidor no acepta el refresh (venció, lo revocaron, o ya se usó): hay
  /// que pedir la clave de nuevo.
  sesionInvalida,

  /// La empresa está suspendida: el servidor rechaza hasta la renovación con
  /// 403 `EMPRESA_SUSPENDIDA`. Hay que cerrar la sesión **con ese aviso**, no
  /// con el de "tu sesión expiró".
  empresaSuspendida,

  /// No se pudo saber —sin señal, el servidor caído, un bloqueo temporal—. La
  /// sesión sigue en pie: perder la conexión no es motivo para cerrarla.
  noDisponible,
}

/// Renueva el token de acceso con el refresh token, **de a uno por vez**.
///
/// El token de acceso dura 30 minutos. Cuando vence, varias peticiones suelen
/// recibir el 401 a la vez (una pantalla pide tres cosas al abrirse). El refresh
/// se **rota**: cada uso entrega uno nuevo y deja inservible el anterior, y
/// presentar uno ya usado hace que el servidor cierre todas las sesiones de esa
/// persona. Si cada petición refrescara por su cuenta, la segunda usaría el
/// refresh que la primera acaba de gastar y sacaría al usuario de la app. Por
/// eso hay un solo vuelo: quien llega con otro en curso espera su resultado.
class RenovadorDeSesion {
  RenovadorDeSesion({
    required this.storage,
    required this.pedir,
    required this.alRenovar,
  });

  final SesionStorage storage;

  /// Pide al servidor una sesión nueva a cambio de este refresh token.
  final Future<SesionUsuario> Function(String refreshToken) pedir;

  /// Se llama con la sesión nueva, ya guardada.
  final void Function(SesionUsuario nueva) alRenovar;

  Future<ResultadoRenovacion>? _enVuelo;

  /// [tokenQueFallo] es el token con que se hizo la petición que recibió el 401.
  /// Si el guardado ya es otro, alguien renovó mientras esa petición estaba en
  /// camino y solo hay que reintentarla: renovar de nuevo gastaría un refresh
  /// que todavía sirve.
  Future<ResultadoRenovacion> renovar({String? tokenQueFallo}) {
    final enCurso = _enVuelo;
    if (enCurso != null) return enCurso;
    final nuevo = _renovar(tokenQueFallo).whenComplete(() => _enVuelo = null);
    return _enVuelo = nuevo;
  }

  Future<ResultadoRenovacion> _renovar(String? tokenQueFallo) async {
    final sesion = await storage.leer();
    if (sesion == null) return ResultadoRenovacion.sesionInvalida;
    if (tokenQueFallo != null && sesion.token != tokenQueFallo) {
      return ResultadoRenovacion.renovada;
    }
    final refresh = sesion.refreshToken;
    // Una sesión guardada antes de que existiera el refresh, o de un servidor
    // que no lo manda: no hay con qué renovar.
    if (refresh == null || refresh.isEmpty) {
      return ResultadoRenovacion.sesionInvalida;
    }

    try {
      final nueva = await pedir(refresh);
      // Se guarda el refresh nuevo de inmediato: el anterior ya no sirve.
      await storage.actualizarSesion(nueva);
      alRenovar(nueva);
      return ResultadoRenovacion.renovada;
    } on ApiException catch (e) {
      // Antes que lo demás: es un 403, que de otro modo se leería como un fallo
      // pasajero y la sesión nunca se cerraría.
      if (e.empresaSuspendida) return ResultadoRenovacion.empresaSuspendida;
      final rechazado =
          e.statusCode == 401 ||
          e.statusCode == 400 ||
          e.codigo == 'SESION_INVALIDA';
      return rechazado
          ? ResultadoRenovacion.sesionInvalida
          : ResultadoRenovacion.noDisponible;
    } on DioException {
      return ResultadoRenovacion.noDisponible;
    }
  }
}
