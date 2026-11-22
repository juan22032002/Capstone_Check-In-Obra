import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formato.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_forma.dart';
import '../../core/theme/app_theme.dart';
import '../../data/modelos/alerta.dart';
import '../../data/modelos/kardex.dart';
import '../../shared_widgets/estados.dart';
import '../../shared_widgets/panel.dart';
import 'bodega_providers.dart';
import 'pantalla_cierre_turno.dart';
import 'pantalla_escaneo.dart';
import 'pantalla_prestamo.dart';
import 'pantalla_solicitudes.dart';

/// Lo primero que ve el bodeguero: cómo va el turno y qué requiere atención.
class PantallaInicioBodega extends ConsumerWidget {
  const PantallaInicioBodega({super.key, required this.alIrA});

  /// Salta a otra pestaña del shell. Los accesos rápidos llevan a Bodega y a
  /// Alertas, que ya existen abajo: duplicar la pantalla sería duplicar el
  /// estado.
  final void Function(int indice) alIrA;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final movimientosHoy = ref.watch(movimientosDeHoyProvider);
    final prestamos = ref.watch(prestamosAbiertosProvider);
    final alertas = ref.watch(alertasSinResolverProvider);

    return RefreshIndicator(
      onRefresh: () async => recargarBodega(ref),
      child: ListView(
        padding: AppEspacio.pantalla,
        children: [
          // El turno es el único marco oscuro de la app dentro de un shell: es
          // lo primero que se mira al tomar el teléfono, y el contraste lo
          // separa de todo lo que viene debajo, que es para actuar.
          Panel(
            padding: EdgeInsets.zero,
            color: AppColors.surfaceDark,
            borderColor: AppColors.surfaceDark,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppEspacio.md,
                    AppEspacio.md,
                    AppEspacio.md,
                    AppEspacio.lg - 4,
                  ),
                  child: Column(
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Turno de hoy',
                          style: AppTexto.rotulo.copyWith(
                            color: AppColors.textOnDark,
                          ),
                        ),
                      ),
                      const SizedBox(height: AppEspacio.md),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Contador(
                              valor:
                                  '${movimientosHoy.valueOrNull?.length ?? 0}',
                              rotulo: 'Movimientos\ndel turno',
                              color: Colors.white,
                              sobreOscuro: true,
                            ),
                          ),
                          Expanded(
                            child: Contador(
                              valor: '${prestamos.valueOrNull?.length ?? 0}',
                              rotulo: 'Herramientas\nprestadas',
                              color: Colors.white,
                              sobreOscuro: true,
                            ),
                          ),
                          Expanded(
                            child: Contador(
                              valor: '${alertas.valueOrNull?.length ?? 0}',
                              rotulo: 'Alertas\nsin resolver',
                              color: (alertas.valueOrNull?.isEmpty ?? true)
                                  ? Colors.white
                                  : AppColors.destructiveOnDark,
                              sobreOscuro: true,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: AppColors.borderOnDark),
                _BotonCierre(),
              ],
            ),
          ),
          const SizedBox(height: AppEspacio.md),
          const _Solicitudes(),
          const SizedBox(height: AppEspacio.lg),
          const Etiqueta('Escanear'),
          const SizedBox(height: AppEspacio.sm + 4),
          // El escaneo va arriba de "Registrar" porque es por donde empieza el
          // trabajo del mesón: primero se identifica a quien viene a buscar
          // algo, o lo que trae en la mano, y recién después se elige qué
          // movimiento anotar.
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _AccesoRapido(
                    icono: Icons.qr_code_scanner,
                    titulo: 'Credencial o pedido',
                    detalle: 'Aprobar lo que pidió o entregar su pedido QR',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const PantallaEscaneoCredencial(),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AppEspacio.sm + 4),
                Expanded(
                  child: _AccesoRapido(
                    icono: Icons.barcode_reader,
                    titulo: 'Código de barras',
                    detalle: 'Encontrar un material o una herramienta',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const PantallaEscaneoCodigo(),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppEspacio.lg),
          const Etiqueta('Capital en la obra'),
          const SizedBox(height: AppEspacio.sm + 4),
          const _ValorEnObra(),
          const SizedBox(height: AppEspacio.lg),
          const Etiqueta('Registrar'),
          const SizedBox(height: AppEspacio.sm + 4),
          // Las dos tarjetas del mismo alto. `stretch` solo no basta dentro de
          // un ListView: la altura que entra no está acotada, así que no hay
          // contra qué estirarse. `IntrinsicHeight` mide primero la más alta y
          // recién ahí `stretch` iguala la otra.
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _AccesoRapido(
                    icono: Icons.inventory_2_outlined,
                    titulo: 'Movimiento',
                    detalle: 'Recepción, despacho o consumo',
                    onTap: () => alIrA(1),
                  ),
                ),
                const SizedBox(width: AppEspacio.sm + 4),
                Expanded(
                  child: _AccesoRapido(
                    icono: Icons.handyman_outlined,
                    titulo: 'Préstamo',
                    detalle: 'Entregar una herramienta',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const PantallaPrestamo(),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppEspacio.lg),
          Row(
            children: [
              const Expanded(child: Etiqueta('Alertas sin resolver')),
              if ((alertas.valueOrNull ?? const []).isNotEmpty)
                TextButton(
                  onPressed: () => alIrA(3),
                  child: const Text('Ver todas'),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Contenido<List<Alerta>>(
            valor: alertas,
            alReintentar: () => ref.invalidate(alertasProvider),
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
                      'Nada pendiente en esta obra.',
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
                for (final alerta in lista.take(3)) ...[
                  _FilaAlertaResumen(alerta: alerta),
                  const SizedBox(height: AppEspacio.sm),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppEspacio.lg),
          const Etiqueta('Últimos movimientos'),
          const SizedBox(height: AppEspacio.sm + 4),
          Contenido<List<MovimientoKardex>>(
            valor: ref.watch(movimientosProvider),
            alReintentar: () => ref.invalidate(movimientosProvider),
            estaVacio: (l) => l.isEmpty,
            vacio: const Vacio(
              icono: Icons.receipt_long_outlined,
              titulo: 'Sin movimientos todavía',
              detalle:
                  'El kardex de esta obra está en blanco. La primera recepción '
                  'de material lo abre.',
            ),
            constructor: (lista) => Panel(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (var i = 0; i < lista.take(5).length; i++)
                    _FilaMovimiento(
                      movimiento: lista[i],
                      ultima: i == lista.take(5).length - 1,
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// La cola de solicitudes de la obra.
///
/// Va arriba de todo lo demás porque es gente esperando: el resto de la
/// pantalla son cifras que se pueden mirar en cualquier momento, esto no.
class _Solicitudes extends ConsumerWidget {
  const _Solicitudes();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final estado = ref.watch(solicitudesPendientesProvider);
    final pendientes = estado.valueOrNull;
    final fallo = estado.hasError;
    final hayGenteEsperando = (pendientes ?? 0) > 0;

    // Si la consulta falló, el panel no puede quedarse diciendo "cargando":
    // tocarlo reintenta en vez de llevar a una lista que tampoco va a cargar.
    void reintentar() {
      ref.invalidate(solicitudesMaterialProvider);
      ref.invalidate(solicitudesHerramientaProvider);
    }

    final (fondo, borde, colorTexto) = switch ((fallo, hayGenteEsperando)) {
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
      _ => (AppColors.card, AppColors.borderControl, AppColors.secondary),
    };

    return PanelTocable(
      semanticLabel: switch ((fallo, pendientes)) {
        (true, _) =>
          'No se pudieron cargar las solicitudes. Tocar para reintentar',
        (_, null) => 'Solicitudes pendientes, cargando',
        (_, 0) => 'Solicitudes: ninguna pendiente. Tocar para ver la cola',
        (_, 1) => '1 solicitud pendiente. Tocar para resolverla',
        (_, final n) => '$n solicitudes pendientes. Tocar para resolverlas',
      },
      borderColor: borde,
      color: fondo,
      onTap: fallo
          ? reintentar
          : () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const PantallaSolicitudesObra(),
              ),
            ),
      child: Row(
        children: [
          // Mismo cuadro que el resto de las filas. Sobre el panel tintado
          // (gente esperando, o error) el cuadro va en blanco: el hundido se
          // perdía contra el tinte.
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: fallo || hayGenteEsperando
                  ? AppColors.card
                  : AppColors.sunken,
              borderRadius: AppForma.borde,
            ),
            child: Icon(
              fallo ? Icons.error_outline : Icons.inbox_outlined,
              size: 21,
              color: fallo || hayGenteEsperando
                  ? colorTexto
                  : AppColors.primary,
            ),
          ),
          const SizedBox(width: AppEspacio.sm + 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Solicitudes', style: AppTexto.subtitulo),
                const SizedBox(height: 2),
                Text(switch ((fallo, pendientes)) {
                  (true, _) => 'No se pudieron cargar. Toca para reintentar.',
                  (_, null) => 'Cargando…',
                  (_, 0) => 'Nadie está esperando material ni herramientas',
                  (_, 1) => '1 trabajador espera respuesta',
                  (_, final n) => '$n solicitudes esperan respuesta',
                }, style: AppTexto.cuerpoChico.copyWith(color: colorTexto)),
              ],
            ),
          ),
          Icon(
            fallo ? Icons.refresh : Icons.chevron_right,
            size: 22,
            color: AppColors.secondary,
          ),
        ],
      ),
    );
  }
}

/// Cuánta plata está parada en la obra, separada en dos cifras.
///
/// Se muestran aparte porque son problemas distintos: el material en bodega es
/// capital inmovilizado que hay que consumir, y las herramientas afuera son
/// valor que hay que recuperar antes de cerrar el turno. Un solo total las
/// volvería una cifra decorativa.
class _ValorEnObra extends ConsumerWidget {
  const _ValorEnObra();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final valor = ref.watch(valorEnObraProvider);

    return Contenido<ValorEnObra>(
      valor: valor,
      alReintentar: () => recargarBodega(ref),
      constructor: (v) => Panel(
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            _FilaValor(
              icono: Icons.inventory_2_outlined,
              titulo: 'Materiales en bodega',
              detalle: 'Stock actual valorizado a precio de catálogo',
              monto: v.materialesEnBodega,
            ),
            const Divider(height: 1, color: AppColors.border),
            _FilaValor(
              icono: Icons.handyman_outlined,
              titulo: 'Herramientas fuera',
              detalle: switch (v.herramientasPrestadas) {
                0 => 'Todas en bodega',
                1 => '1 prestada · valor de reposición',
                final n => '$n prestadas · valor de reposición',
              },
              monto: v.herramientasFuera,
              alerta: v.herramientasPrestadas > 0,
              ultima: true,
            ),
          ],
        ),
      ),
    );
  }
}

