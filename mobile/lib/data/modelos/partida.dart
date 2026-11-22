/// Refleja `PartidaResponse` del backend.
class Partida {
  const Partida({
    required this.id,
    required this.tipo,
    required this.anchoM,
    required this.altoM,
    required this.separacionMontantes,
    required this.obraId,
  });

  final int id;

  /// `TipoPartida`: TABIQUE, CIELO o REVESTIMIENTO.
  final String tipo;
  final double anchoM;
  final double altoM;

  /// Distancia entre montantes, en metros. Es la que define cuántos lleva la
  /// partida (RN-20), así que nunca puede ser cero.
  final double separacionMontantes;
  final int obraId;

  double get superficieM2 => anchoM * altoM;

  String get nombreDelTipo => nombreDeTipoPartida(tipo);

  factory Partida.desdeJson(Map<String, dynamic> j) => Partida(
    id: j['id'] as int,
    tipo: j['tipo'] as String,
    anchoM: (j['anchoM'] as num).toDouble(),
    altoM: (j['altoM'] as num).toDouble(),
    separacionMontantes: (j['separacionMontantes'] as num).toDouble(),
    obraId: j['obraId'] as int,
  );
}

/// Los tipos que acepta el backend, en el orden en que se ofrecen.
const tiposDePartida = ['TABIQUE', 'CIELO', 'REVESTIMIENTO'];

String nombreDeTipoPartida(String tipo) => switch (tipo) {
  'TABIQUE' => 'Tabique',
  'CIELO' => 'Cielo',
  'REVESTIMIENTO' => 'Revestimiento',
  _ => tipo,
};

/// Refleja `ItemCubicadoResponse`: un material de la lista que sale de cubicar.
class ItemCubicado {
  const ItemCubicado({
    required this.id,
    required this.partidaId,
    required this.materialId,
    required this.materialSku,
    required this.materialNombre,
    required this.cantidadCalculada,
    required this.cantidadConMerma,
  });

  final int id;
  final int partidaId;
  final int materialId;
  final String materialSku;
  final String materialNombre;

  /// Lo que pide la geometría, sin holgura.
  final double cantidadCalculada;

  /// Lo que hay que comprar: la calculada más la merma del material (RN-19).
  final double cantidadConMerma;

  /// Lo que se suma por merma. Cero cuando el material no tiene parámetro.
  double get merma => cantidadConMerma - cantidadCalculada;

  factory ItemCubicado.desdeJson(Map<String, dynamic> j) => ItemCubicado(
    id: j['id'] as int,
    partidaId: j['partidaId'] as int,
    materialId: j['materialId'] as int,
    materialSku: j['materialSku'] as String,
    materialNombre: j['materialNombre'] as String,
    cantidadCalculada: (j['cantidadCalculada'] as num).toDouble(),
    cantidadConMerma: (j['cantidadConMerma'] as num).toDouble(),
  );
}
