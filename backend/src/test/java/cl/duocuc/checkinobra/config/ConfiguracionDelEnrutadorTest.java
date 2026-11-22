package cl.duocuc.checkinobra.config;

import org.junit.jupiter.api.Test;

import java.nio.file.Files;
import java.nio.file.Path;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * MT2 (#105): Hibernate arranca sin conexión por defecto. Si alguien quita una de estas
 * propiedades, el arranque intentaría abrir una conexión sin empresa y fallaría en
 * producción, donde ya no hay una base compartida. La suite de pruebas, que sí tiene una,
 * no lo notaría.
 */
class ConfiguracionDelEnrutadorTest {

    private static String propiedades() throws Exception {
        return Files.readString(Path.of("src/main/resources/application.properties"));
    }

    @Test
    void hibernateNoAbreUnaConexionAlArrancar() throws Exception {
        assertThat(propiedades())
                .contains("spring.jpa.properties.hibernate.boot.allow_jdbc_metadata_access=false")
                .contains("spring.jpa.database-platform=org.hibernate.dialect.PostgreSQLDialect")
                .contains("spring.jpa.database=postgresql")
                .contains("spring.jpa.hibernate.ddl-auto=none");
    }

    @Test
    void flywayLoCorreElMigradorPorBaseYNoElAutoconfiguradoDeSpring() throws Exception {
        // El de Spring Boot migra una sola base y necesita una conexión sin empresa.
        assertThat(propiedades()).contains("spring.flyway.enabled=false");
    }
}