class _FilaValor extends StatelessWidget {
  const _FilaValor({
    required this.icono,
    required this.titulo,
    required this.detalle,
    required this.monto,
    this.alerta = false,
    this.ultima = false,
  });

  final IconData icono;
  final String titulo;
  final String detalle;
  final double monto;
  final bool alerta;
  final bool ultima;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$titulo: ${Formato.pesos(monto)}. $detalle',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.all(AppEspacio.md),
        child: Row(
          children: [
            _IconoEnCuadro(icono),
            const SizedBox(width: AppEspacio.sm + 4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    titulo,
                    style: AppTexto.subtitulo.copyWith(fontSize: 14.5),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    detalle,
                    style: AppTexto.cuerpoChico.copyWith(
                      fontSize: 12.5,
                      color: AppColors.secondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppEspacio.sm + 4),
            Text(
              Formato.pesos(monto),
              style: AppTexto.subtitulo.copyWith(
                fontSize: 17,
                letterSpacing: -0.3,
                color: alerta ? AppColors.warningDark : AppColors.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BotonCierre extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fuera = ref.watch(prestamosAbiertosProvider).valueOrNull?.length ?? 0;

    return PanelTocable(
      semanticLabel: 'Cerrar el turno de bodega',
      borderColor: Colors.transparent,
      color: Colors.transparent,
      padding: const EdgeInsets.symmetric(
        horizontal: AppEspacio.md,
        vertical: AppEspacio.sm + 6,
      ),
      onTap: () => Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const PantallaCierreTurno())),
      child: Row(
        children: [
          const Icon(
            Icons.nightlight_outlined,
            size: 20,
            color: AppColors.textOnDark,
          ),
          const SizedBox(width: AppEspacio.sm + 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Cerrar turno',
                  style: AppTexto.subtitulo.copyWith(
                    fontSize: 14.5,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  fuera == 0
                      ? 'No hay herramientas fuera de bodega'
                      : '$fuera ${fuera == 1 ? 'herramienta sigue' : 'herramientas siguen'} fuera',
                  style: AppTexto.cuerpoChico.copyWith(
                    color: fuera == 0
                        ? AppColors.textOnDarkMuted
                        : AppColors.warningOnDark,
                  ),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.chevron_right,
            size: 22,
            color: AppColors.accentOnDark,
          ),
        ],
      ),
    );
  }
}

class _AccesoRapido extends StatelessWidget {
  const _AccesoRapido({
    required this.icono,
    required this.titulo,
    required this.detalle,
    required this.onTap,
  });

  final IconData icono;
  final String titulo;
  final String detalle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PanelTocable(
      semanticLabel: '$titulo. $detalle',
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Ícono en cuadro hundido y en tinta, no en naranjo: son cuatro
          // accesos iguales y el acento, repetido cuatro veces, dejaría de
          // señalar nada.
          _IconoEnCuadro(icono),
          const SizedBox(height: AppEspacio.sm + 6),
          Text(titulo, style: AppTexto.subtitulo.copyWith(fontSize: 15)),
          const SizedBox(height: 2),
          Text(
            detalle,
            style: AppTexto.cuerpoChico.copyWith(
              fontSize: 12.5,
              color: AppColors.secondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _FilaAlertaResumen extends StatelessWidget {
  const _FilaAlertaResumen({required this.alerta});

  final Alerta alerta;

  @override
  Widget build(BuildContext context) {
    return Panel(
      borderIzquierdo: switch (alerta.tipo) {
        'NO_DEVUELTA' => AppColors.destructive,
        'STOCK_CRITICO' => AppColors.warning,
        _ => AppColors.secondary,
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ChipEstado.critico(nombreDeAlerta(alerta.tipo)),
              const Spacer(),
              Text(
                Formato.antiguedad(alerta.fecha),
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.secondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            alerta.mensaje,
            style: const TextStyle(
              fontSize: 13,
              height: 1.35,
              color: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class _FilaMovimiento extends StatelessWidget {
  const _FilaMovimiento({required this.movimiento, required this.ultima});

  final MovimientoKardex movimiento;
  final bool ultima;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppEspacio.md,
        vertical: AppEspacio.sm + 5,
      ),
      decoration: BoxDecoration(
        border: ultima
            ? null
            : const Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _ChipTipo(tipo: movimiento.tipo),
                    const SizedBox(width: 8),
                    Text(
                      Formato.relativa(movimiento.fecha),
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.secondary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  movimiento.materialNombre,
                  style: AppTexto.cuerpo.copyWith(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (movimiento.receptor case final quien?) ...[
                  const SizedBox(height: 3),
                  Text(
                    'a $quien',
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppColors.secondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            Formato.cantidadConSigno(movimiento.cantidadConSigno),
            style: TextStyle(
              fontFeatures: AppTexto.tabulares,
              fontSize: 15,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.2,
              color: movimiento.entra
                  ? AppColors.successDark
                  : AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class _ChipTipo extends StatelessWidget {
  const _ChipTipo({required this.tipo});

  final String tipo;

  @override
  Widget build(BuildContext context) => switch (tipo) {
    'RECEPCION' => ChipEstado.exito('Recepción', conPunto: false),
    'DESPACHO' => ChipEstado.neutro('Despacho'),
    _ => ChipEstado.aviso('Consumo', conPunto: false),
  };
}

/// Ícono sobre un cuadro hundido. Le da a cada fila y a cada acceso un punto
/// de anclaje del mismo tamaño, sin gastar el acento en decoración.
class _IconoEnCuadro extends StatelessWidget {
  const _IconoEnCuadro(this.icono);

  final IconData icono;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Container(
        width: 40,
        height: 40,
        decoration: const BoxDecoration(
          color: AppColors.sunken,
          borderRadius: AppForma.borde,
        ),
        child: Icon(icono, size: 21, color: AppColors.primary),
      ),
    );
  }
}
