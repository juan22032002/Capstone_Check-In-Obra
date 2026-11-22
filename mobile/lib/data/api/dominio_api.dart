import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../features/auth/sesion_controller.dart';
import '../modelos/alerta.dart';
import '../modelos/detalle_obra.dart';
import '../modelos/herramienta.dart';
import '../modelos/importacion.dart';
import '../modelos/kardex.dart';
import '../modelos/material.dart';
import '../modelos/obra.dart';
import '../modelos/partida.dart';
import '../modelos/pedido_especial.dart';
import '../modelos/pedido_herramienta.dart';
import '../modelos/perfil_trabajador.dart';
import '../modelos/presupuesto.dart';
import '../modelos/solicitud.dart';
import '../modelos/trabajador.dart';
import '../modelos/usuario.dart';
import 'auth_api.dart' show ApiException;
import 'cliente_rest.dart';

/// Obras de la empresa. La empresa ya no viaja como parámetro: el backend la
/// saca del token.
class ObrasApi {
  const ObrasApi(this._rest);

  final ClienteRest _rest;

  Future<List<Obra>> listar() => _rest.lista('/api/obras', Obra.desdeJson);

  Future<Obra> obtener(int id) => _rest.uno('/api/obras/$id', Obra.desdeJson);

  /// Todo de una obra en una respuesta: jefe, trabajadores, stock valorizado y
  /// herramientas prestadas en ella.
  Future<DetalleObra> detalle(int id) =>
      _rest.uno('/api/obras/$id/detalle', DetalleObra.desdeJson);

  Future<Obra> crear({
    required String nombre,
    required String cliente,
    required String ubicacion,
    int? jefeTerrenoId,
    String? clave,
  }) => _rest.crear(
    '/api/obras',
    {
      'nombre': nombre,
      'cliente': cliente,
      'ubicacion': ubicacion,
      'jefeTerrenoId': jefeTerrenoId,
    },
    Obra.desdeJson,
    clave: clave,
  );

  /// Asigna o cambia el jefe a cargo. `null` la deja sin jefe.
  Future<Obra> asignarJefe(int obraId, int? jefeTerrenoId, {String? clave}) =>
      _rest.actualizar(
        '/api/obras/$obraId/jefe-terreno',
        {'jefeTerrenoId': jefeTerrenoId},
        Obra.desdeJson,
        clave: clave,
      );

  /// El backend valida antes de cerrar: sin herramientas fuera ni alertas
  /// pendientes. Si no se cumple, responde 409 con el motivo.
  Future<Obra> cerrar(int id, {String? clave}) => _rest.actualizar(
    '/api/obras/$id/cerrar',
    const {},
    Obra.desdeJson,
    clave: clave,
  );
}

class MaterialesApi {
  const MaterialesApi(this._rest);

  final ClienteRest _rest;

  Future<List<MaterialObra>> listar({String? categoria}) => _rest.lista(
    '/api/materiales',
    MaterialObra.desdeJson,
    params: categoria == null ? null : {'categoria': categoria},
  );

  Future<MaterialObra> obtener(int id) =>
      _rest.uno('/api/materiales/$id', MaterialObra.desdeJson);

  /// Lo que se está agotando en las obras activas, crítico primero. Solo
  /// cuenta pares obra-material con movimiento: un material que nunca entró a
  /// una obra no "falta" en ella.
  Future<List<MaterialFaltante>> faltantes() =>
      _rest.lista('/api/materiales/faltantes', MaterialFaltante.desdeJson);

  /// Lo que resuelve el escáner de código de barras: el backend prueba el
  /// código impreso de fábrica y después el SKU, porque quien apunta la cámara
  /// a una etiqueta no sabe cuál de los dos está leyendo.
  Future<MaterialObra> porCodigo(String codigo) => _rest.uno(
    '/api/materiales/por-codigo/${Uri.encodeComponent(codigo)}',
    MaterialObra.desdeJson,
  );

  Future<MaterialObra> crear({
    required String sku,
    required String nombre,
    required String categoria,
    required double precioUnitario,
    required double stockMinimo,
    String? codigoBarra,
    String? clave,
  }) => _rest.crear(
    '/api/materiales',
    {
      'sku': sku,
      'nombre': nombre,
      'categoria': categoria,
      'precioUnitario': precioUnitario,
      'stockMinimo': stockMinimo,
      'codigoBarra': codigoBarra,
    },
    MaterialObra.desdeJson,
    clave: clave,
  );

