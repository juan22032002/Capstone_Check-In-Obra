import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/formato.dart';
import '../../core/network/errores.dart';
import '../../core/network/idempotencia.dart';
import '../../core/pantalla.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_forma.dart';
import '../../core/theme/app_theme.dart';
import '../../data/api/dominio_api.dart';
import '../../data/modelos/perfil_trabajador.dart';
import '../../shared_widgets/estados.dart';
import '../../shared_widgets/panel.dart';
import 'trabajador_providers.dart';

/// La credencial que se muestra en el mesón de bodega.
///
/// Es lo único de esta app que se usa con el teléfono en la mano de otra
/// persona —el bodeguero lo escanea—, así que el QR ocupa el ancho entero, va
/// sobre blanco puro con su margen de silencio y nada se le superpone. Debajo
/// van nombre y RUT en grande, para que el bodeguero confirme de un vistazo
/// que la cara coincide con la credencial.
class PantallaCredencial extends ConsumerWidget {
  const PantallaCredencial({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final perfil = ref.watch(perfilTrabajadorProvider);

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(perfilTrabajadorProvider);
        await ref.read(perfilTrabajadorProvider.future);
      },
      child: ListView(
        padding: AppEspacio.pantalla,
        children: [
          Contenido<PerfilTrabajador>(
            valor: perfil,
            alReintentar: () => ref.invalidate(perfilTrabajadorProvider),
            constructor: (p) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (p.sinConexion) ...[
                  _SinConexion(guardadoEl: p.guardadoEl!),
                  const SizedBox(height: AppEspacio.md),
                ],
                _Tarjeta(perfil: p),
                if (p.credencialQr != null) ...[
                  const SizedBox(height: AppEspacio.md),
                  FilledButton.icon(
                    onPressed: () => mostrarCredencialCompleta(context, p),
                    icon: const Icon(Icons.fullscreen),
                    label: const Text('Mostrar en bodega'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                    ),
                  ),
                ],
                const SizedBox(height: AppEspacio.md),
                Text(
                  'Muéstrala en bodega para retirar lo que pediste o para que '
                  'te presten una herramienta. Se abre a pantalla completa y '
                  'con el brillo al máximo, para que el lector la tome al '
                  'primer intento.',
                  textAlign: TextAlign.center,
                  style: AppTexto.cuerpoChico,
                ),
                const SizedBox(height: AppEspacio.xl),
                // Renovar necesita al servidor: sin conexión solo confundiría.
                if (!p.sinConexion) _Renovar(perfil: p),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Tarjeta extends StatelessWidget {
  const _Tarjeta({required this.perfil});

  final PerfilTrabajador perfil;

  @override
  Widget build(BuildContext context) {
    final p = perfil;
    final codigo = p.credencialQr;

    return Panel(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
      child: Column(
        children: [
          if (codigo == null)
            const _SinCredencial()
          else
            GestureDetector(
              onTap: () => mostrarCredencialCompleta(context, p),
              child: LayoutBuilder(
                // Topado a 300: más grande no se lee mejor y empuja el nombre
                // fuera de la pantalla en un teléfono chico.
                builder: (context, c) => CodigoQr(
                  codigo: codigo,
                  lado: c.maxWidth.clamp(180.0, 300.0),
                ),
              ),
            ),
          const SizedBox(height: AppEspacio.md),
          Text(
            p.nombre,
            textAlign: TextAlign.center,
            style: AppTexto.titulo.copyWith(fontSize: 22),
          ),
          if (p.rut != null) ...[
            const SizedBox(height: 2),
            Text(
              p.rut!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFeatures: AppTexto.tabulares,
                fontSize: 17,
                fontWeight: FontWeight.w500,
                color: AppColors.textMuted,
              ),
            ),
          ],
          const SizedBox(height: AppEspacio.sm + 4),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 6,
            children: [
              if (p.obraNombre != null) ChipEstado.neutro(p.obraNombre!),
              if (p.cuadrillaNombre != null)
                ChipEstado.neutro(p.cuadrillaNombre!),
              if (!p.tieneObra) ChipEstado.aviso('Sin cuadrilla asignada'),
            ],
          ),
        ],
      ),
    );
  }
}

class _SinCredencial extends StatelessWidget {
  const _SinCredencial();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 200,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: AppColors.sunken,
        borderRadius: AppForma.borde,
      ),
      padding: const EdgeInsets.all(AppEspacio.md),
      child: Text(
        'Todavía no tienes credencial. Tira hacia abajo para pedirla, o '
        'avísale al administrador.',
        textAlign: TextAlign.center,
        style: AppTexto.cuerpoChico,
      ),
    );
  }
}

/// Renovar anula el código anterior. Se ofrece abajo y con confirmación: es
/// para cuando se perdió el teléfono o alguien fotografió el código, no algo
/// que se toque por curiosidad.
class _Renovar extends ConsumerStatefulWidget {
  const _Renovar({required this.perfil});

  final PerfilTrabajador perfil;

  @override
  ConsumerState<_Renovar> createState() => _RenovarState();
}

class _RenovarState extends ConsumerState<_Renovar> {
  bool _enviando = false;
  final _intento = IntentoIdempotente();

