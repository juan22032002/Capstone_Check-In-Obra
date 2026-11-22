import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api/dominio_api.dart';
import '../../data/modelos/alerta.dart';
import '../../data/modelos/detalle_obra.dart';
import '../../data/modelos/herramienta.dart';
import '../../data/modelos/kardex.dart';
import '../../data/modelos/material.dart';
import '../../data/modelos/obra.dart';
import '../../data/modelos/pedido_especial.dart';
import '../../data/modelos/solicitud.dart';
import '../../data/modelos/trabajador.dart';
import '../obra/obra_activa.dart';

/// Id de la obra en curso. Todo lo de abajo depende de él, así que si cambia
/// la obra, se recarga la bodega entera sola.
final _obraIdProvider = Provider<int?>(
  (ref) => ref.watch(obraActivaProvider).valueOrNull?.id,
);

/// Todos los movimientos de kardex de la obra.
///
/// Se traen de una vez, y no el stock material por material, porque el stock
/// **es** la suma con signo de estos movimientos: pedirlo aparte serían 34
/// peticiones para reconstruir lo que ya viene en una. Con una obra de meses
/// esta lista crece y habrá que paginarla o pedirle el agregado al servidor;
/// para un turno de bodega son unos cientos de filas.
final movimientosProvider = FutureProvider<List<MovimientoKardex>>((ref) async {
  final obraId = ref.watch(_obraIdProvider);
  if (obraId == null) return const [];
  final movimientos = await ref.watch(kardexApiProvider).porObra(obraId);
  return movimientos..sort((a, b) => b.fecha.compareTo(a.fecha));
});

/// Saldo por material, calculado igual que en el backend.
final stockPorMaterialProvider = Provider<AsyncValue<Map<int, double>>>((ref) {
  return ref.watch(movimientosProvider).whenData((movimientos) {
    final saldos = <int, double>{};
    for (final m in movimientos) {
      saldos[m.materialId] = (saldos[m.materialId] ?? 0) + m.cantidadConSigno;
    }
    return saldos;
  });
});

final catalogoProvider = FutureProvider<List<MaterialObra>>(
  (ref) => ref.watch(materialesApiProvider).listar(),
);

/// Lo que se está agotando en todas las obras activas de la empresa.
final faltantesProvider = FutureProvider<List<MaterialFaltante>>(
  (ref) => ref.watch(materialesApiProvider).faltantes(),
);

/// El catálogo cruzado con el saldo de la obra, ordenado por criticidad:
/// arriba lo que hay que reponer.
final bodegaProvider = Provider<AsyncValue<List<MaterialConStock>>>((ref) {
  final catalogo = ref.watch(catalogoProvider);
  final saldos = ref.watch(stockPorMaterialProvider);

  if (catalogo is AsyncError) {
    return AsyncValue.error(catalogo.error!, catalogo.stackTrace!);
  }
  if (saldos is AsyncError) {
    return AsyncValue.error(saldos.error!, saldos.stackTrace!);
  }
  if (!catalogo.hasValue || !saldos.hasValue) return const AsyncValue.loading();

  final lista =
      [
        for (final m in catalogo.requireValue)
          MaterialConStock(material: m, stock: saldos.requireValue[m.id] ?? 0),
      ]..sort((a, b) {
        final porCriticidad = a.criticidad.compareTo(b.criticidad);
        return porCriticidad != 0
            ? porCriticidad
            : a.material.nombre.compareTo(b.material.nombre);
      });

  return AsyncValue.data(lista);
});

/// Los trabajadores de la obra, para elegir a quién se le entrega o se le
/// presta. El backend los alcanza por la cuadrilla, así que un trabajador sin
/// cuadrilla no aparece — y eso hay que decirlo en pantalla, no dejar la lista
/// vacía sin explicación.
final trabajadoresDeObraProvider = FutureProvider<List<Trabajador>>((
  ref,
) async {
  final obraId = ref.watch(_obraIdProvider);
  if (obraId == null) return const [];
  final lista = await ref.watch(trabajadoresApiProvider).porObra(obraId);
  return lista..sort((a, b) => a.nombre.compareTo(b.nombre));
});

final herramientasProvider = FutureProvider<List<Herramienta>>(
  (ref) => ref.watch(herramientasApiProvider).listar(),
);

final prestamosProvider = FutureProvider<List<Prestamo>>((ref) async {
  final obraId = ref.watch(_obraIdProvider);
  if (obraId == null) return const [];
  return ref.watch(prestamosApiProvider).porObra(obraId);
});

/// Los préstamos que siguen abiertos: la herramienta está fuera de bodega.
final prestamosAbiertosProvider = Provider<AsyncValue<List<Prestamo>>>(
  (ref) => ref
      .watch(prestamosProvider)
      .whenData((lista) => lista.where((p) => p.abierto).toList()),
);

/// Las solicitudes de material que esperan al bodeguero en esta obra.
final solicitudesMaterialProvider = FutureProvider<List<SolicitudMaterial>>((
  ref,
) async {
  final obraId = ref.watch(_obraIdProvider);
  if (obraId == null) return const [];
  final lista = await ref
      .watch(solicitudesApiProvider)
      .materialesPorObra(obraId);
  return lista
    ..sort((a, b) => _masNuevaPrimero(a.fechaSolicitud, b.fechaSolicitud));
});

