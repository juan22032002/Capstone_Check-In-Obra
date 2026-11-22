package cl.duocuc.checkinobra.config;

import org.junit.jupiter.api.Test;

import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.ZoneId;
import java.time.ZoneOffset;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

class LimitadorDeIntentosTest {

    /** Reloj que solo avanza cuando la prueba lo dice. */
    private static final class RelojManual extends Clock {
        private Instant ahora = Instant.parse("2026-11-19T12:00:00Z");

        void avanzar(Duration d) {
            ahora = ahora.plus(d);
        }

        @Override public ZoneId getZone() {
            return ZoneOffset.UTC;
        }

        @Override public Clock withZone(ZoneId zone) {
            return this;
        }

        @Override public Instant instant() {
            return ahora;
        }
    }

    private final RelojManual reloj = new RelojManual();
    private final LimitadorDeIntentos limitador = new LimitadorDeIntentos(
            5, Duration.ofMinutes(1), Duration.ofMinutes(10), Duration.ofHours(24), reloj);

    private void fallar(String clave, int veces) {
        for (int i = 0; i < veces; i++) {
            limitador.registrarFallo(clave);
        }
    }

    @Test
    void cuatroFallosNoBloquean() {
        fallar("u:1", 4);

        assertThat(limitador.bloqueoRestante("u:1")).isEmpty();
    }

    @Test
    void elQuintoFalloBloqueaPorElTiempoBase() {
        fallar("u:1", 5);

        assertThat(limitador.bloqueoRestante("u:1")).contains(Duration.ofMinutes(1));
    }

    @Test
    void elBloqueoSeVaCumpliendoConElReloj() {
        fallar("u:1", 5);
        reloj.avanzar(Duration.ofSeconds(45));

        assertThat(limitador.bloqueoRestante("u:1")).contains(Duration.ofSeconds(15));

        reloj.avanzar(Duration.ofSeconds(15));
        assertThat(limitador.bloqueoRestante("u:1")).isEmpty();
    }

    @Test
    void trasUnBloqueoUnSoloFalloBloqueaDeNuevoYPorElDoble() {
        fallar("u:1", 5);
        reloj.avanzar(Duration.ofMinutes(1));

        fallar("u:1", 1);

        assertThat(limitador.bloqueoRestante("u:1")).contains(Duration.ofMinutes(2));
    }

    @Test
    void elBloqueoCrecePeroTieneTope() {
        fallar("u:1", 5);
        for (int i = 0; i < 8; i++) {
            reloj.avanzar(Duration.ofHours(1));
            fallar("u:1", 1);
        }

        assertThat(limitador.bloqueoRestante("u:1")).contains(Duration.ofMinutes(10));
    }

    @Test
    void unAciertoBorraElHistorial() {
        fallar("u:1", 4);
        limitador.registrarExito("u:1");
        fallar("u:1", 4);

        assertThat(limitador.bloqueoRestante("u:1")).isEmpty();
    }

    @Test
    void sinFallosDuranteElOlvidoVuelveAEmpezarDeCero() {
        fallar("u:1", 5);
        reloj.avanzar(Duration.ofHours(25));

        fallar("u:1", 4);

        assertThat(limitador.bloqueoRestante("u:1")).isEmpty();
    }

    @Test
    void estandoBloqueadaUnFalloNoExtiendeElBloqueo() {
        fallar("u:1", 5);
        reloj.avanzar(Duration.ofSeconds(30));

        fallar("u:1", 10);

        assertThat(limitador.bloqueoRestante("u:1")).contains(Duration.ofSeconds(30));
    }

    @Test
    void lasClavesSonIndependientes() {
        fallar("u:1", 5);

        assertThat(limitador.bloqueoRestante("u:2")).isEmpty();
        assertThat(limitador.bloqueoRestante("ip:1.2.3.4")).isEmpty();
    }

    @Test
    void lasClavesNuevasNoCrecenSinLimiteBajoUnRociado() {
        for (int i = 0; i < LimitadorDeIntentos.MAX_CLAVES + 500; i++) {
            limitador.registrarFallo("e:correo" + i + "@x.cl");
        }

        assertThat(limitador.tamano()).isEqualTo(LimitadorDeIntentos.MAX_CLAVES);
    }

    @Test
    void alLlenarseSeLimpianLasClavesOlvidadas() {
        for (int i = 0; i < LimitadorDeIntentos.MAX_CLAVES; i++) {
            limitador.registrarFallo("e:viejo" + i);
        }
        reloj.avanzar(Duration.ofHours(25));

        limitador.registrarFallo("e:nuevo");
        fallar("e:nuevo", 4);

        assertThat(limitador.bloqueoRestante("e:nuevo")).contains(Duration.ofMinutes(1));
        assertThat(limitador.tamano()).isEqualTo(1);
    }

    @Test
    void unUmbralMenorQueUnoNoTieneSentido() {
        assertThatThrownBy(() -> new LimitadorDeIntentos(
                0, Duration.ofMinutes(1), Duration.ofMinutes(10), Duration.ofHours(1), reloj))
                .isInstanceOf(IllegalArgumentException.class);
    }
}
