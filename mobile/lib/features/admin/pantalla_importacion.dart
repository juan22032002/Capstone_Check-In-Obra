import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/errores.dart';
import '../../core/network/idempotencia.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../data/api/dominio_api.dart';
import '../../data/modelos/importacion.dart';
import '../../shared_widgets/estados.dart';
import '../../shared_widgets/opcion.dart';
import '../../shared_widgets/panel.dart';
import '../bodega/bodega_providers.dart';

/// Solo `.xlsx`. El backend (S-21) no lee el formato `.xls` antiguo: lo rechaza
/// con un 400 aunque sea un Excel válido, porque su estructura no se puede
/// acotar como la de un `.xlsx`.
const extensionesDePlanilla = ['xlsx'];

const mensajePlanillaNoXlsx =
    'La planilla tiene que ser un archivo .xlsx. Si la tienes en .xls, ábrela '
    'en Excel y guárdala como "Libro de Excel (.xlsx)".';

/// Si el nombre del archivo es de una planilla que el servidor acepta.
bool esPlanillaXlsx(String nombre) => nombre.toLowerCase().endsWith('.xlsx');

/// Qué catálogo se está cargando. Son dos planillas distintas —columnas
/// distintas— y mezclarlas es el error más caro posible acá.
enum CatalogoImportable {
  materiales,
  herramientas;

  String get titulo => switch (this) {
    CatalogoImportable.materiales => 'Materiales',
    CatalogoImportable.herramientas => 'Herramientas',
  };

  String get nombrePlantilla => switch (this) {
    CatalogoImportable.materiales => 'materiales-plantilla.xlsx',
    CatalogoImportable.herramientas => 'herramientas-plantilla.xlsx',
  };

  /// Las columnas, en el orden en que las lee el servidor.
  List<(String, String)> get columnas => switch (this) {
    CatalogoImportable.materiales => const [
      ('SKU', 'Único en la empresa. Es el de la guía de despacho'),
      ('NOMBRE', 'Como aparece en el catálogo'),
      ('CATEGORIA', 'METALCOM, VOLCANITA, OSB o FIJACION'),
      ('PRECIO_UNITARIO', 'En pesos, sin símbolo'),
      ('STOCK_MINIMO', 'Bajo esta cantidad se alerta stock crítico'),
      ('CODIGO_BARRA', 'Opcional. El de fábrica, para el escáner'),
    ],
    CatalogoImportable.herramientas => const [
      ('CODIGO', 'El de la etiqueta que se pega a la herramienta'),
      ('NOMBRE', 'Taladro percutor 800 W'),
      ('CATEGORIA', 'Texto libre: Eléctrica, Medición, Manual…'),
      ('VALOR_REPOSICION', 'Cuánto cuesta reponerla si se pierde'),
    ],
  };
}

/// Alta masiva del catálogo desde una planilla Excel.
///
/// Cargar treinta y cuatro materiales a mano en un teléfono es media hora de
/// tecleo y varios errores de dedo que después se propagan a cada presupuesto.
/// La planilla ya existe —el catálogo de la constructora vive en Excel— así
/// que lo que falta es subirla.
///
/// El flujo tiene un paso intermedio a propósito: la planilla se **valida
/// completa** antes de escribir nada, y el administrador ve el informe con la
/// fila exacta de cada problema. Si algo falla, no se importa nada: se corrige
/// el archivo y se vuelve a subir. Importar "lo que se pueda" dejaría el
/// catálogo a medias, sin manera de saber qué entró.
class PantallaImportacion extends ConsumerStatefulWidget {
  const PantallaImportacion({
    super.key,
    this.inicial = CatalogoImportable.materiales,
    this.soloEseCatalogo = false,
  });

  final CatalogoImportable inicial;

  /// Oculta el selector. El bodeguero llega acá desde sus herramientas y no
  /// puede cargar materiales —el catálogo y los precios son del
  /// administrador—, así que ofrecerle la pestaña sería ofrecerle un 403.
  final bool soloEseCatalogo;

