import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_forma.dart';
import '../core/theme/app_theme.dart';
import '../core/theme/movimiento.dart';
import 'presion.dart';

/// Superficie base del sistema: tarjeta blanca con borde fino y radio 12, sin
/// sombra. Sobre el lienzo claro, el borde basta para separarla.
class Panel extends StatelessWidget {
  const Panel({
    super.key,
    required this.child,
    this.color = AppColors.card,
    this.borderColor = AppColors.border,
    this.padding = const EdgeInsets.all(AppEspacio.md),
    this.borderIzquierdo,
    this.animado = false,
  });

  final Widget child;
  final Color color;
  final Color borderColor;
  final EdgeInsets padding;

  /// Funde el color y el borde cuando cambian, en vez de saltar. Para los
  /// paneles que cambian de estado mientras se miran —el saldo que pasa a
  /// ámbar y a rojo según lo que se escribe—; en una lista estática sobra.
  final bool animado;

  /// Franja de color a la izquierda, para marcar criticidad en listas
  /// (rojo = vencido, ámbar = por vencer, verde = al día).
  ///
  /// Es un elemento interno y no un borde: Flutter no dibuja un `Border` con
  /// un lado distinto cuando hay radio, y la tarjeta recorta la franja con su
  /// propia esquina, así que sigue la curva.
  final Color? borderIzquierdo;

  @override
  Widget build(BuildContext context) {
    final decoracion = BoxDecoration(
      color: color,
      borderRadius: AppForma.borde,
      border: Border.all(color: borderColor),
    );

    final contenido = Padding(padding: padding, child: child);
    final franja = borderIzquierdo;
    final cuerpo = franja == null
        ? contenido
        : Stack(
            children: [
              contenido,
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: 4,
                child: ColoredBox(color: franja),
              ),
            ],
          );

    if (!animado) {
      return Container(
        decoration: decoracion,
        clipBehavior: Clip.antiAlias,
        child: cuerpo,
      );
    }
    return AnimatedContainer(
      duration: Movimiento.de(context, Movimiento.estado),
      curve: Movimiento.salida,
      decoration: decoracion,
      clipBehavior: Clip.antiAlias,
      child: cuerpo,
    );
  }
}

/// Panel que se toca.
///
/// El color, el borde y el recorte los pone el `Material`, y el `InkWell` va
/// adentro: así el splash se dibuja sobre el fondo y queda recortado por la
/// esquina. Con `InkWell(child: Panel(...))` el fondo opaco del panel tapaba el
/// splash y el dedo apretaba sin respuesta visible, que en obra termina en un
/// segundo toque, es decir, en la acción repetida.
class PanelTocable extends StatelessWidget {
  const PanelTocable({
    super.key,
    required this.child,
    required this.onTap,
    required this.semanticLabel,
    this.color = AppColors.card,
    this.borderColor = AppColors.borderControl,
    this.padding = const EdgeInsets.all(AppEspacio.md),
    this.borderIzquierdo,
  });

  final Widget child;
  final VoidCallback? onTap;

  /// La misma franja de criticidad que `Panel.borderIzquierdo`.
  final Color? borderIzquierdo;

  /// Lo que anuncia el lector de pantalla. Obligatorio: un panel entero
  /// tocable no se describe solo.
  final String semanticLabel;

