import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/formato.dart';
import '../../core/network/errores.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../data/api/auth_api.dart';
import '../../data/api/dominio_api.dart';
import '../../data/modelos/herramienta.dart';
import '../../data/modelos/material.dart';
import '../../data/modelos/pedido_herramienta.dart';
import '../../shared_widgets/panel.dart';
import 'bodega_providers.dart';
import 'escaner.dart';
import 'pantalla_entrega_pedido.dart';
import 'pantalla_herramientas.dart';
import 'pantalla_movimiento.dart';
import 'pantalla_prestamo.dart';
import 'pantalla_solicitudes.dart';

/// El bodeguero escanea la credencial del trabajador.
///
/// Este es el rol del QR en el sistema: **identificar a la persona**, no al
/// material. El trabajador muestra su credencial en el teléfono, el bodeguero
/// la lee y en la pantalla siguiente aparece lo que esa persona pidió, listo
/// para aprobar o rechazar. Antes había que buscar el nombre en una lista de
/// toda la obra, que con dos Marcelos y guantes puestos es exactamente donde
/// se entrega el material a quien no era.
///
/// El código no autoriza por sí solo: quien aprueba sigue siendo el bodeguero
/// autenticado, y así queda en el kardex.
///
/// El mismo escáner lee el QR de un pedido de herramientas (`PEDIDO:<uuid>`).
/// Los dos los muestra el trabajador en su teléfono, en el mismo mesón: pedirle
/// al bodeguero que elija antes cuál de los dos le van a mostrar sería un paso
/// de más, y el prefijo ya dice cuál es.
class PantallaEscaneoCredencial extends ConsumerWidget {
  const PantallaEscaneoCredencial({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return LectorDeCodigo(
      titulo: 'Escanear credencial o pedido',
      instruccion:
          'Apunta al QR de la credencial o del pedido que el trabajador '
          'tiene en su teléfono.',
      // Solo QR: la credencial es un UUID y no cabe en un código de barras
      // lineal. Aceptar otros formatos acá solo haría que el escáner reaccione
      // a la etiqueta de una caja que pasó por delante.
      formatos: const [BarcodeFormat.qrCode],
      etiquetaManual: 'Código de la credencial o del pedido',
      ayudaManual:
          'Está bajo el QR en la pantalla del trabajador. Sirve si el código '
          'no se deja escanear.',
      alLeer: (codigo) async {
        if (PedidoHerramienta.codigoDesdeQr(codigo) case final uuid?) {
          return _abrirPedido(context, ref, uuid);
        }
        try {
          final trabajador = await ref
              .read(trabajadoresApiProvider)
              .porCredencial(codigo);

          if (!context.mounted) return null;
          // Reemplaza en vez de apilar: al volver desde las solicitudes, el
          // bodeguero quiere la pantalla anterior, no la cámara otra vez.
          await Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) =>
                  PantallaSolicitudesTrabajador(trabajador: trabajador),
            ),
          );
          return null;
        } on ApiException catch (e) {
          // El 404 lo produce tanto un código inventado como la credencial de
          // otra constructora: el backend responde igual en los dos casos a
          // propósito, así que acá tampoco se distingue.
          return e.statusCode == 404
              ? 'Esa credencial no corresponde a ningún trabajador de tu '
                    'empresa. Puede estar vencida si se le renovó el código.'
              : e.mensaje;
        } catch (e) {
          return mensajeDeError(e);
        }
      },
    );
  }

  Future<String?> _abrirPedido(
    BuildContext context,
    WidgetRef ref,
    String uuid,
  ) async {
    try {
      final pedido = await ref.read(pedidosHerramientaApiProvider).porQr(uuid);
      if (!context.mounted) return null;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => PantallaEntregaPedido(pedido: pedido),
        ),
      );
      return null;
    } on ApiException catch (e) {
      // Igual que con la credencial: un código inventado y uno de otra
      // empresa dan el mismo 404.
      return e.statusCode == 404
          ? 'Ese pedido no existe en tu empresa. Pídele al trabajador que '
                'abra de nuevo el QR desde su Inicio.'
          : e.mensaje;
    } catch (e) {
      return mensajeDeError(e);
    }
  }
}

