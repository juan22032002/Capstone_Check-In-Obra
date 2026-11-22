import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formato.dart';
import '../../core/network/errores.dart';
import '../../core/network/idempotencia.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/movimiento.dart';
import '../../data/api/dominio_api.dart';
import '../../data/modelos/material.dart';
import '../../data/modelos/trabajador.dart';
import '../../shared_widgets/campo_texto.dart';
import '../../shared_widgets/estados.dart';
import '../../shared_widgets/opcion.dart';
import '../../shared_widgets/panel.dart';
import '../../shared_widgets/presion.dart';
import '../auth/sesion_controller.dart';
import 'bodega_providers.dart';
import 'pantalla_bodega.dart';
import 'selector_trabajador.dart';

/// Registrar recepción, despacho o consumo.
///
/// Lo que esta pantalla tiene que lograr es que nadie despache a ciegas: antes
/// de confirmar se ve el saldo que va a quedar y, si cruza el mínimo de obra,
/// se dice con todas sus letras. El backend además rechaza con 409 lo que
/// dejaría el saldo negativo, así que la advertencia de acá es para decidir,
/// no para validar.
class PantallaMovimiento extends ConsumerStatefulWidget {
  const PantallaMovimiento({super.key, required this.item});

  final MaterialConStock item;

  @override
  ConsumerState<PantallaMovimiento> createState() => _PantallaMovimientoState();
}

class _PantallaMovimientoState extends ConsumerState<PantallaMovimiento> {
  final _cantidad = TextEditingController();

  /// Lo que se pagó por unidad, según la factura o la guía. Opcional: si quien
  /// recibe no la tiene a mano, la recepción se registra igual.
  final _costo = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  String _tipo = 'RECEPCION';
  Trabajador? _receptor;
  bool _enviando = false;
  String? _error;
  final _intento = IntentoIdempotente();

  @override
  void initState() {
    super.initState();
    // El saldo que va a quedar se recalcula con cada dígito. Sin esto se
    // quedaba en el valor de cuando se abrió la pantalla y la advertencia de
    // "quedarás bajo el mínimo" nunca aparecía mientras se escribía.
    _cantidad.addListener(_alCambiarCantidad);
  }

  void _alCambiarCantidad() => setState(() {});

  @override
  void dispose() {
    _cantidad.removeListener(_alCambiarCantidad);
    _cantidad.dispose();
    _costo.dispose();
    super.dispose();
  }

  double get _valor => Formato.numero(_cantidad.text) ?? 0;

  bool get _entra => _tipo == 'RECEPCION';

  /// Un despacho entrega material a una persona y el kardex tiene que decir a
  /// cuál. Un consumo puede no tenerla —es material que se gastó en la obra— y
  /// una recepción nunca la tiene: el material entra desde un proveedor.
  bool get _pideReceptor => _tipo != 'RECEPCION';

  bool get _receptorObligatorio => _tipo == 'DESPACHO';

  double get _saldoResultante =>
      widget.item.stock + (_entra ? _valor : -_valor);

