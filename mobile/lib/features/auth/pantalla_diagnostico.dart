import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_forma.dart';
import '../../core/theme/app_theme.dart';
import 'diagnostico_conexion.dart';

/// Pantalla de verificación: comprueba que el teléfono alcanza la API.
///
/// No es una pantalla del producto — es una herramienta de diagnóstico para
/// el equipo, que valida la cadena completa teléfono → WiFi → Docker → Postgres
/// antes de empezar a construir las pantallas reales.
///
/// **Solo existe fuera de release.** Muestra la URL del servidor, el contenido
/// del `.env` y el comienzo del token de sesión: útil para armar el entorno,
/// información de más en el teléfono de un usuario (hallazgo S-29). En release
/// la pantalla no se dibuja aunque alguien la abra.
class PantallaDiagnostico extends ConsumerWidget {
  const PantallaDiagnostico({super.key, this.disponible});

  /// Solo para probar: por defecto la pantalla está disponible fuera de release.
  final bool? disponible;

  /// Si el diagnóstico se puede mostrar en este modo de compilación.
  static bool get disponibleEnEstaCompilacion => !kReleaseMode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!(disponible ?? disponibleEnEstaCompilacion)) {
      return const Scaffold(
        body: Center(child: Text('Esta pantalla no está disponible.')),
      );
    }
    final estado = ref.watch(diagnosticoConexionProvider);
    final envCargado = ref.watch(envCargadoProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Verificación de conexión',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!envCargado) const _AvisoSinEnv(),
              if (!envCargado) const SizedBox(height: 14),
              const _TarjetaDestino(),
              const SizedBox(height: 14),
              estado.when(
                loading: () => const _EstadoProbando(),
                error: (e, _) => _TarjetaResultado(
                  resultado: ResultadoConexion(
                    ok: false,
                    titulo: 'Error inesperado',
                    detalle: e.toString(),
                    url: '',
                  ),
                ),
                data: (resultado) => resultado == null
                    ? const _EstadoInicial()
                    : _TarjetaResultado(resultado: resultado),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: estado.isLoading
                    ? null
                    : () => ref
                          .read(diagnosticoConexionProvider.notifier)
                          .probar(),
                child: Text(estado.isLoading ? 'Probando…' : 'Probar conexión'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AvisoSinEnv extends StatelessWidget {
  const _AvisoSinEnv();

  @override
  Widget build(BuildContext context) {
    return const _Panel(
      color: AppColors.warningTint,
      borderColor: AppColors.warning,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'No se encontró el archivo .env',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.warningDark,
            ),
          ),
          SizedBox(height: 6),
          Text(
            'Se está usando la URL por defecto del emulador. Para un celular '
            'físico, copia mobile/.env.example a mobile/.env y pon ahí la IP '
            'del computador.',
            style: TextStyle(
              fontSize: 12.5,
              height: 1.4,
              color: AppColors.warningInk,
            ),
          ),
        ],
      ),
    );
  }
}

class _TarjetaDestino extends ConsumerWidget {
  const _TarjetaDestino();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final estado = ref.watch(diagnosticoConexionProvider);
    final url = estado.valueOrNull?.url;

    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _Etiqueta('Destino'),
          const SizedBox(height: 8),
          Text(
            url ?? 'Se resuelve al probar',
            style: const TextStyle(
              fontFamily: AppTheme.monoFamily,
              fontSize: 14,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Se autentica al administrador semilla para comprobar que la '
            'cadena completa funciona: red, API, base de datos y migraciones.',
            style: TextStyle(
              fontSize: 12.5,
              height: 1.4,
              color: AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _EstadoInicial extends StatelessWidget {
  const _EstadoInicial();

  @override
  Widget build(BuildContext context) {
    return const _Panel(
      child: Row(
        children: [
          Icon(
            Icons.radio_button_unchecked,
            size: 20,
            color: AppColors.textFaint,
          ),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'Sin probar todavía',
              style: TextStyle(fontSize: 13.5, color: AppColors.textMuted),
            ),
          ),
        ],
      ),
    );
  }
}

class _EstadoProbando extends StatelessWidget {
  const _EstadoProbando();

  @override
  Widget build(BuildContext context) {
    return const _Panel(
      child: Row(
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.accentFill,
            ),
          ),
          SizedBox(width: 14),
          Expanded(
            child: Text(
              'Contactando al servidor…',
              style: TextStyle(fontSize: 13.5, color: AppColors.textMuted),
            ),
          ),
        ],
      ),
    );
  }
}

class _TarjetaResultado extends StatelessWidget {
  const _TarjetaResultado({required this.resultado});

  final ResultadoConexion resultado;

  @override
  Widget build(BuildContext context) {
    final ok = resultado.ok;
    final tinte = ok ? AppColors.successTint : AppColors.destructiveTint;
    final borde = ok ? AppColors.success : AppColors.destructive;
    final textoFuerte = ok ? AppColors.successDark : AppColors.destructiveDark;

    return _Panel(
      color: tinte,
      borderColor: borde,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                ok ? Icons.check_circle_outline : Icons.error_outline,
                size: 22,
                color: borde,
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Text(
                  resultado.titulo,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: textoFuerte,
                  ),
                ),
              ),
              if (resultado.latenciaMs != null)
                Text(
                  '${resultado.latenciaMs} ms',
                  style: TextStyle(
                    fontFamily: AppTheme.monoFamily,
                    fontSize: 12,
                    color: textoFuerte,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            resultado.detalle,
            style: TextStyle(fontSize: 13, height: 1.4, color: textoFuerte),
          ),
          if (resultado.sesion != null) ...[
            const SizedBox(height: 14),
            const Divider(height: 1, color: AppColors.border),
            const SizedBox(height: 12),
            _Dato('Usuario', resultado.sesion!.nombre),
            _Dato('Rol', resultado.sesion!.rol, mono: true),
            _Dato('Empresa', '#${resultado.sesion!.empresaId}', mono: true),
            _Dato(
              'Token JWT',
              '${resultado.sesion!.token.substring(0, 24)}…',
              mono: true,
            ),
          ],
          if (resultado.comoArreglarlo != null) ...[
            const SizedBox(height: 14),
            const Divider(height: 1, color: AppColors.border),
            const SizedBox(height: 12),
            const _Etiqueta('Cómo resolverlo'),
            const SizedBox(height: 8),
            Text(
              resultado.comoArreglarlo!,
              style: const TextStyle(
                fontFamily: AppTheme.monoFamily,
                fontSize: 12.5,
                height: 1.5,
                color: AppColors.destructiveDark,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Dato extends StatelessWidget {
  const _Dato(this.etiqueta, this.valor, {this.mono = false});

  final String etiqueta;
  final String valor;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 84,
            child: Text(
              etiqueta,
              style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
          ),
          Expanded(
            child: Text(
              valor,
              style: TextStyle(
                fontFamily: mono ? AppTheme.monoFamily : null,
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                color: AppColors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Etiqueta extends StatelessWidget {
  const _Etiqueta(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) {
    return Text(texto, style: AppTexto.subtitulo.copyWith(fontSize: 15));
  }
}

/// Superficie base: tarjeta blanca con borde fino y el radio del sistema, sin
/// sombra.
class _Panel extends StatelessWidget {
  const _Panel({
    required this.child,
    this.color = AppColors.card,
    this.borderColor = AppColors.border,
  });

  final Widget child;
  final Color color;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppEspacio.md),
      decoration: BoxDecoration(
        color: color,
        borderRadius: AppForma.borde,
        border: Border.all(color: borderColor),
      ),
      child: child,
    );
  }
}
