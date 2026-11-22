import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formato.dart';
import '../../core/network/errores.dart';
import '../../core/network/idempotencia.dart';
import '../../core/theme/app_colors.dart';
import '../../data/api/dominio_api.dart';
import '../../data/modelos/material.dart';
import '../../data/modelos/presupuesto.dart';
import '../../shared_widgets/campo_texto.dart';
import '../../shared_widgets/estados.dart';
import '../../shared_widgets/panel.dart';
import '../../shared_widgets/presion.dart';
import '../bodega/bodega_providers.dart';
import 'presupuesto_providers.dart';

/// Agrega un material al presupuesto (D5).
///
/// El precio no se teclea: el backend copia el vigente del catálogo al agregar
/// (RN-13), y la pantalla lo muestra para que el jefe vea con qué valor queda.
class PantallaAgregarItem extends ConsumerStatefulWidget {
  const PantallaAgregarItem({super.key, required this.presupuesto});

  final Presupuesto presupuesto;

  @override
  ConsumerState<PantallaAgregarItem> createState() =>
      _PantallaAgregarItemState();
}

class _PantallaAgregarItemState extends ConsumerState<PantallaAgregarItem> {
  final _formulario = GlobalKey<FormState>();
  final _cantidad = TextEditingController();
  final _intento = IntentoIdempotente();

  MaterialObra? _material;
  bool _enviando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // El subtotal estimado sigue a lo que se teclea.
    _cantidad.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _cantidad.dispose();
    super.dispose();
  }

  double? get _cantidadValida {
    final v = Formato.numero(_cantidad.text);
    return v != null && v.isFinite && v > 0 ? v : null;
  }

  Future<void> _agregar() async {
    if (_enviando) return;
    final material = _material;
    if (material == null) {
      setState(() => _error = 'Elige un material.');
      return;
    }
    if (!_formulario.currentState!.validate()) return;
    final cantidad = _cantidadValida!;

    setState(() {
      _enviando = true;
      _error = null;
    });
    try {
      final presupuestoId = widget.presupuesto.id;
      await ref
          .read(presupuestosApiProvider)
          .agregarItem(
            presupuestoId,
            materialId: material.id,
            cantidad: cantidad,
            clave: _intento.clavePara([presupuestoId, material.id, cantidad]),
          );
      ref.invalidate(itemsPresupuestoProvider(presupuestoId));
      ref.invalidate(presupuestoDeObraProvider(widget.presupuesto.obraId));
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      Navigator.of(context).pop();
    } catch (e) {
      // Un 409 acá es "se congeló mientras tanto": el total y los botones de
      // la pantalla anterior ya no son los de ahora.
      ref.invalidate(presupuestoDeObraProvider(widget.presupuesto.obraId));
      if (mounted) setState(() => _error = mensajeDeError(e));
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final catalogo = ref.watch(catalogoProvider);
    final material = _material;
    final cantidad = _cantidadValida;

    return PopScope(
      canPop: !_enviando,
      child: Scaffold(
        appBar: AppBar(title: const Text('Agregar ítem')),
        body: SafeArea(
          top: false,
          child: Form(
            key: _formulario,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Etiqueta('Material'),
                const SizedBox(height: 8),
                Contenido<List<MaterialObra>>(
                  valor: catalogo,
                  alReintentar: () => ref.invalidate(catalogoProvider),
                  estaVacio: (l) => l.isEmpty,
                  vacio: const Vacio(
                    icono: Icons.inventory_2_outlined,
                    titulo: 'El catálogo está vacío',
                    detalle:
                        'Un administrador tiene que cargar los materiales '
                        'antes de armar el presupuesto.',
                  ),
                  constructor: (lista) => LayoutBuilder(
                    builder: (context, c) => DropdownMenu<MaterialObra>(
                      width: c.maxWidth,
                      enabled: !_enviando,
                      enableFilter: true,
                      requestFocusOnTap: true,
                      hintText: 'Busca por nombre',
                      onSelected: (m) => setState(() => _material = m),
                      dropdownMenuEntries: [
                        for (final m in lista)
                          DropdownMenuEntry(
                            value: m,
                            label: m.nombre,
                            labelWidget: Text(
                              m.nombre,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                if (material != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    '${material.sku} · precio vigente '
                    '${Formato.pesos(material.precioUnitario)}',
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppColors.secondary,
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                const Etiqueta('Cantidad'),
                const SizedBox(height: 8),
                CampoTexto(
                  controlador: _cantidad,
                  hint: 'Ej. 12',
                  icono: Icons.numbers,
                  mono: true,
                  habilitado: !_enviando,
                  teclado: const TextInputType.numberWithOptions(decimal: true),
                  formatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                  ],
                  validador: (v) => _errorDeCantidad(v ?? ''),
                  alEnviar: (_) => _agregar(),
                ),
                if (material != null && cantidad != null) ...[
                  const SizedBox(height: 14),
                  Panel(
                    color: AppColors.sunken,
                    child: Row(
                      children: [
                        const Expanded(child: Text('Subtotal estimado')),
                        Text(
                          Formato.pesos(cantidad * material.precioUnitario),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  MensajeError(mensaje: _error!),
                ],
                const SizedBox(height: 22),
                BotonEnvio(
                  texto: 'Agregar al presupuesto',
                  textoEnviando: 'Agregando…',
                  enviando: _enviando,
                  alPresionar: _agregar,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String? _errorDeCantidad(String texto) {
    if (texto.trim().isEmpty) return 'Falta la cantidad';
    final v = Formato.numero(texto);
    if (v == null || !v.isFinite) return 'Escribe la cantidad como número';
    if (v <= 0) return 'La cantidad tiene que ser mayor que cero';
    return null;
  }
}
