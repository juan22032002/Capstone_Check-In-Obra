import 'package:dio/dio.dart';

import '../../core/network/api_client.dart';

/// Respuesta de `POST /api/auth/login` — refleja
/// `AuthController.LoginResponse` del backend.
class SesionUsuario {
  const SesionUsuario({
    required this.token,
    required this.usuarioId,
    required this.nombre,
    required this.rol,
    required this.empresaId,
    this.debeCambiarClave = false,
    this.refreshToken,
  });

  final String token;
  final int usuarioId;
  final String nombre;

  /// Valor del enum `RolUsuario`: ADMIN, JEFE_TERRENO, BODEGUERO, TRABAJADOR.
  final String rol;
  final int empresaId;

  /// La cuenta entró con una clave provisoria (la primera del administrador,
  /// o una que otra persona le definió): mientras no la cambie, el servidor
  /// rechaza todo salvo `PUT /api/auth/pin` con 403 `DEBE_CAMBIAR_PIN`.
  final bool debeCambiarClave;

  /// Para pedir otro token de acceso sin la clave (`POST /api/auth/refresh`).
  /// El token de acceso dura 30 minutos; esto, hasta 7 días sin usarse. Se
  /// **rota** en cada uso: hay que guardar el que devuelve cada renovación.
  /// `null` en una sesión guardada antes de que existiera.
  final String? refreshToken;

  /// La misma sesión, marcada como pendiente de cambio de clave.
  SesionUsuario conCambioPendiente() => SesionUsuario(
    token: token,
    usuarioId: usuarioId,
    nombre: nombre,
    rol: rol,
    empresaId: empresaId,
    debeCambiarClave: true,
    refreshToken: refreshToken,
  );

  factory SesionUsuario.desdeJson(Map<String, dynamic> json) => SesionUsuario(
    token: json['token'] as String,
    usuarioId: json['usuarioId'] as int,
    nombre: json['nombre'] as String,
    rol: json['rol'] as String,
    empresaId: json['empresaId'] as int,
    // Ausente en una sesión guardada antes de que existiera, o en un backend
    // que aún no la manda: ahí no hay obligación.
    debeCambiarClave: json['debeCambiarClave'] as bool? ?? false,
    refreshToken: json['refreshToken'] as String?,
  );

  Map<String, dynamic> aJson() => {
    'token': token,
    'usuarioId': usuarioId,
    'nombre': nombre,
    'rol': rol,
    'empresaId': empresaId,
    'debeCambiarClave': debeCambiarClave,
    'refreshToken': refreshToken,
  };
}

/// El `codigo` con que el backend rechaza a una empresa suspendida.
const codigoEmpresaSuspendida = 'EMPRESA_SUSPENDIDA';

/// Lo que se le dice a quien trabaja en una empresa suspendida. No hay nada que
/// la persona pueda hacer en la app: es una decisión de la plataforma.
const mensajeEmpresaSuspendida =
    'Tu empresa está suspendida. Habla con la plataforma.';

/// Se lanza cuando el servidor respondió pero rechazó la petición
/// (por ejemplo, credenciales incorrectas).
class ApiException implements Exception {
  const ApiException(
    this.statusCode,
    this.mensaje, {
    this.codigo,
    this.reintentarEnSegundos,
  });

  final int statusCode;
  final String mensaje;

  /// El `codigo` del cuerpo de error del backend (`STOCK_INSUFICIENTE`,
  /// `YA_RESUELTA`…), cuando lo trae. Permite decidir sin comparar textos: un
  /// 409 puede ser "no alcanza el stock" o "otro bodeguero ya la aprobó", y
  /// esos dos casos se le muestran distinto a quien está en bodega.
  final String? codigo;

  /// Cuánto esperar antes de reintentar, de la cabecera `Retry-After` de un
  /// 429. `null` si no vino.
  final int? reintentarEnSegundos;

  /// El servidor bloqueó el intento por demasiados fallos (`DEMASIADOS_INTENTOS`).
  /// Reintentar antes de tiempo no sirve —ni la clave correcta entra— y alarga
  /// el bloqueo.
  bool get demasiadosIntentos =>
      statusCode == 429 || codigo == 'DEMASIADOS_INTENTOS';

  /// La empresa de quien entró está suspendida: el servidor responde 403
  /// `EMPRESA_SUSPENDIDA` a todo. Se distingue **solo por el código**: un 403 es
  /// también "tu rol no permite esto" y, en otro flujo, `DEBE_CAMBIAR_PIN`, y
  /// ninguno de esos significa que haya que cerrar la sesión.
  bool get empresaSuspendida =>
      statusCode == 403 && codigo == codigoEmpresaSuspendida;