  Future<MaterialObra> actualizarPrecio(
    int id,
    double nuevoPrecio, {
    String? clave,
  }) => _rest.actualizar(
    '/api/materiales/$id/precio',
    {'nuevoPrecio': nuevoPrecio},
    MaterialObra.desdeJson,
    clave: clave,
  );

  Future<ParametroMerma> definirMerma(
    int materialId,
    double porcentaje, {
    String? clave,
  }) => _rest.actualizar(
    '/api/materiales/$materialId/merma',
    {'porcentaje': porcentaje},
    ParametroMerma.desdeJson,
    clave: clave,
  );
}

class KardexApi {
  const KardexApi(this._rest);

  final ClienteRest _rest;

  Future<List<MovimientoKardex>> porObra(int obraId) => _rest.lista(
    '/api/kardex',
    MovimientoKardex.desdeJson,
    params: {'obraId': obraId},
  );

  /// El stock es la suma con signo de los movimientos, no una columna.
  Future<double> stock({required int obraId, required int materialId}) =>
      _rest.numero(
        '/api/kardex/stock',
        params: {'obraId': obraId, 'materialId': materialId},
      );

  /// Devuelve 409 si un DESPACHO o CONSUMO dejaría el saldo negativo.
  /// `trabajadorId` es obligatorio en un DESPACHO —hay que saber a quién se le
  /// entregó— y el backend lo rechaza en una RECEPCION. Con `costoUnitario`
  /// pasa al revés: solo lo acepta en una RECEPCION.
  Future<MovimientoKardex> registrar({
    required int obraId,
    required int materialId,
    required String tipo,
    required double cantidad,
    int? trabajadorId,
    double? costoUnitario,
    String? clave,
  }) => _rest.crear(
    '/api/kardex',
    {
      'obraId': obraId,
      'materialId': materialId,
      'trabajadorId': trabajadorId,
      'tipo': tipo,
      'cantidad': cantidad,
      'costoUnitario': costoUnitario,
    },
    MovimientoKardex.desdeJson,
    clave: clave,
  );
}

class HerramientasApi {
  const HerramientasApi(this._rest);

  final ClienteRest _rest;

  Future<List<Herramienta>> listar() =>
      _rest.lista('/api/herramientas', Herramienta.desdeJson);

  /// Lo que resuelve el escaneo de QR.
  /// El código va codificado: el ingreso manual del escáner acepta cualquier
  /// texto, y un "/" partiría la ruta en dos segmentos —405 en vez de "código
  /// no reconocido"— mientras que un "?" o un "#" la truncarían.
  Future<Herramienta> porCodigo(String codigoQr) => _rest.uno(
    '/api/herramientas/por-codigo/${Uri.encodeComponent(codigoQr)}',
    Herramienta.desdeJson,
  );

  Future<Herramienta> crear({
    required String codigoQr,
    required String nombre,
    required String categoria,
    required double valorReposicion,
    String? clave,
  }) => _rest.crear(
    '/api/herramientas',
    {
      'codigoQr': codigoQr,
      'nombre': nombre,
      'categoria': categoria,
      'valorReposicion': valorReposicion,
    },
    Herramienta.desdeJson,
    clave: clave,
  );
}

class PrestamosApi {
  const PrestamosApi(this._rest);

  final ClienteRest _rest;

  Future<List<Prestamo>> porObra(int obraId) => _rest.lista(
    '/api/prestamos-herramienta',
    Prestamo.desdeJson,
    params: {'obraId': obraId},
  );

  /// Los préstamos de quien entró, abiertos y cerrados. El backend lo saca del
  /// token: un trabajador no puede pedir los de otro.
  Future<List<Prestamo>> mios() =>
      _rest.lista('/api/prestamos-herramienta/mios', Prestamo.desdeJson);

  Future<List<Prestamo>> vencidos() => _rest.lista(
    '/api/prestamos-herramienta',
    Prestamo.desdeJson,
    params: {'soloVencidos': true},
  );

