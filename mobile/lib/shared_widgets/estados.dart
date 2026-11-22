import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/network/errores.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_forma.dart';
import '../core/theme/app_theme.dart';
import '../core/theme/movimiento.dart';
import 'panel.dart';

/// Dibuja un `AsyncValue` con los tres estados resueltos de una vez.
///
/// El caso vacío es un parámetro y no un olvido: una lista sin elementos en
/// obra casi nunca significa "no hay nada", significa "todavía no cargaste el
/// catálogo" o "el turno recién empieza", y decir cuál de las dos ahorra una
/// llamada al jefe de terreno.
class Contenido<T> extends StatelessWidget {
  const Contenido({
    super.key,
    required this.valor,
    required this.constructor,
    required this.alReintentar,
    this.vacio,
    this.estaVacio,
  });

  final AsyncValue<T> valor;
  final Widget Function(T dato) constructor;
  final VoidCallback alReintentar;

  /// Qué mostrar cuando el dato llegó pero no tiene nada dentro.
  final Widget? vacio;
  final bool Function(T dato)? estaVacio;

  /// Refrescar no es cargar. Tras aprobar o despachar se invalidan los
  /// providers, y Riverpod deja un `AsyncLoading` que **conserva** el dato
  /// anterior; antes eso caía en el spinner, así que la cola entera
  /// desaparecía, volvía y perdía el scroll en cada aprobación. Ahora el dato
  /// anterior sigue a la vista hasta que llega el nuevo. Solo la primera carga
  /// —o un cambio de obra, que es otro dato— muestra el spinner.
  @override
  Widget build(BuildContext context) {
    final Widget cuerpo = valor.when(
      skipLoadingOnRefresh: true,
      skipLoadingOnReload: false,
      error: (error, _) => MensajeError(
        key: const ValueKey('error'),
        mensaje: mensajeDeError(error),
        alReintentar: alReintentar,
      ),
      data: (value) => KeyedSubtree(
        key: const ValueKey('dato'),
        child: (estaVacio?.call(value) ?? false) && vacio != null
            ? vacio!
            : constructor(value),
      ),
      loading: () => const Padding(
        key: ValueKey('cargando'),
        padding: EdgeInsets.symmetric(vertical: 48),
        child: Center(
          child: CircularProgressIndicator(color: AppColors.accentFill),
        ),
      ),
    );

    // De cargando a dato se funde en vez de saltar. Entre dos datos no hay
    // transición: la clave es la misma y el contenido se actualiza en su lugar.
    return AnimatedSwitcher(
      duration: Movimiento.de(context, Movimiento.estado),
      switchInCurve: Movimiento.salida,
      switchOutCurve: Movimiento.salida,
      // `passthrough`: el Stack no afloja las restricciones. Dentro de una
      // lista, un Stack común dejaría a cada panel del ancho de su texto.
      layoutBuilder: (actual, anteriores) => Stack(
        fit: StackFit.passthrough,
        alignment: Alignment.topCenter,
        children: [...anteriores, ?actual],
      ),
      child: cuerpo,
    );
  }
}

class MensajeError extends StatelessWidget {
  const MensajeError({super.key, required this.mensaje, this.alReintentar});

  final String mensaje;
  final VoidCallback? alReintentar;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Panel(
        color: AppColors.destructiveTint,
        borderColor: AppColors.destructive,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const ExcludeSemantics(
                  child: Icon(
                    Icons.error_outline,
                    size: 20,
                    color: AppColors.destructiveDark,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    mensaje,
                    style: AppTexto.cuerpoChico.copyWith(
                      fontSize: 14,
                      color: AppColors.destructiveDark,
                    ),
                  ),
                ),
              ],
            ),
            if (alReintentar != null) ...[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: alReintentar,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Reintentar'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.destructiveDark,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Estado vacío con una salida: decir que no hay nada sin decir qué hacer
/// deja a quien está en obra sin siguiente paso.
class Vacio extends StatelessWidget {
  const Vacio({
    super.key,
    required this.icono,
    required this.titulo,
    required this.detalle,
    this.accion,
  });

  final IconData icono;
  final String titulo;
  final String detalle;
  final Widget? accion;

  @override
  Widget build(BuildContext context) {
    // El ícono va dentro de un cuadro hundido: sin él, un ícono de 40 px
    // suelto sobre el lienzo parece un error de carga y no un estado.
    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: AppEspacio.xl + 8,
        horizontal: AppEspacio.lg,
      ),
      child: Column(
        children: [
          ExcludeSemantics(
            child: Container(
              width: 56,
              height: 56,
              decoration: const BoxDecoration(
                color: AppColors.sunken,
                borderRadius: AppForma.borde,
              ),
              child: Icon(icono, size: 26, color: AppColors.secondary),
            ),
          ),
          const SizedBox(height: AppEspacio.md),
          Text(titulo, textAlign: TextAlign.center, style: AppTexto.subtitulo),
          const SizedBox(height: AppEspacio.xs + 2),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Text(
              detalle,
              textAlign: TextAlign.center,
              style: AppTexto.cuerpoChico.copyWith(
                fontSize: 14,
                color: AppColors.secondary,
              ),
            ),
          ),
          if (accion != null) ...[
            const SizedBox(height: AppEspacio.lg),
            accion!,
          ],
        ],
      ),
    );
  }
}

/// Cifra grande con su rótulo debajo — los contadores del inicio de bodega.
///
/// Se centra en su columna: siempre va dentro de un `Expanded` en una fila de
/// tres, y alineado a la izquierda la cifra queda descolgada del rótulo cuando
/// los rótulos tienen anchos distintos ("Movimientos del turno" contra
/// "Alertas sin resolver").
class Contador extends StatelessWidget {
  const Contador({
    super.key,
    required this.valor,
    required this.rotulo,
    this.color = AppColors.primary,
    this.sobreOscuro = false,
  });

  final String valor;
  final String rotulo;
  final Color color;

  /// Va sobre el marco oscuro del turno: el rótulo cambia a su gris claro.
  final bool sobreOscuro;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$valor $rotulo',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Cifras tabulares: al pasar de 9 a 10 el contador no empuja a sus
          // vecinos.
          Text(
            valor,
            textAlign: TextAlign.center,
            style: AppTexto.cifra.copyWith(color: color),
          ),
          const SizedBox(height: AppEspacio.xs + 2),
          Text(
            rotulo,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              height: 1.3,
              letterSpacing: -0.1,
              color: sobreOscuro
                  ? AppColors.textOnDarkMuted
                  : AppColors.secondary,
            ),
          ),
        ],
      ),
    );
  }
}
