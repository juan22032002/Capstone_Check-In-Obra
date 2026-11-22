package cl.duocuc.checkinobra.config;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.NullSource;
import org.junit.jupiter.params.provider.ValueSource;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * SEG1 (#89, S-01): la API no arranca con un secreto JWT ausente, corto o
 * igual al valor de ejemplo. Con el secreto por defecto publicado en el repo,
 * cualquiera firmaba un token ADMIN de cualquier empresa.
 */
class JwtSecretoObligatorioTest {

    /** El valor que estuvo publicado en application.properties y en .env.example. */
    private static final String SECRETO_ANTIGUO = "cambiar-por-un-valor-largo-y-aleatorio";

    /** El marcador que trae .env.example: largo, pero no usable. */
    private static final String MARCADOR_DE_EJEMPLO = "CAMBIAR_generar_con_openssl_rand_base64_48";

    @ParameterizedTest
    @NullSource
    @ValueSource(strings = {"", "   "})
    void sinSecretoLaApiNoArranca(String secreto) {
        assertThatThrownBy(() -> new JwtService(secreto, 480))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("JWT_SECRET");
    }

    @Test
    void unSecretoDeMenosDe32BytesNoArranca() {
        String de31 = "a".repeat(31);

        assertThatThrownBy(() -> new JwtService(de31, 480))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("32");
    }

    @Test
    void elLargoSeMideEnBytesNoEnCaracteres() {
        // 16 caracteres de 2 bytes cada uno = 32 bytes: es válido.
        // 16 caracteres ASCII = 16 bytes: no lo es.
        assertThatCode(() -> new JwtService("ñ".repeat(16) + "", 480)).doesNotThrowAnyException();
        assertThatThrownBy(() -> new JwtService("x".repeat(16), 480))
                .isInstanceOf(IllegalStateException.class);
    }

    @ParameterizedTest
    @ValueSource(strings = {SECRETO_ANTIGUO, MARCADOR_DE_EJEMPLO, "  " + SECRETO_ANTIGUO + "  ",
            "CAMBIAR-POR-UN-VALOR-LARGO-Y-ALEATORIO"})
    void losValoresDeEjemploSeRechazanAunqueSeanLargos(String secreto) {
        assertThat(secreto.getBytes().length).isGreaterThanOrEqualTo(32);

        assertThatThrownBy(() -> new JwtService(secreto, 480))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("ejemplo");
    }

    @Test
    void unSecretoAleatorioDe32BytesOMasArranca() {
        assertThatCode(() -> new JwtService("k9Zq-4vTn_xR2mWb7LpYd0HsJf3QaGc8", 480))
                .doesNotThrowAnyException();
    }

    @Test
    void elMensajeDeErrorNoRepiteElSecretoRecibido() {
        String secreto = "corto-y-confidencial";

        assertThatThrownBy(() -> new JwtService(secreto, 480))
                .hasMessageNotContaining(secreto);
    }
}
