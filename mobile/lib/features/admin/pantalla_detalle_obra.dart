import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formato.dart';
import '../../core/network/errores.dart';
import '../../core/network/idempotencia.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_forma.dart';
import '../../core/theme/app_theme.dart';
import '../../data/api/dominio_api.dart';
import '../../data/modelos/detalle_obra.dart';
import '../../data/modelos/obra.dart';
import '../../data/modelos/usuario.dart';
import '../../shared_widgets/estados.dart';
import '../../shared_widgets/panel.dart';
import '../auth/sesion_controller.dart';
import '../bodega/pantalla_bodega.dart';
import '../obra/obra_activa.dart';
import 'pantalla_usuarios.dart';

/// Ficha de una obra: quién la dirige, quién trabaja en ella y qué tiene.
///
/// El orden de las secciones es el de las preguntas que llegan por teléfono:
/// "¿quién está a cargo?", "¿cuánta gente hay?", "¿qué falta?", "¿qué
/// herramientas andan fuera?". Lo que se está agotando va antes que el resto
/// del stock, porque es lo único de esa lista que pide hacer algo hoy.
class PantallaDetalleObra extends ConsumerWidget {
  const PantallaDetalleObra({super.key, required this.obra});

  /// La obra tal como venía en la lista: se usa para el título mientras carga
  /// el detalle, para no mostrar una pantalla en blanco.
  final Obra obra;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detalle = ref.watch(detalleObraProvider(obra.id));

    return Scaffold(
      appBar: AppBar(title: Text(obra.nombre, overflow: TextOverflow.ellipsis)),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: () async =>
              ref.refresh(detalleObraProvider(obra.id).future),
          child: Contenido<DetalleObra>(
            valor: detalle,
            alReintentar: () => ref.invalidate(detalleObraProvider(obra.id)),
            constructor: (d) => ListView(
              padding: AppEspacio.pantalla,
              children: [
                _Encabezado(obra: d.obra),
                const SizedBox(height: AppEspacio.sm + 4),
                _Resumen(detalle: d),
                const SizedBox(height: AppEspacio.lg),
                _SeccionACargo(detalle: d),
                const SizedBox(height: AppEspacio.lg),
                _SeccionEquipo(detalle: d),
                const SizedBox(height: AppEspacio.lg),
                _SeccionMateriales(detalle: d),
                const SizedBox(height: AppEspacio.lg),
                _SeccionHerramientas(detalle: d),
                if (d.obra.activa) ...[
                  const SizedBox(height: AppEspacio.xl),
                  _BotonCerrar(obra: d.obra, resumen: d.resumen),
                ],
                const SizedBox(height: AppEspacio.lg),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// --- Encabezado y resumen ------------------------------------------------------

class _Encabezado extends StatelessWidget {
  const _Encabezado({required this.obra});

  final Obra obra;

  @override
  Widget build(BuildContext context) {
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Text(obra.nombre, style: AppTexto.titulo)),
              const SizedBox(width: AppEspacio.sm),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: obra.activa
                    ? ChipEstado.exito('Activa')
                    : ChipEstado.neutro('Cerrada'),
              ),
            ],
          ),
          const SizedBox(height: AppEspacio.sm),
          _LineaIcono(icono: Icons.business_outlined, texto: obra.cliente),
          const SizedBox(height: AppEspacio.xs),
          _LineaIcono(icono: Icons.place_outlined, texto: obra.ubicacion),
        ],
      ),
    );
  }
}

class _LineaIcono extends StatelessWidget {
  const _LineaIcono({required this.icono, required this.texto});

  final IconData icono;
  final String texto;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ExcludeSemantics(
          child: Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icono, size: 16, color: AppColors.textFaint),
          ),
        ),
        const SizedBox(width: AppEspacio.sm),
        Expanded(child: Text(texto, style: AppTexto.cuerpoChico)),
      ],
    );
  }
}

/// Las cuatro cifras de la obra y, debajo, cuánta plata hay parada en ella.
class _Resumen extends StatelessWidget {
  const _Resumen({required this.detalle});

  final DetalleObra detalle;

