import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_colors.dart';
import 'app_forma.dart';

/// Escala tipográfica. Inter con tracking negativo en todos los tamaños: es lo
/// que le da a la app aspecto de instrumento y no de formulario.
///
/// El tracking se da en píxeles porque Flutter no acepta `em`: son los -0,01 a
/// -0,02 em de la referencia, calculados para cada tamaño.
///
/// Los rasgos de Inter van activados en toda la app y no por pantalla:
/// - `tnum`: cifras tabulares. Una columna de saldos o una cantidad que cambia
///   mientras se escribe no "baila" de ancho. Reemplaza a la monoespaciada
///   que se usaba para los datos, sin perder el alineado.
/// - `cv05`: ele con cola. En un SKU o un código de herramienta, confundir l
///   con 1 manda a buscar otra ficha.
///
/// El cero con barra (`zero`) se probó y se quitó: en direcciones, RUTs y
/// montos le daba a todo un aire de terminal, y los códigos del sistema se
/// guardan en mayúsculas sin O ambigua en la práctica.
abstract final class AppTexto {
  static const familia = 'Inter';

  static const rasgos = [FontFeature('cv05')];

  /// Cifras tabulares, solo para números: un saldo que cambia mientras se
  /// escribe o una columna de stock no "bailan" de ancho. No van en toda la
  /// app porque en Inter también ensanchan el guion, y un SKU como
  /// MET-MONT-90 quedaba con los guiones separados como en una terminal.
  static const tabulares = [FontFeature.tabularFigures(), FontFeature('cv05')];

  /// Cifra protagonista: el contador del turno, el saldo tras un movimiento.
  static const cifra = TextStyle(
    fontFeatures: tabulares,
    fontSize: 28,
    height: 1.1,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.6,
  );

  static const titulo = TextStyle(
    fontSize: 20,
    height: 1.3,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.3,
    color: AppColors.primary,
  );

  static const subtitulo = TextStyle(
    fontSize: 16,
    height: 1.35,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.2,
    color: AppColors.primary,
  );

  static const cuerpo = TextStyle(
    fontSize: 15,
    height: 1.45,
    fontWeight: FontWeight.w400,
    letterSpacing: -0.15,
    color: AppColors.primary,
  );

  static const cuerpoChico = TextStyle(
    fontSize: 13,
    height: 1.45,
    fontWeight: FontWeight.w400,
    letterSpacing: -0.1,
    color: AppColors.textMuted,
  );

  /// Rótulo de campo o de sección: en tipo oración y con peso, no en
  /// mayúsculas espaciadas. Se lee más rápido y no grita.
  static const rotulo = TextStyle(
    fontSize: 13,
    height: 1.3,
    fontWeight: FontWeight.w500,
    letterSpacing: -0.1,
    color: AppColors.textMuted,
  );

  /// Dato duro dentro de una fila: SKU, código, cantidad, hora.
  static const dato = TextStyle(
    fontSize: 12.5,
    height: 1.35,
    fontWeight: FontWeight.w500,
    letterSpacing: 0,
    color: AppColors.secondary,
  );
}

/// Tema de la app.
///
/// Lienzo claro, tarjetas blancas con borde fino y radio 12, un solo acento
/// naranjo para la acción principal y nada de sombras en lo que está sobre el
/// lienzo: la profundidad la dan el contraste de superficies y el borde. Lo
/// único que flota —hojas, diálogos, avisos— lleva una sombra suave, porque
/// sí está encima de otra cosa.
///
/// Hay un solo tema y es claro. No es un olvido: la app se usa a pleno sol
/// sobre andamios, donde el fondo claro con texto oscuro es lo que se lee, y
/// `MaterialApp` la fija con `themeMode: ThemeMode.light` para que el modo
/// oscuro del sistema no la arrastre a una paleta que nadie verificó.
abstract final class AppTheme {
  /// Datos duros: códigos, cantidades y horas. Es Inter con cifras tabulares
  /// (ver `AppTexto.rasgos`): el nombre se conserva porque las pantallas lo
  /// usan para marcar qué texto es un dato.
  static const monoFamily = AppTexto.familia;

