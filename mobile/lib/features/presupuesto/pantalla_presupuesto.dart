import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formato.dart';
import '../../core/network/errores.dart';
import '../../core/network/idempotencia.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../data/api/dominio_api.dart';
import '../../data/modelos/presupuesto.dart';
import '../../shared_widgets/estados.dart';
import '../../shared_widgets/panel.dart';
import '../../shared_widgets/presion.dart';
import '../bodega/bodega_providers.dart';
import 'pantalla_agregar_item.dart';
import 'pantalla_agregar_partida.dart';
import 'presupuesto_providers.dart';

/// El presupuesto de la obra en curso: crearlo (D4), cargarle ítems (D5),
/// aprobarlo (D6) y congelarlo (D7).
///
/// Las acciones que se ofrecen salen del estado, no de un permiso: en
/// BORRADOR se agrega y se aprueba, en APROBADO se agrega o se congela, y
/// CONGELADO no ofrece ninguna — es la línea base de la desviación.
class PantallaPresupuesto extends ConsumerStatefulWidget {
  const PantallaPresupuesto({super.key});

  @override
  ConsumerState<PantallaPresupuesto> createState() =>
      _PantallaPresupuestoState();
}

class _PantallaPresupuestoState extends ConsumerState<PantallaPresupuesto> {
  final _intento = IntentoIdempotente();
  bool _enviando = false;
  String? _error;

  /// Ejecuta una escritura sobre el presupuesto y refresca el estado.
  ///
  /// Se refresca también si falla: un 409 casi siempre significa que el estado
  /// cambió desde otro teléfono, y dejar la pantalla con los botones viejos
  /// invita a repetir el error.
  Future<void> _ejecutar(
    int obraId,
    Future<void> Function(String clave) accion,
    List<Object?> huella,
  ) async {
    if (_enviando) return;
    setState(() {
      _enviando = true;
      _error = null;
    });
    try {
      await accion(_intento.clavePara(huella));
      _intento.reiniciar();
      if (!mounted) return;
      HapticFeedback.mediumImpact();
    } catch (e) {
      if (mounted) setState(() => _error = mensajeDeError(e));
    } finally {
      ref.invalidate(presupuestoDeObraProvider(obraId));
      if (mounted) setState(() => _enviando = false);
    }
  }

  Future<bool> _confirmar(String titulo, String detalle, String accion) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(titulo),
        content: Text(detalle),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.accentFill,
            ),
            child: Text(accion),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final obra = ref.watch(obraEnCursoProvider);
    if (obra == null) return const SizedBox.shrink();
    final presupuesto = ref.watch(presupuestoDeObraProvider(obra.id));

    return RefreshIndicator(
      onRefresh: () async {
        final p = await ref.refresh(presupuestoDeObraProvider(obra.id).future);
        if (p != null) ref.invalidate(itemsPresupuestoProvider(p.id));
      },
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Contenido<Presupuesto?>(
            valor: presupuesto,
            alReintentar: () =>
                ref.invalidate(presupuestoDeObraProvider(obra.id)),
            constructor: (p) => p == null
                ? _SinPresupuesto(
                    enviando: _enviando,
                    alCrear: () => _ejecutar(
                      obra.id,
                      (clave) async => ref
                          .read(presupuestosApiProvider)
                          .crear(obra.id, clave: clave),
                      [obra.id, 'crear'],
                    ),
                  )
                : _Presupuesto(
                    presupuesto: p,
                    enviando: _enviando,
                    alAprobar: () async {
                      final ok = await _confirmar(
                        'Aprobar el presupuesto',
                        'Dejas constancia de que la línea base fue revisada. '
                            'Después solo queda congelarlo.',
                        'Aprobar',
                      );
                      if (!ok) return;
                      await _ejecutar(
                        obra.id,
                        (clave) async => ref
                            .read(presupuestosApiProvider)
                            .aprobar(p.id, clave: clave),
                        [p.id, 'aprobar'],
                      );
                    },
                    alCongelar: () async {
                      final ok = await _confirmar(
                        'Congelar el presupuesto',
                        'Será la referencia contra la que se mide la '
                            'desviación. No se podrá editar ni volver atrás.',
                        'Congelar',
                      );
                      if (!ok) return;
                      await _ejecutar(
                        obra.id,
                        (clave) async => ref
                            .read(presupuestosApiProvider)
                            .congelar(p.id, clave: clave),
                        [p.id, 'congelar'],
                      );
                    },
                  ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 14),
            MensajeError(mensaje: _error!),
          ],
        ],
      ),
    );
  }
}

class _SinPresupuesto extends StatelessWidget {
  const _SinPresupuesto({required this.enviando, required this.alCrear});

  final bool enviando;
  final VoidCallback alCrear;