  @override
  Widget build(BuildContext context) {
    final r = detalle.resumen;
    return Panel(
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Contador(
                  valor: '${r.cantidadTrabajadores}',
                  rotulo: 'Personas',
                ),
              ),
              Expanded(
                child: Contador(
                  valor: '${r.materialesPorReponer}',
                  rotulo: 'Por\nreponer',
                  color: r.materialesCriticos > 0
                      ? AppColors.destructiveDark
                      : r.materialesBajos > 0
                      ? AppColors.warningDark
                      : AppColors.primary,
                ),
              ),
              Expanded(
                child: Contador(
                  valor: '${r.herramientasEnObra}',
                  rotulo: 'Herram.\nprestadas',
                  color: r.herramientasVencidas > 0
                      ? AppColors.destructiveDark
                      : AppColors.primary,
                ),
              ),
              Expanded(
                child: Contador(
                  valor: '${r.alertasPendientes}',
                  rotulo: 'Alertas',
                  color: r.alertasPendientes > 0
                      ? AppColors.warningDark
                      : AppColors.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppEspacio.md),
          const Divider(height: 1, color: AppColors.border),
          const SizedBox(height: AppEspacio.sm + 4),
          _FilaValor(rotulo: 'Materiales en bodega', valor: r.valorMateriales),
          const SizedBox(height: AppEspacio.xs + 2),
          _FilaValor(
            rotulo: 'Herramientas prestadas',
            valor: r.valorHerramientas,
          ),
        ],
      ),
    );
  }
}

class _FilaValor extends StatelessWidget {
  const _FilaValor({required this.rotulo, required this.valor});

  final String rotulo;
  final double valor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(rotulo, style: AppTexto.cuerpoChico)),
        Text(
          Formato.pesos(valor),
          style: const TextStyle(
            fontFeatures: AppTexto.tabulares,
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.primary,
          ),
        ),
      ],
    );
  }
}

/// Encabezado de sección con un conteo a la derecha y, si hace falta, una
/// acción.
class _TituloSeccion extends StatelessWidget {
  const _TituloSeccion(this.texto, {this.accion});

  final String texto;
  final Widget? accion;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppEspacio.sm + 4),
      child: Row(
        children: [
          Expanded(child: Etiqueta(texto)),
          ?accion,
        ],
      ),
    );
  }
}

// --- A cargo -------------------------------------------------------------------

class _SeccionACargo extends ConsumerWidget {
  const _SeccionACargo({required this.detalle});

  final DetalleObra detalle;

  /// Solo un jefe de terreno o un admin puede dirigir una obra: el backend
  /// rechaza cualquier otro rol, así que la lista se filtra acá en vez de
  /// ofrecer opciones que van a fallar.
  Future<void> _elegirJefe(BuildContext context, WidgetRef ref) async {
    final obra = detalle.obra;
    final usuarios = await ref
        .read(usuariosProvider.future)
        .catchError((_) => const <UsuarioEmpresa>[]);
    final candidatos = usuarios
        .where((u) => u.rol == 'JEFE_TERRENO' || u.rol == 'ADMIN')
        .toList();
    if (!context.mounted) return;

    if (candidatos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No hay ningún usuario con rol Jefe de terreno o Administrador.',
          ),
        ),
      );
      return;
    }

    final elegido = await showModalBottomSheet<UsuarioEmpresa>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Jefe a cargo de ${obra.nombre}',
                  style: AppTexto.subtitulo,
                ),
              ),
            ),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: candidatos.length,
                separatorBuilder: (_, _) =>
                    const Divider(height: 1, color: AppColors.border),
                itemBuilder: (_, i) {
                  final u = candidatos[i];
                  return ListTile(
                    leading: Iniciales(u.nombre, tamano: 38),
                    title: Text(u.nombre),
                    subtitle: Text(
                      u.rut ?? 'sin RUT registrado',
                      style: TextStyle(
                        fontFamily: AppTheme.monoFamily,
                        fontSize: 12,
                        color: u.rut == null
                            ? AppColors.warningDark
                            : AppColors.secondary,
                      ),
                    ),
                    onTap: () => Navigator.of(context).pop(u),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (elegido == null) return;
    try {
      await ref.read(obrasApiProvider).asignarJefe(obra.id, elegido.id);
      ref.invalidate(todasLasObrasProvider);
      ref.invalidate(obrasActivasProvider);
      ref.invalidate(detalleObraProvider(obra.id));
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${elegido.nombre} queda a cargo de ${obra.nombre}'),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(mensajeDeError(e))));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final jefes = detalle.jefes;
    // Solo el admin asigna jefe; el resto ve la ficha sin el botón.
    final esAdmin = ref.watch(sesionProvider).valueOrNull?.rol == 'ADMIN';
    final puedeAsignar = esAdmin && detalle.obra.activa;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TituloSeccion(
          'A cargo',
          accion: puedeAsignar
              ? TextButton(
                  onPressed: () => _elegirJefe(context, ref),
                  child: Text(jefes.isEmpty ? 'Asignar jefe' : 'Cambiar jefe'),
                )
              : null,
        ),
        if (jefes.isEmpty)
          Panel(
            color: AppColors.warningTint,
            borderColor: AppColors.warning,
            child: Row(
              children: [
                const Icon(
                  Icons.engineering_outlined,
                  color: AppColors.warningDark,
                ),
                const SizedBox(width: AppEspacio.sm + 4),
                Expanded(
                  child: Text(
                    'Sin jefe de terreno asignado. Nadie responde por la '
                    'desviación de esta obra.',
                    style: AppTexto.cuerpoChico.copyWith(
                      color: AppColors.warningInk,
                    ),
                  ),
                ),
              ],
            ),
          )
        else
          for (final j in jefes) ...[
            Panel(
              child: Row(
                children: [
                  Iniciales(j.nombre, tamano: 40),
                  const SizedBox(width: AppEspacio.sm + 4),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          j.nombre,
                          style: AppTexto.cuerpo.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          j.rut ?? 'sin RUT registrado',
                          style: AppTexto.dato,
                        ),
                      ],
                    ),
                  ),
                  ChipEstado.neutro(nombreDeRol(j.rol)),
                ],
              ),
            ),
            const SizedBox(height: AppEspacio.sm),
          ],
      ],
    );
  }
}