/// El bodeguero escanea el código de barras de un material o una herramienta.
///
/// Es el otro escaneo, y resuelve un problema distinto al de la credencial:
/// encontrar la ficha correcta sin buscarla en una lista de treinta y cuatro
/// materiales parecidos. El código puede ser el de fábrica del envase, el SKU
/// de la empresa o el de la etiqueta de una herramienta; quien apunta la
/// cámara no tiene por qué saber cuál es.
class PantallaEscaneoCodigo extends ConsumerWidget {
  const PantallaEscaneoCodigo({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return LectorDeCodigo(
      titulo: 'Escanear código',
      instruccion:
          'Apunta al código de barras del envase o a la etiqueta de la '
          'herramienta.',
      // Los formatos que de verdad llegan a una bodega: EAN y UPC vienen de
      // fábrica, Code 128 y Code 39 son los de las etiquetas que se imprimen
      // en la obra, y el QR va porque algunas herramientas se etiquetan así.
      formatos: const [
        BarcodeFormat.ean13,
        BarcodeFormat.ean8,
        BarcodeFormat.upcA,
        BarcodeFormat.upcE,
        BarcodeFormat.code128,
        BarcodeFormat.code39,
        BarcodeFormat.code93,
        BarcodeFormat.itf14,
        BarcodeFormat.qrCode,
      ],
      etiquetaManual: 'Código o SKU',
      ayudaManual:
          'Si la etiqueta está rota o borrada, escribe el SKU del material o '
          'el código de la herramienta.',
      alLeer: (codigo) => _resolver(context, ref, codigo),
    );
  }

  /// Primero material y después herramienta.
  ///
  /// Son dos catálogos distintos y el código no dice a cuál pertenece, así que
  /// se prueban en el orden en que se escanean las cosas en bodega: llega un
  /// camión con material muchas más veces de las que se registra una
  /// herramienta.
  Future<String?> _resolver(
    BuildContext context,
    WidgetRef ref,
    String codigo,
  ) async {
    // El QR de un pedido también es un QR: se dice cuál escáner lo lee antes
    // de buscarlo en dos catálogos donde no va a estar.
    if (PedidoHerramienta.codigoDesdeQr(codigo) != null) {
      return 'Eso es el QR de un pedido de herramientas. Léelo desde '
          '"Escanear credencial o pedido": este escáner busca materiales y '
          'herramientas.';
    }
    try {
      final material = await ref.read(materialesApiProvider).porCodigo(codigo);

      // El saldo tiene que estar cargado antes de abrir el movimiento: esa
      // pantalla muestra "el saldo que va a quedar" y con el kardex a medio
      // cargar mostraría cero, que es peor que no mostrar nada.
      if (!ref.read(movimientosProvider).hasValue) {
        await ref.read(movimientosProvider.future);
      }
      final stock =
          ref.read(stockPorMaterialProvider).valueOrNull?[material.id] ?? 0;

      if (!context.mounted) return null;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => PantallaMovimiento(
            item: MaterialConStock(material: material, stock: stock),
          ),
        ),
      );
      return null;
    } on ApiException catch (e) {
      if (e.statusCode != 404) return e.mensaje;
    } catch (e) {
      return mensajeDeError(e);
    }

