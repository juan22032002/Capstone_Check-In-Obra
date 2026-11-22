import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_forma.dart';
import '../../shared_widgets/campo_texto.dart';

/// La cámara leyendo códigos, con todo lo que en obra hace falta alrededor.
///
/// Es una sola pieza para los dos escaneos del bodeguero —la credencial QR del
/// trabajador y el código de barras de un material o una herramienta— porque
/// lo único que cambia entre ellos es qué formatos se aceptan y qué se hace con
/// el texto leído.
///
/// Dos decisiones que no son de estilo:
///
/// - **Siempre hay salida a mano.** Una etiqueta rota, una credencial mojada o
///   un permiso de cámara denegado no pueden dejar al bodeguero sin poder
///   despachar. El código se puede teclear, y eso además hace la pantalla
///   utilizable con lector de pantalla.
/// - **Un código a la vez.** Mientras la consulta al servidor está en curso, el
///   escáner queda desarmado. Sin eso, la cámara vuelve a leer el mismo código
///   varias veces por segundo y dispara la misma operación en ráfaga.
class LectorDeCodigo extends StatefulWidget {
  const LectorDeCodigo({
    super.key,
    required this.titulo,
    required this.instruccion,
    required this.formatos,
    required this.alLeer,
    required this.etiquetaManual,
    this.ayudaManual,
  });

  final String titulo;

  /// Qué apuntar, en una línea. Va sobre la cámara.
  final String instruccion;

  final List<BarcodeFormat> formatos;

  /// Qué hacer con el código leído. Devuelve el mensaje de error a mostrar, o
  /// `null` si salió bien — en cuyo caso quien lo implementa ya navegó a otra
  /// pantalla y este escáner no vuelve a armarse.
  final Future<String?> Function(String codigo) alLeer;

  /// Rótulo del campo de ingreso manual: "Código de la credencial", "Código del
  /// material".
  final String etiquetaManual;

  final String? ayudaManual;

  @override
  State<LectorDeCodigo> createState() => _LectorDeCodigoState();
}

class _LectorDeCodigoState extends State<LectorDeCodigo> {
  late final MobileScannerController _camara = MobileScannerController(
    formats: widget.formatos,
    // `noDuplicates` evita releer el mismo código en cada cuadro. El desarme
    // manual de abajo sigue haciendo falta: `noDuplicates` no sabe cuándo
    // terminó la petición que disparó la primera lectura.
    detectionSpeed: DetectionSpeed.noDuplicates,
  );

  final _manual = TextEditingController();
  bool _ocupado = false;
  bool _linterna = false;
  String? _error;

  @override
  void dispose() {
    _manual.dispose();
    _camara.dispose();
    super.dispose();
  }

  Future<void> _procesar(String codigo) async {
    final limpio = codigo.trim();
    if (_ocupado || limpio.isEmpty) return;

    // Confirma en la mano que la cámara leyó: con guantes y a pleno sol, el
    // cambio de texto en pantalla no siempre se ve.
    HapticFeedback.selectionClick();
    setState(() {
      _ocupado = true;
      _error = null;
    });

    final error = await widget.alLeer(limpio);

    // Si salió bien, quien implementó `alLeer` ya navegó: este widget puede
    // estar desmontado y tocar su estado reventaría.
    if (!mounted) return;
    if (error != null) {
      await _rearmar();
      if (!mounted) return;
    }
    setState(() {
      _ocupado = false;
      _error = error;
    });
  }

