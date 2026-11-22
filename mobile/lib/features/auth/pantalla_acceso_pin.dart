import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/errores.dart';
import '../../core/politica_clave.dart';
import '../../core/storage/sesion_storage.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_forma.dart';
import '../../shared_widgets/panel.dart';
import '../../shared_widgets/presion.dart';
import 'sesion_controller.dart';

/// Acceso rápido con PIN para el usuario que el teléfono ya recuerda.
///
/// El teclado es propio, no el del sistema: teclas grandes que se aciertan
/// con guantes, y así el PIN nunca pasa por el teclado predictivo de Android.
class PantallaAccesoPin extends ConsumerStatefulWidget {
  const PantallaAccesoPin({super.key});

  @override
  ConsumerState<PantallaAccesoPin> createState() => _PantallaAccesoPinState();
}

class _PantallaAccesoPinState extends ConsumerState<PantallaAccesoPin> {
  String _pin = '';

  Future<void> _tecla(String d, UsuarioRecordado usuario) async {
    if (_pin.length >= 4) return;
    setState(() => _pin += d);
    if (_pin.length == 4) {
      // Pequeña pausa para que se vea el cuarto punto antes de validar.
      await Future<void>.delayed(const Duration(milliseconds: 120));
      if (!mounted) return;
      await ref
          .read(sesionProvider.notifier)
          .entrarConPin(
            usuarioId: usuario.usuarioId,
            empresaId: usuario.empresaId,
            pin: _pin,
          );
      // Si falló, se limpia para reintentar.
      if (mounted && ref.read(sesionProvider).hasError) {
        setState(() => _pin = '');
      }
    }
  }

