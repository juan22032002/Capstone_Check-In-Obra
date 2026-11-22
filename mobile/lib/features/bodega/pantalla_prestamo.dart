import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formato.dart';
import '../../core/network/errores.dart';
import '../../core/network/idempotencia.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../data/api/dominio_api.dart';
import '../../data/modelos/herramienta.dart';
import '../../data/modelos/trabajador.dart';
import '../../shared_widgets/campo_texto.dart';
import '../../shared_widgets/estados.dart';
import '../../shared_widgets/panel.dart';
import '../../shared_widgets/presion.dart';
import '../auth/sesion_controller.dart';
import 'bodega_providers.dart';
import 'selector_trabajador.dart';
import 'solicitudes_acciones.dart';

/// Autorizar el préstamo de una herramienta.
///
/// Tres datos y ninguno es opcional: qué herramienta, a quién, y hasta cuándo.
/// El último es el que después dispara la alerta de herramienta no devuelta —
/// sin fecha de devolución esperada no hay nada que vencer.
class PantallaPrestamo extends ConsumerStatefulWidget {
  const PantallaPrestamo({super.key, this.herramienta});

  /// Preseleccionada cuando se entra desde el catálogo.
  final Herramienta? herramienta;

  @override
  ConsumerState<PantallaPrestamo> createState() => _PantallaPrestamoState();
}

class _PantallaPrestamoState extends ConsumerState<PantallaPrestamo> {
  Herramienta? _herramienta;
  Trabajador? _trabajador;
  late DateTime _devolucion;
  bool _enviando = false;
  String? _error;
  final _intento = IntentoIdempotente();

  @override
  void initState() {
    super.initState();
    _herramienta = widget.herramienta;
    // Por defecto, fin del turno: es lo que pasa en la mayoría de los
    // préstamos, y hace que el caso común no requiera tocar nada.
    _devolucion = devolucionPorDefecto(DateTime.now());
  }

  Future<void> _elegirHerramienta() async {
    final disponibles = (ref.read(herramientasProvider).valueOrNull ?? const [])
        .where((h) => h.disponible)
        .toList();

    if (disponibles.isEmpty) {
      setState(
        () => _error = 'No hay herramientas disponibles: están todas prestadas o en mantención.',
      );
      return;
    }

    final elegida = await showModalBottomSheet<Herramienta>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 18, 16, 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Herramientas disponibles',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: disponibles.length,
                separatorBuilder: (_, _) =>
                    const Divider(height: 1, color: AppColors.border),
                itemBuilder: (_, i) {
                  final h = disponibles[i];
                  return ListTile(
                    title: Text(h.nombre),
                    subtitle: Text(
                      '${h.codigoQr} · ${Formato.pesos(h.valorReposicion)}',
                      style: const TextStyle(
                        fontFamily: AppTheme.monoFamily,
                        fontSize: 12,
                      ),
                    ),
                    onTap: () => Navigator.of(context).pop(h),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (elegida != null) setState(() => _herramienta = elegida);
  }

  Future<void> _elegirFecha() async {
    final ahora = DateTime.now();
    final fecha = await showDatePicker(
      context: context,
      initialDate: _devolucion,
      firstDate: DateTime(ahora.year, ahora.month, ahora.day),
      lastDate: ahora.add(const Duration(days: 90)),
      helpText: 'Devolución esperada',
    );
    if (fecha == null || !mounted) return;

    final hora = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_devolucion),
      helpText: 'Hora de devolución',
    );
    if (!mounted) return;

    setState(() {
      _devolucion = DateTime(
        fecha.year,
        fecha.month,
        fecha.day,
        hora?.hour ?? 18,
        hora?.minute ?? 0,
      );
    });
  }

