import 'package:dio/dio.dart';

import '../../data/api/auth_api.dart';
import '../formato.dart';

/// Traduce cualquier fallo a un mensaje que le sirva a quien está en obra.
///
/// Un "connection error" pelado no le dice nada a un bodeguero con guantes.
/// Las causas reales en esta app son siempre las mismas pocas, así que se
/// nombran directamente.
String mensajeDeError(Object error) {
  if (error is ApiException) {
    // Empresa suspendida: no es un "sin permiso" ni algo que reintentar.
    if (error.empresaSuspendida) return mensajeEmpresaSuspendida;
    // Demasiados intentos fallidos: se dice cuánto esperar. El backend bloquea
    // la cuenta aunque la clave sea la correcta, así que reintentar antes solo
    // alarga la espera.
    if (error.demasiadosIntentos) {
      final espera = error.reintentarEnSegundos;
      return espera == null
          ? 'Demasiados intentos. Espera un momento antes de volver a intentar.'
          : 'Demasiados intentos. Espera ${Formato.espera(espera)} antes de '
                'volver a intentar.';
    }
    // Una solicitud que va en un pedido con QR no se resuelve sola. El backend
    // lo explica, pero en términos del modelo; esto dice qué hacer.
    if (error.codigo == 'EN_PEDIDO') {
      return 'Esta herramienta va en un pedido con QR: se entrega o se '
          'cancela el pedido completo.';
    }
    return error.mensaje;
  }

  if (error is DioException) {
    return switch (error.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout => 'El servidor no respondió a tiempo. Revisa la señal e inténtalo de nuevo.',
      DioExceptionType.connectionError => 'No hay conexión con el servidor. Verifica que estés en la red de la obra.',
      DioExceptionType.badCertificate =>
        'El certificado del servidor no es válido.',
      DioExceptionType.cancel => 'La operación se canceló.',
      _ => error.message ?? 'Fallo de red',
    };
  }

  return 'Ocurrió un error inesperado.';
}
