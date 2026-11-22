package cl.duocuc.checkinobra.config;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.core.env.Environment;
import org.springframework.core.NestedExceptionUtils;
import org.springframework.dao.DataAccessException;
import org.springframework.jdbc.core.JdbcTemplate;

import java.nio.file.Files;
import java.nio.file.Path;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.SQLException;
import java.sql.Statement;
import java.util.List;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.catchThrowable;

/**
 * SEG6 (#94, S-07 y S-31) y MT0 (#103): la API conecta con un usuario sin
 * superusuario y sin permisos de DDL; Flyway usa otro, que es dueño del esquema.
 *
 * <p>Corre contra el Postgres real de la suite, que tiene que haberse creado con
 * {@code db/crear-roles.sh} (compose lo hace solo; la CI, en un paso previo).
 * Si falla por "checkinobra_app", falta ese paso: ver el README.
 */
@SpringBootTest
class RolesDeBaseDeDatosTest {

    private static final String APP = "checkinobra_app";
    private static final String MIGRADOR = "checkinobra_migrador";

    @Autowired private JdbcTemplate jdbc;
    @Autowired private Environment entorno;

    @Value("${spring.datasource.url}") private String url;
    @Value("${spring.datasource.username}") private String usuarioApp;
    @Value("${spring.datasource.password}") private String claveApp;
    @Value("${spring.flyway.user}") private String usuarioMigrador;
    @Value("${spring.flyway.password}") private String claveMigrador;

    @Test
    void laApiConectaComoCheckinobraAppYNoEsSuperusuario() {
        String actual = jdbc.queryForObject("SELECT current_user", String.class);
        Boolean esSuper = jdbc.queryForObject(
                "SELECT rolsuper FROM pg_roles WHERE rolname = ?", Boolean.class, APP);

        assertThat(actual).isEqualTo(APP);
        assertThat(esSuper).isFalse();
    }

    @Test
    void elMigradorTampocoEsSuperusuario() {
        Boolean esSuper = jdbc.queryForObject(
                "SELECT rolsuper FROM pg_roles WHERE rolname = ?", Boolean.class, MIGRADOR);

        assertThat(esSuper).isFalse();
    }

    @Test
    void laApiNoPuedeCrearAlterarNiBorrarTablas() {
        for (String ddl : List.of(
                "CREATE TABLE tabla_que_no_debe_existir (id int)",
                "ALTER TABLE usuarios ADD COLUMN columna_que_no_debe_existir int",
                "DROP TABLE presupuestos",
                "TRUNCATE TABLE flyway_schema_history")) {
            Throwable error = catchThrowable(() -> jdbc.execute(ddl));

            assertThat(error).as(ddl).isInstanceOf(DataAccessException.class);
            // Spring envuelve el error de Postgres; el motivo está en la causa.
            assertThat(NestedExceptionUtils.getMostSpecificCause(error).getMessage())
                    .as(ddl)
                    .satisfiesAnyOf(
                            m -> assertThat(m).contains("permission denied"),
                            m -> assertThat(m).contains("must be owner"));
        }
    }

    @Test
    void laApiSiPuedeLeerYEscribirDatos() {
        Integer filas = jdbc.queryForObject("SELECT count(*) FROM empresas", Integer.class);

        assertThat(filas).isNotNull();
        assertThat(jdbc.update("DELETE FROM empresas WHERE id = -1")).isZero();
    }

    @Test
    void flywayUsaAlMigradorYEsElDuenioDeTodasLasTablas() {
        // El dueño, no installed_by: en una base anterior a esto el historial de
        // Flyway conserva al usuario que migró antes, pero roles.sql le pasó las
        // tablas al migrador y es quien puede alterarlas de ahora en adelante.
        List<String> duenios = jdbc.queryForList(
                "SELECT DISTINCT tableowner FROM pg_tables WHERE schemaname = 'public'", String.class);

        assertThat(usuarioMigrador).isEqualTo(MIGRADOR);
        assertThat(duenios).containsExactly(MIGRADOR);
    }

    @Test
    void laApiYElMigradorNoComparteContrasena() {
        assertThat(usuarioApp).isEqualTo(APP);
        assertThat(claveApp).isNotBlank().isNotEqualTo(claveMigrador);
    }

    @Test
    void lasTablasQueCreeElMigradorQuedanAccesiblesParaLaApi() throws SQLException {
        String tabla = "prueba_privilegios_" + UUID.randomUUID().toString().replace("-", "");
        try (Connection migrador = DriverManager.getConnection(url, usuarioMigrador, claveMigrador);
             Statement ddl = migrador.createStatement()) {
            try {
                ddl.execute("CREATE TABLE " + tabla + " (id serial PRIMARY KEY, dato int)");

                // Sin ningún GRANT: lo da ALTER DEFAULT PRIVILEGES de roles.sql.
                jdbc.update("INSERT INTO " + tabla + " (dato) VALUES (1)");
                assertThat(jdbc.queryForObject("SELECT count(*) FROM " + tabla, Integer.class)).isEqualTo(1);
                assertThat(jdbc.update("DELETE FROM " + tabla)).isEqualTo(1);
            } finally {
                ddl.execute("DROP TABLE IF EXISTS " + tabla);
            }
        }
    }

    @Test
    void laConfiguracionNoTraeContrasenasNiUsuarioPorDefecto() throws Exception {
        String propiedades = Files.readString(Path.of("src/main/resources/application.properties"));

        assertThat(propiedades)
                .doesNotContainPattern("SPRING_DATASOURCE_PASSWORD:[^}]")
                .doesNotContainPattern("SPRING_DATASOURCE_USERNAME:[^}]")
                .doesNotContain("postgres}");
    }

    @Test
    void openInViewEstaDesactivado() {
        // Con open-in-view la conexión queda tomada durante toda la petición HTTP,
        // incluida la serialización de la respuesta (S-31).
        assertThat(entorno.getProperty("spring.jpa.open-in-view", Boolean.class)).isFalse();
    }

    @Test
    void composeNoPublicaPostgresEnTodasLasInterfaces() throws Exception {
        List<String> lineas = Files.readAllLines(Path.of("..", "docker-compose.yml"));

        List<String> publicaciones = lineas.stream()
                .map(String::strip)
                .filter(l -> l.startsWith("- \"") && l.contains(":5432"))
                .toList();

        assertThat(publicaciones).isNotEmpty();
        assertThat(publicaciones).allSatisfy(p -> assertThat(p).startsWith("- \"127.0.0.1:"));
    }

    @Test
    void composeNoTraeContrasenasDeBaseDeDatosEnClaro() throws Exception {
        String compose = Files.readString(Path.of("..", "docker-compose.yml"));

        assertThat(compose)
                .doesNotContain("PASSWORD: postgres")
                .doesNotContain("USERNAME: postgres");
    }
}
