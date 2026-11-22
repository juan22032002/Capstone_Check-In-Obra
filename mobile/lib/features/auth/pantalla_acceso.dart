import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/errores.dart';
import '../../core/politica_clave.dart';
import '../../core/storage/sesion_storage.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_forma.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/movimiento.dart';
import '../../data/api/auth_api.dart';
import '../../shared_widgets/panel.dart';
import '../../shared_widgets/presion.dart';
import 'pantalla_acceso_pin.dart';
import 'sesion_controller.dart';

/// La puerta de entrada, con dos caras.
///
/// **Si el teléfono recuerda a alguien**, esa persona es la pantalla: su nombre
/// en el saludo, su tarjeta y un solo botón para entrar con el PIN. Es el caso
/// de todos los días en obra —el mismo bodeguero, el mismo teléfono— y antes
/// quedaba enterrado bajo un formulario de correo que esa persona nunca usa.
///
/// **Si no recuerda a nadie**, o si se pide "Usar otro correo", aparece el
/// formulario de correo + PIN, que es la vía de administradores y jefes de
/// terreno.
///
/// Nota sobre el diseño: el mockup rotula el segundo campo como "Contraseña",
/// pero `Usuario` no tiene contraseña —solo `pinHash`—. Se rotula "PIN" para
/// que coincida con lo que el backend realmente valida.
class PantallaAcceso extends ConsumerStatefulWidget {
  const PantallaAcceso({super.key});

  @override
  ConsumerState<PantallaAcceso> createState() => _PantallaAccesoState();
}

class _PantallaAccesoState extends ConsumerState<PantallaAcceso> {
  final _email = TextEditingController();
  final _pin = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _ocultarPin = true;

  /// Hay alguien recordado, pero se eligió entrar con otro correo.
  bool _usarCorreo = false;

  @override
  void dispose() {
    _email.dispose();
    _pin.dispose();
    super.dispose();
  }

