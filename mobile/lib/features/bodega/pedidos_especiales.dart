import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formato.dart';
import '../../core/network/errores.dart';
import '../../core/network/idempotencia.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_forma.dart';
import '../../core/theme/app_theme.dart';
import '../../data/api/auth_api.dart';
import '../../data/api/dominio_api.dart';
import '../../data/modelos/pedido_especial.dart';
import '../../shared_widgets/globo_texto.dart';
import '../../shared_widgets/panel.dart';
import '../../shared_widgets/presion.dart';
import 'bodega_providers.dart';
import 'solicitudes_acciones.dart' show rechazarSolicitud;

/// Chip del estado de un pedido especial, visto desde bodega.
Widget chipDePedido(String estado) => switch (estado) {
  'PENDIENTE' => ChipEstado.aviso('Nuevo'),
  'EN_GESTION' => ChipEstado.aviso('Consiguiéndolo'),
  'LISTO_PARA_RETIRO' => ChipEstado.exito('Listo para retirar'),
  'ENTREGADO' => ChipEstado.exito('Entregado, sin confirmar', conPunto: false),
  'RECIBIDO' => ChipEstado.neutro('Recibido'),
  'RECHAZADO' => ChipEstado.critico('Rechazado', conPunto: false),
  _ => ChipEstado.neutro(nombreDeEstadoPedido(estado)),
};

/// Un pedido especial en la cola de bodega o del administrador.
///
/// El botón principal es siempre el paso siguiente —conseguirlo, avisar que
/// llegó, entregarlo— y debajo van los atajos: entregar de inmediato si el
/// trabajador está en el mesón, o rechazar con un motivo.
class FilaPedidoEspecial extends ConsumerStatefulWidget {
  const FilaPedidoEspecial({
    super.key,
    required this.pedido,
    this.mostrarObra = false,
  });

  final PedidoEspecial pedido;

  /// En la vista del administrador, que mezcla obras.
  final bool mostrarObra;

  @override
  ConsumerState<FilaPedidoEspecial> createState() => _FilaPedidoEspecialState();
}

class _FilaPedidoEspecialState extends ConsumerState<FilaPedidoEspecial> {
  bool _enviando = false;
  final _intento = IntentoIdempotente();