  Future<void> _registrar() async {
    // Dos toques dentro del mismo cuadro llegan los dos acá: el botón recién
    // se deshabilita en el siguiente build. El teclado ("listo") es otra vía.
    if (_enviando) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();

    final obra = ref.read(obraEnCursoProvider);
    final sesion = ref.read(sesionProvider).valueOrNull;
    if (obra == null || sesion == null) return;

    if (_receptorObligatorio && _receptor == null) {
      setState(
        () => _error = 'Indica a qué trabajador se le entrega el material.',
      );
      return;
    }

    setState(() {
      _enviando = true;
      _error = null;
    });

    final receptorId = _pideReceptor ? _receptor?.id : null;
    // El backend rechaza el costo fuera de una recepción: se manda solo ahí.
    final costo = _entra ? Formato.numero(_costo.text) : null;
    try {
      await ref
          .read(kardexApiProvider)
          .registrar(
            obraId: obra.id,
            materialId: widget.item.material.id,
            trabajadorId: receptorId,
            tipo: _tipo,
            cantidad: _valor,
            costoUnitario: costo,
            clave: _intento.clavePara([
              obra.id,
              widget.item.material.id,
              receptorId,
              _tipo,
              _valor,
              costo,
            ]),
          );

      recargarBodega(ref);
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${_rotuloDe(_tipo)} registrada: '
            '${Formato.cantidad(_valor)} ${unidadDe(widget.item.material.categoria)} '
            'de ${widget.item.material.nombre}'
            '${_receptor == null ? '' : ' a ${_receptor!.nombre}'}',
          ),
        ),
      );
    } catch (e) {
      // Un 409 acá es "stock insuficiente" o que el trabajador no es de esta
      // obra (`OBRA_NO_ASIGNADA`) o no tiene cuadrilla (`SIN_CUADRILLA`): no es
      // un fallo de red ni un error de la app, es el sistema impidiendo un
      // descuadre. Se muestra tal como lo explica el backend y no se reintenta:
      // la respuesta no cambia hasta que se elija otro trabajador.
      if (mounted) setState(() => _error = mensajeDeError(e));
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.item.material;
    final unidad = unidadDe(m.categoria);
    final cruzaElMinimo =
        !_entra && _valor > 0 && _saldoResultante < m.stockMinimo;
    final dejaNegativo = !_entra && _saldoResultante < 0;

    // Con el movimiento en vuelo no se puede volver atrás: saldría de la
    // pantalla sin saber si quedó registrado.
    return PopScope(
      canPop: !_enviando,
      child: Scaffold(
        appBar: AppBar(title: const Text('Movimiento de bodega')),
        body: SafeArea(
          top: false,
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _SelectorTipo(
                  tipo: _tipo,
                  alCambiar: (t) => setState(() {
                    _tipo = t;
                    // Una recepción no lleva receptor: dejarlo colgado mandaría
                    // un dato que el backend rechaza.
                    if (t == 'RECEPCION') _receptor = null;
                  }),
                ),
                const SizedBox(height: 18),
                Panel(
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              m.nombre,
                              style: const TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w600,
                                color: AppColors.primary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${m.sku} · ${Formato.cantidad(widget.item.stock)} $unidad en bodega',
                              style: const TextStyle(
                                fontFamily: AppTheme.monoFamily,
                                fontSize: 12.5,
                                color: AppColors.secondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (_pideReceptor) ...[
                  const SizedBox(height: 18),
                  CampoConEtiqueta(
                    etiqueta: _receptorObligatorio
                        ? 'Trabajador que recibe'
                        : 'Trabajador (opcional)',
                    campo: SelectorTrabajador(
                      elegido: _receptor,
                      habilitado: !_enviando,
                      obligatorio: _receptorObligatorio,
                      alElegir: (t) => setState(() => _receptor = t),
                    ),
                    ayuda: _receptorObligatorio
                        ? 'Queda en el kardex: es lo que permite saber después a '
                              'quién se le entregó este material.'
                        : null,
                  ),
                ],
                const SizedBox(height: 18),
                CampoConEtiqueta(
                  etiqueta: 'Cantidad a ${_verboDe(_tipo)}',
                  campo: CampoTexto(
                    controlador: _cantidad,
                    hint: '0',
                    icono: Icons.tag,
                    mono: true,
                    teclado: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    formatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                    ],
                    habilitado: !_enviando,
                    sufijo: Padding(
                      padding: const EdgeInsets.only(right: 14),
                      child: Text(
                        unidad,
                        style: const TextStyle(
                          fontSize: 14,
                          color: AppColors.secondary,
                        ),
                      ),
                    ),
                    validador: (v) {
                      final n = Formato.numero(v ?? '');
                      if (n == null || n <= 0) {
                        return 'Escribe una cantidad mayor a cero';
                      }
                      return null;
                    },
                    alEnviar: (_) => _registrar(),
                  ),
                ),
                if (_entra) ...[
                  const SizedBox(height: 18),
                  CampoConEtiqueta(
                    etiqueta: 'Costo unitario pagado (opcional)',
                    campo: CampoTexto(
                      controlador: _costo,
                      hint: Formato.pesos(m.costoVigente).substring(1),
                      icono: Icons.attach_money,
                      mono: true,
                      teclado: TextInputType.number,
                      formatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                      ],
                      habilitado: !_enviando,
                      sufijo: Padding(
                        padding: const EdgeInsets.only(right: 14),
                        child: Text(
                          '/ $unidad',
                          style: const TextStyle(
                            fontSize: 14,
                            color: AppColors.secondary,
                          ),
                        ),
                      ),
                      validador: (v) {
                        if (v == null || v.trim().isEmpty) return null;
                        final n = Formato.numero(v);
                        if (n == null || n <= 0) {
                          return 'Escribe un costo mayor a cero, o déjalo vacío';
                        }
                        return null;
                      },
                    ),
                    ayuda: m.tieneCostoReal
                        ? 'El de la factura o guía. La última compra fue a '
                              '${Formato.pesos(m.ultimoCostoUnitario!)}; el catálogo '
                              'dice ${Formato.pesos(m.precioUnitario)}.'
                        : 'El de la factura o guía. Es lo que muestra el '
                              'catálogo como costo real del material.',
                  ),
                ],
                const SizedBox(height: 16),
                _Saldo(
                  saldo: _saldoResultante,
                  unidad: unidad,
                  minimo: m.stockMinimo,
                  cruzaElMinimo: cruzaElMinimo,
                  dejaNegativo: dejaNegativo,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  MensajeError(mensaje: _error!),
                ],
                const SizedBox(height: 20),
                BotonEnvio(
                  texto: 'Registrar ${_rotuloDe(_tipo).toLowerCase()}',
                  textoEnviando: 'Registrando…',
                  enviando: _enviando,
                  alPresionar: _registrar,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _rotuloDe(String tipo) => switch (tipo) {
  'RECEPCION' => 'Recepción',
  'DESPACHO' => 'Despacho',
  _ => 'Consumo',
};

String _verboDe(String tipo) => switch (tipo) {
  'RECEPCION' => 'recibir',
  'DESPACHO' => 'despachar',
  _ => 'consumir',
};

class _SelectorTipo extends StatelessWidget {
  const _SelectorTipo({required this.tipo, required this.alCambiar});

  final String tipo;
  final void Function(String) alCambiar;

  @override
  Widget build(BuildContext context) {
    const tipos = ['RECEPCION', 'DESPACHO', 'CONSUMO'];
    return Row(
      children: [
        for (final t in tipos) ...[
          Expanded(
            child: Opcion(
              texto: _rotuloDe(t),
              elegida: t == tipo,
              expandida: true,
              alTocar: () {
                if (t != tipo) HapticFeedback.selectionClick();
                alCambiar(t);
              },
            ),
          ),
          if (t != tipos.last) const SizedBox(width: 8),
        ],
      ],
    );
  }
}

/// El saldo que va a quedar. Es lo que convierte esta pantalla en una decisión
/// informada en vez de un formulario a ciegas.
class _Saldo extends StatelessWidget {
  const _Saldo({
    required this.saldo,
    required this.unidad,
    required this.minimo,
    required this.cruzaElMinimo,
    required this.dejaNegativo,
  });

  final double saldo;
  final String unidad;
  final double minimo;
  final bool cruzaElMinimo;
  final bool dejaNegativo;

  @override
  Widget build(BuildContext context) {
    final (fondo, borde, textoColor) = switch ((dejaNegativo, cruzaElMinimo)) {
      (true, _) => (
        AppColors.destructiveTint,
        AppColors.destructive,
        AppColors.destructiveDark,
      ),
      (_, true) => (
        AppColors.warningTint,
        AppColors.warning,
        AppColors.warningDark,
      ),
      _ => (AppColors.background, AppColors.border, AppColors.primary),
    };

    return Semantics(
      liveRegion: true,
      child: Panel(
        animado: true,
        color: fondo,
        borderColor: borde,
        child: AnimatedSize(
          duration: Movimiento.de(context, Movimiento.estado),
          curve: Movimiento.salida,
          alignment: Alignment.topCenter,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Saldo tras el movimiento',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ),
                  Text(
                    '${Formato.cantidad(saldo)} $unidad',
                    style: TextStyle(
                      fontFeatures: AppTexto.tabulares,
                      fontFamily: AppTheme.monoFamily,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: textoColor,
                    ),
                  ),
                ],
              ),
              if (dejaNegativo) ...[
                const SizedBox(height: 10),
                Text(
                  'No hay tanto en bodega. El servidor va a rechazar este '
                  'movimiento: el stock no puede quedar negativo.',
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.4,
                    color: textoColor,
                  ),
                ),
              ] else if (cruzaElMinimo) ...[
                const SizedBox(height: 10),
                Text(
                  'Quedarás bajo el stock mínimo de ${Formato.cantidad(minimo)} $unidad. '
                  'Se generará una alerta de stock crítico.',
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.4,
                    color: textoColor,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