  /// La operación ya estaba hecha: otro bodeguero se adelantó o el reintento
  /// llegó después de un éxito cuya respuesta se perdió. No es un error que
  /// haya que corregir, es un estado que hay que refrescar.
  bool get yaEstabaHecho => codigo == 'YA_RESUELTA' || codigo == 'YA_DEVUELTO';

  @override
  String toString() => 'ApiException($statusCode): $mensaje';
}

class AuthApi {
  AuthApi(this._client);

  final ApiClient _client;

  /// Login por correo + PIN. En el backend, el correo ubica al usuario
  /// (`Usuario.autenticarPorEmail`) y el PIN lo autentica (`Usuario.autenticar`).
  Future<SesionUsuario> login({required String email, required String pin}) =>
      _postLogin('/api/auth/login', {'email': email, 'pin': pin});

  /// Login solo con PIN, para el usuario que el teléfono ya recuerda.
  /// Es la vía del rol TRABAJADOR: nadie escribe un correo con guantes puestos.
  ///
  /// Lleva también la empresa: los ids de usuario se repiten entre empresas,
  /// así que `usuarioId` solo no dice de quién es el PIN.
  Future<SesionUsuario> loginPorPin({
    required int usuarioId,
    required int empresaId,
    required String pin,
  }) => _postLogin('/api/auth/login-pin', {
    'usuarioId': usuarioId,
    'empresaId': empresaId,
    'pin': pin,
  });

  /// Cambia la clave de quien tiene la sesión (`PUT /api/auth/pin`). El
  /// servidor exige la actual con el mismo bloqueo por intentos que el login, y
  /// devuelve una sesión nueva, ya sin la obligación de cambiarla: esa es la
  /// que hay que usar de ahí en adelante.
  Future<SesionUsuario> cambiarClave({
    required String claveActual,
    required String claveNueva,
  }) => _enviarSesion(
    () => _client.dio.put<Map<String, dynamic>>(
      '/api/auth/pin',
      data: {'pinActual': claveActual, 'pinNuevo': claveNueva},
    ),
  );

  /// Canjea un refresh token por una sesión nueva, con otro refresh token. El
  /// que se manda queda revocado. Un 401 con `SESION_INVALIDA` dice que hay
  /// que pedir la clave de nuevo.
  Future<SesionUsuario> renovar(String refreshToken) => _enviarSesion(
    () => _client.dio.post<Map<String, dynamic>>(
      '/api/auth/refresh',
      data: {'refreshToken': refreshToken},
    ),
  );

  /// Revoca el refresh token en el servidor (`POST /api/auth/logout`, que
  /// responde 204 exista o no). Es lo último que se hace al cerrar sesión y no
  /// debe impedirlo: si falla, la sesión local ya se cerró y el refresh vence
  /// solo a los 7 días.
  Future<void> cerrarSesion(String refreshToken) async {
    await _client.dio.post<dynamic>(
      '/api/auth/logout',
      data: {'refreshToken': refreshToken},
    );
  }

  Future<SesionUsuario> _postLogin(String ruta, Map<String, dynamic> cuerpo) =>
      _enviarSesion(
        () => _client.dio.post<Map<String, dynamic>>(ruta, data: cuerpo),
      );

  Future<SesionUsuario> _enviarSesion(
    Future<Response<Map<String, dynamic>>> Function() enviar,
  ) async {
    final respuesta = await enviar();

    final codigo = respuesta.statusCode ?? 0;
    if (codigo == 200 && respuesta.data != null) {
      return SesionUsuario.desdeJson(respuesta.data!);
    }
    throw ApiException(
      codigo,
      _mensajeDeError(respuesta.data, codigo),
      codigo: respuesta.data?['codigo'] as String?,
      reintentarEnSegundos: segundosDeEspera(
        respuesta.headers.value('retry-after'),
      ),
    );
  }

  /// El valor de `Retry-After` en segundos, o `null` si falta o no es un número
  /// (la cabecera también admite una fecha; el backend manda segundos).
  static int? segundosDeEspera(String? cabecera) {
    final segundos = int.tryParse(cabecera?.trim() ?? '');
    return segundos != null && segundos > 0 ? segundos : null;
  }

  /// El backend responde errores con el formato de `ApiExceptionHandler`:
  /// `{instante, status, mensaje}`.
  String _mensajeDeError(Map<String, dynamic>? cuerpo, int codigo) {
    final mensaje = cuerpo?['mensaje'];
    if (mensaje is String && mensaje.isNotEmpty) return mensaje;
    return switch (codigo) {
      400 => 'Correo o PIN incorrectos',
      403 => 'Sin autorización para esta acción',
      404 => 'Ruta no encontrada — ¿es la URL correcta del backend?',
      _ => 'El servidor respondió con código $codigo',
    };
  }
}
