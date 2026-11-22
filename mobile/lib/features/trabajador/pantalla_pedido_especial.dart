import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formato.dart';
import '../../core/network/errores.dart';
import '../../core/network/idempotencia.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_forma.dart';
import '../../core/theme/app_theme.dart';
import '../../data/api/dominio_api.dart';
import '../../shared_widgets/campo_texto.dart';
import '../../shared_widgets/estados.dart';
import '../../shared_widgets/presion.dart';
import 'pantalla_pedir.dart' show CampoParaQue;
import 'trabajador_providers.dart';

/// Pedir algo que bodega no puede entregar hoy: no está en el catálogo, o está
/// pero no queda.
///
/// A diferencia de una solicitud normal, esto no se resuelve en el mesón: le
/// llega a bodega y al administrador como un encargo, lo consiguen, le avisan
/// cuando está listo para retirar, se lo entregan y él confirma que lo recibió.
class PantallaPedidoEspecial extends ConsumerStatefulWidget {
  const PantallaPedidoEspecial({
    super.key,
    required this.esHerramienta,
    this.nombreInicial = '',
    this.materialId,
    this.herramientaId,
    this.unidadInicial,
  });

  final bool esHerramienta;
  final String nombreInicial;

  /// Si viene del catálogo —existe pero no hay—, el pedido apunta a él y el
  /// nombre queda fijo.
  final int? materialId;
  final int? herramientaId;
  final String? unidadInicial;

  @override
  ConsumerState<PantallaPedidoEspecial> createState() =>
      _PantallaPedidoEspecialState();
}