  Future<void> _avanzar(PasoPedido paso) async {
    final p = widget.pedido;
    String? nota;
    if (paso == PasoPedido.entregar) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('¿Entregar ${p.nombre}?'),
          content: Text(
            'Se lo pasas a ${p.trabajadorNombre}, y él confirma en su app que '
            'lo recibió.'
            '${p.materialId != null ? '\n\nEs un material del catálogo: si '
                      'llegó a bodega, regístralo como recepción y entrégalo '
                      'con su despacho, para que el stock cuadre.' : ''}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Entregar'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    } else {
      final resultado = await showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        builder: (_) => _HojaNota(pedido: p, paso: paso),
      );
      if (resultado == null) return;
      nota = resultado;
    }

    if (_enviando || !mounted) return;
    setState(() => _enviando = true);
    try {
      await ref
          .read(pedidosEspecialesApiProvider)
          .avanzar(
            p.id,
            paso,
            nota: nota,
            clave: _intento.clavePara([p.id, paso, nota]),
          );
      _intento.reiniciar();
      recargarBodega(ref);
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(switch (paso) {
            PasoPedido.gestionar =>
              '${p.trabajadorNombre} verá que lo estás consiguiendo',
            PasoPedido.listo =>
              'Le avisamos a ${p.trabajadorNombre} que puede retirarlo',
            PasoPedido.entregar =>
              'Entregado. Falta que ${p.trabajadorNombre} lo confirme',
          }),
        ),
      );
    } catch (e) {
      // Otro de bodega pudo moverlo antes: se refresca para ver en qué quedó.
      if (e is ApiException && e.codigo == 'TRANSICION_INVALIDA') {
        recargarBodega(ref);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(mensajeDeError(e))));
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.pedido;
    final paso = p.siguientePaso;

    return Panel(
      borderIzquierdo: switch (p.estado) {
        'PENDIENTE' => AppColors.warning,
        'LISTO_PARA_RETIRO' => AppColors.success,
        _ => null,
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              chipDePedido(p.estado),
              const SizedBox(width: 8),
              const Spacer(),
              if (p.fechaSolicitud case final fecha?)
                Text(
                  Formato.antiguedad(fecha),
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.secondary,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            p.nombre,
            style: const TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w600,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            [
              p.esHerramienta ? 'Herramienta' : 'Material',
              p.esHerramienta && p.unidad == null
                  ? (p.cantidad == 1
                        ? '1 unidad'
                        : '${p.cantidadConUnidad} unidades')
                  : p.cantidadConUnidad,
              if (p.materialId != null || p.herramientaId != null)
                'del catálogo, sin stock'
              else
                'fuera del catálogo',
              if (widget.mostrarObra && p.obraNombre.isNotEmpty) p.obraNombre,
            ].join(' · '),
            style: AppTexto.dato,
          ),
          const SizedBox(height: AppEspacio.sm),
          GloboTexto(
            texto: p.descripcion,
            autor: p.trabajadorRut == null
                ? p.trabajadorNombre
                : '${p.trabajadorNombre} · ${p.trabajadorRut}',
          ),
          if (p.notaBodega case final nota? when nota.isNotEmpty) ...[
            const SizedBox(height: AppEspacio.sm),
            Text(
              'Nota de ${p.gestionadoPorNombre ?? 'bodega'}: “$nota”',
              style: AppTexto.cuerpoChico,
            ),
          ],
          if (p.porConfirmar) ...[
            const SizedBox(height: AppEspacio.sm),
            Text(
              'Esperando que ${p.trabajadorNombre} confirme que lo recibió.',
              style: AppTexto.cuerpoChico,
            ),
          ],
          if (paso != null) ...[
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _enviando ? null : () => _avanzar(paso),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(44),
              ),
              child: Text(_enviando ? 'Guardando…' : paso.rotulo),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                if (paso != PasoPedido.entregar)
                  TextButton(
                    onPressed: _enviando
                        ? null
                        : () => _avanzar(PasoPedido.entregar),
                    child: const Text('Entregar ahora'),
                  ),
                const Spacer(),
                TextButton(
                  onPressed: _enviando
                      ? null
                      : () => rechazarSolicitud(
                          context,
                          titulo: 'Rechazar ${p.nombre}',
                          alConfirmar: (motivo, clave) => ref
                              .read(pedidosEspecialesApiProvider)
                              .rechazar(p.id, motivo: motivo, clave: clave),
                        ),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.destructiveDark,
                  ),
                  child: const Text('Rechazar'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Nota opcional al trabajador al pasar a "consiguiéndolo" o "listo": es lo
/// que evita que venga a preguntar al mesón cada hora.
class _HojaNota extends StatefulWidget {
  const _HojaNota({required this.pedido, required this.paso});

  final PedidoEspecial pedido;
  final PasoPedido paso;

  @override
  State<_HojaNota> createState() => _HojaNotaState();
}

class _HojaNotaState extends State<_HojaNota> {
  late final _nota = TextEditingController(
    text: widget.pedido.notaBodega ?? '',
  );

  @override
  void dispose() {
    _nota.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final listo = widget.paso == PasoPedido.listo;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.pedido.nombre, style: AppTexto.subtitulo),
              Text(
                'Para ${widget.pedido.trabajadorNombre}',
                style: AppTexto.dato,
              ),
              const SizedBox(height: 16),
              Text(
                listo
                    ? 'Mensaje para el trabajador (opcional)'
                    : '¿Cuándo llega? (opcional)',
                style: AppTexto.rotulo,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _nota,
                minLines: 2,
                maxLines: 4,
                maxLength: 300,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: listo
                      ? 'Ej.: está en el mesón, pídelo a Jorge'
                      : 'Ej.: lo trae el proveedor el jueves',
                ),
              ),
              const SizedBox(height: 12),
              BotonEnvio(
                texto: widget.paso.rotulo,
                textoEnviando: 'Guardando…',
                enviando: false,
                alPresionar: () => Navigator.of(context).pop(_nota.text),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
