import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_forma.dart';
import '../../core/theme/app_theme.dart';
import '../../data/modelos/herramienta.dart';
import '../../data/modelos/perfil_trabajador.dart';
import '../../shared_widgets/estados.dart';
import '../../shared_widgets/panel.dart';
import 'filas_trabajador.dart';
import 'pantalla_pedido_qr.dart';
import 'pantalla_pedir.dart';
import 'trabajador_providers.dart';

/// Inicio del trabajador: dónde está, qué puede pedir, qué tiene en su poder y
/// qué espera de bodega.
///
/// Lo vencido va primero y en rojo porque es lo único de esta pantalla que le
/// genera un problema a él: la alerta de "no devuelta" sale con su nombre.
class PantallaInicioTrabajador extends ConsumerWidget {
  const PantallaInicioTrabajador({super.key, required this.perfil});

  final PerfilTrabajador perfil;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enMiPoder = ref.watch(enMiPoderProvider);
    final pendientes = ref.watch(misPendientesProvider);
    final porConfirmar = ref.watch(porConfirmarProvider);
    final novedades = ref.watch(misSolicitudesProvider).whenData(_novedades);
    final porRetirar = ref.watch(pedidosPorRetirarProvider);

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(perfilTrabajadorProvider);
        recargarTrabajador(ref);
        await ref.read(misSolicitudesProvider.future);
      },
      child: ListView(
        padding: AppEspacio.pantalla,
        children: [
          // Lo que bodega ya le pasó va antes que todo: es lo único de la
          // pantalla que espera algo de él.
          if (porConfirmar.valueOrNull?.isNotEmpty ?? false) ...[
            _Seccion<MiSolicitud>(
              titulo: 'Confirma que lo recibiste',
              valor: porConfirmar,
              alReintentar: () => ref.invalidate(misSolicitudesProvider),
              vacio: '',
              fila: (s) => FilaMiSolicitud(solicitud: s),
            ),
            const SizedBox(height: AppEspacio.lg),
          ],
          // Lo que ya pidió con QR y tiene que ir a buscar: el código tiene
          // que estar a un toque al llegar al mesón.
          for (final pedido in porRetirar) ...[
            TarjetaPedidoPorRetirar(pedido: pedido),
            const SizedBox(height: AppEspacio.md),
          ],
          _Obra(perfil: perfil),
          const SizedBox(height: AppEspacio.md),
          Row(
            children: [
              Expanded(
                child: _BotonPedir(
                  icono: Icons.inventory_2_outlined,
                  titulo: 'Pedir material',
                  habilitado: perfil.puedePedirMaterial,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => PantallaPedirMaterial(perfil: perfil),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppEspacio.sm + 4),
              Expanded(
                child: _BotonPedir(
                  icono: Icons.handyman_outlined,
                  titulo: 'Pedir herramienta',
                  habilitado: perfil.puedePedirMaterial,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const PantallaPedirHerramienta(),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppEspacio.lg),
          _Seccion<Prestamo>(
            titulo: 'En tu poder',
            valor: enMiPoder,
            alReintentar: () => ref.invalidate(misPrestamosProvider),
            vacio: 'No tienes herramientas prestadas.',
            fila: (p) => FilaPrestamo(prestamo: p),
          ),
          const SizedBox(height: AppEspacio.lg),
          _Seccion<MiSolicitud>(
            titulo: 'Esperando a bodega',
            valor: pendientes,
            alReintentar: () => ref.invalidate(misSolicitudesProvider),
            vacio: 'No tienes solicitudes pendientes.',
            fila: (s) => FilaMiSolicitud(solicitud: s),
          ),
          if (novedades.valueOrNull?.isNotEmpty ?? false) ...[
            const SizedBox(height: AppEspacio.lg),
            _Seccion<MiSolicitud>(
              titulo: 'Resueltas hace poco',
              valor: novedades,
              alReintentar: () => ref.invalidate(misSolicitudesProvider),
              vacio: '',
              fila: (s) => FilaMiSolicitud(solicitud: s),
            ),
          ],
          const SizedBox(height: AppEspacio.lg),
        ],
      ),
    );
  }

  /// Lo que bodega resolvió en los últimos tres días. Sin esto, una
  /// solicitud rechazada desaparecía de "Esperando" sin que nadie le dijera
  /// al trabajador por qué.
  static List<MiSolicitud> _novedades(List<MiSolicitud> todas) {
    final desde = DateTime.now().subtract(const Duration(days: 3));
    return todas
        .where(
          (s) =>
              !s.enEspera &&
              !s.porConfirmar &&
              !s.retirada &&
              (s.fecha?.isAfter(desde) ?? false),
        )
        .take(3)
        .toList();
  }
}

class _Obra extends StatelessWidget {
  const _Obra({required this.perfil});

  final PerfilTrabajador perfil;

  @override
  Widget build(BuildContext context) {
    final p = perfil;
    if (!p.tieneObra) {
      return _Aviso(
        icono: Icons.group_off_outlined,
        texto:
            'Todavía no estás en ninguna cuadrilla, así que no hay bodega a '
            'la que pedirle. Avísale a tu jefe de terreno.',
      );
    }
    if (!p.obraActiva) {
      return _Aviso(
        icono: Icons.lock_outline,
        texto:
            '${p.obraNombre} está cerrada: ya no entra ni sale material. Si '
            'te cambiaron de obra, pide que te asignen a la nueva cuadrilla.',
      );
    }
    return Panel(
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(
              color: AppColors.sunken,
              borderRadius: AppForma.borde,
            ),
            child: const Icon(
              Icons.domain_outlined,
              color: AppColors.secondary,
            ),
          ),
          const SizedBox(width: AppEspacio.sm + 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.obraNombre!,
                  style: AppTexto.cuerpo.copyWith(fontWeight: FontWeight.w600),
                ),
                if (p.cuadrillaNombre != null)
                  Text(p.cuadrillaNombre!, style: AppTexto.dato),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Aviso extends StatelessWidget {
  const _Aviso({required this.icono, required this.texto});

  final IconData icono;
  final String texto;

  @override
  Widget build(BuildContext context) {
    return Panel(
      color: AppColors.warningTint,
      borderColor: AppColors.warning,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icono, color: AppColors.warningDark),
          const SizedBox(width: AppEspacio.sm + 4),
          Expanded(
            child: Text(
              texto,
              style: AppTexto.cuerpoChico.copyWith(
                fontSize: 14,
                color: AppColors.warningInk,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Las dos acciones principales, grandes y lado a lado: es lo que se viene a
/// hacer, con guantes y apurado.
class _BotonPedir extends StatelessWidget {
  const _BotonPedir({
    required this.icono,
    required this.titulo,
    required this.habilitado,
    required this.onTap,
  });

  final IconData icono;
  final String titulo;
  final bool habilitado;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PanelTocable(
      semanticLabel: habilitado ? titulo : '$titulo, no disponible',
      onTap: habilitado ? onTap : null,
      color: habilitado ? AppColors.card : AppColors.background,
      borderColor: habilitado ? AppColors.borderControl : AppColors.border,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: habilitado ? AppColors.accentTint : AppColors.sunken,
              borderRadius: AppForma.borde,
            ),
            child: Icon(
              icono,
              size: 21,
              color: habilitado ? AppColors.accentFill : AppColors.textFaint,
            ),
          ),
          const SizedBox(height: AppEspacio.sm + 4),
          Text(
            titulo,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              height: 1.25,
              color: habilitado ? AppColors.primary : AppColors.secondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _Seccion<T> extends StatelessWidget {
  const _Seccion({
    required this.titulo,
    required this.valor,
    required this.alReintentar,
    required this.vacio,
    required this.fila,
  });

  final String titulo;
  final AsyncValue<List<T>> valor;
  final VoidCallback alReintentar;
  final String vacio;
  final Widget Function(T) fila;

  @override
  Widget build(BuildContext context) {
    final n = valor.valueOrNull?.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Etiqueta(n == null || n == 0 ? titulo : '$titulo ($n)'),
        const SizedBox(height: AppEspacio.sm + 4),
        Contenido<List<T>>(
          valor: valor,
          alReintentar: alReintentar,
          estaVacio: (l) => l.isEmpty,
          vacio: Text(vacio, style: AppTexto.cuerpoChico),
          constructor: (lista) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final x in lista) ...[
                fila(x),
                const SizedBox(height: AppEspacio.sm),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
