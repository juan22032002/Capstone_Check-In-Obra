package cl.duocuc.checkinobra.config;

import java.time.Duration;

/** Demasiados intentos de login fallidos: la cuenta o la IP está bloqueada (429). */
public class DemasiadosIntentosException extends RuntimeException {

    /** Para el {@code codigo} del cuerpo de error: la app decide sin leer el mensaje. */
    public static final String CODIGO = "DEMASIADOS_INTENTOS";

    private final Duration espera;

    public DemasiadosIntentosException(Duration espera) {
        super("Demasiados intentos fallidos. Vuelve a intentarlo en " + minutosRedondeados(espera) + " min.");
        this.espera = espera;
    }

    public Duration espera() {
        return espera;
    }

    /** Segundos para la cabecera Retry-After, nunca menos de 1. */
    public long segundos() {
        return Math.max(1, (espera.toMillis() + 999) / 1000);
    }

    private static long minutosRedondeados(Duration d) {
        return Math.max(1, (d.toSeconds() + 59) / 60);
    }
}
