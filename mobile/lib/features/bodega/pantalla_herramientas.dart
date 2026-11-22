import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formato.dart';
import '../../core/network/errores.dart';
import '../../data/api/auth_api.dart';
import '../../core/network/idempotencia.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../data/api/dominio_api.dart';
import '../../data/modelos/herramienta.dart';
import '../../shared_widgets/campo_texto.dart';
import '../../shared_widgets/estados.dart';
import '../../shared_widgets/panel.dart';
import '../admin/pantalla_importacion.dart';
import 'bodega_providers.dart';
import 'pantalla_prestamo.dart';

/// Las herramientas de la empresa y los préstamos abiertos de la obra.
///
/// Se muestran juntas porque la pregunta del bodeguero es una sola: qué está
/// fuera y desde cuándo. Una lista de herramientas sin sus préstamos obligaría
/// a cruzarlas a mano.
class PantallaHerramientas extends ConsumerStatefulWidget {
  const PantallaHerramientas({super.key});

  @override
  ConsumerState<PantallaHerramientas> createState() =>
      _PantallaHerramientasState();
}

class _PantallaHerramientasState extends ConsumerState<PantallaHerramientas> {
  final _busqueda = TextEditingController();

  @override
  void dispose() {
    _busqueda.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final abiertos = ref.watch(prestamosAbiertosProvider);
    final herramientas = ref.watch(herramientasProvider);
    final texto = _busqueda.text.trim().toLowerCase();

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(herramientasProvider);
        ref.invalidate(prestamosProvider);
      },
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          FilledButton.icon(
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const PantallaPrestamo())),
            icon: const Icon(Icons.add),
            label: const Text('Prestar herramienta'),
          ),
          const SizedBox(height: 10),
          // Las herramientas las etiqueta y las da de alta la propia bodega
          // cuando llegan: veinte taladros nuevos son una planilla, no veinte
          // formularios.
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const PantallaImportacion(
                  inicial: CatalogoImportable.herramientas,
                  soloEseCatalogo: true,
                ),
              ),
            ),
            icon: const Icon(Icons.upload_file, size: 20),
            label: const Text('Importar herramientas desde Excel'),
          ),
          const SizedBox(height: 20),
          const Etiqueta('Fuera de bodega'),
          const SizedBox(height: 8),
          Contenido<List<Prestamo>>(
            valor: abiertos,
            alReintentar: () => ref.invalidate(prestamosProvider),
            estaVacio: (l) => l.isEmpty,
            vacio: const Panel(
              child: Row(
                children: [
                  ExcludeSemantics(
                    child: Icon(
                      Icons.check_circle_outline,
                      size: 20,
                      color: AppColors.successDark,
                    ),
                  ),
                  SizedBox(width: 11),
                  Expanded(
                    child: Text(
                      'Todas las herramientas están en bodega.',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            constructor: (lista) => Column(
              children: [
                for (final p in lista) ...[
                  FilaPrestamo(prestamo: p),
                  const SizedBox(height: 8),
                ],
              ],
            ),
          ),
          const SizedBox(height: 22),
          const Etiqueta('Catálogo de herramientas'),
          const SizedBox(height: 8),
          CampoTexto(
            controlador: _busqueda,
            hint: 'Buscar por nombre o código QR',
            icono: Icons.search,
            mono: true,
            alEnviar: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          Contenido<List<Herramienta>>(
            valor: herramientas,
            alReintentar: () => ref.invalidate(herramientasProvider),
            estaVacio: (l) => l.isEmpty,
            vacio: const Vacio(
              icono: Icons.handyman_outlined,
              titulo: 'Sin herramientas registradas',
              detalle:
                  'Las herramientas las da de alta un administrador o un '
                  'bodeguero, con su código QR.',
            ),
            constructor: (todas) {
              final lista = todas
                  .where(
                    (h) =>
                        texto.isEmpty ||
                        h.nombre.toLowerCase().contains(texto) ||
                        h.codigoQr.toLowerCase().contains(texto),
                  )
                  .toList();
              if (lista.isEmpty) {
                return const Vacio(
                  icono: Icons.search_off,
                  titulo: 'Ninguna coincide',
                  detalle: 'Prueba con otra parte del nombre o del código.',
                );
              }
              return Column(
                children: [
                  for (final h in lista) ...[
                    _FilaHerramienta(herramienta: h),
                    const SizedBox(height: 8),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Un préstamo abierto, con el botón de recibir la herramienta.
class FilaPrestamo extends ConsumerStatefulWidget {
  const FilaPrestamo({super.key, required this.prestamo});

  final Prestamo prestamo;

  @override
  ConsumerState<FilaPrestamo> createState() => _FilaPrestamoState();
}

class _FilaPrestamoState extends ConsumerState<FilaPrestamo> {
  bool _enviando = false;
  final _intento = IntentoIdempotente();

  Future<void> _recibir(String estado) async {
    if (_enviando) return;
    setState(() => _enviando = true);
    try {
      await ref
          .read(prestamosApiProvider)
          .registrarDevolucion(
            widget.prestamo.id,
            nuevoEstadoHerramienta: estado,
            clave: _intento.clavePara([widget.prestamo.id, estado]),
          );
      recargarBodega(ref);
      ref.invalidate(herramientasProvider);
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Devolución registrada: ${widget.prestamo.herramientaNombre}',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      // Ya devuelta: otro bodeguero la recibió, o el reintento llegó después
      // de un éxito cuya respuesta se perdió. Lo que falta es refrescar.
      if (e is ApiException && e.yaEstabaHecho) {
        recargarBodega(ref);
        ref.invalidate(herramientasProvider);
      }
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(mensajeDeError(e))));
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  /// Al recibir hay que decir en qué estado vuelve: si vuelve dañada, no puede
  /// quedar disponible para el siguiente préstamo.
  Future<void> _preguntarEstado() async {
    final estado = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 18, 16, 8),
              child: Text(
                '¿En qué estado vuelve?',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(
                Icons.check_circle_outline,
                color: AppColors.successDark,
              ),
              title: const Text('Disponible'),
              subtitle: const Text('Vuelve a estar para prestar'),
              onTap: () => Navigator.of(context).pop('DISPONIBLE'),
            ),
            ListTile(
              leading: const Icon(
                Icons.build_outlined,
                color: AppColors.warningDark,
              ),
              title: const Text('En mantención'),
              subtitle: const Text('No se puede prestar hasta repararla'),
              onTap: () => Navigator.of(context).pop('MANTENCION'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (estado != null) await _recibir(estado);
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.prestamo;
    return Panel(
      borderIzquierdo: p.vencido ? AppColors.destructive : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  p.herramientaNombre,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (p.vencido)
                ChipEstado.critico('Vencida')
              else
                ChipEstado.neutro('Prestada'),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            p.trabajadorNombre +
                (p.fechaDevolEsperada == null
                    ? ''
                    : ' · vence ${Formato.relativa(p.fechaDevolEsperada!)}'),
            style: TextStyle(
              fontSize: 12,
              color: p.vencido
                  ? AppColors.destructiveDark
                  : AppColors.secondary,
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _enviando ? null : _preguntarEstado,
            icon: _enviando
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.assignment_returned_outlined, size: 18),
            label: Text(_enviando ? 'Registrando…' : 'Registrar devolución'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(44),
              side: const BorderSide(color: AppColors.borderControl),
              foregroundColor: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class _FilaHerramienta extends StatelessWidget {
  const _FilaHerramienta({required this.herramienta});

  final Herramienta herramienta;

  @override
  Widget build(BuildContext context) {
    // Solo las disponibles se pueden prestar; las demás son informativas, y
    // hacerlas tocables prometería una acción que el backend rechazaría.
    if (!herramienta.disponible) return Panel(child: _interior());
    return PanelTocable(
      semanticLabel:
          'Prestar ${herramienta.nombre}, código ${herramienta.codigoQr}',
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PantallaPrestamo(herramienta: herramienta),
        ),
      ),
      child: _interior(),
    );
  }

  Widget _interior() {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                herramienta.nombre,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${herramienta.codigoQr} · reposición '
                '${Formato.pesos(herramienta.valorReposicion)}',
                style: const TextStyle(
                  fontFamily: AppTheme.monoFamily,
                  fontSize: 12.5,
                  color: AppColors.secondary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        switch (herramienta.estado) {
          'DISPONIBLE' => ChipEstado.exito('Disponible'),
          'PRESTADA' => ChipEstado.neutro('Prestada'),
          _ => ChipEstado.aviso('Mantención'),
        },
      ],
    );
  }
}