  Future<void> _autorizar() async {
    if (_enviando) return;
    final obra = ref.read(obraEnCursoProvider);
    final sesion = ref.read(sesionProvider).valueOrNull;
    if (obra == null || sesion == null) return;

    if (_herramienta == null) {
      setState(() => _error = 'Elige la herramienta que se va a prestar.');
      return;
    }
    if (_trabajador == null) {
      setState(() => _error = 'Elige a qué trabajador se le presta.');
      return;
    }
    if (!_devolucion.isAfter(DateTime.now())) {
      setState(
        () => _error =
            'La devolución esperada ya pasó. Elige una fecha y hora futuras.',
      );
      return;
    }

    setState(() {
      _enviando = true;
      _error = null;
    });

    try {
      await ref
          .read(prestamosApiProvider)
          .prestar(
            herramientaId: _herramienta!.id,
            trabajadorId: _trabajador!.id,
            obraId: obra.id,
            fechaDevolEsperada: _devolucion,
            clave: _intento.clavePara([
              _herramienta!.id,
              _trabajador!.id,
              obra.id,
              _devolucion,
            ]),
          );

      recargarBodega(ref);
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${_herramienta!.nombre} entregada a ${_trabajador!.nombre}',
          ),
        ),
      );
    } catch (e) {
      // Un 409 `OBRA_NO_ASIGNADA` o `SIN_CUADRILLA` es que el trabajador no es de
      // esta obra o no tiene cuadrilla: se muestra el mensaje del servidor y no
      // se reintenta, porque la respuesta no cambia hasta elegir a otro.
      if (mounted) setState(() => _error = mensajeDeError(e));
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_enviando,
      child: Scaffold(
        appBar: AppBar(title: const Text('Nuevo préstamo')),
        body: SafeArea(
          top: false,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              CampoConEtiqueta(
                etiqueta: 'Herramienta',
                campo: _herramienta == null
                    ? PanelTocable(
                        semanticLabel: 'Elegir la herramienta que se presta',
                        onTap: _enviando ? null : _elegirHerramienta,
                        child: const Row(
                          children: [
                            Icon(
                              Icons.handyman_outlined,
                              size: 22,
                              color: AppColors.secondary,
                            ),
                            SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Elegir herramienta',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: AppColors.textMuted,
                                ),
                              ),
                            ),
                            Icon(
                              Icons.chevron_right,
                              size: 22,
                              color: AppColors.secondary,
                            ),
                          ],
                        ),
                      )
                    : PanelTocable(
                        semanticLabel:
                            'Herramienta ${_herramienta!.nombre}. Tocar para cambiar',
                        onTap: _enviando ? null : _elegirHerramienta,
                        borderColor: AppColors.accentFill,
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _herramienta!.nombre,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    '${_herramienta!.codigoQr} · reposición '
                                    '${Formato.pesos(_herramienta!.valorReposicion)}',
                                    style: const TextStyle(
                                      fontFamily: AppTheme.monoFamily,
                                      fontSize: 12.5,
                                      color: AppColors.secondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Text(
                              'Cambiar',
                              style: TextStyle(
                                fontSize: 12.5,
                                color: AppColors.accentFill,
                              ),
                            ),
                          ],
                        ),
                      ),
              ),
              const SizedBox(height: 18),
              CampoConEtiqueta(
                etiqueta: 'Trabajador que la recibe',
                campo: SelectorTrabajador(
                  elegido: _trabajador,
                  habilitado: !_enviando,
                  alElegir: (t) => setState(() => _trabajador = t),
                ),
                ayuda:
                    'Queda registrado con su RUT: es quien responde por la '
                    'herramienta hasta devolverla.',
              ),
              const SizedBox(height: 18),
              CampoConEtiqueta(
                etiqueta: 'Devolución esperada',
                campo: PanelTocable(
                  semanticLabel:
                      'Devolución esperada ${Formato.fechaHora(_devolucion)}. Tocar para cambiar',
                  onTap: _enviando ? null : _elegirFecha,
                  child: Row(
                    children: [
                      const Icon(
                        Icons.event_outlined,
                        size: 22,
                        color: AppColors.secondary,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          Formato.fechaHora(_devolucion),
                          style: const TextStyle(
                            fontFamily: AppTheme.monoFamily,
                            fontSize: 14,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                      const Text(
                        'Cambiar',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: AppColors.accentFill,
                        ),
                      ),
                    ],
                  ),
                ),
                ayuda:
                    'Pasada esta hora, la herramienta aparece como vencida y se '
                    'genera una alerta.',
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                MensajeError(mensaje: _error!),
              ],
              const SizedBox(height: 22),
              BotonEnvio(
                texto: 'Autorizar préstamo',
                textoEnviando: 'Autorizando…',
                enviando: _enviando,
                alPresionar: _autorizar,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