/// Las solicitudes de herramienta pendientes de la obra.
///
/// Van por separado de las de material aunque la pantalla las muestre juntas:
/// son dos endpoints y dos formas de aprobar, y mezclarlas en un solo provider
/// obligaría a que un fallo en una dejara sin datos a la otra.
final solicitudesHerramientaProvider =
    FutureProvider<List<SolicitudHerramienta>>((ref) async {
      final obraId = ref.watch(_obraIdProvider);
      if (obraId == null) return const [];
      final lista = await ref
          .watch(solicitudesApiProvider)
          .herramientasPorObra(obraId);
      return lista
        ..sort((a, b) => _masNuevaPrimero(a.fechaSolicitud, b.fechaSolicitud));
    });

/// Los pedidos especiales abiertos de la obra: lo que hay que conseguir, y lo
/// entregado que el trabajador todavía no confirma.
final pedidosEspecialesObraProvider = FutureProvider<List<PedidoEspecial>>((
  ref,
) async {
  final obraId = ref.watch(_obraIdProvider);
  if (obraId == null) return const [];
  return ref.watch(pedidosEspecialesApiProvider).listar(obraId: obraId);
});

/// Los abiertos de toda la empresa: la vista del administrador, que no
/// trabaja sobre una obra.
final pedidosEspecialesEmpresaProvider = FutureProvider<List<PedidoEspecial>>(
  (ref) => ref.watch(pedidosEspecialesApiProvider).listar(),
);

/// Cuántas solicitudes esperan respuesta, para el contador del inicio y el
/// badge de la pestaña. Mientras alguna de las dos listas cargue, no hay
/// número que mostrar.
final solicitudesPendientesProvider = Provider<AsyncValue<int>>((ref) {
  final materiales = ref.watch(solicitudesMaterialProvider);
  final herramientas = ref.watch(solicitudesHerramientaProvider);
  // Los pedidos especiales suman solo si su carga funciona: son un agregado a
  // la cola, y que fallen no debe apagar el contador de lo de siempre.
  final especiales =
      ref
          .watch(pedidosEspecialesObraProvider)
          .valueOrNull
          ?.where((p) => p.siguientePaso != null)
          .length ??
      0;

  // Un fallo tiene que llegar como fallo. Colapsarlo en "cargando" dejaba el
  // panel del inicio girando para siempre justo en lo único que avisa que hay
  // alguien esperando en el mesón, y sin manera de reintentar.
  if (materiales case AsyncError(:final error, :final stackTrace)) {
    return AsyncValue.error(error, stackTrace);
  }
  if (herramientas case AsyncError(:final error, :final stackTrace)) {
    return AsyncValue.error(error, stackTrace);
  }
  if (!materiales.hasValue || !herramientas.hasValue) {
    return const AsyncValue.loading();
  }
  return AsyncValue.data(
    materiales.requireValue.where((s) => s.pendiente).length +
        herramientas.requireValue.where((s) => s.pendiente).length +
        especiales,
  );
});

/// Lo que un trabajador tiene pedido, de los dos tipos a la vez.
///
/// Es lo que se consulta después de escanear su credencial: el bodeguero lo
/// tiene enfrente y necesita ver todo lo suyo junto, no una lista por tipo.
class SolicitudesDeTrabajador {
  const SolicitudesDeTrabajador({
    required this.materiales,
    required this.herramientas,
  });

  final List<SolicitudMaterial> materiales;
  final List<SolicitudHerramienta> herramientas;

  List<SolicitudMaterial> get materialesPendientes =>
      materiales.where((s) => s.pendiente).toList();

  List<SolicitudHerramienta> get herramientasPendientes =>
      herramientas.where((s) => s.pendiente).toList();

  int get cuantasPendientes =>
      materialesPendientes.length + herramientasPendientes.length;

  bool get vacio => materiales.isEmpty && herramientas.isEmpty;
}

/// Todo lo que pidió un trabajador. Las dos consultas van en paralelo: el
/// bodeguero está parado frente a él esperando la pantalla.
final solicitudesDeTrabajadorProvider =
    FutureProvider.family<SolicitudesDeTrabajador, int>((
      ref,
      trabajadorId,
    ) async {
      final api = ref.watch(solicitudesApiProvider);
      final (materiales, herramientas) = await (
        api.materialesPorTrabajador(trabajadorId),
        api.herramientasPorTrabajador(trabajadorId),
      ).wait;

      return SolicitudesDeTrabajador(
        materiales: materiales
          ..sort(
            (a, b) => _masNuevaPrimero(a.fechaSolicitud, b.fechaSolicitud),
          ),
        herramientas: herramientas
          ..sort(
            (a, b) => _masNuevaPrimero(a.fechaSolicitud, b.fechaSolicitud),
          ),
      );
    });

/// Fecha con la que se ordena una solicitud. Nunca debería faltar —el backend
/// la pone al crearla— pero el modelo la deja nula, así que se define un orden
/// en vez de reventar.
final _sinFecha = DateTime.fromMillisecondsSinceEpoch(0);

