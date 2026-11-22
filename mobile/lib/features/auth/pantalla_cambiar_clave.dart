import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/errores.dart';
import '../../core/politica_clave.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../data/api/auth_api.dart';
import '../../shared_widgets/campo_texto.dart';
import '../../shared_widgets/estados.dart';
import '../../shared_widgets/presion.dart';
import 'sesion_controller.dart';

/// Lo único que puede hacer una cuenta con clave provisoria: cambiarla.
///
/// El servidor rechaza todo lo demás con 403 `DEBE_CAMBIAR_PIN`, así que no hay
/// "omitir": sin cambiarla no hay app que mostrar. Quien no quiere hacerlo
/// ahora puede cerrar la sesión.
class PantallaCambiarClave extends ConsumerStatefulWidget {
  const PantallaCambiarClave({super.key, required this.sesion});

  final SesionUsuario sesion;

  @override
  ConsumerState<PantallaCambiarClave> createState() =>
      _PantallaCambiarClaveState();
}

class _PantallaCambiarClaveState extends ConsumerState<PantallaCambiarClave> {
  final _formulario = GlobalKey<FormState>();
  final _actual = TextEditingController();
  final _nueva = TextEditingController();
  final _repetida = TextEditingController();

  bool _enviando = false;
  String? _error;

  String get _rol => widget.sesion.rol;
  String get _que => PoliticaClave.etiqueta(_rol);

  @override
  void dispose() {
    _actual.dispose();
    _nueva.dispose();
    _repetida.dispose();
    super.dispose();
  }

  Future<void> _cambiar() async {
    if (_enviando) return;
    if (!(_formulario.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _enviando = true;
      _error = null;
    });
    try {
      // Si sale bien, la sesión nueva reemplaza a esta y la raíz muestra la
      // app: esta pantalla desaparece sola.
      await ref
          .read(sesionProvider.notifier)
          .cambiarClave(claveActual: _actual.text, claveNueva: _nueva.text);
      if (mounted) HapticFeedback.mediumImpact();
    } catch (e) {
      if (mounted) setState(() => _error = mensajeDeError(e));
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // No hay a dónde volver: es la raíz mientras la clave sea provisoria.
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: Text('Cambia tu $_que'),
          actions: [
            TextButton(
              onPressed: _enviando
                  ? null
                  : () => ref.read(sesionProvider.notifier).salir(),
              child: const Text('Cerrar sesión'),
            ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: Form(
            key: _formulario,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'Hola, ${widget.sesion.nombre}. Tu cuenta tiene una $_que '
                  'provisoria: quien la creó la conoce. Define una propia para '
                  'seguir; hasta entonces no puedes usar la app.',
                  style: AppTexto.cuerpoChico.copyWith(
                    color: AppColors.textMuted,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 20),
                CampoConEtiqueta(
                  etiqueta: 'Tu $_que actual',
                  campo: CampoTexto(
                    controlador: _actual,
                    hint: 'La provisoria',
                    icono: Icons.lock_outline,
                    mono: true,
                    oculto: true,
                    maxLength: PoliticaClave.maximoClave,
                    teclado: TextInputType.visiblePassword,
                    habilitado: !_enviando,
                    validador: (v) =>
                        (v == null || v.isEmpty) ? 'Escribe la actual' : null,
                  ),
                ),
                const SizedBox(height: 16),
                CampoConEtiqueta(
                  etiqueta: 'Nueva $_que',
                  campo: CampoTexto(
                    controlador: _nueva,
                    hint: PoliticaClave.esPin(_rol)
                        ? '••••'
                        : 'Mínimo ${PoliticaClave.minimoClave} caracteres',
                    icono: Icons.lock_reset,
                    mono: true,
                    oculto: true,
                    maxLength: PoliticaClave.esPin(_rol)
                        ? PoliticaClave.largoPin
                        : PoliticaClave.maximoClave,
                    teclado: PoliticaClave.esPin(_rol)
                        ? TextInputType.number
                        : TextInputType.visiblePassword,
                    formatters: PoliticaClave.esPin(_rol)
                        ? [FilteringTextInputFormatter.digitsOnly]
                        : null,
                    habilitado: !_enviando,
                    validador: (v) {
                      final clave = v ?? '';
                      return PoliticaClave.error(clave, rol: _rol) ??
                          (clave == _actual.text
                              ? 'Elige una distinta de la actual'
                              : null);
                    },
                  ),
                  ayuda: PoliticaClave.esPin(_rol)
                      ? 'Son 4 dígitos.'
                      : 'De ${PoliticaClave.minimoClave} a '
                            '${PoliticaClave.maximoClave} caracteres. Una frase '
                            'larga es más segura y más fácil de recordar que una '
                            'palabra rara.',
                ),
                const SizedBox(height: 16),
                CampoConEtiqueta(
                  etiqueta: 'Repite la nueva $_que',
                  campo: CampoTexto(
                    controlador: _repetida,
                    hint: 'Otra vez',
                    icono: Icons.check,
                    mono: true,
                    oculto: true,
                    maxLength: PoliticaClave.maximoClave,
                    teclado: PoliticaClave.esPin(_rol)
                        ? TextInputType.number
                        : TextInputType.visiblePassword,
                    habilitado: !_enviando,
                    validador: (v) =>
                        v == _nueva.text ? null : 'No coincide con la nueva',
                    alEnviar: (_) => _cambiar(),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  MensajeError(mensaje: _error!),
                ],
                const SizedBox(height: 22),
                BotonEnvio(
                  texto: 'Cambiar $_que',
                  textoEnviando: 'Cambiando…',
                  enviando: _enviando,
                  alPresionar: _cambiar,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