  /// Préstamo directo del bodeguero, sin pasar por una solicitud previa.
  Future<Prestamo> prestar({
    required int herramientaId,
    required int trabajadorId,
    required int obraId,
    required DateTime fechaDevolEsperada,
    String? clave,
  }) => _rest.crear(
    '/api/prestamos-herramienta',
    {
      'herramientaId': herramientaId,
      'trabajadorId': trabajadorId,
      'obraId': obraId,
      'fechaDevolEsperada': fechaDevolEsperada.toIso8601String(),
    },
    Prestamo.desdeJson,
    clave: clave,
  );

  Future<Prestamo> registrarDevolucion(
    int prestamoId, {
    required String nuevoEstadoHerramienta,
    String? clave,
  }) => _rest.actualizar(
    '/api/prestamos-herramienta/$prestamoId/devolucion',
    {'nuevoEstadoHerramienta': nuevoEstadoHerramienta},
    Prestamo.desdeJson,
    clave: clave,
  );
}

class AlertasApi {
  const AlertasApi(this._rest);

  final ClienteRest _rest;

  Future<List<Alerta>> porObra(int obraId, {bool soloSinResolver = false}) =>
      _rest.lista(
        '/api/alertas',
        Alerta.desdeJson,
        params: {'obraId': obraId, 'soloSinResolver': soloSinResolver},
      );

  Future<Alerta> resolver(int alertaId, {String? clave}) => _rest.actualizar(
    '/api/alertas/$alertaId/resolver',
    const {},
    Alerta.desdeJson,
    clave: clave,
  );

  /// Barre la obra y crea las alertas que correspondan. Se dispara al abrir
  /// Alertas y al cerrar turno: el backend no tiene tareas programadas.
  Future<List<Alerta>> detectarNoDevueltas(int obraId) => _rest.crearLista(
    '/api/alertas/detectar-no-devueltas?obraId=$obraId',
    const {},
    Alerta.desdeJson,
  );

  Future<List<Alerta>> detectarStockCritico(int obraId) => _rest.crearLista(
    '/api/alertas/detectar-stock-critico?obraId=$obraId',
    const {},
    Alerta.desdeJson,
  );

  Future<Alerta> cerrarTurno({
    required int obraId,
    required String mensaje,
    String? clave,
  }) => _rest.crear(
    '/api/alertas/cierre-turno',
    {'obraId': obraId, 'mensaje': mensaje},
    Alerta.desdeJson,
    clave: clave,
  );
}

class UsuariosApi {
  const UsuariosApi(this._rest);

  final ClienteRest _rest;

  Future<List<UsuarioEmpresa>> listar() =>
      _rest.lista('/api/usuarios', UsuarioEmpresa.desdeJson);

  Future<UsuarioEmpresa> crear({
    required String nombre,
    required String email,
    required String rut,
    required String rol,
    required String pinInicial,
    String? clave,
  }) => _rest.crear(
    '/api/usuarios',
    {
      'nombre': nombre,
      'email': email,
      'rut': rut,
      'rol': rol,
      'pinInicial': pinInicial,
    },
    UsuarioEmpresa.desdeJson,
    clave: clave,
  );

  Future<UsuarioEmpresa> redefinirPin(
    int usuarioId,
    String nuevoPin, {
    String? clave,
  }) => _rest.actualizar(
    '/api/usuarios/$usuarioId/pin',
    {'nuevoPin': nuevoPin},
    UsuarioEmpresa.desdeJson,
    clave: clave,
  );
}

class TrabajadoresApi {
  const TrabajadoresApi(this._rest);

  final ClienteRest _rest;

  /// Los trabajadores de una obra. El backend los alcanza por la cuadrilla, así
  /// que un trabajador sin cuadrilla asignada no aparece en ninguna obra.
  Future<List<Trabajador>> porObra(int obraId) => _rest.lista(
    '/api/trabajadores',
    Trabajador.desdeJson,
    params: {'obraId': obraId},
  );

  /// El trabajador que entró, con su obra y su credencial QR.
  Future<PerfilTrabajador> yo() =>
      _rest.uno('/api/trabajadores/yo', PerfilTrabajador.desdeJson);

  /// Emite una credencial nueva y anula la anterior. Es lo que se hace si se
  /// pierde el teléfono o alguien fotografió el código.
  Future<PerfilTrabajador> renovarMiCredencial({String? clave}) =>
      _rest.actualizar(
        '/api/trabajadores/yo/credencial',
        const {},
        PerfilTrabajador.desdeJson,
        clave: clave,
      );

