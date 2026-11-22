package cl.duocuc.checkinobra.config;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

import java.util.List;
import java.util.UUID;

/**
 * Tabla {@code claves_idempotencia}: quién ya mandó qué clave y qué se le
 * respondió.
 *
 * <p>SQL directo y no una entidad JPA, por dos razones. La reserva depende de
 * {@code INSERT ... ON CONFLICT DO NOTHING}, que es atómico en la base y no
 * tiene equivalente en JPA. Y cada sentencia se confirma sola, fuera de la
 * transacción del negocio: la reserva tiene que verse desde la otra petición
 * <b>antes</b> de que la primera termine, que es justo cuando llega el doble tap.
 */
@Component
public class RegistroIdempotencia {

    /**
     * Una reserva sin respuesta más vieja que esto se da por abandonada: el
     * servidor se cayó a mitad de camino. Ninguna operación legítima tarda tanto.
     */
    static final String ABANDONO = "2 minutes";

    /**
     * Cuánto se recuerda una clave. La app reintenta en segundos y hoy no tiene
     * cola offline; una semana deja margen de sobra.
     */
    static final String RETENCION = "7 days";

    public sealed interface Reserva {
    }

    /** La clave es nueva: esta petición se ejecuta. */
    public record Reservada() implements Reserva {
    }

    /** La primera petición todavía no termina. */
    public record EnCurso() implements Reserva {
    }

    /** La clave ya se usó con otra ruta u otro cuerpo. */
    public record ClaveReutilizada() implements Reserva {
    }

    /** La primera ya terminó: se devuelve lo mismo que se respondió entonces. */
    public record Repetida(int status, String contentType, byte[] cuerpo) implements Reserva {
    }

    private record Fila(String huella, Integer status, String contentType, byte[] cuerpo) {
    }

    private final JdbcTemplate jdbc;
    private final ResolutorDeBases resolutor;

    public RegistroIdempotencia(JdbcTemplate jdbc, ResolutorDeBases resolutor) {
        this.jdbc = jdbc;
        this.resolutor = resolutor;
    }

    public Reserva reservar(Long usuarioId, UUID clave, String huella, String metodo, String ruta) {
        int insertadas = jdbc.update("""
                INSERT INTO claves_idempotencia (usuario_id, clave, huella, metodo, ruta)
                VALUES (?, ?, ?, ?, ?)
                ON CONFLICT (usuario_id, clave) DO NOTHING
                """, usuarioId, clave, huella, metodo, recortar(ruta, 500));
        if (insertadas == 1) {
            return new Reservada();
        }

        List<Fila> filas = jdbc.query("""
                SELECT huella, status, content_type, cuerpo
                FROM claves_idempotencia
                WHERE usuario_id = ? AND clave = ?
                """,
                (rs, i) -> new Fila(
                        rs.getString("huella"),
                        (Integer) rs.getObject("status"),
                        rs.getString("content_type"),
                        rs.getBytes("cuerpo")),
                usuarioId, clave);
        if (filas.isEmpty()) {
            // Se liberó entre el INSERT y el SELECT: la primera falló sin
            // respuesta que guardar. Se vuelve a intentar desde cero.
            return reservar(usuarioId, clave, huella, metodo, ruta);
        }

        Fila fila = filas.getFirst();
        if (!fila.huella().equals(huella)) {
            return new ClaveReutilizada();
        }
        if (fila.status() != null) {
            return new Repetida(fila.status(), fila.contentType(), fila.cuerpo());
        }
        return retomarAbandonada(usuarioId, clave) ? new Reservada() : new EnCurso();
    }

    /** Atómico: si dos reintentos llegan juntos a retomar, solo uno lo logra. */
    private boolean retomarAbandonada(Long usuarioId, UUID clave) {
        return jdbc.update("""
                UPDATE claves_idempotencia SET creada_en = now()
                WHERE usuario_id = ? AND clave = ? AND status IS NULL
                  AND creada_en < now() - CAST(? AS INTERVAL)
                """, usuarioId, clave, ABANDONO) == 1;
    }

    public void guardar(Long usuarioId, UUID clave, int status, String contentType, byte[] cuerpo) {
        jdbc.update("""
                UPDATE claves_idempotencia SET status = ?, content_type = ?, cuerpo = ?
                WHERE usuario_id = ? AND clave = ?
                """, status, recortar(contentType, 200), cuerpo, usuarioId, clave);
    }

    /**
     * Suelta una reserva cuya respuesta no se guarda (un 5xx, un conflicto de
     * bloqueo): el reintento con la misma clave vuelve a ejecutar.
     */
    public void liberar(Long usuarioId, UUID clave) {
        jdbc.update("DELETE FROM claves_idempotencia WHERE usuario_id = ? AND clave = ? AND status IS NULL",
                usuarioId, clave);
    }

    @Scheduled(cron = "0 17 * * * *")
    public void purgarVencidas() {
        // Es la única tarea que corre fuera de una petición: no hay empresa en el
        // contexto, así que recorre las de todas las bases y fija la de cada una. Si una
        // falla se anota y sigue con las demás.
        for (Long empresaId : resolutor.empresas()) {
            try {
                TenantContext.ejecutarEn(empresaId, () -> jdbc.update(
                        "DELETE FROM claves_idempotencia WHERE creada_en < now() - CAST(? AS INTERVAL)", RETENCION));
            } catch (RuntimeException e) {
                org.slf4j.LoggerFactory.getLogger(RegistroIdempotencia.class)
                        .error("No se pudo purgar las claves de la empresa {}: {}", empresaId, e.getMessage());
            }
        }
    }

    private static String recortar(String texto, int largo) {
        return texto == null || texto.length() <= largo ? texto : texto.substring(0, largo);
    }
}
