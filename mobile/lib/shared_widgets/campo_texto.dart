import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_forma.dart';
import '../core/theme/app_theme.dart';

/// Campo de formulario del sistema. Los bordes y el relleno los pone el
/// `inputDecorationTheme`, así que acá solo va lo propio de cada campo.
class CampoTexto extends StatelessWidget {
  const CampoTexto({
    super.key,
    required this.controlador,
    required this.hint,
    required this.icono,
    this.teclado,
    this.oculto = false,
    this.mono = false,
    this.maxLength,
    this.formatters,
    this.sufijo,
    this.validador,
    this.alEnviar,
    this.habilitado = true,
  });

  final TextEditingController controlador;
  final String hint;
  final IconData icono;
  final TextInputType? teclado;
  final bool oculto;

  /// Monoespaciada para datos duros: códigos, SKU, cantidades, correos.
  final bool mono;

  final int? maxLength;
  final List<TextInputFormatter>? formatters;
  final Widget? sufijo;
  final String? Function(String?)? validador;
  final void Function(String)? alEnviar;
  final bool habilitado;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controlador,
      keyboardType: teclado,
      obscureText: oculto,
      maxLength: maxLength,
      inputFormatters: formatters,
      validator: validador,
      onFieldSubmitted: alEnviar,
      enabled: habilitado,
      autocorrect: false,
      enableSuggestions: false,
      style: TextStyle(
        fontSize: 16,
        letterSpacing: mono ? 0 : -0.15,
        fontWeight: mono ? FontWeight.w500 : FontWeight.w400,
        color: AppColors.primary,
      ),
      decoration: InputDecoration(
        hintText: hint,
        counterText: '',
        prefixIcon: Padding(
          padding: const EdgeInsets.only(left: 14, right: 10),
          child: Icon(icono, size: 20, color: AppColors.secondary),
        ),
        prefixIconConstraints: const BoxConstraints(
          minWidth: 44,
          minHeight: 44,
        ),
        // Centrado en alto: un sufijo de texto ("pl", "kg") quedaba pegado
        // arriba, porque la caja del sufijo es más alta que la línea.
        suffixIcon: sufijo == null
            ? null
            : Center(widthFactor: 1, heightFactor: 1, child: sufijo),
      ),
    );
  }
}

/// Rótulo + campo, que es como aparecen siempre en las pantallas.
class CampoConEtiqueta extends StatelessWidget {
  const CampoConEtiqueta({
    super.key,
    required this.etiqueta,
    required this.campo,
    this.ayuda,
  });

  final String etiqueta;
  final Widget campo;
  final String? ayuda;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Tipo oración: "Cantidad a despachar" se lee de un vistazo; en
        // mayúsculas espaciadas había que deletrearlo.
        Text(etiqueta, style: AppTexto.rotulo),
        const SizedBox(height: AppEspacio.sm),
        campo,
        if (ayuda != null) ...[
          const SizedBox(height: AppEspacio.sm - 2),
          Text(
            ayuda!,
            style: AppTexto.cuerpoChico.copyWith(
              fontSize: 12.5,
              color: AppColors.secondary,
            ),
          ),
        ],
      ],
    );
  }
}