  Future<void> _entrar() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    await ref
        .read(sesionProvider.notifier)
        .entrarConCorreo(email: _email.text, pin: _pin.text);
  }

  void _irAlPin() =>
      Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const PantallaAccesoPin()));

  @override
  Widget build(BuildContext context) {
    final sesion = ref.watch(sesionProvider);
    final aviso = ref.watch(avisoDeAccesoProvider);
    final recordado = ref.watch(usuarioRecordadoProvider).valueOrNull;
    // El acceso rápido por PIN es solo del TRABAJADOR: el backend rechaza
    // `login-pin` para los demás roles, que entran con correo y clave.
    final conPin =
        recordado != null && PoliticaClave.esPin(recordado.rol) && !_usarCorreo;
    final duracion = Movimiento.de(context, Movimiento.estado);

    final Widget cuerpo = conPin
        ? _PanelRecordado(
            key: const ValueKey('recordado'),
            recordado: recordado,
            alEntrar: _irAlPin,
            alUsarCorreo: () => setState(() => _usarCorreo = true),
            alOlvidar: () =>
                ref.read(sesionProvider.notifier).cambiarDeUsuario(),
          )
        : _formulario(sesion, recordado);

    // Sin `AppBar`, Android pinta su propio fondo bajo la barra de estado y
    // quedaba una franja más oscura sobre el marco. Transparente y con íconos
    // claros, el marco llega hasta arriba.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
      ),
      // En la cara del correo, "atrás" vuelve a la del PIN en vez de cerrar
      // la app: se llegó ahí desde "Usar otro correo" y es lo que se espera.
      child: PopScope(
        canPop: !_usarCorreo || recordado == null,
        onPopInvokedWithResult: (salio, _) {
          if (!salio) setState(() => _usarCorreo = false);
        },
        child: Scaffold(
          backgroundColor: AppColors.surfaceDark,
          body: Column(
            children: [
              _Encabezado(
                nombre: conPin ? _primerNombre(recordado.nombre) : null,
                duracion: duracion,
              ),
              // La hoja blanca sube sobre el marco oscuro, con el mismo radio que
              // el resto de las superficies, solo arriba.
              Expanded(
                child: Container(
                  width: double.infinity,
                  clipBehavior: Clip.antiAlias,
                  decoration: const BoxDecoration(
                    color: AppColors.card,
                    borderRadius: AppForma.bordeHoja,
                  ),
                  // `bottom` sí: el último elemento quedaba bajo la barra de
                  // gestos en los teléfonos sin botones físicos.
                  child: SafeArea(
                    top: false,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(
                        AppEspacio.lg,
                        AppEspacio.xl,
                        AppEspacio.lg,
                        AppEspacio.lg,
                      ),
                      // Cambiar de cara es un fundido corto: sin él, el formulario
                      // aparece de golpe en el lugar de la tarjeta y parece otra
                      // pantalla.
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Por qué se llegó acá (hoy: la empresa quedó
                          // suspendida). Se queda hasta que se descarta o se
                          // entra.
                          if (aviso != null) ...[
                            _AvisoDeAcceso(
                              mensaje: aviso,
                              alDescartar: () =>
                                  ref
                                          .read(avisoDeAccesoProvider.notifier)
                                          .state =
                                      null,
                            ),
                            const SizedBox(height: AppEspacio.md),
                          ],
                          AnimatedSwitcher(
                            duration: duracion,
                            switchInCurve: Movimiento.salida,
                            switchOutCurve: Movimiento.salida,
                            layoutBuilder: (actual, anteriores) => Stack(
                              alignment: Alignment.topCenter,
                              children: [...anteriores, ?actual],
                            ),
                            child: cuerpo,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _formulario(
    AsyncValue<SesionUsuario?> sesion,
    UsuarioRecordado? recordado,
  ) {
    return Form(
      key: _formKey,
      child: Column(
        key: const ValueKey('correo'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Correo de empresa', style: AppTexto.rotulo),
          const SizedBox(height: AppEspacio.sm),
          _CampoTexto(
            controlador: _email,
            hint: 'nombre@empresa.cl',
            icono: Icons.mail_outline,
            teclado: TextInputType.emailAddress,
            autofill: const [AutofillHints.email],
            // Si se llegó desde "Usar otro correo", el siguiente paso es
            // escribirlo: no hace falta tocar el campo primero.
            autofocus: _usarCorreo,
            validador: (v) => (v == null || !v.contains('@'))
                ? 'Escribe un correo válido'
                : null,
          ),
          const SizedBox(height: AppEspacio.md + 4),
          const Text('PIN o clave', style: AppTexto.rotulo),
          const SizedBox(height: AppEspacio.sm),
          _CampoTexto(
            controlador: _pin,
            hint: 'Tu clave',
            icono: Icons.lock_outline,
            // Texto y no solo dígitos: administradores, jefes y bodegueros
            // entran con una clave de 8 a 72 caracteres. El trabajador que
            // use este formulario sigue tecleando su PIN de 4 dígitos.
            teclado: TextInputType.visiblePassword,
            oculto: _ocultarPin,
            mono: true,
            maxLength: PoliticaClave.maximoClave,
            // Un botón que es solo un ícono no se anuncia solo: sin `tooltip`,
            // el lector de pantalla lo lee como "botón" a secas. El texto
            // cambia con el estado, para que se sepa qué va a pasar al tocarlo.
            sufijo: IconButton(
              tooltip: _ocultarPin ? 'Mostrar la clave' : 'Ocultar la clave',
              icon: Icon(
                _ocultarPin
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                size: 20,
                color: AppColors.secondary,
              ),
              onPressed: () => setState(() => _ocultarPin = !_ocultarPin),
            ),
            validador: (v) => PoliticaClave.errorAlEntrar(v ?? ''),
            alEnviar: (_) => _entrar(),
          ),
          if (sesion.hasError) ...[
            const SizedBox(height: AppEspacio.md),
            _Error(mensaje: mensajeDeError(sesion.error!)),
          ],
          const SizedBox(height: AppEspacio.lg),
          // Mientras carga se mantiene el texto junto al giro: un botón que se
          // queda solo con un spinner pierde su nombre, y quien mira ya no
          // sabe qué se está haciendo.
          BotonEnvio(
            texto: 'Entrar',
            textoEnviando: 'Entrando…',
            enviando: sesion.isLoading,
            alPresionar: _entrar,
          ),
          const SizedBox(height: AppEspacio.lg),
          Text(
            'Administradores, jefes de terreno y bodegueros entran con su correo '
            'y su clave. Solo el trabajador entra con PIN: el teléfono lo '
            'recuerda y el PIN nunca sale del equipo.',
            style: AppTexto.cuerpoChico.copyWith(color: AppColors.secondary),
          ),
          if (recordado != null && PoliticaClave.esPin(recordado.rol)) ...[
            const SizedBox(height: AppEspacio.md),
            Align(
              alignment: Alignment.centerLeft,
              child: _Enlace(
                icono: Icons.arrow_back,
                texto:
                    'Volver a entrar como ${_primerNombre(recordado.nombre)}',
                alTocar: () => setState(() => _usarCorreo = false),
              ),
            ),
          ],
          const SizedBox(height: AppEspacio.lg),
          const _Version(),
        ],
      ),
    );
  }
}

String _primerNombre(String nombre) {
  final partes = nombre.trim().split(RegExp(r'\s+'));
  return partes.isEmpty || partes.first.isEmpty ? nombre : partes.first;
}

/// El marco oscuro: logo y el saludo, que dice en qué cara se está.
class _Encabezado extends StatelessWidget {
  const _Encabezado({required this.nombre, required this.duracion});

  /// Primer nombre de quien el teléfono recuerda; `null` en el formulario de
  /// correo.
  final String? nombre;
  final Duration duracion;

  @override
  Widget build(BuildContext context) {
    final saludo = nombre;
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppEspacio.lg,
          AppEspacio.lg,
          AppEspacio.lg,
          AppEspacio.xl,
        ),
        child: SizedBox(
          width: double.infinity,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Image.asset(
                'assets/images/logo.png',
                height: 64,
                // El PNG ya trae el nombre bajo el isotipo, así que no lleva
                // texto al lado. El `semanticLabel` cubre a los lectores de
                // pantalla.
                semanticLabel: 'Check-In Obra',
              ),
              const SizedBox(height: AppEspacio.xl),
              AnimatedSwitcher(
                duration: duracion,
                switchInCurve: Movimiento.salida,
                switchOutCurve: Movimiento.salida,
                layoutBuilder: (actual, anteriores) => Stack(
                  alignment: Alignment.topLeft,
                  children: [...anteriores, ?actual],
                ),
                child: saludo != null
                    ? _Saludo(
                        key: const ValueKey('saludo'),
                        arriba: 'Hola de nuevo,',
                        grande: saludo,
                      )
                    : const _Saludo(
                        key: ValueKey('correo'),
                        arriba: 'Con el correo de tu empresa',
                        grande: 'Inicia sesión',
                        arribaDebajo: true,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Dos líneas: una chica y una grande. En la cara del PIN la chica va arriba
/// ("Hola de nuevo," / "Jorge"); en la del correo va abajo, como bajada.
class _Saludo extends StatelessWidget {
  const _Saludo({
    super.key,
    required this.arriba,
    required this.grande,
    this.arribaDebajo = false,
  });

  final String arriba;
  final String grande;
  final bool arribaDebajo;

  @override
  Widget build(BuildContext context) {
    final chica = Text(
      arriba,
      style: const TextStyle(
        fontSize: 16,
        height: 1.35,
        letterSpacing: -0.15,
        color: AppColors.textOnDark,
      ),
    );
    final principal = Semantics(
      header: true,
      child: Text(
        grande,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 32,
          height: 1.15,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.8,
          color: Colors.white,
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: arribaDebajo
          ? [principal, const SizedBox(height: AppEspacio.xs), chica]
          : [chica, const SizedBox(height: AppEspacio.xs), principal],
    );
  }
}

/// La cara del día a día: quién es, y entrar.
class _PanelRecordado extends StatelessWidget {
  const _PanelRecordado({
    super.key,
    required this.recordado,
    required this.alEntrar,
    required this.alUsarCorreo,
    required this.alOlvidar,
  });

  final UsuarioRecordado recordado;
  final VoidCallback alEntrar;
  final VoidCallback alUsarCorreo;
  final VoidCallback alOlvidar;

  @override
  Widget build(BuildContext context) {
    final nombre = _primerNombre(recordado.nombre);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MergeSemantics(
          child: Row(
            children: [
              Iniciales(recordado.nombre, tamano: 56),
              const SizedBox(width: AppEspacio.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      recordado.nombre,
                      style: AppTexto.subtitulo.copyWith(fontSize: 18),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      nombreDeRol(recordado.rol),
                      style: AppTexto.cuerpoChico.copyWith(
                        fontSize: 14,
                        color: AppColors.secondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppEspacio.lg),
        // El único naranjo de la pantalla: es lo que se viene a hacer.
        Presionable(
          child: FilledButton.icon(
            onPressed: alEntrar,
            icon: const Icon(Icons.dialpad, size: 20),
            label: const Text('Entrar con mi PIN'),
          ),
        ),
        const SizedBox(height: AppEspacio.lg),
        const Divider(),
        const SizedBox(height: AppEspacio.sm),
        Align(
          alignment: Alignment.centerLeft,
          child: _Enlace(
            icono: Icons.mail_outline,
            texto: 'Usar otro correo',
            alTocar: alUsarCorreo,
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: _Enlace(
            icono: Icons.person_off_outlined,
            texto: 'No soy $nombre',
            // Olvidarlo es la salida de un teléfono prestado o heredado: el
            // siguiente en entrar no tiene por qué ver el nombre del anterior.
            alTocar: alOlvidar,
          ),
        ),
        const SizedBox(height: AppEspacio.xl),
        const _Version(),
      ],
    );
  }
}

/// Acción secundaria de la hoja: texto en tinta con su ícono, sin caja. Deja
/// todo el peso visual al botón principal.
class _Enlace extends StatelessWidget {
  const _Enlace({
    required this.icono,
    required this.texto,
    required this.alTocar,
  });

  final IconData icono;
  final String texto;
  final VoidCallback alTocar;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: alTocar,
      icon: Icon(icono, size: 19, color: AppColors.secondary),
      label: Text(texto),
      style: TextButton.styleFrom(
        foregroundColor: AppColors.primary,
        padding: const EdgeInsets.symmetric(horizontal: AppEspacio.sm),
        textStyle: const TextStyle(
          fontFamily: AppTexto.familia,
          fontSize: 15,
          fontWeight: FontWeight.w500,
          letterSpacing: -0.15,
        ),
      ),
    );
  }
}

class _Version extends StatelessWidget {
  const _Version();

  @override
  Widget build(BuildContext context) {
    return Text(
      'Check-In-Obra, versión 1.0',
      textAlign: TextAlign.center,
      style: AppTexto.dato,
    );
  }
}

/// Un aviso fijo sobre el acceso, con la salida de descartarlo.
class _AvisoDeAcceso extends StatelessWidget {
  const _AvisoDeAcceso({required this.mensaje, required this.alDescartar});

  final String mensaje;
  final VoidCallback alDescartar;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Panel(
        color: AppColors.warningTint,
        borderColor: AppColors.warning,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const ExcludeSemantics(
                  child: Icon(
                    Icons.info_outline,
                    size: 20,
                    color: AppColors.warningDark,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    mensaje,
                    style: AppTexto.cuerpoChico.copyWith(
                      fontSize: 14,
                      color: AppColors.warningInk,
                    ),
                  ),
                ),
              ],
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: alDescartar,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.warningDark,
                ),
                child: const Text('Entendido'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CampoTexto extends StatelessWidget {
  const _CampoTexto({
    required this.controlador,
    required this.hint,
    required this.icono,
    this.teclado,
    this.oculto = false,
    this.mono = false,
    this.maxLength,
    this.sufijo,
    this.validador,
    this.alEnviar,
    this.autofill,
    this.autofocus = false,
  });

  final TextEditingController controlador;
  final String hint;
  final IconData icono;
  final TextInputType? teclado;
  final bool oculto;
  final bool mono;
  final int? maxLength;
  final Widget? sufijo;
  final String? Function(String?)? validador;
  final void Function(String)? alEnviar;
  final Iterable<String>? autofill;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controlador,
      keyboardType: teclado,
      obscureText: oculto,
      maxLength: maxLength,
      validator: validador,
      onFieldSubmitted: alEnviar,
      autofillHints: autofill,
      autofocus: autofocus,
      autocorrect: false,
      enableSuggestions: false,
      style: TextStyle(
        fontSize: 16,
        letterSpacing: mono ? 0 : -0.15,
        fontWeight: mono ? FontWeight.w500 : FontWeight.w400,
        color: AppColors.primary,
      ),
      // Bordes y radio del tema. Sobre la hoja blanca el campo lleva el
      // relleno del lienzo, que lo separa sin depender solo del contorno.
      decoration: InputDecoration(
        hintText: hint,
        counterText: '',
        prefixIcon: Padding(
          padding: const EdgeInsets.only(left: 14, right: 10),
          child: Icon(icono, size: 20, color: AppColors.secondary),
        ),
        prefixIconConstraints: const BoxConstraints(
          minWidth: 44,
          minHeight: 44,
        ),
        suffixIcon: sufijo,
        fillColor: AppColors.background,
      ),
    );
  }
}

class _Error extends StatelessWidget {
  const _Error({required this.mensaje});

  final String mensaje;

  @override
  Widget build(BuildContext context) {
    // `liveRegion` hace que el lector de pantalla lea el mensaje en cuanto
    // aparece. Sin esto el error se dibuja en silencio: quien no lo ve se
    // queda esperando a que el botón haga algo.
    return Semantics(
      liveRegion: true,
      child: Panel(
        color: AppColors.destructiveTint,
        borderColor: AppColors.destructive,
        padding: const EdgeInsets.all(AppEspacio.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const ExcludeSemantics(
              child: Icon(
                Icons.error_outline,
                size: 20,
                color: AppColors.destructiveDark,
              ),
            ),
            const SizedBox(width: AppEspacio.sm + 4),
            Expanded(
              child: Text(
                mensaje,
                style: AppTexto.cuerpoChico.copyWith(
                  fontSize: 14,
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