  /// Reinicia la cámara después de un código que no se pudo resolver.
  ///
  /// `DetectionSpeed.noDuplicates` recuerda el último código leído y lo ignora
  /// mientras se siga viendo el mismo, y esa memoria solo se limpia al arrancar
  /// la cámara. Sin este reinicio, un código que falló una vez —un material que
  /// todavía no está en el catálogo, una credencial renovada— no se puede
  /// volver a intentar: se vuelve a apuntar, la cámara no reacciona, y en obra
  /// eso se lee como que la app se colgó.
  Future<void> _rearmar() async {
    final linternaEncendida = _linterna;
    try {
      await _camara.stop();
      await _camara.start();
      // La linterna se apaga al reiniciar la cámara. Si estaba encendida es
      // porque hay poca luz, que es justamente cuando falla la lectura.
      if (linternaEncendida) await _camara.toggleTorch();
    } on MobileScannerException {
      // La cámara no está disponible: el `errorBuilder` ya lo dice en pantalla
      // y el ingreso manual de abajo sigue funcionando.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.titulo),
        actions: [
          IconButton(
            tooltip: _linterna ? 'Apagar la linterna' : 'Encender la linterna',
            icon: Icon(_linterna ? Icons.flashlight_on : Icons.flashlight_off),
            onPressed: () async {
              await _camara.toggleTorch();
              if (mounted) setState(() => _linterna = !_linterna);
            },
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(child: _camaraConMarco()),
            if (_error != null) _BandaDeError(mensaje: _error!),
            _IngresoManual(
              controlador: _manual,
              etiqueta: widget.etiquetaManual,
              ayuda: widget.ayudaManual,
              habilitado: !_ocupado,
              alBuscar: () => _procesar(_manual.text),
            ),
          ],
        ),
      ),
    );
  }

  Widget _camaraConMarco() {
    return LayoutBuilder(
      builder: (context, restricciones) {
        // El recuadro es cuadrado y ocupa el 70 % del lado corto: apuntar a un
        // código pequeño con toda la pantalla activa hace que la cámara lea
        // cualquier cosa que ande cerca.
        final lado = restricciones.biggest.shortestSide * 0.7;
        final ventana = Rect.fromCenter(
          center: restricciones.biggest.center(Offset.zero),
          width: lado,
          height: lado,
        );

        return Stack(
          fit: StackFit.expand,
          children: [
            MobileScanner(
              controller: _camara,
              scanWindow: ventana,
              errorBuilder: (context, error) => _SinCamara(error: error),
              onDetect: (captura) {
                final codigo = captura.barcodes
                    .map((b) => b.rawValue)
                    .firstWhere(
                      (v) => v != null && v.isNotEmpty,
                      orElse: () => null,
                    );
                if (codigo != null) _procesar(codigo);
              },
            ),
            IgnorePointer(
              child: CustomPaint(painter: _MarcoDeEscaneo(ventana: ventana)),
            ),
            Positioned(
              left: 20,
              right: 20,
              bottom: 24,
              child: Semantics(
                liveRegion: true,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 11,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceDark.withValues(alpha: 0.88),
                    borderRadius: AppForma.borde,
                  ),
                  child: Row(
                    children: [
                      if (_ocupado) ...[
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 12),
                      ],
                      Expanded(
                        child: Text(
                          _ocupado ? 'Buscando…' : widget.instruccion,
                          style: const TextStyle(
                            fontSize: 13,
                            height: 1.35,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// El recuadro de puntería: oscurece todo menos la ventana de lectura.
class _MarcoDeEscaneo extends CustomPainter {
  const _MarcoDeEscaneo({required this.ventana});

  final Rect ventana;

  @override
  void paint(Canvas lienzo, Size tamano) {
    // La ventana lleva el radio del sistema: es la única forma de la
    // pantalla, y recta se veía ajena al resto de la app.
    final ventanaRedonda = RRect.fromRectAndRadius(
      ventana,
      const Radius.circular(AppForma.radio),
    );
    final fuera = Path()
      ..addRect(Rect.fromLTWH(0, 0, tamano.width, tamano.height))
      ..addRRect(ventanaRedonda)
      ..fillType = PathFillType.evenOdd;
    lienzo.drawPath(
      fuera,
      Paint()..color = Colors.black.withValues(alpha: 0.55),
    );

    lienzo.drawRRect(
      ventanaRedonda,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = AppColors.accent,
    );
  }

  @override
  bool shouldRepaint(_MarcoDeEscaneo anterior) => anterior.ventana != ventana;
}

/// Cuando la cámara no se puede usar —permiso denegado, hardware ocupado— la
/// pantalla no se queda en negro: dice qué pasó y deja el ingreso manual, que
/// sigue abajo.
class _SinCamara extends StatelessWidget {
  const _SinCamara({required this.error});

  final MobileScannerException error;

  @override
  Widget build(BuildContext context) {
    final mensaje = switch (error.errorCode) {
      MobileScannerErrorCode.permissionDenied =>
        'La app no tiene permiso para usar la cámara. Actívalo en los ajustes '
            'de Android, o escribe el código a mano acá abajo.',
      MobileScannerErrorCode.unsupported =>
        'Este teléfono no puede escanear. Escribe el código a mano.',
      _ =>
        'No se pudo abrir la cámara. Escribe el código a mano mientras tanto.',
    };

    return Container(
      color: AppColors.surfaceDark,
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.no_photography_outlined,
              size: 40,
              color: AppColors.textOnDark,
            ),
            const SizedBox(height: 14),
            Text(
              mensaje,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13.5,
                height: 1.45,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BandaDeError extends StatelessWidget {
  const _BandaDeError({required this.mensaje});

  final String mensaje;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        color: AppColors.destructiveTint,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const ExcludeSemantics(
              child: Icon(
                Icons.error_outline,
                size: 19,
                color: AppColors.destructiveDark,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                mensaje,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  color: AppColors.destructiveDark,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IngresoManual extends StatelessWidget {
  const _IngresoManual({
    required this.controlador,
    required this.etiqueta,
    required this.ayuda,
    required this.habilitado,
    required this.alBuscar,
  });

  final TextEditingController controlador;
  final String etiqueta;
  final String? ayuda;
  final bool habilitado;
  final VoidCallback alBuscar;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.card,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: CampoConEtiqueta(
        etiqueta: etiqueta,
        campo: CampoTexto(
          controlador: controlador,
          hint: 'Escríbelo si no se deja escanear',
          icono: Icons.keyboard_alt_outlined,
          mono: true,
          habilitado: habilitado,
          alEnviar: (_) => alBuscar(),
          sufijo: IconButton(
            tooltip: 'Buscar el código escrito',
            icon: const Icon(Icons.arrow_forward, size: 20),
            color: AppColors.accentFill,
            onPressed: habilitado ? alBuscar : null,
          ),
        ),
        ayuda: ayuda,
      ),
    );
  }
}