  final Color color;
  final Color borderColor;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: semanticLabel,
      child: Presionable(
        habilitado: onTap != null,
        child: Material(
          color: color,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: AppForma.borde,
            side: BorderSide(color: borderColor),
          ),
          child: InkWell(
            onTap: onTap,
            child: Stack(
              children: [
                Padding(
                  padding: padding,
                  child: ExcludeSemantics(child: child),
                ),
                if (borderIzquierdo case final franja?)
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    width: 4,
                    child: ColoredBox(color: franja),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Título de sección: en tipo oración y con peso, no en mayúsculas espaciadas.
/// Ordena la pantalla por bloques sin gritar.
class Etiqueta extends StatelessWidget {
  const Etiqueta(this.texto, {super.key, this.color = AppColors.primary});

  final String texto;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      child: Text(
        texto,
        style: AppTexto.subtitulo.copyWith(fontSize: 15, color: color),
      ),
    );
  }
}

/// Chip de estado tintado. Nunca texto de color puro sobre blanco: siempre
/// fondo claro con el texto en su paso oscuro, para cumplir el 4.5:1.
class ChipEstado extends StatelessWidget {
  const ChipEstado({
    super.key,
    required this.texto,
    required this.fondo,
    required this.textoColor,
    this.punto,
  });

  /// Verde — a tiempo, disponible, aprobada.
  factory ChipEstado.exito(String texto, {bool conPunto = true}) => ChipEstado(
    texto: texto,
    fondo: AppColors.successTint,
    textoColor: AppColors.successDark,
    punto: conPunto ? AppColors.success : null,
  );

  /// Ámbar — por vencer, pendiente, en mantención.
  factory ChipEstado.aviso(String texto, {bool conPunto = true}) => ChipEstado(
    texto: texto,
    fondo: AppColors.warningTint,
    textoColor: AppColors.warningDark,
    punto: conPunto ? AppColors.warning : null,
  );

  /// Rojo — vencido, stock crítico, rechazada.
  factory ChipEstado.critico(String texto, {bool conPunto = true}) =>
      ChipEstado(
        texto: texto,
        fondo: AppColors.destructiveTint,
        textoColor: AppColors.destructiveDark,
        punto: conPunto ? AppColors.destructive : null,
      );

  /// Gris — neutro, entregada, cerrada.
  factory ChipEstado.neutro(String texto) => ChipEstado(
    texto: texto,
    fondo: AppColors.sunken,
    textoColor: AppColors.textMuted,
  );

  final String texto;
  final Color fondo;
  final Color textoColor;
  final Color? punto;

  @override
  Widget build(BuildContext context) {
    // El chip no quiebra línea. Con el texto del sistema al 200 %, un chip
    // largo desborda la fila que lo contiene, así que se topa el escalado del
    // chip —y solo del chip— en 1.15. Parece poco, pero parte de 12 px: al
    // máximo queda en 13,8, más grande que el chip anterior de 10 px con su
    // tope de 1.3 (13 px).
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.15,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: fondo,
          borderRadius: AppForma.bordeChip,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (punto != null) ...[
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(color: punto, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
            ],
            Text(
              texto,
              softWrap: false,
              style: TextStyle(
                fontSize: 12,
                height: 1.3,
                fontWeight: FontWeight.w500,
                letterSpacing: -0.1,
                color: textoColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Iniciales sobre cuadro sólido — el "avatar" del sistema.
class Iniciales extends StatelessWidget {
  const Iniciales(this.nombre, {super.key, this.tamano = 44});

  final String nombre;
  final double tamano;

  static String de(String nombre) {
    final partes = nombre
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (partes.isEmpty) return '?';
    if (partes.length == 1) {
      return partes.first.substring(0, 1).toUpperCase();
    }
    return (partes[0].substring(0, 1) + partes[1].substring(0, 1))
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    // Las iniciales son una abreviatura decorativa: el nombre completo
    // siempre está escrito al lado. Leerlas en voz alta ("E S") solo agrega
    // ruido antes del dato que sí importa.
    return Container(
      width: tamano,
      height: tamano,
      decoration: const BoxDecoration(
        color: AppColors.sunken,
        borderRadius: AppForma.borde,
      ),
      alignment: Alignment.center,
      child: ExcludeSemantics(
        // El cuadro tiene lado fijo, así que el texto no puede escalar sin
        // desbordarlo.
        child: MediaQuery.withNoTextScaling(
          child: Text(
            de(nombre),
            style: TextStyle(
              fontSize: tamano * 0.34,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.3,
              color: AppColors.primary,
            ),
          ),
        ),
      ),
    );
  }
}
