/// Una obra con un poco de todo: un material bien, uno por agotarse y uno
/// bajo el mínimo; dos taladros y un esmeril vencido.
library;

Map<String, dynamic> herramientaDePrueba(
  int id,
  String nombre, {
  bool vencida = false,
}) => {
  'prestamoId': id * 10,
  'herramientaId': id,
  'codigoQr': 'HER-$id',
  'nombre': nombre,
  'categoria': 'ELECTRICA',
  'estado': 'PRESTADA',
  'valorReposicion': 100000,
  'prestadaA': {
    'trabajadorId': 7,
    'nombre': 'Marcelo Sepúlveda',
    'rut': '17.930.556-9',
  },
  'fechaDevolEsperada': '2026-09-30T18:00:00',
  'vencida': vencida,
};

Map<String, dynamic> detalleDePrueba() => {
  'obra': {
    'id': 3,
    'nombre': 'Los Almendros',
    'cliente': 'Inmobiliaria Aconcagua',
    'ubicacion': 'Ñuñoa',
    'estado': 'ACTIVA',
    'jefeTerrenoNombre': 'Ana Rojas',
    'jefeTerrenoRut': '12.345.678-5',
  },
  'jefes': [
    {
      'usuarioId': 2,
      'nombre': 'Ana Rojas',
      'rut': '12.345.678-5',
      'rol': 'JEFE_TERRENO',
    },
  ],
  'cuadrillas': [
    {'id': 1, 'nombre': 'Tabiques', 'cantidadTrabajadores': 2},
  ],
  'trabajadores': [
    {
      'id': 7,
      'nombre': 'Marcelo Sepúlveda',
      'rut': '17.930.556-9',
      'cuadrillaId': 1,
      'cuadrillaNombre': 'Tabiques',
    },
  ],
  'materiales': [
    {
      'materialId': 1,
      'sku': 'A',
      'nombre': 'Montante',
      'categoria': 'METALCOM',
      'stock': 100,
      'stockMinimo': 40,
      'precioUnitario': 1000,
      'ultimoCostoUnitario': null,
      'costoPromedio': null,
      'valorStock': 100000,
      'estado': 'OK',
    },
    {
      'materialId': 2,
      'sku': 'B',
      'nombre': 'Volcanita',
      'categoria': 'VOLCANITA',
      'stock': 45,
      'stockMinimo': 40,
      'precioUnitario': 5980,
      'ultimoCostoUnitario': 6100,
      'costoPromedio': 6050,
      'valorStock': 274500,
      'estado': 'BAJO',
    },
    {
      'materialId': 3,
      'sku': 'C',
      'nombre': 'Tornillo',
      'categoria': 'FIJACION',
      'stock': 2,
      'stockMinimo': 10,
      'precioUnitario': 3000,
      'ultimoCostoUnitario': null,
      'costoPromedio': null,
      'valorStock': 6000,
      'estado': 'CRITICO',
    },
  ],
  'herramientas': [
    herramientaDePrueba(1, 'Taladro percutor'),
    herramientaDePrueba(2, 'Taladro percutor'),
    herramientaDePrueba(3, 'Esmeril angular', vencida: true),
  ],
  'resumen': {
    'cantidadTrabajadores': 1,
    'cantidadJefes': 1,
    'materialesCriticos': 1,
    'materialesBajos': 1,
    'valorMateriales': 380500,
    'herramientasEnObra': 3,
    'herramientasVencidas': 1,
    'valorHerramientas': 300000,
    'alertasPendientes': 0,
  },
};
