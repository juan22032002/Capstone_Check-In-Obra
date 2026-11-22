import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/errores.dart';
import '../../core/network/idempotencia.dart';
import '../../core/pantalla.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_forma.dart';
import '../../core/theme/app_theme.dart';
import '../../data/api/auth_api.dart';
import '../../data/api/dominio_api.dart';
import '../../data/modelos/pedido_herramienta.dart';
import '../../shared_widgets/globo_texto.dart';
import '../../shared_widgets/panel.dart';
import 'pantalla_credencial.dart';
import 'trabajador_providers.dart';

/// Abre el QR de un pedido de herramientas.
Future<void> mostrarPedidoQr(BuildContext context, PedidoHerramienta pedido) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => PantallaPedidoQr(pedido: pedido)),
    );

/// El QR con que se retira un pedido de varias herramientas.
///
/// Se muestra igual que la credencial —sobre blanco y con el brillo al
/// máximo— porque se usa igual: el teléfono en el mesón y el lector del
/// bodeguero encima. A diferencia de la credencial, no es a pantalla completa:
/// debajo va la lista de lo pedido, para que el trabajador confirme que es el
/// pedido correcto, y la opción de cancelarlo.
class PantallaPedidoQr extends ConsumerStatefulWidget {
  const PantallaPedidoQr({super.key, required this.pedido});

  final PedidoHerramienta pedido;

  @override
  ConsumerState<PantallaPedidoQr> createState() => _PantallaPedidoQrState();
}

class _PantallaPedidoQrState extends ConsumerState<PantallaPedidoQr> {
  bool _cancelando = false;
  final _intento = IntentoIdempotente();

  @override
  void initState() {
    super.initState();
    Pantalla.brilloMaximo();
  }

  @override
  void dispose() {
    Pantalla.brilloNormal();
    super.dispose();
  }