// --- Equipo --------------------------------------------------------------------

class _SeccionEquipo extends StatelessWidget {
  const _SeccionEquipo({required this.detalle});

  final DetalleObra detalle;

  @override
  Widget build(BuildContext context) {
    final trabajadores = detalle.trabajadores;
    final porCuadrilla = <String, List<TrabajadorDeObra>>{};
    for (final t in trabajadores) {
      porCuadrilla
          .putIfAbsent(t.cuadrillaNombre ?? 'Sin cuadrilla', () => [])
          .add(t);
    }
    for (final lista in porCuadrilla.values) {
      lista.sort((a, b) => a.nombre.compareTo(b.nombre));
    }
    final cuadrillas = detalle.cuadrillas.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TituloSeccion(
          'Equipo',
          accion: Text(
            '${trabajadores.length} en $cuadrillas '
            '${cuadrillas == 1 ? 'cuadrilla' : 'cuadrillas'}',
            style: AppTexto.dato,
          ),
        ),
        if (trabajadores.isEmpty)
          Panel(
            child: Text(
              detalle.cuadrillas.isEmpty
                  ? 'La obra no tiene cuadrillas. Los trabajadores se asocian '
                        'a una obra a través de su cuadrilla.'
                  : 'Las cuadrillas de esta obra todavía no tienen '
                        'trabajadores.',
              style: AppTexto.cuerpoChico,
            ),
          )
        else
          for (final e in porCuadrilla.entries) ...[
            _Cuadrilla(nombre: e.key, trabajadores: e.value),
            const SizedBox(height: AppEspacio.sm),
          ],
      ],
    );
  }
}

/// Una cuadrilla plegable. Plegada muestra el conteo; con veinte personas por
/// cuadrilla, desplegarlas todas empujaría el stock fuera de la pantalla.
class _Cuadrilla extends StatefulWidget {
  const _Cuadrilla({required this.nombre, required this.trabajadores});

  final String nombre;
  final List<TrabajadorDeObra> trabajadores;

  @override
  State<_Cuadrilla> createState() => _CuadrillaState();
}

class _CuadrillaState extends State<_Cuadrilla> {
  bool _abierta = false;