  @override
  Widget build(BuildContext context) {
    return Vacio(
      icono: Icons.request_quote_outlined,
      titulo: 'Esta obra no tiene presupuesto',
      detalle:
          'Créalo para cargarle los materiales y tener una base contra la '
          'cual comparar lo que se gasta. Nace como borrador.',
      accion: BotonEnvio(
        texto: 'Crear presupuesto',
        textoEnviando: 'Creando…',
        enviando: enviando,
        alPresionar: alCrear,
      ),
    );
  }
}

class _Presupuesto extends ConsumerWidget {
  const _Presupuesto({
    required this.presupuesto,
    required this.enviando,
    required this.alAprobar,
    required this.alCongelar,
  });

  final Presupuesto presupuesto;
  final bool enviando;
  final VoidCallback alAprobar;
  final VoidCallback alCongelar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(itemsPresupuestoProvider(presupuesto.id));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Cabecera(presupuesto: presupuesto),
        const SizedBox(height: 16),
        if (presupuesto.editable) ...[
          OutlinedButton.icon(
            onPressed: enviando
                ? null
                : () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          PantallaAgregarItem(presupuesto: presupuesto),
                    ),
                  ),
            icon: const Icon(Icons.add),
            label: const Text('Agregar ítem'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: enviando
                ? null
                : () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          PantallaAgregarPartida(presupuesto: presupuesto),
                    ),
                  ),
            icon: const Icon(Icons.straighten),
            label: const Text('Agregar una partida cubicada'),
          ),
          const SizedBox(height: 10),
          if (presupuesto.esBorrador)
            BotonEnvio(
              texto: 'Aprobar presupuesto',
              textoEnviando: 'Aprobando…',
              enviando: enviando,
              alPresionar: alAprobar,
            )
          else
            BotonEnvio(
              texto: 'Congelar presupuesto',
              textoEnviando: 'Congelando…',
              enviando: enviando,
              alPresionar: alCongelar,
            ),
          const SizedBox(height: 18),
        ],
        const Etiqueta('Ítems'),
        const SizedBox(height: 10),
        Contenido<List<PresupuestoItem>>(
          valor: items,
          alReintentar: () =>
              ref.invalidate(itemsPresupuestoProvider(presupuesto.id)),
          estaVacio: (l) => l.isEmpty,
          vacio: Vacio(
            icono: Icons.playlist_add,
            titulo: 'Sin ítems todavía',
            detalle: presupuesto.editable
                ? 'Agrega materiales: cada uno toma el precio vigente del '
                      'catálogo.'
                : 'Este presupuesto se congeló sin ítems.',
          ),
          constructor: (lista) => Column(
            children: [
              for (final i in lista) ...[
                FilaPresupuestoItem(item: i),
                const SizedBox(height: 8),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _Cabecera extends StatelessWidget {
  const _Cabecera({required this.presupuesto});

  final Presupuesto presupuesto;

  @override
  Widget build(BuildContext context) {
    final estado = switch (presupuesto.estado) {
      'BORRADOR' => ChipEstado.aviso('Borrador'),
      'APROBADO' => ChipEstado.exito('Aprobado'),
      _ => ChipEstado.neutro('Congelado'),
    };

    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Presupuesto · ${presupuesto.obraNombre}',
                  style: AppTexto.subtitulo,
                ),
              ),
              const SizedBox(width: 8),
              estado,
            ],
          ),
          const SizedBox(height: 12),
          Text(
            Formato.pesos(presupuesto.total),
            style: AppTexto.cifra.copyWith(color: AppColors.primary),
          ),
          const Text(
            'total',
            style: TextStyle(fontSize: 12, color: AppColors.secondary),
          ),
          if (presupuesto.congelado) ...[
            const SizedBox(height: 10),
            Text(
              presupuesto.fechaCongelado == null
                  ? 'Congelado: es la línea base de la desviación.'
                  : 'Congelado el ${Formato.fecha(presupuesto.fechaCongelado!)}: '
                        'es la línea base de la desviación.',
              style: AppTexto.cuerpoChico.copyWith(color: AppColors.textMuted),
            ),
          ],
        ],
      ),
    );
  }
}

class FilaPresupuestoItem extends StatelessWidget {
  const FilaPresupuestoItem({super.key, required this.item});

  final PresupuestoItem item;

  @override
  Widget build(BuildContext context) {
    final cantidad = Formato.cantidad(item.cantidad);
    final precio = Formato.pesos(item.precioUnitario);
    final subtotal = Formato.pesos(item.subtotal);

    return Semantics(
      label: '${item.materialNombre}, $cantidad a $precio, subtotal $subtotal',
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
                    '$cantidad × $precio',
                    style: AppTexto.dato.copyWith(color: AppColors.secondary),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(subtotal, style: AppTexto.dato),
          ],
        ),
      ),
    );
  }
}