  Future<void> _cancelar() async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Cancelar el pedido?'),
        content: const Text(
          'Las herramientas vuelven a quedar disponibles para otros y este '
          'código deja de servir en bodega.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('No, mantener'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.destructiveDark,
            ),
            child: const Text('Cancelar pedido'),
          ),
        ],
      ),
    );
    if (confirmado != true || _cancelando || !mounted) return;

    setState(() => _cancelando = true);
    final mensajero = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(pedidosHerramientaApiProvider)
          .cancelar(
            widget.pedido.id,
            clave: _intento.clavePara([widget.pedido.id]),
          );
      recargarTrabajador(ref);
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      Navigator.of(context).pop();
      mensajero.showSnackBar(
        const SnackBar(
          content: Text(
            'Pedido cancelado. Las herramientas quedan para quien las pida.',
          ),
        ),
      );
    } catch (e) {
      // Un 409 es que bodega ya lo entregó, o que se canceló desde otro
      // teléfono: lo que se muestra acá quedó viejo.
      if (e is ApiException && e.statusCode == 409) recargarTrabajador(ref);
      if (!mounted) return;
      mensajero.showSnackBar(SnackBar(content: Text(mensajeDeError(e))));
    } finally {
      if (mounted) setState(() => _cancelando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.pedido;
    final rut = p.trabajador.rut;
    return PopScope(
      canPop: !_cancelando,
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          title: const Text('Retiro de herramientas'),
          backgroundColor: Colors.white,
        ),
        body: SafeArea(
          top: false,
          child: LayoutBuilder(
            builder: (context, c) {
              // Grande, pero dejando ver el comienzo de la lista: el QR no
              // necesita más de 320 para leerse al primer intento.
              final lado = math.max(180.0, math.min(c.maxWidth - 48, 320.0));
              return ListView(
                padding: AppEspacio.pantalla,
                children: [
                  Center(
                    child: CodigoQr(
                      codigo: p.contenidoQr,
                      lado: lado,
                      etiqueta: 'Código QR del pedido de herramientas',
                    ),
                  ),
                  const SizedBox(height: AppEspacio.sm),
                  // Escrito, para el ingreso a mano en bodega: con la pantalla
                  // trizada o el lector sin luz, el QR no siempre se deja leer.
                  SelectableText(
                    p.contenidoQr,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontFamily: AppTheme.monoFamily,
                      fontSize: 12,
                      color: AppColors.secondary,
                    ),
                  ),
                  const SizedBox(height: AppEspacio.md),
                  if (p.pendiente)
                    Text(
                      'Muéstralo en bodega para retirarlas',
                      textAlign: TextAlign.center,
                      style: AppTexto.titulo.copyWith(fontSize: 20),
                    )
                  else
                    Center(child: _ChipEstadoPedido(estado: p.estado)),
                  const SizedBox(height: 4),
                  Text(
                    rut == null
                        ? p.trabajador.nombre
                        : '${p.trabajador.nombre} · $rut',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontFeatures: AppTexto.tabulares,
                      fontSize: 15,
                      color: AppColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: AppEspacio.lg),
                  Etiqueta(
                    p.solicitudes.length == 1
                        ? '1 herramienta'
                        : '${p.solicitudes.length} herramientas',
                  ),
                  const SizedBox(height: AppEspacio.sm),
                  for (final s in p.solicitudes) ...[
                    _FilaHerramienta(nombre: s.herramientaNombre),
                    const SizedBox(height: AppEspacio.sm),
                  ],
                  if (p.descripcion case final d? when d.trim().isNotEmpty) ...[
                    const SizedBox(height: AppEspacio.sm),
                    GloboTexto(texto: d),
                  ],
                  if (p.pendiente) ...[
                    const SizedBox(height: AppEspacio.xl),
                    Center(
                      child: TextButton.icon(
                        onPressed: _cancelando ? null : _cancelar,
                        icon: _cancelando
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.close, size: 18),
                        label: Text(
                          _cancelando ? 'Cancelando…' : 'Cancelar pedido',
                        ),
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.destructiveDark,
                        ),
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _FilaHerramienta extends StatelessWidget {
  const _FilaHerramienta({required this.nombre});

  final String nombre;

  @override
  Widget build(BuildContext context) {
    return Panel(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          const Icon(
            Icons.handyman_outlined,
            size: 20,
            color: AppColors.secondary,
          ),
          const SizedBox(width: AppEspacio.sm + 4),
          Expanded(
            child: Text(
              nombre,
              style: AppTexto.cuerpo.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChipEstadoPedido extends StatelessWidget {
  const _ChipEstadoPedido({required this.estado});

  final String estado;

  @override
  Widget build(BuildContext context) => switch (estado) {
    'ENTREGADO' => ChipEstado.exito(nombreDeEstadoPedido(estado)),
    'PENDIENTE' => ChipEstado.aviso(nombreDeEstadoPedido(estado)),
    _ => ChipEstado.neutro(nombreDeEstadoPedido(estado)),
  };
}

/// Acceso al QR de un pedido que espera retiro, para Inicio e Historial.
///
/// Sin esto, quien cerró la pantalla del QR después de pedir no tenía cómo
/// volver a ella, y llegaba al mesón con las manos vacías.
class TarjetaPedidoPorRetirar extends StatelessWidget {
  const TarjetaPedidoPorRetirar({super.key, required this.pedido});

  final PedidoHerramienta pedido;

  @override
  Widget build(BuildContext context) {
    final nombres = pedido.solicitudes.map((s) => s.herramientaNombre).toList();
    final detalle = nombres.length <= 3
        ? nombres.join(', ')
        : '${nombres.take(2).join(', ')} y ${nombres.length - 2} más';
    return PanelTocable(
      semanticLabel:
          'Herramientas por retirar: $detalle. Tocar para mostrar el código',
      onTap: () => mostrarPedidoQr(context, pedido),
      borderIzquierdo: AppColors.accentFill,
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(
              color: AppColors.accentTint,
              borderRadius: AppForma.borde,
            ),
            child: const Icon(Icons.qr_code_2, color: AppColors.accentFill),
          ),
          const SizedBox(width: AppEspacio.sm + 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Herramientas por retirar',
                  style: AppTexto.cuerpo.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(detalle, style: AppTexto.dato),
              ],
            ),
          ),
          const SizedBox(width: AppEspacio.sm),
          const Text(
            'Ver QR',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.accentFill,
            ),
          ),
        ],
      ),
    );
  }
}