  void _borrar() {
    if (_pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    final sesion = ref.watch(sesionProvider);
    final recordadoAsync = ref.watch(usuarioRecordadoProvider);

    // Sin `AppBar`, Android pinta su propio fondo bajo la barra de estado y
    // quedaba una franja más oscura sobre el marco. Transparente y con íconos
    // claros, el marco llega hasta arriba.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
      ),
      child: Scaffold(
        backgroundColor: AppColors.surfaceDark,
        body: recordadoAsync.when(
          loading: () => const Center(
            child: CircularProgressIndicator(color: Colors.white),
          ),
          error: (e, _) => Center(
            child: Text(
              mensajeDeError(e),
              style: const TextStyle(color: Colors.white),
            ),
          ),
          data: (usuario) {
            if (usuario == null || !PoliticaClave.esPin(usuario.rol)) {
              // Sin usuario recordado, o con uno que no es trabajador (el
              // backend solo acepta `login-pin` para ese rol), no hay a quién
              // autenticar por PIN: se vuelve.
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) Navigator.of(context).maybePop();
              });
              return const SizedBox.shrink();
            }
            return Column(
              children: [
                _Encabezado(usuario: usuario),
                Expanded(
                  child: Container(
                    width: double.infinity,
                    clipBehavior: Clip.antiAlias,
                    decoration: const BoxDecoration(
                      color: AppColors.card,
                      borderRadius: AppForma.bordeHoja,
                    ),
                    child: SafeArea(
                      top: false,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(
                          AppEspacio.lg,
                          AppEspacio.xl,
                          AppEspacio.lg,
                          AppEspacio.lg,
                        ),
                        child: Column(
                          children: [
                            _Titulo(
                              error: sesion.hasError
                                  ? mensajeDeError(sesion.error!)
                                  : null,
                              cargando: sesion.isLoading,
                            ),
                            const SizedBox(height: AppEspacio.md + 4),
                            _Puntos(
                              cantidad: _pin.length,
                              error: sesion.hasError,
                            ),
                            const SizedBox(height: AppEspacio.xl),
                            _Teclado(
                              habilitado: !sesion.isLoading,
                              alPulsar: (d) => _tecla(d, usuario),
                              alLimpiar: () => setState(() => _pin = ''),
                              alBorrar: _borrar,
                            ),
                            const SizedBox(height: AppEspacio.lg),
                            const Panel(
                              color: AppColors.background,
                              padding: EdgeInsets.all(AppEspacio.md),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    Icons.lock_outline,
                                    size: 19,
                                    color: AppColors.secondary,
                                  ),
                                  SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      'El PIN no se guarda en el teléfono. Si lo '
                                      'olvidaste, lo restablece el administrador '
                                      'de la empresa.',
                                      style: TextStyle(
                                        fontSize: 13,
                                        height: 1.45,
                                        color: AppColors.textMuted,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Encabezado extends ConsumerWidget {
  const _Encabezado({required this.usuario});

  final UsuarioRecordado usuario;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 16, 20),
        child: Column(
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: 'Volver al acceso con correo',
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
                const Expanded(
                  child: Text(
                    'Acceso con PIN',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Panel(
                color: AppColors.surfaceDark,
                borderColor: AppColors.borderOnDark,
                padding: const EdgeInsets.all(AppEspacio.md),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: const BoxDecoration(
                        color: AppColors.borderOnDark,
                        borderRadius: AppForma.borde,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        Iniciales.de(usuario.nombre),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            usuario.nombre,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            nombreDeRol(usuario.rol),
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.textOnDarkMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: () async {
                        await ref
                            .read(sesionProvider.notifier)
                            .cambiarDeUsuario();
                        if (context.mounted) Navigator.of(context).maybePop();
                      },
                      child: const Text(
                        'Cambiar',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.accentOnDark,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Titulo extends StatelessWidget {
  const _Titulo({this.error, required this.cargando});

  final String? error;
  final bool cargando;

  @override
  Widget build(BuildContext context) {
    // Este texto es el único aviso de que el PIN falló: el teclado no cambia
    // y los puntos solo se vacían. `liveRegion` hace que se anuncie al pasar
    // de "Verificando…" a un error, en vez de cambiar en silencio.
    return Semantics(
      liveRegion: true,
      child: cargando
          ? const Text(
              'Verificando…',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.textMuted,
              ),
            )
          : Text(
              error ?? 'Ingresa tu PIN de 4 dígitos',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: error != null
                    ? AppColors.destructiveDark
                    : AppColors.primary,
              ),
            ),
    );
  }
}

class _Puntos extends StatelessWidget {
  const _Puntos({required this.cantidad, required this.error});

  final int cantidad;
  final bool error;

  @override
  Widget build(BuildContext context) {
    // Cuántos dígitos van es la única confirmación de que la tecla registró.
    // Es información gráfica pura, así que se dice en palabras y se anuncia
    // en cuanto cambia.
    return Semantics(
      liveRegion: true,
      label: '$cantidad de 4 dígitos ingresados',
      excludeSemantics: true,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(4, (i) {
          final lleno = i < cantidad;
          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 7),
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: lleno
                  ? (error ? AppColors.destructive : AppColors.primary)
                  : Colors.white,
              // El borde es lo único que dibuja un punto vacío: con el gris
              // anterior medía 1.5:1 sobre blanco y sencillamente no se veía
              // a pleno sol.
              border: Border.all(
                color: error ? AppColors.destructive : AppColors.borderControl,
                width: 2,
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _Teclado extends StatelessWidget {
  const _Teclado({
    required this.habilitado,
    required this.alPulsar,
    required this.alLimpiar,
    required this.alBorrar,
  });

  final bool habilitado;
  final void Function(String) alPulsar;
  final VoidCallback alLimpiar;
  final VoidCallback alBorrar;

  @override
  Widget build(BuildContext context) {
    // Las celdas tienen proporción fija (`childAspectRatio`), así que un
    // dígito a 25 px con el texto del sistema al 200 % no cabe. Se topa el
    // escalado del teclado en 1.4 — las teclas ya son grandes por diseño, lo
    // que este tope protege es que el "LIMPIAR" no desborde su celda.
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.4,
      child: GridView.count(
        crossAxisCount: 3,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        // Teclas de ~62 px de alto: muy por encima del mínimo de 44 px.
        childAspectRatio: 1.6,
        children: [
          for (final d in ['1', '2', '3', '4', '5', '6', '7', '8', '9'])
            _Tecla(
              semanticLabel: d,
              onTap: habilitado ? () => alPulsar(d) : null,
              child: Text(
                d,
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w500,
                  letterSpacing: -0.3,
                  color: AppColors.primary,
                ),
              ),
            ),
          _Tecla(
            semanticLabel: 'Limpiar el PIN',
            conFondo: false,
            onTap: habilitado ? alLimpiar : null,
            child: const Text(
              'Limpiar',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textMuted,
              ),
            ),
          ),
          _Tecla(
            semanticLabel: '0',
            onTap: habilitado ? () => alPulsar('0') : null,
            child: const Text(
              '0',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w500,
                letterSpacing: -0.3,
                color: AppColors.primary,
              ),
            ),
          ),
          _Tecla(
            // Tecla solo de ícono: sin esta etiqueta se anuncia como "botón".
            semanticLabel: 'Borrar el último dígito',
            conFondo: false,
            onTap: habilitado ? alBorrar : null,
            child: const Icon(
              Icons.backspace_outlined,
              size: 24,
              color: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class _Tecla extends StatelessWidget {
  const _Tecla({
    required this.child,
    required this.semanticLabel,
    this.onTap,
    this.conFondo = true,
  });

  final Widget child;

  /// Lo que anuncia el lector de pantalla al enfocar la tecla.
  final String semanticLabel;

  final VoidCallback? onTap;
  final bool conFondo;

  @override
  Widget build(BuildContext context) {
    // El `Material` va afuera y pone el color; el `Container` de adentro solo
    // dibuja el borde. Al revés —que es como estaba— el fondo opaco del
    // `Container` tapa el splash del `InkWell` y la tecla no acusa recibo:
    // se aprieta y no pasa nada. Con guantes y sin respuesta visible, se
    // aprieta de nuevo, y el PIN termina con un dígito de más.
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: semanticLabel,
      excludeSemantics: true,
      child: Presionable(
        habilitado: onTap != null,
        child: Material(
          color: conFondo ? AppColors.background : Colors.transparent,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: AppForma.borde,
            side: conFondo
                ? const BorderSide(color: AppColors.borderControl)
                : BorderSide.none,
          ),
          child: InkWell(
            // Un pulso por tecla: con guantes, es la confirmación de que el
            // dígito entró aunque no se mire la fila de puntos.
            onTap: onTap == null
                ? null
                : () {
                    HapticFeedback.selectionClick();
                    onTap!();
                  },
            child: Center(child: child),
          ),
        ),
      ),
    );
  }
}