/// De la más reciente a la más antigua, que es como se atiende una cola de
/// bodega cuando ya se resolvió lo urgente.
int _masNuevaPrimero(DateTime? a, DateTime? b) =>
    (b ?? _sinFecha).compareTo(a ?? _sinFecha);

final alertasProvider = FutureProvider<List<Alerta>>((ref) async {
  final obraId = ref.watch(_obraIdProvider);
  if (obraId == null) return const [];

  // El backend no tiene tareas programadas: las alertas se detectan cuando
  // alguien mira. Barrer acá es lo que hace que la lista esté al día al
  // abrirla, en vez de mostrar lo que quedó de ayer.
  final api = ref.watch(alertasApiProvider);
  await api.detectarNoDevueltas(obraId);
  await api.detectarStockCritico(obraId);

  final alertas = await api.porObra(obraId);
  return alertas..sort((a, b) => b.fecha.compareTo(a.fecha));
});

final alertasSinResolverProvider = Provider<AsyncValue<List<Alerta>>>(
  (ref) => ref
      .watch(alertasProvider)
      .whenData((lista) => lista.where((a) => !a.resuelto).toList()),
);

/// Los movimientos de hoy — el turno en curso, para los contadores del inicio
/// y el resumen del cierre.
final movimientosDeHoyProvider = Provider<AsyncValue<List<MovimientoKardex>>>((
  ref,
) {
  return ref.watch(movimientosProvider).whenData((lista) {
    final ahora = DateTime.now();
    final hoy = DateTime(ahora.year, ahora.month, ahora.day);
    return lista.where((m) => m.fecha.isAfter(hoy)).toList();
  });
});

/// Cuánta plata hay parada en la obra.
///
/// Son dos cifras distintas y las dos importan: el material que está en bodega
/// es capital inmovilizado, y las herramientas que están afuera son el valor
/// que hay que recuperar antes de cerrar el turno. Sumarlas en un solo número
/// las volvería inútiles.
class ValorEnObra {
  const ValorEnObra({
    required this.materialesEnBodega,
    required this.herramientasFuera,
    required this.herramientasPrestadas,
  });

  /// Suma de stock × costo de cada material: el de la última compra si hay,
  /// el de catálogo si no.
  final double materialesEnBodega;

  /// Valor de reposición de las herramientas que siguen prestadas.
  final double herramientasFuera;

  final int herramientasPrestadas;

  double get total => materialesEnBodega + herramientasFuera;
}

final valorEnObraProvider = Provider<AsyncValue<ValorEnObra>>((ref) {
  final bodega = ref.watch(bodegaProvider);
  final abiertos = ref.watch(prestamosAbiertosProvider);
  final herramientas = ref.watch(herramientasProvider);

  if (!bodega.hasValue || !abiertos.hasValue || !herramientas.hasValue) {
    return const AsyncValue.loading();
  }

  final materiales = bodega.requireValue.fold<double>(
    0,
    // El saldo puede ser negativo si hubo un descuadre; se cuenta tal cual en
    // vez de topar en cero, porque maquillarlo escondería el problema.
    (total, m) => total + m.stock * m.material.costoVigente,
  );

  final porId = {for (final h in herramientas.requireValue) h.id: h};
  final fuera = abiertos.requireValue.fold<double>(
    0,
    (total, p) => total + (porId[p.herramientaId]?.valorReposicion ?? 0),
  );

  return AsyncValue.data(
    ValorEnObra(
      materialesEnBodega: materiales,
      herramientasFuera: fuera,
      herramientasPrestadas: abiertos.requireValue.length,
    ),
  );
});

/// Recarga todo lo que depende de la obra. Se llama tras registrar un
/// movimiento o una devolución, porque cambian varias pantallas a la vez:
/// el saldo del material, los contadores del turno y las alertas.
void recargarBodega(WidgetRef ref) {
  ref.invalidate(movimientosProvider);
  ref.invalidate(prestamosProvider);
  ref.invalidate(alertasProvider);
  ref.invalidate(herramientasProvider);
  ref.invalidate(solicitudesMaterialProvider);
  ref.invalidate(solicitudesHerramientaProvider);
  // La familia se invalida entera: tras aprobar, la lista del trabajador que
  // se acaba de atender queda vieja igual que la de la obra.
  ref.invalidate(solicitudesDeTrabajadorProvider);
  // Un movimiento cambia el saldo —y una recepción con costo, el último costo
  // del material—, así que el aviso de faltantes, el catálogo y la ficha de
  // la obra quedan viejos igual que la bodega.
  ref.invalidate(faltantesProvider);
  ref.invalidate(pedidosEspecialesObraProvider);
  ref.invalidate(pedidosEspecialesEmpresaProvider);
  ref.invalidate(catalogoProvider);
  ref.invalidate(detalleObraProvider);
}

/// La obra en curso, para los encabezados.
final obraEnCursoProvider = Provider<Obra?>(
  (ref) => ref.watch(obraActivaProvider).valueOrNull,
);