  static const _hairline = BorderSide(color: AppColors.border);

  static ThemeData get light {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      fontFamily: AppTexto.familia,
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.accentFill,
        brightness: Brightness.light,
        primary: AppColors.accentFill,
        onPrimary: Colors.white,
        surface: AppColors.card,
        onSurface: AppColors.primary,
        surfaceTint: Colors.transparent,
        outline: AppColors.borderControl,
        outlineVariant: AppColors.border,
        error: AppColors.destructiveDark,
      ),
      splashFactory: InkSparkle.splashFactory,
    );

    final textos = base.textTheme
        .apply(
          fontFamily: AppTexto.familia,
          bodyColor: AppColors.primary,
          displayColor: AppColors.primary,
        )
        .copyWith(
          bodyLarge: AppTexto.cuerpo,
          bodyMedium: AppTexto.cuerpo.copyWith(fontSize: 14),
          bodySmall: AppTexto.cuerpoChico,
          titleLarge: AppTexto.titulo,
          titleMedium: AppTexto.subtitulo,
          titleSmall: AppTexto.subtitulo.copyWith(fontSize: 14),
          labelLarge: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.15,
          ),
        );

    // Los rasgos se aplican a cada estilo del tema; los `TextStyle` que las
    // pantallas escriben a mano los heredan del `DefaultTextStyle`.
    //
    // La familia se repite acá porque los `AppTexto` que reemplazan a los del
    // tema no la declaran: sin esto el `DefaultTextStyle` salía sin familia y
    // todo texto que no la pusiera a mano se dibujaba en la fuente del
    // sistema (Roboto en Android), no en Inter.
    TextStyle? conRasgos(TextStyle? t) => t?.copyWith(
      fontFamily: AppTexto.familia,
      fontFeatures: AppTexto.rasgos,
      letterSpacing: t.letterSpacing ?? -0.1,
    );

    final textoFinal = textos.copyWith(
      displayLarge: conRasgos(textos.displayLarge),
      displayMedium: conRasgos(textos.displayMedium),
      displaySmall: conRasgos(textos.displaySmall),
      headlineLarge: conRasgos(textos.headlineLarge),
      headlineMedium: conRasgos(textos.headlineMedium),
      headlineSmall: conRasgos(textos.headlineSmall),
      titleLarge: conRasgos(textos.titleLarge),
      titleMedium: conRasgos(textos.titleMedium),
      titleSmall: conRasgos(textos.titleSmall),
      bodyLarge: conRasgos(textos.bodyLarge),
      bodyMedium: conRasgos(textos.bodyMedium),
      bodySmall: conRasgos(textos.bodySmall),
      labelLarge: conRasgos(textos.labelLarge),
      labelMedium: conRasgos(textos.labelMedium),
      labelSmall: conRasgos(textos.labelSmall),
    );

    const botonForma = RoundedRectangleBorder(borderRadius: AppForma.borde);

    return base.copyWith(
      textTheme: textoFinal,

      // Barra superior blanca con tinta pizarra y una línea fina abajo. El
      // marco oscuro se guarda para el acceso y el panel del turno.
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.card,
        foregroundColor: AppColors.primary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleSpacing: 16,
        shape: const Border(bottom: _hairline),
        systemOverlayStyle: SystemUiOverlayStyle.dark.copyWith(
          statusBarColor: Colors.transparent,
        ),
        iconTheme: const IconThemeData(color: AppColors.primary, size: 24),
        titleTextStyle: AppTexto.subtitulo.copyWith(
          fontFamily: AppTexto.familia,
          fontSize: 17,
          fontFeatures: AppTexto.rasgos,
        ),
      ),

      // Pestañas: blancas, con línea fina arriba y el tinte del acento como
      // indicador. Es el único lugar, además del botón principal, donde el
      // naranjo marca un estado.
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.card,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        height: 68,
        indicatorColor: AppColors.accentTint,
        indicatorShape: botonForma,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: WidgetStateProperty.resolveWith(
          (estados) => IconThemeData(
            size: 24,
            color: estados.contains(WidgetState.selected)
                ? AppColors.accentFill
                : AppColors.secondary,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (estados) => TextStyle(
            fontFamily: AppTexto.familia,
            fontSize: 12,
            letterSpacing: -0.1,
            fontWeight: estados.contains(WidgetState.selected)
                ? FontWeight.w600
                : FontWeight.w500,
            color: estados.contains(WidgetState.selected)
                ? AppColors.primary
                : AppColors.secondary,
          ),
        ),
      ),

      cardTheme: const CardThemeData(
        color: AppColors.card,
        elevation: 0,
        margin: EdgeInsets.zero,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          side: _hairline,
          borderRadius: AppForma.borde,
        ),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.accentFill,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.sunken,
          disabledForegroundColor: AppColors.secondary,
          // 52 px: por debajo de 44 no se acierta con guantes puestos.
          minimumSize: const Size.fromHeight(52),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          elevation: 0,
          shape: botonForma,
          textStyle: const TextStyle(
            fontFamily: AppTexto.familia,
            fontSize: 16,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.2,
          ),
        ),
      ),

      // Secundario: contorno de control (3.4:1) y tinta pizarra. Deja todo el
      // color para la acción principal que tiene al lado.
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          minimumSize: const Size.fromHeight(52),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          side: const BorderSide(color: AppColors.borderControl),
          shape: botonForma,
          textStyle: const TextStyle(
            fontFamily: AppTexto.familia,
            fontSize: 16,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.2,
          ),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.accentFill,
          minimumSize: const Size(48, 44),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          shape: botonForma,
          textStyle: const TextStyle(
            fontFamily: AppTexto.familia,
            fontSize: 14,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.1,
          ),
        ),
      ),

      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: AppColors.primary,
          minimumSize: const Size(48, 48),
          shape: botonForma,
        ),
      ),

      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.accentFill,
        foregroundColor: Colors.white,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
        shape: botonForma,
        extendedTextStyle: TextStyle(
          fontFamily: AppTexto.familia,
          fontSize: 15,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.15,
        ),
      ),

      // Campo blanco sobre el lienzo, con el contorno de control que lo
      // identifica como un lugar donde escribir (3.3:1, sobre el 3:1 de WCAG).
      inputDecorationTheme: const InputDecorationTheme(
        filled: true,
        fillColor: AppColors.card,
        contentPadding: EdgeInsets.symmetric(vertical: 16, horizontal: 14),
        hintStyle: TextStyle(color: AppColors.secondary, letterSpacing: -0.1),
        border: OutlineInputBorder(
          borderRadius: AppForma.borde,
          borderSide: BorderSide(color: AppColors.borderControl),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppForma.borde,
          borderSide: BorderSide(color: AppColors.borderControl),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: AppForma.borde,
          borderSide: BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppForma.borde,
          borderSide: BorderSide(color: AppColors.accent, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: AppForma.borde,
          borderSide: BorderSide(color: AppColors.destructive),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: AppForma.borde,
          borderSide: BorderSide(color: AppColors.destructive, width: 2),
        ),
        errorStyle: TextStyle(
          fontSize: 12.5,
          color: AppColors.destructiveDark,
          letterSpacing: -0.1,
        ),
      ),

      dividerTheme: const DividerThemeData(
        color: AppColors.border,
        thickness: 1,
        space: 1,
      ),

      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        minVerticalPadding: 10,
        shape: RoundedRectangleBorder(borderRadius: AppForma.borde),
        titleTextStyle: TextStyle(
          fontFamily: AppTexto.familia,
          fontSize: 15,
          fontWeight: FontWeight.w500,
          letterSpacing: -0.15,
          color: AppColors.primary,
        ),
        subtitleTextStyle: TextStyle(
          fontFamily: AppTexto.familia,
          fontSize: 12.5,
          letterSpacing: 0,
          color: AppColors.secondary,
        ),
        iconColor: AppColors.secondary,
      ),

      chipTheme: ChipThemeData(
        backgroundColor: AppColors.card,
        selectedColor: AppColors.accentTint,
        side: const BorderSide(color: AppColors.borderControl),
        shape: const RoundedRectangleBorder(borderRadius: AppForma.bordeChip),
        labelStyle: const TextStyle(
          fontFamily: AppTexto.familia,
          fontSize: 13,
          fontWeight: FontWeight.w500,
          letterSpacing: -0.1,
          color: AppColors.primary,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      ),

      // Lo que flota sí lleva sombra, y una sola: es lo único que está encima
      // de otra superficie.
      dialogTheme: const DialogThemeData(
        backgroundColor: AppColors.card,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shadowColor: Color(0x33000000),
        shape: RoundedRectangleBorder(borderRadius: AppForma.borde),
        titleTextStyle: AppTexto.titulo,
        contentTextStyle: TextStyle(
          fontFamily: AppTexto.familia,
          fontSize: 14,
          height: 1.45,
          letterSpacing: -0.1,
          color: AppColors.textMuted,
        ),
      ),

      // Flotante: la barra fija tapaba el botón principal justo cuando
      // aparece la confirmación, que es cuando alguien quiere registrar el
      // siguiente movimiento.
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.surfaceDark,
        elevation: 6,
        contentTextStyle: TextStyle(
          fontFamily: AppTexto.familia,
          fontSize: 14,
          color: Colors.white,
          height: 1.4,
          letterSpacing: -0.1,
        ),
        actionTextColor: AppColors.accentOnDark,
        shape: RoundedRectangleBorder(borderRadius: AppForma.borde),
        insetPadding: EdgeInsets.fromLTRB(16, 0, 16, 16),
      ),

      // Las hojas de aprobar y rechazar se cierran arrastrando: el tirador
      // lo dice sin palabras.
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.card,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: AppColors.borderControl,
        dragHandleSize: Size(36, 4),
        elevation: 8,
        shadowColor: Color(0x33000000),
        shape: RoundedRectangleBorder(borderRadius: AppForma.bordeHoja),
      ),

      datePickerTheme: const DatePickerThemeData(
        backgroundColor: AppColors.card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: AppForma.borde),
        headerBackgroundColor: AppColors.card,
        headerForegroundColor: AppColors.primary,
      ),
      timePickerTheme: const TimePickerThemeData(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: AppForma.borde),
        hourMinuteShape: RoundedRectangleBorder(borderRadius: AppForma.borde),
        dayPeriodShape: RoundedRectangleBorder(borderRadius: AppForma.borde),
      ),

      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.accentFill,
        linearTrackColor: AppColors.sunken,
      ),

      badgeTheme: const BadgeThemeData(
        backgroundColor: AppColors.destructive,
        textColor: Colors.white,
        textStyle: TextStyle(
          fontFamily: AppTexto.familia,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          fontFeatures: AppTexto.tabulares,
        ),
      ),

      tooltipTheme: const TooltipThemeData(
        decoration: BoxDecoration(
          color: AppColors.surfaceDark,
          borderRadius: AppForma.bordeChip,
        ),
        textStyle: TextStyle(
          fontFamily: AppTexto.familia,
          fontSize: 12.5,
          color: Colors.white,
        ),
      ),

      // Transición de Android moderna: la pantalla nueva entra desde la
      // derecha con un fundido corto. Es la que el teléfono ya usa en el resto
      // del sistema, así que no enseña nada nuevo.
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        },
      ),
    );
  }
}
