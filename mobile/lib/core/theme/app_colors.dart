import 'package:flutter/material.dart';

/// Paleta de Check-In-Obra — los valores salen tal cual de
/// `docs/design-system/Check-In-Obra_Design_System.md`.
///
/// Sobre el naranjo: el catálogo define `#EA580C` como acento, pero sobre
/// blanco mide 3.56:1 y no pasa el 4.5:1 que exige el propio checklist del
/// design system. Por eso el acento se reserva para íconos y marcas, y el
/// relleno de botón primario usa `#C2410C` (5.1:1).
abstract final class AppColors {
  static const primary = Color(0xFF334155);
  static const secondary = Color(0xFF64748B);

  /// Acento — solo íconos, marcas de gráfico y foco.
  static const accent = Color(0xFFEA580C);

  /// Relleno de botón primario — versión con contraste suficiente.
  static const accentFill = Color(0xFFC2410C);

  /// Lienzo de toda la app. Las tarjetas blancas se separan de él por el
  /// borde fino, no por sombra. Se evaluó bajarlo a slate-100 para que las
  /// tarjetas resaltaran más, pero ahí `secondary` cae a 4.34:1 y las ayudas
  /// de los formularios, que van sobre el lienzo, dejan de pasar el 4.5:1.
  static const background = Color(0xFFF8FAFC);
  static const card = Color(0xFFFFFFFF);

  /// Superficie hundida dentro de una tarjeta: el saldo neutro, una fila
  /// agrupada, el fondo de un chip neutro. Es el "Fog" de la referencia,
  /// llevado a la familia pizarra del sistema.
  static const sunken = Color(0xFFF1F5F9);

  /// Tinte del acento: pestaña activa, fila elegida. El `accentFill` mide
  /// 4.88:1 encima, así que un texto naranjo sobre este fondo se lee.
  static const accentTint = Color(0xFFFFF7ED);

  /// Separador decorativo entre superficies. Mide 1.2:1 y con eso basta:
  /// no identifica ningún control, solo agrupa.
  static const border = Color(0xFFE2E8F0);

  /// Borde de un control — campo de texto, tecla, panel que se toca.
  /// Mide 3.3:1 sobre el relleno de los campos, por encima del 3:1 que
  /// exige WCAG para el contorno que identifica un componente. El `border`
  /// decorativo no sirve acá: sobre el relleno queda en 1.2:1 y el campo
  /// parece un bloque de texto, no algo donde escribir.
  static const borderControl = Color(0xFF7E8CA0);

  /// Semáforo. Se usan como chip tintado (fondo claro + texto oscuro),
  /// nunca como texto de color puro sobre blanco.
  static const success = Color(0xFF059669);
  static const successDark = Color(0xFF047857);
  static const successTint = Color(0xFFECFDF5);

  static const warning = Color(0xFFD97706);
  static const warningDark = Color(0xFFB45309);
  static const warningTint = Color(0xFFFFFBEB);

  /// Texto largo sobre `warningTint`: un párrafo de advertencia pide más
  /// contraste que un chip (8.9:1 contra 4.8:1 de `warningDark`).
  static const warningInk = Color(0xFF92400E);

  static const destructive = Color(0xFFDC2626);
  static const destructiveDark = Color(0xFFB91C1C);
  static const destructiveTint = Color(0xFFFEF2F2);

  static const textMuted = Color(0xFF475569);

  /// Texto y bordes tenues **sobre fondo claro**. Mide 2.6:1 sobre blanco,
  /// así que no se usa para texto: solo para íconos decorativos que
  /// acompañan a un texto que ya dice lo mismo.
  static const textFaint = Color(0xFF94A3B8);

  /// Texto secundario **sobre las superficies oscuras** (`primary` y el
  /// panel `surfaceDark`). Mide 7:1 sobre `primary`; `textFaint` ahí se
  /// quedaba en 4:1 y no pasaba el 4.5:1 del propio design system.
  static const textOnDark = Color(0xFFCBD5E1);

  /// Marco oscuro. Se reserva para dos lugares: el encabezado del acceso y el
  /// panel del turno en Inicio. Usarlo en cualquier otra parte le quitaría la
  /// función de marco y lo volvería una tarjeta más.
  static const surfaceDark = Color(0xFF1E293B);
  static const borderOnDark = Color(0xFF334155);

  /// Texto terciario sobre el marco oscuro: rótulos de las cifras (5.7:1).
  static const textOnDarkMuted = Color(0xFF94A3B8);

  /// Semáforo sobre el marco oscuro: los pasos oscuros de siempre ahí no
  /// llegan al 3:1 de un número grande; estos pasan el 4.5:1.
  static const destructiveOnDark = Color(0xFFF87171);
  static const warningOnDark = Color(0xFFFBBF24);

  /// El acento sobre el marco oscuro. `accent` ahí mide 4.1:1; este, 6.5:1.
  static const accentOnDark = Color(0xFFFB923C);
}
