package cl.duocuc.checkinobra.config;

import java.util.Optional;
import java.util.function.Supplier;

/**
 * La empresa a la que pertenece lo que está haciendo este hilo (MT2, #105).
 *
 * <p>Lo llena {@link JwtAuthFilter} con la empresa del token y lo limpia en un
 * {@code finally} cuando la petición termina, y {@link TenantRoutingDataSource} lo
 * lee para abrir la base de esa empresa y ninguna otra. No hay una empresa por
 * defecto: sin una en el contexto, tocar la base falla.
 *
 * <p>Fuera de una petición (tareas programadas, arranque) la empresa se fija a mano
 * con {@link #ejecutarEn}, que además restaura la anterior al terminar.
 */
public final class TenantContext {

    private static final ThreadLocal<Long> EMPRESA = new ThreadLocal<>();

    private TenantContext() {
    }

    /** La empresa de este hilo, o vacío si no hay ninguna. */
    public static Optional<Long> actual() {
        return Optional.ofNullable(EMPRESA.get());
    }

    public static void fijar(Long empresaId) {
        EMPRESA.set(empresaId);
    }

    public static void limpiar() {
        EMPRESA.remove();
    }

    /** Corre la tarea con esa empresa y deja la que había antes. */
    public static <T> T ejecutarEn(Long empresaId, Supplier<T> tarea) {
        Long anterior = EMPRESA.get();
        EMPRESA.set(empresaId);
        try {
            return tarea.get();
        } finally {
            if (anterior == null) {
                EMPRESA.remove();
            } else {
                EMPRESA.set(anterior);
            }
        }
    }

    public static void ejecutarEn(Long empresaId, Runnable tarea) {
        ejecutarEn(empresaId, () -> {
            tarea.run();
            return null;
        });
    }
}
