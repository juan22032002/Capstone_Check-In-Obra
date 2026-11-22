import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/movimiento.dart';

/// Hunde levemente lo que se está apretando.
///
/// El splash de Material se pierde con guantes y a pleno sol: el dedo tapa
/// justo el punto donde nace. Una escala de 0,97 sobre todo el control se ve
/// alrededor del dedo y confirma que el toque llegó antes de que llegue la
/// respuesta del servidor — que es lo que evita el segundo toque "por si acaso".
///
/// No intercepta el gesto: escucha el puntero y deja pasar el toque al
/// `InkWell` o botón que envuelve.
class Presionable extends StatefulWidget {
  const Presionable({super.key, required this.child, this.habilitado = true});

  final Widget child;
  final bool habilitado;

  @override
  State<Presionable> createState() => _PresionableState();
}

class _PresionableState extends State<Presionable> {
  bool _apretado = false;

  void _cambiar(bool apretado) {
    if (!widget.habilitado && apretado) return;
    if (_apretado != apretado) setState(() => _apretado = apretado);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => _cambiar(true),
      onPointerUp: (_) => _cambiar(false),
      onPointerCancel: (_) => _cambiar(false),
      child: AnimatedScale(
        scale: _apretado ? Movimiento.escalaPresion : 1,
        duration: Movimiento.de(context, Movimiento.presion),
        curve: Movimiento.salida,
        child: widget.child,
      ),
    );
  }
}

/// El botón que confirma una escritura: registrar, aprobar, prestar, cerrar.
///
/// Reúne lo que cada pantalla hacía a mano y a medias: mientras se envía queda
/// deshabilitado, muestra el progreso junto al verbo en gerundio y lo anuncia
/// al lector de pantalla; el cambio de texto es un fundido corto en vez de un
/// salto. El ancho no cambia entre un estado y otro, así que el botón no
/// "baila" bajo el dedo.
class BotonEnvio extends StatelessWidget {
  const BotonEnvio({
    super.key,
    required this.texto,
    required this.textoEnviando,
    required this.enviando,
    required this.alPresionar,
    this.color,
  });

  final String texto;
  final String textoEnviando;
  final bool enviando;
  final VoidCallback? alPresionar;

  /// Relleno distinto al primario, para acciones destructivas.
  final Color? color;

  Color get _relleno => color ?? AppColors.accentFill;

  @override
  Widget build(BuildContext context) {
    final habilitado = !enviando && alPresionar != null;
    return Semantics(
      liveRegion: enviando,
      child: Presionable(
        habilitado: habilitado,
        child: FilledButton(
          onPressed: habilitado ? alPresionar : null,
          // Deshabilitado por estar enviando, conserva su color: pasar a gris
          // en el mismo instante del toque se lee como un error, no como
          // "recibido". Deshabilitado por otra razón, sí se apaga.
          style: FilledButton.styleFrom(
            backgroundColor: _relleno,
            disabledBackgroundColor: enviando ? _relleno : null,
            disabledForegroundColor: enviando ? Colors.white : null,
          ),
          child: AnimatedSwitcher(
            duration: Movimiento.de(context, Movimiento.estado),
            switchInCurve: Movimiento.salida,
            switchOutCurve: Movimiento.salida,
            child: enviando
                ? Row(
                    key: const ValueKey('enviando'),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(textoEnviando),
                    ],
                  )
                : Text(texto, key: const ValueKey('listo')),
          ),
        ),
      ),
    );
  }
}
