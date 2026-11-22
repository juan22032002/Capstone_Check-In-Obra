import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formato.dart';
import '../../core/network/errores.dart';
import '../../core/network/idempotencia.dart';
import '../../core/theme/app_colors.dart';
import '../../data/api/dominio_api.dart';
import '../../data/modelos/partida.dart';
import '../../shared_widgets/campo_texto.dart';
import '../../shared_widgets/estados.dart';
import '../../shared_widgets/opcion.dart';
import '../../shared_widgets/panel.dart';
import '../../shared_widgets/presion.dart';
import '../bodega/bodega_providers.dart';
import 'cubicacion_providers.dart';
import 'pantalla_detalle_partida.dart';

/// Crea una partida con su geometría (D1).
///
/// Termina abriendo la partida recién creada: lo siguiente que quiere el jefe
/// es cubicarla, y volver a la lista para buscarla sería un paso de más.
class PantallaNuevaPartida extends ConsumerStatefulWidget {
  const PantallaNuevaPartida({super.key});

  @override
  ConsumerState<PantallaNuevaPartida> createState() =>
      _PantallaNuevaPartidaState();
}

class _PantallaNuevaPartidaState extends ConsumerState<PantallaNuevaPartida> {
  final _formulario = GlobalKey<FormState>();
  final _ancho = TextEditingController();
  final _alto = TextEditingController();
  final _separacion = TextEditingController();
  final _intento = IntentoIdempotente();

  String _tipo = tiposDePartida.first;
  bool _enviando = false;
  String? _error;

  @override
  void dispose() {
    _ancho.dispose();
    _alto.dispose();
    _separacion.dispose();
    super.dispose();
  }

  Future<void> _crear() async {
    if (_enviando) return;
    final obra = ref.read(obraEnCursoProvider);
    if (obra == null || !_formulario.currentState!.validate()) return;

    final ancho = Formato.numero(_ancho.text)!;
    final alto = Formato.numero(_alto.text)!;
    final separacion = Formato.numero(_separacion.text)!;

    setState(() {
      _enviando = true;
      _error = null;
    });
    try {
      final partida = await ref
          .read(partidasApiProvider)
          .crear(
            obraId: obra.id,
            tipo: _tipo,
            anchoM: ancho,
            altoM: alto,
            separacionMontantes: separacion,
            clave: _intento.clavePara([
              obra.id,
              _tipo,
              ancho,
              alto,
              separacion,
            ]),
          );
      ref.invalidate(partidasDeObraProvider(obra.id));
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => PantallaDetallePartida(partida: partida),
        ),
      );
    } catch (e) {
      if (mounted) setState(() => _error = mensajeDeError(e));
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final obra = ref.watch(obraEnCursoProvider);

    return PopScope(
      canPop: !_enviando,
      child: Scaffold(
        appBar: AppBar(title: const Text('Nueva partida')),
        body: SafeArea(
          top: false,
          child: Form(
            key: _formulario,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (obra != null)
                  Text(
                    'En ${obra.nombre}',
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textMuted,
                    ),
                  ),
                const SizedBox(height: 16),
                const Etiqueta('Tipo de partida'),
                const SizedBox(height: 8),
                Row(
                  children: [
                    for (final t in tiposDePartida) ...[
                      Expanded(
                        child: Opcion(
                          texto: nombreDeTipoPartida(t),
                          elegida: _tipo == t,
                          expandida: true,
                          alTocar: _enviando
                              ? null
                              : () => setState(() => _tipo = t),
                        ),
                      ),
                      if (t != tiposDePartida.last) const SizedBox(width: 8),
                    ],
                  ],
                ),
                const SizedBox(height: 20),
                const Etiqueta('Ancho (m)'),
                const SizedBox(height: 8),
                _campo(_ancho, 'Ej. 4,8', Icons.swap_horiz, 'el ancho'),
                const SizedBox(height: 16),
                const Etiqueta('Alto (m)'),
                const SizedBox(height: 8),
                _campo(_alto, 'Ej. 2,4', Icons.swap_vert, 'el alto'),
                const SizedBox(height: 16),
                const Etiqueta('Separación entre montantes (m)'),
                const SizedBox(height: 8),
                _campo(
                  _separacion,
                  'Ej. 0,6',
                  Icons.view_week_outlined,
                  'la separación',
                ),
                const SizedBox(height: 6),
                const Text(
                  'Define cuántos montantes lleva: el ancho dividido por la '
                  'separación, redondeado hacia arriba, más uno.',
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.4,
                    color: AppColors.secondary,
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  MensajeError(mensaje: _error!),
                ],
                const SizedBox(height: 22),
                BotonEnvio(
                  texto: 'Crear partida',
                  textoEnviando: 'Creando…',
                  enviando: _enviando,
                  alPresionar: _crear,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _campo(
    TextEditingController controlador,
    String hint,
    IconData icono,
    String rotulo,
  ) {
    return CampoTexto(
      controlador: controlador,
      hint: hint,
      icono: icono,
      mono: true,
      habilitado: !_enviando,
      teclado: const TextInputType.numberWithOptions(decimal: true),
      formatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
      validador: (v) => MedidasPartida.error(v ?? '', rotulo),
    );
  }
}