  Future<Trabajador> porCredencial(String credencialQr) => _rest.uno(
    '/api/trabajadores/por-credencial/${Uri.encodeComponent(credencialQr)}',
    Trabajador.desdeJson,
  );
}

/// Las solicitudes que el trabajador levanta y el bodeguero resuelve.
///
/// Quién aprueba o rechaza no viaja en el cuerpo: el backend lo toma del
/// token. Antes se mandaba como `aprobadorId`/`rechazadorId` y el servidor lo
/// creía, así que cualquier bodeguero podía resolver a nombre de otro. Lo
/// mismo vale para `usuarioId` en el kardex y `autorizadorId` en el préstamo.
///
/// Aprobar no devuelve la solicitud: devuelve lo que la solicitud produjo —un
/// movimiento de kardex si era material, un préstamo si era herramienta—.
/// Es la forma del backend y conviene respetarla, porque es lo que hay que
/// mostrar después de aprobar.
class SolicitudesApi {
  const SolicitudesApi(this._rest);

  final ClienteRest _rest;

  // --- Del trabajador ---------------------------------------------------------
  //
  // Quién pide no viaja: el backend lo toma del token, igual que al aprobar.

  Future<List<SolicitudMaterial>> misMateriales() => _rest.lista(
    '/api/solicitudes-material/mias',
    SolicitudMaterial.desdeJson,
  );

  Future<List<SolicitudHerramienta>> misHerramientas() => _rest.lista(
    '/api/solicitudes-herramienta/mias',
    SolicitudHerramienta.desdeJson,
  );

  /// Sin `obraId` el backend usa la de su cuadrilla. Rechaza con 409 si no
  /// tiene cuadrilla, si la obra no es la suya o si está cerrada.
  ///
  /// `descripcion` es para qué lo necesita: 3 a 300 caracteres.
  Future<SolicitudMaterial> pedirMaterial({
    required int materialId,
    int? obraId,
    required double cantidad,
    required String descripcion,
    String? clave,
  }) => _rest.crear(
    '/api/solicitudes-material',
    {
      'materialId': materialId,
      'obraId': obraId,
      'cantidad': cantidad,
      'descripcion': descripcion,
    },
    SolicitudMaterial.desdeJson,
    clave: clave,
  );

  /// Siempre una: cada herramienta es una unidad con su propio QR. El backend
  /// rechaza con 409 si no está disponible o si ya la tiene pedida.
  Future<SolicitudHerramienta> pedirHerramienta({
    required int herramientaId,
    required String descripcion,
    String? clave,
  }) => _rest.crear(
    '/api/solicitudes-herramienta',
    {'herramientaId': herramientaId, 'cantidad': 1, 'descripcion': descripcion},
    SolicitudHerramienta.desdeJson,
    clave: clave,
  );

  /// Solo una pendiente y propia. 409 si el bodeguero ya la resolvió.
  Future<SolicitudMaterial> cancelarMaterial(
    int solicitudId, {
    String? clave,
  }) => _rest.actualizar(
    '/api/solicitudes-material/$solicitudId/cancelar',
    const {},
    SolicitudMaterial.desdeJson,
    clave: clave,
  );

  Future<SolicitudHerramienta> cancelarHerramienta(
    int solicitudId, {
    String? clave,
  }) => _rest.actualizar(
    '/api/solicitudes-herramienta/$solicitudId/cancelar',
    const {},
    SolicitudHerramienta.desdeJson,
    clave: clave,
  );

  /// El trabajador confirma que recibió lo que bodega le aprobó. 409
  /// NO_ENTREGADA si no estaba aprobada — incluida una repetición, que la app
  /// trata como "ya estaba".
  Future<SolicitudMaterial> confirmarRecepcionMaterial(
    int solicitudId, {
    String? clave,
  }) => _rest.actualizar(
    '/api/solicitudes-material/$solicitudId/confirmar-recepcion',
    const {},
    SolicitudMaterial.desdeJson,
    clave: clave,
  );

  Future<SolicitudHerramienta> confirmarRecepcionHerramienta(
    int solicitudId, {
    String? clave,
  }) => _rest.actualizar(
    '/api/solicitudes-herramienta/$solicitudId/confirmar-recepcion',
    const {},
    SolicitudHerramienta.desdeJson,
    clave: clave,
  );

  // --- De bodega ---------------------------------------------------------------

