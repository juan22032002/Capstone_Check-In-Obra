package cl.duocuc.checkinobra.config;

import com.zaxxer.hikari.HikariConfig;
import com.zaxxer.hikari.HikariDataSource;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.jdbc.core.JdbcTemplate;

import javax.sql.DataSource;
import java.util.Collection;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * MT2 (#105): el enrutador abre la base de la empresa del contexto y ninguna otra, y sin
 * empresa falla. Contra dos bases de Postgres distintas: la de la empresa y la de catálogo
 * hacen de "empresa 1" y "empresa 2".
 */
@SpringBootTest
class TenantRoutingDataSourceTest {

    private static final long EMPRESA_UNO = 1L;
    private static final long EMPRESA_DOS = 2L;

    @Value("${spring.datasource.url}") private String urlUno;
    @Value("${spring.datasource.username}") private String usuarioUno;
    @Value("${spring.datasource.password}") private String claveUno;
    @Value("${checkinobra.catalogo.url}") private String urlDos;
    @Value("${checkinobra.catalogo.username}") private String usuarioDos;
    @Value("${checkinobra.catalogo.password}") private String claveDos;

    private HikariDataSource baseUno;
    private HikariDataSource baseDos;
    private JdbcTemplate enrutado;

    @BeforeEach
    void armarElEnrutador() {
        baseUno = pool(urlUno, usuarioUno, claveUno);
        baseDos = pool(urlDos, usuarioDos, claveDos);
        Map<Long, DataSource> bases = Map.of(EMPRESA_UNO, baseUno, EMPRESA_DOS, baseDos);
        ResolutorDeBases resolutor = new ResolutorDeBases() {
            @Override
            public DataSource baseDe(Long empresaId) {
                if (empresaId == null) {
                    throw new SinEmpresaEnContextoException("No hay empresa en el contexto");
                }
                DataSource base = bases.get(empresaId);
                if (base == null) {
                    throw new SinEmpresaEnContextoException("La empresa " + empresaId + " no tiene base");
                }
                return base;
            }

            @Override
            public boolean conoce(Long empresaId) {
                return bases.containsKey(empresaId);
            }

            @Override
            public Collection<Long> empresas() {
                return List.copyOf(bases.keySet());
            }
        };
        enrutado = new JdbcTemplate(new TenantRoutingDataSource(resolutor));
    }

    @AfterEach
    void cerrar() {
        TenantContext.limpiar();
        baseUno.close();
        baseDos.close();
    }

    private static HikariDataSource pool(String url, String usuario, String clave) {
        HikariConfig config = new HikariConfig();
        config.setJdbcUrl(url);
        config.setUsername(usuario);
        config.setPassword(clave);
        config.setMaximumPoolSize(3);
        return new HikariDataSource(config);
    }

    private String baseActual() {
        return enrutado.queryForObject("SELECT current_database()", String.class);
    }

    @Test
    void cadaEmpresaAbreSuPropiaBase() {
        String deUno = TenantContext.ejecutarEn(EMPRESA_UNO, this::baseActual);
        String deDos = TenantContext.ejecutarEn(EMPRESA_DOS, this::baseActual);

        assertThat(deUno).isEqualTo("checkinobra");
        assertThat(deDos).isEqualTo("checkinobra_catalogo");
    }

    @Test
    void sinEmpresaEnElContextoFallaYNoCaeEnUnaBasePorDefecto() {
        assertThatThrownBy(this::baseActual)
                .isInstanceOf(SinEmpresaEnContextoException.class)
                .hasMessageContaining("empresa");
    }

    @Test
    void unaEmpresaSinBaseRegistradaFalla() {
        assertThatThrownBy(() -> TenantContext.ejecutarEn(99L, this::baseActual))
                .isInstanceOf(SinEmpresaEnContextoException.class)
                .hasMessageContaining("99");
    }

    @Test
    void despuesDeLaTareaVuelveAFallarSinEmpresa() {
        TenantContext.ejecutarEn(EMPRESA_UNO, this::baseActual);

        assertThatThrownBy(this::baseActual).isInstanceOf(SinEmpresaEnContextoException.class);
    }

    @Test
    void dosHilosConEmpresasDistintasNoSeMezclan() throws Exception {
        ExecutorService hilos = Executors.newFixedThreadPool(2);
        try {
            for (int vuelta = 0; vuelta < 20; vuelta++) {
                Future<String> a = hilos.submit(() -> TenantContext.ejecutarEn(EMPRESA_UNO, this::baseActual));
                Future<String> b = hilos.submit(() -> TenantContext.ejecutarEn(EMPRESA_DOS, this::baseActual));

                assertThat(a.get()).isEqualTo("checkinobra");
                assertThat(b.get()).isEqualTo("checkinobra_catalogo");
            }
        } finally {
            hilos.shutdown();
        }
    }

    @Test
    void elPoolDeUnaEmpresaNoTieneCredencialesParaLaBaseDeOtra() {
        // Lo que hace físico el aislamiento: desde la base de la empresa no hay camino a otra.
        JdbcTemplate comoEmpresaUno = new JdbcTemplate(baseUno);
        assertThat(comoEmpresaUno.queryForObject("SELECT current_user", String.class)).isEqualTo(usuarioUno);
        assertThatThrownBy(() -> new JdbcTemplate(pool(urlDos, usuarioUno, claveUno))
                .queryForObject("SELECT 1", Integer.class)).hasMessageContaining("permission denied");
    }
}
