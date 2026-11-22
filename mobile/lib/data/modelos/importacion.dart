/// Refleja `ResultadoImportacion` del backend.
///
/// El mismo objeto vuelve de la simulación y de la importación real: lo único
/// que cambia es [confirmado]. Eso es a propósito —la app muestra el informe
/// antes de dejar apretar el botón, y ese informe es exactamente la validación
/// que después decide si se escribe.
class ResultadoImportacion {
  const ResultadoImportacion({
    required this.confirmado,
    required this.filasLeidas,
    required this.filasValidas,
    required this.importadas,
    required this.errores,
  });

  final bool confirmado;
  final int filasLeidas;
  final int filasValidas;
  final int importadas;
  final List<ErrorDeFila> errores;

  /// La planilla completa pasó la validación: se puede importar tal cual.
  bool get listaParaImportar => errores.isEmpty;

  factory ResultadoImportacion.desdeJson(Map<String, dynamic> j) =>
      ResultadoImportacion(
        confirmado: j['confirmado'] as bool,
        filasLeidas: j['filasLeidas'] as int,
        filasValidas: j['filasValidas'] as int,
        importadas: j['importadas'] as int,
        errores: [
          for (final e in (j['errores'] as List<dynamic>? ?? const []))
            ErrorDeFila.desdeJson(e as Map<String, dynamic>),
        ],
      );
}

/// Un problema concreto, ubicado en la fila del archivo que hay que corregir.
class ErrorDeFila {
  const ErrorDeFila({required this.fila, required this.detalle});

  /// Número de fila **como lo muestra Excel**, para poder ir directo a ella.
  final int fila;
  final String detalle;

  factory ErrorDeFila.desdeJson(Map<String, dynamic> j) =>
      ErrorDeFila(fila: j['fila'] as int, detalle: j['detalle'] as String);
}