  Future<List<SolicitudMaterial>> materialesPorObra(
    int obraId, {
    bool soloPendientes = true,
  }) => _rest.lista(
    '/api/solicitudes-material',
    SolicitudMaterial.desdeJson,
    params: {'obraId': obraId, 'soloPendientes': soloPendientes},
  );

  /// Todo lo que pidió un trabajador, resuelto o no. Es lo que se consulta tras
  /// escanear su credencial.
  Future<List<SolicitudMaterial>> materialesPorTrabajador(int trabajadorId) =>
      _rest.lista(
        '/api/solicitudes-material',
        SolicitudMaterial.desdeJson,
        params: {'trabajadorId': trabajadorId},
      );

  /// `cantidadAEntregar` puede ser menor que la pedida: si no hay tanto en
  /// bodega, se entrega lo que hay. El backend rechaza con 409 lo que dejaría
  /// el saldo negativo.
  Future<MovimientoKardex> aprobarMaterial(
    int solicitudId, {
    required double cantidadAEntregar,
    String? clave,
  }) => _rest.actualizar(
    '/api/solicitudes-material/$solicitudId/aprobar',
    {'cantidadAEntregar': cantidadAEntregar},
    MovimientoKardex.desdeJson,
    clave: clave,
  );

  Future<SolicitudMaterial> rechazarMaterial(
    int solicitudId, {
    required String motivo,
    String? clave,
  }) => _rest.actualizar(
    '/api/solicitudes-material/$solicitudId/rechazar',
    {'motivo': motivo},
    SolicitudMaterial.desdeJson,
    clave: clave,
  );

  Future<List<SolicitudHerramienta>> herramientasPorObra(
    int obraId, {
    bool soloPendientes = true,
  }) => _rest.lista(
    '/api/solicitudes-herramienta',
    SolicitudHerramienta.desdeJson,
    params: {'obraId': obraId, 'soloPendientes': soloPendientes},
  );

  Future<List<SolicitudHerramienta>> herramientasPorTrabajador(
    int trabajadorId,
  ) => _rest.lista(
    '/api/solicitudes-herramienta',
    SolicitudHerramienta.desdeJson,
    params: {'trabajadorId': trabajadorId},
  );

  /// Aprobar genera el préstamo, así que la fecha de devolución esperada es
  /// obligatoria: es la que después vence y dispara la alerta.
  Future<Prestamo> aprobarHerramienta(
    int solicitudId, {
    required DateTime fechaDevolEsperada,
    String? clave,
  }) => _rest.actualizar(
    '/api/solicitudes-herramienta/$solicitudId/aprobar',
    {'fechaDevolEsperada': fechaDevolEsperada.toIso8601String()},
    Prestamo.desdeJson,
    clave: clave,
  );

  Future<SolicitudHerramienta> rechazarHerramienta(
    int solicitudId, {
    required String motivo,
    String? clave,
  }) => _rest.actualizar(
    '/api/solicitudes-herramienta/$solicitudId/rechazar',
    {'motivo': motivo},
    SolicitudHerramienta.desdeJson,
    clave: clave,
  );
}

/// Lo que hay que conseguir: pedidos fuera del catálogo o sin stock.
///
/// No tocan el kardex. Lo que llega entra por la recepción normal y sale con
/// el despacho de siempre; el pedido solo sigue en qué va.
class PedidosEspecialesApi {
  const PedidosEspecialesApi(this._rest);

  final ClienteRest _rest;

  /// `materialId` o `herramientaId` —nunca los dos— cuando lo pedido existe en
  /// el catálogo pero no había.
  Future<PedidoEspecial> crear({
    required String tipo,
    required String nombre,
    required double cantidad,
    String? unidad,
    required String descripcion,
    int? materialId,
    int? herramientaId,
    String? clave,
  }) => _rest.crear(
    '/api/pedidos-especiales',
    {
      'tipo': tipo,
      'nombre': nombre,
      'cantidad': cantidad,
      'unidad': unidad,
      'descripcion': descripcion,
      'materialId': materialId,
      'herramientaId': herramientaId,
    },
    PedidoEspecial.desdeJson,
    clave: clave,
  );

  Future<List<PedidoEspecial>> mios() =>
      _rest.lista('/api/pedidos-especiales/mios', PedidoEspecial.desdeJson);