    try {
      final herramienta = await ref
          .read(herramientasApiProvider)
          .porCodigo(codigo);

      if (!context.mounted) return null;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) =>
              PantallaHerramientaEscaneada(herramienta: herramienta),
        ),
      );
      return null;
    } on ApiException catch (e) {
      if (e.statusCode != 404) return e.mensaje;
      // Una credencial es un UUID, y es lo que más se cuela acá: alguien
      // apunta a la pantalla del trabajador desde el escáner equivocado.
      // Decir cuál es el correcto ahorra el "no funciona".
      return _pareceCredencial(codigo)
          ? 'Eso parece la credencial de un trabajador. Léela desde '
                '"Escanear credencial o pedido": este escáner busca materiales y '
                'herramientas.'
          : 'El código $codigo no está en el catálogo de tu empresa. '
                'Si el material es nuevo, hay que darlo de alta primero.';
    } catch (e) {
      return mensajeDeError(e);
    }
  }

  static final _uuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    caseSensitive: false,
  );

  bool _pareceCredencial(String codigo) => _uuid.hasMatch(codigo.trim());
}

/// Lee un código y lo **devuelve**, en vez de resolverlo contra el catálogo.
///
/// Es el escaneo al revés: se usa al dar de alta un material, para copiar el
/// código de barras del envase al formulario sin transcribir trece dígitos a
/// mano —que es justo donde se cuela el error que después deja el escáner sin
/// encontrar nada—.
class PantallaCapturaCodigo extends StatelessWidget {
  const PantallaCapturaCodigo({super.key});

  @override
  Widget build(BuildContext context) {
    return LectorDeCodigo(
      titulo: 'Leer código de barras',
      instruccion: 'Apunta al código de barras impreso en el envase.',
      formatos: const [
        BarcodeFormat.ean13,
        BarcodeFormat.ean8,
        BarcodeFormat.upcA,
        BarcodeFormat.upcE,
        BarcodeFormat.code128,
        BarcodeFormat.code39,
        BarcodeFormat.code93,
        BarcodeFormat.itf14,
      ],
      etiquetaManual: 'Código de barras',
      ayudaManual: 'Si prefieres, escríbelo a mano.',
      alLeer: (codigo) async {
        Navigator.of(context).pop(codigo);
        return null;
      },
    );
  }
}

/// La herramienta que se acaba de escanear, con la acción que corresponde a su
/// estado.
///
/// Escanear una herramienta significa cosas opuestas según dónde esté: si está
/// en bodega, se va a prestar; si está prestada, la están devolviendo. Elegir
/// por el estado —en vez de llevar siempre al préstamo— es lo que evita que el
/// bodeguero tenga que acordarse de a quién se la dio.
class PantallaHerramientaEscaneada extends ConsumerWidget {
  const PantallaHerramientaEscaneada({super.key, required this.herramienta});

  final Herramienta herramienta;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prestamo = ref
        .watch(prestamosAbiertosProvider)
        .valueOrNull
        ?.where((p) => p.herramientaId == herramienta.id)
        .firstOrNull;

    return Scaffold(
      appBar: AppBar(title: const Text('Herramienta escaneada')),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          herramienta.nombre,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      switch (herramienta.estado) {
                        'DISPONIBLE' => ChipEstado.exito('En bodega'),
                        'PRESTADA' => ChipEstado.aviso('Prestada'),
                        _ => ChipEstado.critico('Mantención'),
                      },
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${herramienta.codigoQr} · reposición '
                    '${Formato.pesos(herramienta.valorReposicion)}',
                    style: const TextStyle(
                      fontFamily: AppTheme.monoFamily,
                      fontSize: 12,
                      color: AppColors.secondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            if (prestamo != null) ...[
              const Etiqueta('Está fuera de bodega'),
              const SizedBox(height: 8),
              FilaPrestamo(prestamo: prestamo),
            ] else if (herramienta.disponible) ...[
              const Etiqueta('Acción'),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: () => Navigator.of(context).pushReplacement(
                  MaterialPageRoute(
                    builder: (_) => PantallaPrestamo(herramienta: herramienta),
                  ),
                ),
                icon: const Icon(Icons.handyman_outlined),
                label: const Text('Prestar esta herramienta'),
              ),
            ] else
              const Panel(
                color: AppColors.warningTint,
                borderColor: AppColors.warning,
                child: Text(
                  'Está en mantención: no se puede prestar hasta que alguien '
                  'la devuelva a disponible desde su ficha.',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: AppColors.warningDark,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
