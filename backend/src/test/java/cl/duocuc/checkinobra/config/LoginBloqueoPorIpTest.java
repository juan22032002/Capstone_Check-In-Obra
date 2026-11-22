package cl.duocuc.checkinobra.config;

import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.server.LocalServerPort;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * SEG2 (#90): el bloqueo por IP corta a quien recorre muchas cuentas, aunque
 * cada una reciba pocos intentos y ninguna llegue a bloquearse sola.
 */
@SpringBootTest(
        webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT,
        properties = "checkinobra.login.ip.max-fallos=8")
class LoginBloqueoPorIpTest {

    @LocalServerPort
    private int puerto;

    private final HttpClient http = HttpClient.newHttpClient();

    @Test
    void unaIpQueRecorreMuchasCuentasQuedaBloqueadaAunqueNingunaLoEste() throws Exception {
        List<Integer> estados = new ArrayList<>();
        for (int i = 0; i < 12; i++) {
            // Una cuenta distinta cada vez: ninguna acumula 5 fallos.
            estados.add(loginCorreo("rociado-" + UUID.randomUUID() + "@test.cl").statusCode());
        }

        assertThat(estados.subList(0, 8)).containsOnly(400);
        assertThat(estados.subList(8, 12)).containsOnly(429);
    }

    private HttpResponse<String> loginCorreo(String email) throws Exception {
        HttpRequest r = HttpRequest.newBuilder(URI.create("http://localhost:" + puerto + "/api/auth/login"))
                .header("Content-Type", "application/json")
                .POST(HttpRequest.BodyPublishers.ofString(
                        "{\"email\": \"%s\", \"pin\": \"0000\"}".formatted(email)))
                .build();
        return http.send(r, HttpResponse.BodyHandlers.ofString());
    }
}