  /// Sin `obraId`, los de toda la empresa: es la vista del administrador.
  Future<List<PedidoEspecial>> listar({
    int? obraId,
    bool soloAbiertos = true,
  }) => _rest.lista(
    '/api/pedidos-especiales',
    PedidoEspecial.desdeJson,
    params: {'obraId': ?obraId, 'soloAbiertos': soloAbiertos},
  );

  /// Avanza un paso. 409 TRANSICION_INVALIDA si otro de bodega ya lo movió.
  Future<PedidoEspecial> avanzar(
    int id,
    PasoPedido paso, {
    String? nota,
    String? clave,
  }) => _rest.actualizar(
    '/api/pedidos-especiales/$id/${paso.ruta}',
    {if (nota != null && nota.trim().isNotEmpty) 'nota': nota.trim()},
    PedidoEspecial.desdeJson,
    clave: clave,
  );

  Future<PedidoEspecial> rechazar(
    int id, {
    required String motivo,
    String? clave,
  }) => _rest.actualizar(
    '/api/pedidos-especiales/$id/rechazar',
    {'motivo': motivo},
    PedidoEspecial.desdeJson,
    clave: clave,
  );

  Future<PedidoEspecial> cancelar(int id, {String? clave}) => _rest.actualizar(
    '/api/pedidos-especiales/$id/cancelar',
    const {},
    PedidoEspecial.desdeJson,
    clave: clave,
  );

  Future<PedidoEspecial> confirmarRecepcion(int id, {String? clave}) =>
      _rest.actualizar(
        '/api/pedidos-especiales/$id/confirmar-recepcion',
        const {},
        PedidoEspecial.desdeJson,
        clave: clave,
      );
}

/// Varias herramientas pedidas de una vez y retiradas con un QR.
///
/// Crear es todo o nada: si una de las herramientas ya no está disponible, el
/// backend responde 409 y no queda ninguna pedida. Así el trabajador no llega
/// al mesón con un QR que cubre la mitad de lo que necesitaba.
class PedidosHerramientaApi {
  const PedidosHerramientaApi(this._rest);

  final ClienteRest _rest;

  // --- Del trabajador ---------------------------------------------------------

  Future<PedidoHerramienta> crear({
    required List<int> herramientaIds,
    required String descripcion,
    String? clave,
  }) => _rest.crear(
    '/api/pedidos-herramienta',
    {'herramientaIds': herramientaIds, 'descripcion': descripcion},
    PedidoHerramienta.desdeJson,
    clave: clave,
  );

  /// Los suyos, primero los que esperan retiro.
  Future<List<PedidoHerramienta>> mios() =>
      _rest.lista('/api/pedidos-herramienta/mios', PedidoHerramienta.desdeJson);

  Future<PedidoHerramienta> cancelar(int id, {String? clave}) =>
      _rest.actualizar(
        '/api/pedidos-herramienta/$id/cancelar',
        const {},
        PedidoHerramienta.desdeJson,
        clave: clave,
      );

  // --- De bodega ---------------------------------------------------------------
  //
  // Reciben el UUID sin el prefijo `PEDIDO:` del QR. Un código desconocido o
  // de otra empresa da 404, igual que la credencial.

  Future<PedidoHerramienta> porQr(String codigoQr) => _rest.uno(
    '/api/pedidos-herramienta/qr/${Uri.encodeComponent(codigoQr)}',
    PedidoHerramienta.desdeJson,
  );

  /// Entrega todas las herramientas del pedido con la misma devolución
  /// esperada. 409 YA_RESUELTA si ya se había entregado.
  Future<EntregaPedido> entregar(
    String codigoQr, {
    required DateTime fechaDevolEsperada,
    String? clave,
  }) => _rest.actualizar(
    '/api/pedidos-herramienta/qr/${Uri.encodeComponent(codigoQr)}/entregar',
    {'fechaDevolEsperada': fechaDevolEsperada.toIso8601String()},
    EntregaPedido.desdeJson,
    clave: clave,
  );
}

/// Alta masiva de catálogo desde una planilla Excel.
///
/// Se llama dos veces con el mismo archivo: primero sin confirmar —para ver el
/// informe— y después confirmando. No es una llamada de más: es lo que evita
/// cargar un catálogo a ciegas y descubrir el error cuando ya está adentro.
class ImportacionApi {
  const ImportacionApi(this._rest);

  final ClienteRest _rest;

