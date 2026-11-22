package cl.duocuc.checkinobra.config;

import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.server.LocalServerPort;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.json.JsonMapper;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * SEG11 (#99, S-12 y S-13): en desarrollo, Swagger y la descripción de la API siguen públicos y
 * funcionan con springdoc 3 sobre Spring Boot 4. El único endpoint del actuator que sale es
 * {@code health}, sin detalles.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class DocumentacionEnDesarrolloTest {

    @LocalServerPort private int puerto;

    private final HttpClient http = HttpClient.newHttpClient();

    private HttpResponse<String> get(String ruta) throws Exception {
        return http.send(HttpRequest.newBuilder(URI.create("http://localhost:" + puerto + ruta)).GET().build(),
                HttpResponse.BodyHandlers.ofString());
    }

    @Test
    void laDescripcionDeLaApiSeSirveYTrae100OMasRutas() throws Exception {
        HttpResponse<String> r = get("/v3/api-docs");

        assertThat(r.statusCode()).isEqualTo(200);
        JsonNode docs = JsonMapper.builder().build().readTree(r.body());
        assertThat(docs.get("openapi").asString()).startsWith("3.");
        assertThat(docs.get("paths").size()).isGreaterThan(50);
    }

    @Test
    void laInterfazDeSwaggerCarga() throws Exception {
        HttpResponse<String> r = get("/swagger-ui/index.html");

        assertThat(r.statusCode()).isEqualTo(200);
        assertThat(r.body()).containsIgnoringCase("swagger");
    }

    @Test
    void healthEsPublicoYSinDetalles() throws Exception {
        for (String ruta : new String[] {"/actuator/health", "/actuator/health/liveness"}) {
            HttpResponse<String> r = get(ruta);

            assertThat(r.statusCode()).as(ruta).isEqualTo(200);
            assertThat(r.body()).as(ruta).contains("\"status\":\"UP\"").doesNotContain("components").doesNotContain("details");
        }
    }

    @Test
    void elRestoDelActuatorNoEstaExpuesto() throws Exception {
        for (String ruta : new String[] {"/actuator/env", "/actuator/beans", "/actuator/mappings", "/actuator/heapdump"}) {
            // No existe (404) o exige autenticación (401): nunca 200.
            assertThat(get(ruta).statusCode()).as(ruta).isNotEqualTo(200);
        }
    }
}