  @override
  Widget build(BuildContext context) {
    final n = widget.trabajadores.length;
    return Material(
      color: AppColors.card,
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(
        borderRadius: AppForma.borde,
        side: BorderSide(color: AppColors.border),
      ),
      child: Column(
        children: [
          Semantics(
            button: true,
            expanded: _abierta,
            label: '${widget.nombre}, $n trabajadores',
            excludeSemantics: true,
            child: InkWell(
              onTap: () => setState(() => _abierta = !_abierta),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppEspacio.md,
                  vertical: 14,
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.groups_outlined,
                      size: 20,
                      color: AppColors.secondary,
                    ),
                    const SizedBox(width: AppEspacio.sm + 4),
                    Expanded(
                      child: Text(
                        widget.nombre,
                        style: AppTexto.cuerpo.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Text(
                      n == 1 ? '1 persona' : '$n personas',
                      style: AppTexto.dato,
                    ),
                    const SizedBox(width: AppEspacio.xs),
                    AnimatedRotation(
                      turns: _abierta ? 0.5 : 0,
                      duration: const Duration(milliseconds: 180),
                      child: const Icon(
                        Icons.expand_more,
                        color: AppColors.secondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: !_abierta
                ? const SizedBox(width: double.infinity)
                : Column(
                    children: [
                      const Divider(height: 1, color: AppColors.border),
                      for (final t in widget.trabajadores)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppEspacio.md,
                            vertical: 10,
                          ),
                          child: Row(
                            children: [
                              Iniciales(t.nombre, tamano: 32),
                              const SizedBox(width: AppEspacio.sm + 4),
                              Expanded(
                                child: Text(
                                  t.nombre,
                                  style: AppTexto.cuerpoChico.copyWith(
                                    fontSize: 14,
                                    color: AppColors.primary,
                                  ),
                                ),
                              ),
                              if (t.rut != null)
                                Text(t.rut!, style: AppTexto.dato),
                            ],
                          ),
                        ),
                      const SizedBox(height: AppEspacio.xs),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

// --- Materiales ----------------------------------------------------------------

class _SeccionMateriales extends StatefulWidget {
  const _SeccionMateriales({required this.detalle});

  final DetalleObra detalle;

  @override
  State<_SeccionMateriales> createState() => _SeccionMaterialesState();
}

class _SeccionMaterialesState extends State<_SeccionMateriales> {
  /// Con el filtro puesto se ve solo lo que hay que reponer. Arranca así si
  /// algo falta: es lo que se viene a buscar.
  late bool _soloFaltantes = widget.detalle.faltantes.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    // El backend ya los manda en este orden; se reordena igual para que la
    // pantalla no dependa de eso.
    final todos = [...widget.detalle.materiales]
      ..sort((a, b) {
        final porEstado = a.estado.index.compareTo(b.estado.index);
        return porEstado != 0 ? porEstado : a.nombre.compareTo(b.nombre);
      });
    final faltantes = widget.detalle.faltantes;
    final visibles = _soloFaltantes ? faltantes : todos;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TituloSeccion(
          'Materiales',
          accion: Text('${todos.length} en bodega', style: AppTexto.dato),
        ),
        if (todos.isEmpty)
          Panel(
            child: Text(
              'Esta obra todavía no tiene movimientos de bodega. El stock '
              'aparece con la primera recepción.',
              style: AppTexto.cuerpoChico,
            ),
          )
        else ...[
          if (faltantes.isNotEmpty) ...[
            SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(
                  value: true,
                  label: Text('Por reponer (${faltantes.length})'),
                ),
                ButtonSegment(
                  value: false,
                  label: Text('Todos (${todos.length})'),
                ),
              ],
              selected: {_soloFaltantes},
              onSelectionChanged: (s) =>
                  setState(() => _soloFaltantes = s.first),
            ),
            const SizedBox(height: AppEspacio.sm + 4),
          ],
          for (final m in visibles) ...[
            _FilaMaterialDeObra(material: m),
            const SizedBox(height: AppEspacio.sm),
          ],
        ],
      ],
    );
  }
}

class _FilaMaterialDeObra extends StatelessWidget {
  const _FilaMaterialDeObra({required this.material});

  final MaterialDeObra material;

  @override
  Widget build(BuildContext context) {
    final m = material;
    final unidad = unidadDe(m.categoria);
    final (franja, chip) = switch (m.estado) {
      EstadoStock.critico => (
        AppColors.destructive,
        ChipEstado.critico('Bajo el mínimo'),
      ),
      EstadoStock.bajo => (AppColors.warning, ChipEstado.aviso('Por agotarse')),
      EstadoStock.ok => (null, null),
    };

    return Semantics(
      label:
          '${m.nombre}: ${Formato.cantidad(m.stock)} $unidad, mínimo '
          '${Formato.cantidad(m.stockMinimo)}. '
          '${chip == null ? '' : '${chip.texto}. '}'
          'Valor ${Formato.pesos(m.valorStock)}',
      excludeSemantics: true,
      child: Panel(
        borderIzquierdo: franja,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        m.nombre,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(m.sku, style: AppTexto.dato),
                    ],
                  ),
                ),
                const SizedBox(width: AppEspacio.sm),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${Formato.cantidad(m.stock)} $unidad',
                      style: TextStyle(
                        fontFeatures: AppTexto.tabulares,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: switch (m.estado) {
                          EstadoStock.critico => AppColors.destructiveDark,
                          EstadoStock.bajo => AppColors.warningDark,
                          EstadoStock.ok => AppColors.primary,
                        },
                      ),
                    ),
                    Text(
                      'mín. ${Formato.cantidad(m.stockMinimo)}',
                      style: AppTexto.dato.copyWith(fontSize: 11.5),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: AppEspacio.sm + 2),
            BarraStock(stock: m.stock, minimo: m.stockMinimo, estado: m.estado),
            const SizedBox(height: AppEspacio.sm + 2),
            Row(
              children: [
                ?chip,
                if (chip != null) const SizedBox(width: AppEspacio.sm),
                Expanded(
                  child: Text(
                    '${m.ultimoCostoUnitario == null ? 'Catálogo' : 'Costo'} '
                    '${Formato.pesos(m.costoVigente)} / $unidad',
                    style: AppTexto.dato.copyWith(fontSize: 11.5),
                  ),
                ),
                Text(
                  Formato.pesos(m.valorStock),
                  style: const TextStyle(
                    fontFeatures: AppTexto.tabulares,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
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

/// Barra de stock con una marca en el mínimo.
///
/// El mínimo queda siempre a la mitad de la barra —el tope es el doble del
/// mínimo—, así que en cualquier material se lee igual: bajo la marca, falta.
/// Una barra contra "capacidad" no sirve acá porque la bodega de obra no
/// tiene capacidad definida.
class BarraStock extends StatelessWidget {
  const BarraStock({
    super.key,
    required this.stock,
    required this.minimo,
    required this.estado,
  });

  final double stock;
  final double minimo;
  final EstadoStock estado;

  @override
  Widget build(BuildContext context) {
    final tope = minimo > 0 ? minimo * 2 : (stock > 0 ? stock : 1);
    final proporcion = (stock / tope).clamp(0.0, 1.0);
    final color = switch (estado) {
      EstadoStock.critico => AppColors.destructive,
      EstadoStock.bajo => AppColors.warning,
      EstadoStock.ok => AppColors.success,
    };

    return ExcludeSemantics(
      child: SizedBox(
        height: 8,
        child: LayoutBuilder(
          builder: (context, c) => Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                decoration: const BoxDecoration(
                  color: AppColors.sunken,
                  borderRadius: BorderRadius.all(Radius.circular(4)),
                ),
              ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutCubic,
                width: c.maxWidth * proporcion,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: const BorderRadius.all(Radius.circular(4)),
                ),
              ),
              if (minimo > 0)
                Positioned(
                  left: c.maxWidth / 2 - 1,
                  top: -2,
                  bottom: -2,
                  child: Container(width: 2, color: AppColors.primary),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// --- Herramientas --------------------------------------------------------------

class _SeccionHerramientas extends StatelessWidget {
  const _SeccionHerramientas({required this.detalle});

  final DetalleObra detalle;

  @override
  Widget build(BuildContext context) {
    final grupos = detalle.herramientasAgrupadas;
    final total = detalle.herramientas.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TituloSeccion(
          'Herramientas',
          accion: Text(
            total == 1 ? '1 en la obra' : '$total en la obra',
            style: AppTexto.dato,
          ),
        ),
        if (grupos.isEmpty)
          Panel(
            child: Text(
              'No hay herramientas prestadas en esta obra.',
              style: AppTexto.cuerpoChico,
            ),
          )
        else
          for (final g in grupos) ...[
            _GrupoHerramienta(grupo: g),
            const SizedBox(height: AppEspacio.sm),
          ],
      ],
    );
  }
}

class _GrupoHerramienta extends StatelessWidget {
  const _GrupoHerramienta({required this.grupo});

  final GrupoHerramientas grupo;

  @override
  Widget build(BuildContext context) {
    final g = grupo;
    return Panel(
      borderIzquierdo: g.vencidas > 0 ? AppColors.destructive : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  g.nombre,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
              ),
              Text(
                '× ${g.cantidad}',
                style: const TextStyle(
                  fontFeatures: AppTexto.tabulares,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            'Reposición ${Formato.pesos(g.valor)}',
            style: AppTexto.dato.copyWith(fontSize: 11.5),
          ),
          const SizedBox(height: AppEspacio.sm),
          for (final h in g.unidades)
            Padding(
              padding: const EdgeInsets.only(top: AppEspacio.xs + 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Icon(
                      Icons.person_outline,
                      size: 16,
                      color: h.vencida
                          ? AppColors.destructiveDark
                          : AppColors.textFaint,
                    ),
                  ),
                  const SizedBox(width: AppEspacio.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          h.prestadaA ?? 'En bodega de la obra',
                          style: AppTexto.cuerpoChico.copyWith(
                            color: AppColors.primary,
                          ),
                        ),
                        Text(
                          h.fechaDevolEsperada == null
                              ? h.codigoQr
                              : '${h.codigoQr} · devuelve '
                                    '${Formato.relativa(h.fechaDevolEsperada!)}',
                          style: AppTexto.dato.copyWith(fontSize: 11.5),
                        ),
                      ],
                    ),
                  ),
                  if (h.vencida) ChipEstado.critico('Vencida'),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// --- Cierre --------------------------------------------------------------------

/// Cerrar una obra congela su comparación entre presupuesto y consumo. El
/// backend rechaza con 409 si quedan herramientas fuera o alertas sin
/// resolver; como la ficha ya sabe las dos cosas, lo dice antes de intentarlo.
class _BotonCerrar extends ConsumerStatefulWidget {
  const _BotonCerrar({required this.obra, required this.resumen});

  final Obra obra;
  final ResumenObra resumen;

  @override
  ConsumerState<_BotonCerrar> createState() => _BotonCerrarState();
}

class _BotonCerrarState extends ConsumerState<_BotonCerrar> {
  bool _enviando = false;
  final _intento = IntentoIdempotente();

  Future<void> _cerrar() async {
    final r = widget.resumen;
    final pendientes = [
      if (r.herramientasEnObra > 0)
        '${r.herramientasEnObra} herramientas siguen prestadas',
      if (r.alertasPendientes > 0)
        '${r.alertasPendientes} alertas sin resolver',
    ];

    final confirmado = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('¿Cerrar ${widget.obra.nombre}?'),
        content: Text(
          pendientes.isEmpty
              ? 'Después de cerrarla no se puede registrar más movimiento '
                    'contra ella, y su desviación queda fijada. No se puede '
                    'reabrir.'
              : 'Todavía hay ${pendientes.join(' y ')}. El sistema no deja '
                    'cerrar la obra hasta resolverlo.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(pendientes.isEmpty ? 'Cancelar' : 'Entendido'),
          ),
          if (pendientes.isEmpty)
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.destructiveDark,
                minimumSize: const Size(0, 44),
              ),
              child: const Text('Cerrar obra'),
            ),
        ],
      ),
    );
    if (confirmado != true || _enviando) return;

    setState(() => _enviando = true);
    try {
      await ref
          .read(obrasApiProvider)
          .cerrar(widget.obra.id, clave: _intento.clavePara([widget.obra.id]));
      ref.invalidate(todasLasObrasProvider);
      ref.invalidate(obrasActivasProvider);
      ref.invalidate(detalleObraProvider(widget.obra.id));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${widget.obra.nombre} quedó cerrada')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(mensajeDeError(e))));
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Cerrar es del admin: los demás roles ven la ficha sin el botón.
    final esAdmin = ref.watch(sesionProvider).valueOrNull?.rol == 'ADMIN';
    if (!esAdmin) return const SizedBox.shrink();

    return OutlinedButton.icon(
      onPressed: _enviando ? null : _cerrar,
      icon: _enviando
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.lock_outline, size: 18),
      label: Text(_enviando ? 'Cerrando…' : 'Cerrar obra'),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        side: const BorderSide(color: AppColors.borderControl),
        foregroundColor: AppColors.destructiveDark,
      ),
    );
  }
}