  Future<ResultadoImportacion> materiales({
    required Uint8List contenido,
    required String nombreArchivo,
    bool confirmar = false,
    String? clave,
  }) => _rest.subir(
    '/api/materiales/importar',
    ResultadoImportacion.desdeJson,
    contenido: contenido,
    nombreArchivo: nombreArchivo,
    params: {'confirmar': confirmar},
    clave: clave,
  );

  Future<ResultadoImportacion> herramientas({
    required Uint8List contenido,
    required String nombreArchivo,
    bool confirmar = false,
    String? clave,
  }) => _rest.subir(
    '/api/herramientas/importar',
    ResultadoImportacion.desdeJson,
    contenido: contenido,
    nombreArchivo: nombreArchivo,
    params: {'confirmar': confirmar},
    clave: clave,
  );

  /// La planilla vacía con las columnas en el orden que espera el servidor.
  /// Se descarga antes de llenarla: el lector va por posición, no por el
  /// nombre del encabezado.
  Future<Uint8List> plantillaDeMateriales() =>
      _rest.descargar('/api/materiales/plantilla-importacion');

  Future<Uint8List> plantillaDeHerramientas() =>
      _rest.descargar('/api/herramientas/plantilla-importacion');
}

/// Partidas de una obra y su cubicación. Crear y cubicar son de JEFE_TERRENO o
/// ADMIN; las lecturas las admite el backend para cualquier rol.
class PartidasApi {
  const PartidasApi(this._rest);

  final ClienteRest _rest;

  Future<List<Partida>> porObra(int obraId) => _rest.lista(
    '/api/partidas',
    Partida.desdeJson,
    params: {'obraId': obraId},
  );

  Future<Partida> crear({
    required int obraId,
    required String tipo,
    required double anchoM,
    required double altoM,
    required double separacionMontantes,
    String? clave,
  }) => _rest.crear(
    '/api/partidas',
    {
      'obraId': obraId,
      'tipo': tipo,
      'anchoM': anchoM,
      'altoM': altoM,
      'separacionMontantes': separacionMontantes,
    },
    Partida.desdeJson,
    clave: clave,
  );

  /// Recalcula y **reemplaza** los ítems anteriores de la partida (RN-21):
  /// cubicar dos veces no duplica la lista.
  Future<List<ItemCubicado>> cubicar(int partidaId, {String? clave}) =>
      _rest.crearLista(
        '/api/partidas/$partidaId/cubicar',
        const {},
        ItemCubicado.desdeJson,
        clave: clave,
      );

  Future<List<ItemCubicado>> itemsCubicados(int partidaId) => _rest.lista(
    '/api/partidas/$partidaId/items-cubicados',
    ItemCubicado.desdeJson,
  );
}

/// Presupuesto de una obra: uno por obra (RN-10), con ciclo
/// BORRADOR → APROBADO → CONGELADO.
class PresupuestosApi {
  const PresupuestosApi(this._rest);

  final ClienteRest _rest;

