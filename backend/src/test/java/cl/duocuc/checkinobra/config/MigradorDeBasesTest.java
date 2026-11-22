package cl.duocuc.checkinobra.config;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DriverManagerDataSource;

import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * MT3 (#106): Flyway por cada base del catálogo. Una base vacía queda en la última versión,
 * el resultado de cada una queda en el catálogo, y una que falla no impide a las demás.
 *
 * <p>La "base vacía" es un esquema nuevo dentro de la base de catálogo, que el migrador
 * (su dueño) sí puede crear; el rol de la API no puede crear bases.
 */
@SpringBootTest
class MigradorDeBasesTest {

    @Autowired private MigradorDeBases migrador;
    @Autowired private CatalogoDeEmpresas catalogo;

    @Value("${spring.datasource.url}") private String urlEmpresa;
    @Value("${spring.datasource.username}") private String usuarioEmpresa;
    @Value("${spring.datasource.password}") private String claveEmpresa;
    @Value("${checkinobra.catalogo.url}") private String urlCatalogo;
    @Value("${checkinobra.catalogo.username}") private String usuarioCatalogo;
    @Value("${checkinobra.catalogo.password}") private String claveCatalogo;
    @Value("${spring.flyway.user}") private String migradorUsuario;
    @Value("${spring.flyway.password}") private String migradorClave;

    private JdbcTemplate comoMigrador;
    private JdbcTemplate enElCatalogo;
    private String esquema;
    private final List<Long> registradas = new ArrayList<>();

    @BeforeEach
    void preparar() {
        comoMigrador = new JdbcTemplate(new DriverManagerDataSource(urlCatalogo, migradorUsuario, migradorClave));
        enElCatalogo = new JdbcTemplate(new DriverManagerDataSource(urlCatalogo, usuarioCatalogo, claveCatalogo));
        esquema = "mig_" + UUID.randomUUID().toString().substring(0, 8);
    }

    @AfterEach
    void limpiar() {
        comoMigrador.execute("DROP SCHEMA IF EXISTS " + esquema + " CASCADE");
        for (Long id : registradas) {
            enElCatalogo.update("DELETE FROM empresas WHERE id = ?", id);
        }
    }

    private JdbcTemplate comoLaEmpresa() {
        return new JdbcTemplate(new DriverManagerDataSource(urlEmpresa, usuarioEmpresa, claveEmpresa));
    }

    @Test
    void unaBaseVaciaQuedaEnLaUltimaVersion() {
        comoMigrador.execute("CREATE SCHEMA " + esquema);
        // La misma versión a la que llegó la base de la empresa de esta suite.
        Integer ultimaDeLaEmpresa = comoLaEmpresa().queryForObject(
                "SELECT max(version::int) FROM flyway_schema_history WHERE success", Integer.class);
        Integer aplicadasEnLaEmpresa = comoLaEmpresa().queryForObject(
                "SELECT count(*) FROM flyway_schema_history WHERE success AND version IS NOT NULL", Integer.class);

        migrador.migrarUrl(urlCatalogo + "?currentSchema=" + esquema);

        Integer ultima = comoMigrador.queryForObject(
                "SELECT max(version::int) FROM " + esquema + ".flyway_schema_history WHERE success", Integer.class);
        Integer aplicadas = comoMigrador.queryForObject(
                "SELECT count(*) FROM " + esquema + ".flyway_schema_history WHERE success AND version IS NOT NULL",
                Integer.class);
        assertThat(ultima).isEqualTo(ultimaDeLaEmpresa);
        // La suite arranca en una base nueva sin V2; una anterior la conserva en su historial.
        assertThat(aplicadas).isBetween(aplicadasEnLaEmpresa - 1, aplicadasEnLaEmpresa);
        assertThat(comoMigrador.queryForList(
                "SELECT table_name FROM information_schema.tables WHERE table_schema = ?", String.class, esquema))
                .contains("empresas", "usuarios", "obras", "materiales", "kardex_movimientos", "claves_idempotencia");
    }

    @Test
    void migrarDosVecesEsIdempotente() {
        comoMigrador.execute("CREATE SCHEMA " + esquema);
        String url = urlCatalogo + "?currentSchema=" + esquema;

        migrador.migrarUrl(url);
        migrador.migrarUrl(url);

        Integer repetidas = comoMigrador.queryForObject(
                "SELECT count(*) - count(DISTINCT version) FROM " + esquema
                        + ".flyway_schema_history WHERE version IS NOT NULL", Integer.class);
        assertThat(repetidas).isZero();
    }

    @Test
    void unaBaseQueFallaQuedaAnotadaYNoImpideMigrarLasDemas() {
        long mala = registrar("base_que_no_existe_" + esquema);
        EmpresaConBuenaBase buena = empresaConLaBaseDeEstaSuite();

        List<MigradorDeBases.Resultado> resultados = migrador.migrarTodas();

        MigradorDeBases.Resultado deLaMala = resultado(resultados, mala);
        assertThat(deLaMala.ok()).isFalse();
        assertThat(deLaMala.error()).isNotBlank();
        assertThat(resultado(resultados, buena.id()).ok()).isTrue();

        // Queda en el catálogo: la mala con su error y sin abrirse, la buena al día.
        var enCatalogo = catalogo.listar();
        var registradaMala = enCatalogo.stream().filter(e -> e.id() == mala).findFirst().orElseThrow();
        assertThat(registradaMala.migracionEstado()).isEqualTo("ERROR");
        assertThat(registradaMala.migracionError()).isNotBlank();
        assertThat(registradaMala.abierta()).isFalse();
        var registradaBuena = enCatalogo.stream().filter(e -> e.id() == buena.id()).findFirst().orElseThrow();
        assertThat(registradaBuena.migracionEstado()).isEqualTo("OK");
        assertThat(registradaBuena.abierta()).isTrue();
    }

    @Test
    void unaEmpresaSuspendidaNoSeMigra() {
        long id = registrar("base_suspendida_" + esquema);
        enElCatalogo.update("UPDATE empresas SET estado = 'SUSPENDIDA' WHERE id = ?", id);

        List<MigradorDeBases.Resultado> resultados = migrador.migrarTodas();

        assertThat(resultados).extracting(MigradorDeBases.Resultado::empresaId).doesNotContain(id);
    }

    @Test
    void unaBaseNuevaEmpiezaPendienteYNoSeAbreHastaMigrar() {
        long id = registrar("base_nueva_" + esquema);

        var e = catalogo.listar().stream().filter(x -> x.id() == id).findFirst().orElseThrow();

        assertThat(e.migracionEstado()).isEqualTo("PENDIENTE");
        assertThat(e.abierta()).isFalse();
    }

    // ---------------------------------------------------------------------

    private record EmpresaConBuenaBase(long id) {
    }

    /** La base de esta suite, ya registrada o registrándola: es la única base real que hay. */
    private EmpresaConBuenaBase empresaConLaBaseDeEstaSuite() {
        String base = catalogo.nombreBaseActual();
        return catalogo.buscarPorBase(base)
                .map(e -> new EmpresaConBuenaBase(e.id()))
                .orElseGet(() -> new EmpresaConBuenaBase(registrarCon(base)));
    }

    private long registrar(String nombreBase) {
        return registrarCon(nombreBase);
    }

    private long registrarCon(String nombreBase) {
        long id = catalogo.registrar(null, "MB-" + UUID.randomUUID().toString().substring(0, 10), "Empresa " + esquema,
                nombreBase, usuarioEmpresa, "env:SPRING_DATASOURCE_PASSWORD");
        registradas.add(id);
        return id;
    }

    private static MigradorDeBases.Resultado resultado(List<MigradorDeBases.Resultado> todos, long id) {
        return todos.stream().filter(r -> r.empresaId() == id).findFirst().orElseThrow();
    }
}
