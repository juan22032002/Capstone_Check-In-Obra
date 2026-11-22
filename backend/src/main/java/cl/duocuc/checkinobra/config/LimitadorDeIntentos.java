package cl.duocuc.checkinobra.config;

import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.util.Optional;
import java.util.concurrent.ConcurrentHashMap;

/**
 * Cuenta intentos fallidos por clave (una cuenta, una IP) y bloquea por un
 * tiempo que crece con cada bloqueo seguido (S-02).
 *
 * <p>La primera ronda tolera {@code maxFallos} intentos. Una vez que la clave
 * ya fue bloqueada, un solo fallo más la bloquea de nuevo y por el doble: si
 * después de cada bloqueo volvieran a regalarse {@code maxFallos} intentos,
 * un PIN de 4 dígitos seguiría cayendo por fuerza bruta, solo que más lento.
 * Un acierto borra el historial; también lo borra el paso de {@code olvido}
 * sin fallos.
 *
 * <p>El estado vive en memoria: se reinicia con la API y no se comparte entre
 * instancias. Hoy hay una sola instancia; con varias haría falta una tabla o
 * Redis. Está acotado ({@link #MAX_CLAVES}) para que rociar la API con correos
 * inventados no llene la memoria.
 */
public class LimitadorDeIntentos {

    static final int MAX_CLAVES = 10_000;

    /** Tope del exponente, para que {@code base * 2^n} no desborde antes del tope de duración. */
    private static final int MAX_EXPONENTE = 20;

    private record Estado(int fallosEnLaRonda, int bloqueos, Instant bloqueadoHasta, Instant ultimoFallo) {
    }

    private final int maxFallos;
    private final Duration bloqueoBase;
    private final Duration bloqueoMaximo;
    private final Duration olvido;
    private final Clock reloj;
    private final ConcurrentHashMap<String, Estado> estados = new ConcurrentHashMap<>();

    public LimitadorDeIntentos(
            int maxFallos, Duration bloqueoBase, Duration bloqueoMaximo, Duration olvido, Clock reloj) {
        if (maxFallos < 1) {
            throw new IllegalArgumentException("maxFallos debe ser al menos 1");
        }
        this.maxFallos = maxFallos;
        this.bloqueoBase = bloqueoBase;
        this.bloqueoMaximo = bloqueoMaximo;
        this.olvido = olvido;
        this.reloj = reloj;
    }

    /** Cuánto falta para que la clave pueda volver a intentar; vacío si no está bloqueada. */
    public Optional<Duration> bloqueoRestante(String clave) {
        Estado estado = estados.get(clave);
        Instant ahora = reloj.instant();
        if (estado == null || estado.bloqueadoHasta() == null || !estado.bloqueadoHasta().isAfter(ahora)) {
            return Optional.empty();
        }
        return Optional.of(Duration.between(ahora, estado.bloqueadoHasta()));
    }

    /** Anota un fallo; si con él se pasa el umbral, bloquea. No hace nada si ya está bloqueada. */
    public void registrarFallo(String clave) {
        Instant ahora = reloj.instant();
        if (!estados.containsKey(clave) && !hayLugarPara(ahora)) {
            return;
        }
        estados.compute(clave, (k, previo) -> siguienteEstado(previo, ahora));
    }

    /** Un acierto borra el historial de la clave. */
    public void registrarExito(String clave) {
        estados.remove(clave);
    }

    int tamano() {
        return estados.size();
    }

    private Estado siguienteEstado(Estado previo, Instant ahora) {
        if (previo != null && previo.bloqueadoHasta() != null && previo.bloqueadoHasta().isAfter(ahora)) {
            return previo;
        }
        Estado base = previo == null || estaOlvidado(previo, ahora) ? new Estado(0, 0, null, null) : previo;
        int fallos = base.fallosEnLaRonda() + 1;
        int umbral = base.bloqueos() == 0 ? maxFallos : 1;
        if (fallos < umbral) {
            return new Estado(fallos, base.bloqueos(), base.bloqueadoHasta(), ahora);
        }
        return new Estado(0, base.bloqueos() + 1, ahora.plus(duracionDelBloqueo(base.bloqueos())), ahora);
    }

    private Duration duracionDelBloqueo(int bloqueosPrevios) {
        Duration crecida = bloqueoBase.multipliedBy(1L << Math.min(bloqueosPrevios, MAX_EXPONENTE));
        return crecida.compareTo(bloqueoMaximo) > 0 ? bloqueoMaximo : crecida;
    }

    private boolean estaOlvidado(Estado estado, Instant ahora) {
        return estado.ultimoFallo() != null && estado.ultimoFallo().plus(olvido).isBefore(ahora);
    }

    private boolean hayLugarPara(Instant ahora) {
        if (estados.size() < MAX_CLAVES) {
            return true;
        }
        estados.entrySet().removeIf(e -> {
            Estado s = e.getValue();
            boolean bloqueada = s.bloqueadoHasta() != null && s.bloqueadoHasta().isAfter(ahora);
            return !bloqueada && estaOlvidado(s, ahora);
        });
        return estados.size() < MAX_CLAVES;
    }
}