  /// `null` cuando la obra aún no tiene presupuesto: el backend lo responde con
  /// 404, y acá eso es un estado normal —el jefe todavía no lo crea— y no un
  /// error.
  Future<Presupuesto?> porObra(int obraId) async {
    try {
      return await _rest.uno(
        '/api/presupuestos',
        Presupuesto.desdeJson,
        params: {'obraId': obraId},
      );
    } on ApiException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  /// Responde 409 si la obra ya tiene uno.
  Future<Presupuesto> crear(int obraId, {String? clave}) => _rest.crear(
    '/api/presupuestos',
    {'obraId': obraId},
    Presupuesto.desdeJson,
    clave: clave,
  );

  Future<List<PresupuestoItem>> items(int presupuestoId) => _rest.lista(
    '/api/presupuestos/$presupuestoId/items',
    PresupuestoItem.desdeJson,
  );

  /// El precio lo pone el backend, del catálogo vigente (RN-13). Responde 409
  /// si el presupuesto está congelado (RN-12).
  Future<PresupuestoItem> agregarItem(
    int presupuestoId, {
    required int materialId,
    required double cantidad,
    String? clave,
  }) => _rest.crear(
    '/api/presupuestos/$presupuestoId/items',
    {'materialId': materialId, 'cantidad': cantidad},
    PresupuestoItem.desdeJson,
    clave: clave,
  );

  /// Agrega de una vez los ítems cubicados de una partida, con su cantidad con
  /// merma y el precio vigente (RN-13). Es atómico: entran todos o ninguno.
  ///
  /// Responde 409 si el presupuesto está congelado, si la partida es de otra
  /// obra o si todavía no se cubicó. **No deduplica**: llamarlo dos veces con
  /// la misma partida duplica las filas, así que la pantalla debe impedir el
  /// segundo envío y reintentar con la misma `clave`.
  Future<List<PresupuestoItem>> agregarDesdePartida(
    int presupuestoId, {
    required int partidaId,
    String? clave,
  }) => _rest.crearLista(
    '/api/presupuestos/$presupuestoId/items/desde-partida',
    {'partidaId': partidaId},
    PresupuestoItem.desdeJson,
    clave: clave,
  );

  /// Solo un BORRADOR pasa a APROBADO (RN-11); otro estado responde 409.
  Future<Presupuesto> aprobar(int presupuestoId, {String? clave}) =>
      _rest.actualizar(
        '/api/presupuestos/$presupuestoId/aprobar',
        const {},
        Presupuesto.desdeJson,
        clave: clave,
      );

  /// Solo un APROBADO pasa a CONGELADO, y no vuelve atrás (RN-11).
  Future<Presupuesto> congelar(int presupuestoId, {String? clave}) =>
      _rest.actualizar(
        '/api/presupuestos/$presupuestoId/congelar',
        const {},
        Presupuesto.desdeJson,
        clave: clave,
      );
}

class EmpresaApi {
  const EmpresaApi(this._rest);

  final ClienteRest _rest;

  Future<Empresa> mia() => _rest.uno('/api/empresas/mia', Empresa.desdeJson);
}

// --- Providers ---------------------------------------------------------------

/// Depende de **quién** entró, no solo del cliente HTTP. Todos los datos de la
/// app cuelgan de acá —catálogo, obras, usuarios, préstamos—, así que cuando
/// cambia la persona se reconstruye la cadena entera. Sin esto, quien entra
/// después en el mismo teléfono veía en caché el catálogo y el padrón del
/// anterior, aunque fuera de otra empresa, hasta tirar para refrescar.
final clienteRestProvider = Provider<ClienteRest>((ref) {
  ref.watch(
    sesionProvider.select(
      (s) => (s.valueOrNull?.usuarioId, s.valueOrNull?.empresaId),
    ),
  );
  return ClienteRest(ref.watch(apiClientProvider));
});

final obrasApiProvider = Provider(
  (ref) => ObrasApi(ref.watch(clienteRestProvider)),
);
final materialesApiProvider = Provider(
  (ref) => MaterialesApi(ref.watch(clienteRestProvider)),
);
final kardexApiProvider = Provider(
  (ref) => KardexApi(ref.watch(clienteRestProvider)),
);
final herramientasApiProvider = Provider(
  (ref) => HerramientasApi(ref.watch(clienteRestProvider)),
);
final prestamosApiProvider = Provider(
  (ref) => PrestamosApi(ref.watch(clienteRestProvider)),
);
final alertasApiProvider = Provider(
  (ref) => AlertasApi(ref.watch(clienteRestProvider)),
);
final usuariosApiProvider = Provider(
  (ref) => UsuariosApi(ref.watch(clienteRestProvider)),
);
final trabajadoresApiProvider = Provider(
  (ref) => TrabajadoresApi(ref.watch(clienteRestProvider)),
);
final partidasApiProvider = Provider(
  (ref) => PartidasApi(ref.watch(clienteRestProvider)),
);
final presupuestosApiProvider = Provider(
  (ref) => PresupuestosApi(ref.watch(clienteRestProvider)),
);
final empresaApiProvider = Provider(
  (ref) => EmpresaApi(ref.watch(clienteRestProvider)),
);
final solicitudesApiProvider = Provider(
  (ref) => SolicitudesApi(ref.watch(clienteRestProvider)),
);
final pedidosEspecialesApiProvider = Provider(
  (ref) => PedidosEspecialesApi(ref.watch(clienteRestProvider)),
);
final pedidosHerramientaApiProvider = Provider(
  (ref) => PedidosHerramientaApi(ref.watch(clienteRestProvider)),
);
final importacionApiProvider = Provider(
  (ref) => ImportacionApi(ref.watch(clienteRestProvider)),
);
