package cl.duocuc.checkinobra.config;

import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.server.LocalServerPort;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * SEG11 (#99, S-12): con el perfil {@code prod}, Swagger y {@code /v3/api-docs} no se sirven, y
 * lo que no es público sigue exigiendo token.
 */
@SpringBootTest(
        webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT,
        properties = "spring.profiles.active=prod")
class DocumentacionEnProduccionTest {

    @LocalServerPort private int puerto;

    private final HttpClient http = HttpClient.newHttpClient();

    private HttpResponse<String> get(String ruta) throws Exception {
        return http.send(HttpRequest.newBuilder(URI.create("http://localhost:" + puerto + ruta)).GET().build(),
                HttpResponse.BodyHandlers.ofString());
    }

    @Test
    void ni_la_descripcion_de_la_api_ni_swagger_se_sirven() throws Exception {
        for (String ruta : new String[] {"/v3/api-docs", "/v3/api-docs/swagger-config", "/swagger-ui.html", "/swagger-ui/index.html"}) {
            HttpResponse<String> r = get(ruta);

            // 401 (ya no es pública) o 404 (springdoc apagado): nunca el documento ni la interfaz.
            assertThat(r.statusCode()).as(ruta).isIn(401, 403, 404);
            assertThat(r.body()).as(ruta).doesNotContain("\"openapi\"").doesNotContain("swagger-ui-bundle");
        }
    }

    @Test
    void healthSigueDisponibleParaElHealthcheck() throws Exception {
        assertThat(get("/actuator/health/liveness").statusCode()).isEqualTo(200);
    }

    @Test
    void loQueNoEsPublicoSigueExigiendoToken() throws Exception {
        assertThat(get("/api/obras").statusCode()).isEqualTo(401);
    }
}