  @override
  ConsumerState<PantallaImportacion> createState() =>
      _PantallaImportacionState();
}

class _PantallaImportacionState extends ConsumerState<PantallaImportacion> {
  late CatalogoImportable _catalogo = widget.inicial;

  Uint8List? _contenido;
  String? _nombreArchivo;
  ResultadoImportacion? _informe;
  bool _trabajando = false;
  String? _error;

  /// Cuántos registros quedaron guardados, cuando ya se importó.
  int? _importados;

  /// La confirmación es la escritura: sube el mismo archivo y lo da de alta.
  /// Si la respuesta se pierde y se vuelve a confirmar, sin clave el segundo
  /// envío chocaría con los SKU que el primero ya creó y diría "error" sobre
  /// una importación que salió bien.
  final _intento = IntentoIdempotente();

  void _cambiarCatalogo(CatalogoImportable nuevo) {
    // Con una subida en vuelo, su informe terminaría mostrado bajo el otro
    // catálogo.
    if (nuevo == _catalogo || _trabajando) return;
    // Las columnas cambian: la planilla elegida ya no sirve, y dejarla
    // seleccionada invitaría a subir el archivo de materiales como si fuera el
    // de herramientas.
    setState(() {
      _catalogo = nuevo;
      _contenido = null;
      _nombreArchivo = null;
      _informe = null;
      _importados = null;
      _error = null;
    });
  }