class _PantallaPedidoEspecialState
    extends ConsumerState<PantallaPedidoEspecial> {
  late final _nombre = TextEditingController(text: widget.nombreInicial);
  late final _cantidad = TextEditingController(
    text: widget.esHerramienta ? '1' : '',
  );
  late final _unidad = TextEditingController(text: widget.unidadInicial ?? '');
  final _paraQue = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _enviando = false;
  String? _error;
  final _intento = IntentoIdempotente();

  bool get _delCatalogo =>
      widget.materialId != null || widget.herramientaId != null;

  @override
  void dispose() {
    _nombre.dispose();
    _cantidad.dispose();
    _unidad.dispose();
    _paraQue.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    if (_enviando) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();

    final nombre = _nombre.text.trim();
    final cantidad = Formato.numero(_cantidad.text)!;
    final unidad = _unidad.text.trim().isEmpty ? null : _unidad.text.trim();
    final paraQue = _paraQue.text.trim();
    final tipo = widget.esHerramienta ? 'HERRAMIENTA' : 'MATERIAL';

    setState(() {
      _enviando = true;
      _error = null;
    });
    try {
      await ref
          .read(pedidosEspecialesApiProvider)
          .crear(
            tipo: tipo,
            nombre: nombre,
            cantidad: cantidad,
            unidad: unidad,
            descripcion: paraQue,
            materialId: widget.materialId,
            herramientaId: widget.herramientaId,
            clave: _intento.clavePara([
              tipo,
              nombre,
              cantidad,
              unidad,
              paraQue,
              widget.materialId,
              widget.herramientaId,
            ]),
          );
      recargarTrabajador(ref);
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Pediste $nombre. Te avisamos en Inicio cuando esté listo para '
            'retirar.',
          ),
        ),
      );
      // Vuelve hasta Inicio: la lista de pedir ya no sirve de nada.
      Navigator.of(context).popUntil((r) => r.isFirst);
    } catch (e) {
      if (mounted) setState(() => _error = mensajeDeError(e));
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final que = widget.esHerramienta ? 'herramienta' : 'material';
    return PopScope(
      canPop: !_enviando,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            widget.esHerramienta
                ? 'Pedir que consigan una herramienta'
                : 'Pedir que consigan material',
          ),
        ),
        body: SafeArea(
          top: false,
          child: Form(
            key: _formKey,
            child: ListView(
              padding: AppEspacio.pantalla,
              children: [
                _ComoFunciona(delCatalogo: _delCatalogo),
                const SizedBox(height: AppEspacio.lg),
                CampoConEtiqueta(
                  etiqueta: widget.esHerramienta
                      ? '¿Qué herramienta?'
                      : '¿Qué material?',
                  campo: CampoTexto(
                    controlador: _nombre,
                    hint: widget.esHerramienta
                        ? 'Ej.: sierra caladora'
                        : 'Ej.: perfil omega 0,85 mm',
                    icono: widget.esHerramienta
                        ? Icons.handyman_outlined
                        : Icons.inventory_2_outlined,
                    // Si viene del catálogo, el nombre es el del catálogo:
                    // cambiarlo lo desconectaría del material que apunta.
                    habilitado: !_enviando && !_delCatalogo,
                    validador: (v) {
                      final t = v?.trim() ?? '';
                      if (t.length < 2) return 'Escribe qué necesitas';
                      if (t.length > 120) return 'Máximo 120 caracteres';
                      return null;
                    },
                  ),
                  ayuda: _delCatalogo
                      ? 'Está en el catálogo, pero hoy no hay en bodega.'
                      : 'Descríbelo como lo pedirías en la ferretería: medida, '
                            'marca o modelo si importa.',
                ),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 3,
                      child: CampoConEtiqueta(
                        etiqueta: 'Cantidad',
                        campo: CampoTexto(
                          controlador: _cantidad,
                          hint: '0',
                          icono: Icons.tag,
                          mono: true,
                          teclado: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          formatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp(r'[0-9.,]'),
                            ),
                          ],
                          habilitado: !_enviando,
                          validador: (v) {
                            final n = Formato.numero(v ?? '');
                            if (n == null || n <= 0) return 'Mayor a cero';
                            return null;
                          },
                        ),
                      ),
                    ),
                    if (!widget.esHerramienta) ...[
                      const SizedBox(width: AppEspacio.sm + 4),
                      Expanded(
                        flex: 2,
                        child: CampoConEtiqueta(
                          etiqueta: 'Unidad',
                          campo: CampoTexto(
                            controlador: _unidad,
                            hint: 'pl, kg',
                            icono: Icons.straighten,
                            habilitado: !_enviando,
                            maxLength: 20,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 16),
                CampoParaQue(
                  controlador: _paraQue,
                  habilitado: !_enviando,
                  hint: widget.esHerramienta
                      ? 'Ej.: cortar las placas curvas del cielo del hall'
                      : 'Ej.: terminar el cielo del hall, faltan 20 tiras',
                ),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  MensajeError(mensaje: _error!),
                ],
                const SizedBox(height: 16),
                BotonEnvio(
                  texto: 'Enviar pedido de $que',
                  textoEnviando: 'Enviando…',
                  enviando: _enviando,
                  alPresionar: _enviar,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Los pasos del pedido, antes de llenarlo: quien pide tiene que saber que no
/// es inmediato y que al final le toca confirmar a él.
class _ComoFunciona extends StatelessWidget {
  const _ComoFunciona({required this.delCatalogo});

  final bool delCatalogo;

  @override
  Widget build(BuildContext context) {
    const pasos = [
      'Bodega y el administrador reciben tu pedido.',
      'Lo consiguen y te avisan cuando esté listo para retirar.',
      'Te lo entregan y tú confirmas en la app que lo recibiste.',
    ];
    return Container(
      padding: const EdgeInsets.all(AppEspacio.md),
      decoration: const BoxDecoration(
        color: AppColors.sunken,
        borderRadius: AppForma.borde,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            delCatalogo ? 'No queda en bodega' : 'No está en la lista',
            style: AppTexto.subtitulo.copyWith(fontSize: 15),
          ),
          const SizedBox(height: AppEspacio.sm),
          for (final (i, paso) in pasos.indexed)
            Padding(
              padding: const EdgeInsets.only(top: AppEspacio.xs + 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      color: AppColors.card,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '${i + 1}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppEspacio.sm + 2),
                  Expanded(child: Text(paso, style: AppTexto.cuerpoChico)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
