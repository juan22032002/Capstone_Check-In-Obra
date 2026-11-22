import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formato.dart';
import '../../core/network/errores.dart';
import '../../core/network/idempotencia.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../data/api/dominio_api.dart';
import '../../data/modelos/partida.dart';
import '../../shared_widgets/estados.dart';
import '../../shared_widgets/panel.dart';
import '../../shared_widgets/presion.dart';
import 'cubicacion_providers.dart';

/// Una partida con lo que salió de cubicarla (D2 y D3).
///
/// Los ítems se leen antes de calcular: el jefe revisa el resultado vigente
/// sin tener que cubicar de nuevo, que reemplazaría lo anterior (RN-21).
class PantallaDetallePartida extends ConsumerStatefulWidget {
  const PantallaDetallePartida({super.key, required this.partida});

  final Partida partida;

  @override
  ConsumerState<PantallaDetallePartida> createState() =>
      _PantallaDetallePartidaState();
}

class _PantallaDetallePartidaState
    extends ConsumerState<PantallaDetallePartida> {
  final _intento = IntentoIdempotente();
  bool _cubicando = false;
  String? _error;

  Future<void> _cubicar() async {
    if (_cubicando) return;
    setState(() {
      _cubicando = true;
      _error = null;
    });
    try {
      final id = widget.partida.id;
      await ref
          .read(partidasApiProvider)
          .cubicar(id, clave: _intento.clavePara([id]));
      // Cada cubicación es una intención nueva: la siguiente no debe
      // confundirse con un reintento de esta.
      _intento.reiniciar();
      ref.invalidate(itemsCubicadosProvider(id));
      if (!mounted) return;
      HapticFeedback.mediumImpact();
    } catch (e) {
      if (mounted) setState(() => _error = mensajeDeError(e));
    } finally {
      if (mounted) setState(() => _cubicando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final partida = widget.partida;
    final items = ref.watch(itemsCubicadosProvider(partida.id));
    final hayItems = items.valueOrNull?.isNotEmpty ?? false;

    return PopScope(
      canPop: !_cubicando,
      child: Scaffold(
        appBar: AppBar(title: Text('${partida.nombreDelTipo} #${partida.id}')),
        body: SafeArea(
          top: false,
          child: RefreshIndicator(
            onRefresh: () async =>
                ref.refresh(itemsCubicadosProvider(partida.id).future),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _ResumenPartida(partida: partida),
                const SizedBox(height: 20),
                BotonEnvio(
                  texto: hayItems ? 'Cubicar de nuevo' : 'Cubicar partida',
                  textoEnviando: 'Cubicando…',
                  enviando: _cubicando,
                  alPresionar: _cubicar,
                ),
                if (hayItems) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'Cubicar de nuevo reemplaza el cálculo anterior.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: AppColors.secondary,
                    ),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  MensajeError(mensaje: _error!),
                ],
                const SizedBox(height: 24),
                const Etiqueta('Materiales'),
                const SizedBox(height: 10),
                Contenido<List<ItemCubicado>>(
                  valor: items,
                  alReintentar: () =>
                      ref.invalidate(itemsCubicadosProvider(partida.id)),
                  estaVacio: (l) => l.isEmpty,
                  vacio: const Vacio(
                    icono: Icons.calculate_outlined,
                    titulo: 'Todavía no se cubica',
                    detalle:
                        'Toca «Cubicar partida» para calcular qué materiales '
                        'lleva y cuántos, con merma.',
                  ),
                  constructor: (lista) => Column(
                    children: [
                      for (final item in lista) ...[
                        FilaItemCubicado(item: item),
                        const SizedBox(height: 8),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ResumenPartida extends StatelessWidget {
  const _ResumenPartida({required this.partida});

  final Partida partida;

  @override
  Widget build(BuildContext context) {
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(partida.nombreDelTipo, style: AppTexto.subtitulo),
          const SizedBox(height: 10),
          Wrap(
            spacing: 20,
            runSpacing: 10,
            children: [
              _Medida('Ancho', '${Formato.cantidad(partida.anchoM)} m'),
              _Medida('Alto', '${Formato.cantidad(partida.altoM)} m'),
              _Medida(
                'Montantes cada',
                '${Formato.cantidad(partida.separacionMontantes)} m',
              ),
              _Medida(
                'Superficie',
                '${Formato.cantidad(partida.superficieM2)} m²',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Medida extends StatelessWidget {
  const _Medida(this.rotulo, this.valor);

  final String rotulo;
  final String valor;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$rotulo $valor',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            rotulo,
            style: const TextStyle(fontSize: 12, color: AppColors.secondary),
          ),
          const SizedBox(height: 2),
          Text(valor, style: AppTexto.dato),
        ],
      ),
    );
  }
}

/// Un material de la lista: lo que hay que comprar a la derecha, lo que pide
/// la geometría debajo, y por qué difieren (la merma).
class FilaItemCubicado extends StatelessWidget {
  const FilaItemCubicado({super.key, required this.item});

  final ItemCubicado item;

  @override
  Widget build(BuildContext context) {
    final conMerma = Formato.cantidad(item.cantidadConMerma);
    final calculada = Formato.cantidad(item.cantidadCalculada);

    return Semantics(
      label:
          '${item.materialNombre}, calculada $calculada, con merma $conMerma',
      excludeSemantics: true,
      child: Panel(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.materialNombre, style: AppTexto.subtitulo),
                  const SizedBox(height: 2),
                  Text(
                    item.materialSku,
                    style: AppTexto.dato.copyWith(color: AppColors.secondary),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(conMerma, style: AppTexto.cifra),
                const Text(
                  'con merma',
                  style: TextStyle(fontSize: 12, color: AppColors.secondary),
                ),
                const SizedBox(height: 2),
                Text(
                  'calculada $calculada',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