  Future<void> _descargarPlantilla() async {
    if (_trabajando) return;
    setState(() {
      _trabajando = true;
      _error = null;
    });
    try {
      final api = ref.read(importacionApiProvider);
      final bytes = switch (_catalogo) {
        CatalogoImportable.materiales => await api.plantillaDeMateriales(),
        CatalogoImportable.herramientas => await api.plantillaDeHerramientas(),
      };

      final destino = await FilePicker.saveFile(
        fileName: _catalogo.nombrePlantilla,
        bytes: bytes,
        mimeType:
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      );

      if (!mounted || destino == null) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Plantilla guardada: ${_catalogo.nombrePlantilla}'),
        ),
      );
    } catch (e) {
      if (mounted) setState(() => _error = mensajeDeError(e));
    } finally {
      if (mounted) setState(() => _trabajando = false);
    }
  }

  /// Elegir el archivo y validarlo son un solo gesto: un archivo elegido y no
  /// revisado no sirve de nada, y obligar a apretar "validar" después de
  /// elegirlo solo agrega un paso.
  Future<void> _elegirYValidar() async {
    if (_trabajando) return;
    final archivo = await FilePicker.pickFile(
      dialogTitle: 'Planilla de ${_catalogo.titulo.toLowerCase()}',
      type: FileType.custom,
      allowedExtensions: extensionesDePlanilla,
    );
    if (archivo == null || !mounted) return;

    // El selector de algunos teléfonos deja elegir "cualquier archivo" aunque se
    // le pida solo `xlsx`. El backend rechaza lo que no sea `.xlsx` con un 400;
    // se avisa acá y se ahorra subirlo.
    if (!esPlanillaXlsx(archivo.name)) {
      setState(() {
        _error = mensajePlanillaNoXlsx;
        _informe = null;
        _importados = null;
        _contenido = null;
        _nombreArchivo = null;
      });
      return;
    }

    setState(() {
      _trabajando = true;
      _error = null;
      _informe = null;
      _importados = null;
      _nombreArchivo = archivo.name;
    });

    try {
      // Se leen los bytes en vez de usar la ruta: en Android el explorador
      // devuelve un `content://` y un archivo de Drive o del correo no tiene
      // ruta local que abrir.
      final contenido = await archivo.readAsBytes();
      _contenido = contenido;

      final informe = await _subir(contenido, archivo.name, confirmar: false);
      if (!mounted) return;
      setState(() => _informe = informe);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = mensajeDeError(e);
        _contenido = null;
      });
    } finally {
      if (mounted) setState(() => _trabajando = false);
    }
  }

  Future<void> _importar() async {
    if (_trabajando) return;
    final contenido = _contenido;
    final nombre = _nombreArchivo;
    if (contenido == null || nombre == null) return;

    setState(() {
      _trabajando = true;
      _error = null;
    });

    try {
      final informe = await _subir(
        contenido,
        nombre,
        confirmar: true,
        // El mismo objeto de bytes es el mismo archivo: elegir otro lo
        // reemplaza y con eso cambia la clave.
        clave: _intento.clavePara([_catalogo, contenido, nombre]),
      );

      // El catálogo cambió: la bodega, el presupuesto y el escáner lo leen de
      // los mismos providers.
      ref.invalidate(catalogoProvider);
      ref.invalidate(herramientasProvider);

      if (!mounted) return;
      setState(() {
        _informe = informe;
        _importados = informe.importadas;
        _contenido = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = mensajeDeError(e));
    } finally {
      if (mounted) setState(() => _trabajando = false);
    }
  }

  Future<ResultadoImportacion> _subir(
    Uint8List contenido,
    String nombre, {
    required bool confirmar,
    String? clave,
  }) {
    final api = ref.read(importacionApiProvider);
    return switch (_catalogo) {
      CatalogoImportable.materiales => api.materiales(
        contenido: contenido,
        nombreArchivo: nombre,
        confirmar: confirmar,
        clave: clave,
      ),
      CatalogoImportable.herramientas => api.herramientas(
        contenido: contenido,
        nombreArchivo: nombre,
        confirmar: confirmar,
        clave: clave,
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final informe = _informe;

    return Scaffold(
      appBar: AppBar(title: const Text('Importación masiva')),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (!widget.soloEseCatalogo) ...[
              _SelectorCatalogo(
                catalogo: _catalogo,
                habilitado: !_trabajando,
                alCambiar: _cambiarCatalogo,
              ),
              const SizedBox(height: 18),
            ],
            _Columnas(catalogo: _catalogo),
            const SizedBox(height: 18),
            OutlinedButton.icon(
              onPressed: _trabajando ? null : _descargarPlantilla,
              icon: const Icon(Icons.download_outlined, size: 20),
              label: Text(
                'Descargar plantilla de ${_catalogo.titulo.toLowerCase()}',
              ),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: _trabajando ? null : _elegirYValidar,
              icon: const Icon(Icons.upload_file, size: 20),
              label: Text(
                _nombreArchivo == null
                    ? 'Elegir planilla (.xlsx)'
                    : 'Elegir otra planilla',
              ),
            ),
            if (_nombreArchivo case final nombre?) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(
                    Icons.description_outlined,
                    size: 18,
                    color: AppColors.secondary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      nombre,
                      style: const TextStyle(
                        fontFamily: AppTheme.monoFamily,
                        fontSize: 12,
                        color: AppColors.secondary,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            if (_trabajando) ...[
              const SizedBox(height: 20),
              const Center(
                child: CircularProgressIndicator(color: AppColors.accentFill),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 18),
              MensajeError(mensaje: _error!),
            ],
            if (_importados case final cuantos?) ...[
              const SizedBox(height: 18),
              _Importado(cuantos: cuantos, catalogo: _catalogo),
            ] else if (informe != null) ...[
              const SizedBox(height: 18),
              _Informe(informe: informe, catalogo: _catalogo),
              if (informe.listaParaImportar) ...[
                const SizedBox(height: 14),
                FilledButton(
                  onPressed: _trabajando ? null : _importar,
                  child: Text(
                    'Importar ${informe.filasValidas} '
                    '${_catalogo.titulo.toLowerCase()}',
                  ),
                ),
              ],
            ],
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _SelectorCatalogo extends StatelessWidget {
  const _SelectorCatalogo({
    required this.catalogo,
    required this.habilitado,
    required this.alCambiar,
  });

  final CatalogoImportable catalogo;
  final bool habilitado;
  final void Function(CatalogoImportable) alCambiar;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final c in CatalogoImportable.values) ...[
          Expanded(
            child: Opcion(
              texto: c.titulo,
              semanticLabel: 'Importar ${c.titulo}',
              elegida: c == catalogo,
              expandida: true,
              alTocar: habilitado ? () => alCambiar(c) : null,
            ),
          ),
          if (c != CatalogoImportable.values.last) const SizedBox(width: 8),
        ],
      ],
    );
  }
}

/// Las columnas esperadas, escritas donde se van a necesitar.
///
/// El servidor lee por posición, así que una columna cambiada de lugar arruina
/// el archivo entero. Decirlo acá evita el primer intento fallido de todos.
class _Columnas extends StatelessWidget {
  const _Columnas({required this.catalogo});

  final CatalogoImportable catalogo;

  @override
  Widget build(BuildContext context) {
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'La planilla tiene que traer estas columnas, en este orden y con '
            'una fila de encabezado:',
            style: TextStyle(
              fontSize: 12.5,
              height: 1.4,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 12),
          for (final (i, (columna, detalle)) in catalogo.columnas.indexed) ...[
            if (i > 0) const SizedBox(height: 9),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 22,
                  child: Text(
                    '${i + 1}.',
                    style: const TextStyle(
                      fontFamily: AppTheme.monoFamily,
                      fontSize: 12,
                      color: AppColors.secondary,
                    ),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        columna,
                        style: const TextStyle(
                          fontFamily: AppTheme.monoFamily,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        detalle,
                        style: const TextStyle(
                          fontSize: 12.5,
                          height: 1.3,
                          color: AppColors.secondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// El informe de la validación, con la fila exacta de cada problema.
class _Informe extends StatelessWidget {
  const _Informe({required this.informe, required this.catalogo});

  final ResultadoImportacion informe;
  final CatalogoImportable catalogo;

  @override
  Widget build(BuildContext context) {
    final ok = informe.listaParaImportar;

    return Semantics(
      liveRegion: true,
      child: Panel(
        color: ok ? AppColors.successTint : AppColors.destructiveTint,
        borderColor: ok ? AppColors.success : AppColors.destructive,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  ok ? Icons.fact_check_outlined : Icons.report_outlined,
                  size: 20,
                  color: ok ? AppColors.successDark : AppColors.destructiveDark,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    ok
                        ? '${informe.filasValidas} '
                              '${catalogo.titulo.toLowerCase()} listos para '
                              'importar'
                        : '${informe.errores.length} de '
                              '${informe.filasLeidas} filas tienen problemas',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                      color: ok
                          ? AppColors.successDark
                          : AppColors.destructiveDark,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              ok
                  ? 'Todavía no se guardó nada: revisa la cifra y confirma '
                        'abajo.'
                  : 'No se importó nada. Corrige estas filas en la planilla y '
                        'vuelve a subirla — la importación es todo o nada.',
              style: TextStyle(
                fontSize: 12.5,
                height: 1.4,
                color: ok ? AppColors.successDark : AppColors.destructiveDark,
              ),
            ),
            if (informe.errores.isNotEmpty) ...[
              const SizedBox(height: 12),
              for (final error in informe.errores) ...[
                Padding(
                  padding: const EdgeInsets.only(bottom: 7),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 62,
                        child: Text(
                          'Fila ${error.fila}',
                          style: const TextStyle(
                            fontFamily: AppTheme.monoFamily,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.destructiveDark,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          error.detalle,
                          style: const TextStyle(
                            fontSize: 12.5,
                            height: 1.35,
                            color: AppColors.destructiveDark,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _Importado extends StatelessWidget {
  const _Importado({required this.cuantos, required this.catalogo});

  final int cuantos;
  final CatalogoImportable catalogo;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Panel(
        color: AppColors.successTint,
        borderColor: AppColors.success,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.check_circle_outline,
              size: 20,
              color: AppColors.successDark,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '$cuantos ${catalogo.titulo.toLowerCase()} quedaron en el '
                'catálogo de la empresa.',
                style: const TextStyle(
                  fontSize: 13.5,
                  height: 1.4,
                  fontWeight: FontWeight.w600,
                  color: AppColors.successDark,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
