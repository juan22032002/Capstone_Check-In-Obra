import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../shared_widgets/estados.dart';

/// Lo que se muestra cuando la app se compiló con una configuración que no se
/// puede usar —hoy, una URL de servidor sin https:// en release.
///
/// No hay sesión ni red todavía, así que no depende de ningún provider.
class PantallaConfiguracionInvalida extends StatelessWidget {
  const PantallaConfiguracionInvalida({super.key, required this.mensaje});

  final String mensaje;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Check-In-Obra',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'La app no puede conectarse',
                      textAlign: TextAlign.center,
                      style: AppTexto.titulo,
                    ),
                    const SizedBox(height: 16),
                    MensajeError(mensaje: mensaje),
                    const SizedBox(height: 16),
                    const Text(
                      'Avisa a quien administra la app: esta versión quedó mal '
                      'configurada.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