  Future<void> _renovar() async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Renovar tu credencial?'),
        content: const Text(
          'El código actual deja de servir de inmediato, incluida cualquier '
          'captura o foto que alguien tenga de él. Hazlo si perdiste el '
          'teléfono o crees que otra persona lo está usando.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Renovar'),
          ),
        ],
      ),
    );
    if (confirmado != true || _enviando) return;

    setState(() => _enviando = true);
    try {
      await ref
          .read(trabajadoresApiProvider)
          .renovarMiCredencial(
            // La huella es el código que se quiere anular: reintentar tras un
            // timeout repite la misma renovación, no emite dos.
            clave: _intento.clavePara([widget.perfil.credencialQr]),
          );
      _intento.reiniciar();
      ref.invalidate(perfilTrabajadorProvider);
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Credencial renovada. La anterior ya no sirve.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(mensajeDeError(e))));
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: TextButton.icon(
        onPressed: _enviando ? null : _renovar,
        icon: _enviando
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.autorenew, size: 18),
        label: Text(_enviando ? 'Renovando…' : 'Perdí el teléfono: renovar'),
        style: TextButton.styleFrom(foregroundColor: AppColors.textMuted),
      ),
    );
  }
}

/// El QR sobre blanco puro con su margen de silencio: lo mismo en la tarjeta,
/// a pantalla completa y en el pedido de herramientas.
class CodigoQr extends StatelessWidget {
  const CodigoQr({
    super.key,
    required this.codigo,
    required this.lado,
    this.etiqueta = 'Código QR de tu credencial',
  });

  final String codigo;
  final double lado;

  /// Qué es, para el lector de pantalla.
  final String etiqueta;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      image: true,
      label: etiqueta,
      child: Container(
        color: Colors.white,
        child: QrImageView(
          data: codigo,
          size: lado,
          // El margen blanco alrededor es parte del código: sin él, el
          // escáner confunde el borde de la tarjeta con un módulo.
          padding: const EdgeInsets.all(12),
          backgroundColor: Colors.white,
          eyeStyle: const QrEyeStyle(
            eyeShape: QrEyeShape.square,
            color: Color(0xFF0F172A),
          ),
          dataModuleStyle: const QrDataModuleStyle(
            dataModuleShape: QrDataModuleShape.square,
            color: Color(0xFF0F172A),
          ),
          errorCorrectionLevel: QrErrorCorrectLevel.M,
        ),
      ),
    );
  }
}

/// Sin señal se muestra la última copia guardada. Se dice de cuándo es: si
/// el trabajador la renovó desde otro teléfono, esta ya no sirve.
class _SinConexion extends StatelessWidget {
  const _SinConexion({required this.guardadoEl});

  final DateTime guardadoEl;

  @override
  Widget build(BuildContext context) {
    return Panel(
      borderIzquierdo: AppColors.warning,
      child: Row(
        children: [
          const Icon(Icons.cloud_off, size: 20, color: AppColors.secondary),
          const SizedBox(width: AppEspacio.sm + 4),
          Expanded(
            child: Text(
              'Sin conexión. Es la credencial guardada '
              '${Formato.relativa(guardadoEl)}; sirve igual en bodega.',
              style: AppTexto.cuerpoChico,
            ),
          ),
        ],
      ),
    );
  }
}

/// Abre la credencial a pantalla completa.
Future<void> mostrarCredencialCompleta(
  BuildContext context,
  PerfilTrabajador perfil,
) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    fullscreenDialog: true,
    builder: (_) => PantallaCredencialCompleta(perfil: perfil),
  ),
);

/// La credencial como la ve el bodeguero: solo el código, el nombre y el RUT,
/// sobre blanco, sin barras del sistema y con el brillo al máximo. Se cierra
/// con un toque en cualquier parte: el trabajador tiene guantes.
class PantallaCredencialCompleta extends StatefulWidget {
  const PantallaCredencialCompleta({super.key, required this.perfil});

  final PerfilTrabajador perfil;

  @override
  State<PantallaCredencialCompleta> createState() =>
      _PantallaCredencialCompletaState();
}

class _PantallaCredencialCompletaState
    extends State<PantallaCredencialCompleta> {
  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    Pantalla.brilloMaximo();
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    Pantalla.brilloNormal();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.perfil;
    return Scaffold(
      backgroundColor: Colors.white,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.of(context).pop(),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, c) {
              // Lo más grande que quepa dejando sitio al nombre debajo. Sin
              // bajar de 180: más chico el lector ya no lo toma.
              final lado = math.max(
                180.0,
                math.min(c.maxWidth - 32, c.maxHeight - 200),
              );
              return Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CodigoQr(codigo: p.credencialQr!, lado: lado),
                  const SizedBox(height: AppEspacio.lg),
                  Text(
                    p.nombre,
                    textAlign: TextAlign.center,
                    style: AppTexto.titulo.copyWith(fontSize: 26),
                  ),
                  if (p.rut != null)
                    Text(
                      p.rut!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontFeatures: AppTexto.tabulares,
                        fontSize: 20,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textMuted,
                      ),
                    ),
                  const SizedBox(height: AppEspacio.xl),
                  Text('Toca para cerrar', style: AppTexto.cuerpoChico),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
