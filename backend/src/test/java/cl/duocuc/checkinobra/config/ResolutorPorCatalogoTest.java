package cl.duocuc.checkinobra.config;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.core.env.Environment;
import org.springframework.jdbc.core.JdbcTemplate;

import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * MT2 (#105): los pools se arman leyendo el catálogo, con la contraseña que dice la
 * referencia al secreto, y una empresa mal registrada no impide que funcionen las demás.
 */
@SpringBootTest
class ResolutorPorCatalogoTest {

    @Autowired private CatalogoDeEmpresas catalogo;
    @Autowired private Environment entorno;

    @Value("${spring.datasource.url}") private String urlDelServidor;
    @Value("${checkinobra.catalogo.url}") private String urlCatalogo;
    @Value("${checkinobra.catalogo.username}") private String usuarioCatalogo;
    @Value("${checkinobra.catalogo.password}") private String claveCatalogo;

    private JdbcTemplate enElCatalogo;
    private final List<Long> registradas = new ArrayList<>();
    private ResolutorPorCatalogo resolutor;
    private String s;

    @BeforeEach
    void preparar() {
        enElCatalogo = new JdbcTemplate(new org.springframework.jdbc.datasource.DriverManagerDataSource(
                urlCatalogo, usuarioCatalogo, claveCatalogo));
        s = UUID.randomUUID().toString().substring(0, 8);
    }

    @AfterEach
    void limpiar() {
        if (resolutor != null) {
            resolutor.destroy();
        }
        for (Long id : registradas) {
            enElCatalogo.update("DELETE FROM empresas WHERE id = ?", id);
        }
    }

    /** Una empresa cuya "base" es la del catálogo, con el usuario y la variable de su contraseña. */
    private long registrar(String base, String usuario, String secretoRef) {
        long id = catalogo.registrar(null, "RC-" + UUID.randomUUID().toString().substring(0, 10),
                "Empresa " + s, base + "_" + s, usuario, secretoRef);
        registradas.add(id);
        // Una base solo se abre si su migración salió bien.
        catalogo.marcarMigracion(id, true, null);
        return id;
    }

    /** El catálogo tiene que dar nombres de base únicos, pero acá la base real es la del catálogo. */
    private long registrarContraElCatalogo() {
        long id = registrar("ficticia", usuarioCatalogo, "env:CATALOGO_PASSWORD");
        // nombre_base apunta a una base que existe: la del catálogo.
        enElCatalogo.update("UPDATE empresas SET nombre_base = 'checkinobra_catalogo' WHERE id = ?", id);
        return id;
    }

    private ResolutorPorCatalogo resolutor() {
        resolutor = new ResolutorPorCatalogo(catalogo, entorno, urlDelServidor, 2);
        return resolutor;
    }

    @Test
    void armaUnPoolPorEmpresaConLaContrasenaDeSuReferencia() {
        long id = registrarContraElCatalogo();

        ResolutorPorCatalogo r = resolutor();

        assertThat(r.conoce(id)).isTrue();
        assertThat(r.empresas()).contains(id);
        String base = new JdbcTemplate(r.baseDe(id)).queryForObject("SELECT current_database()", String.class);
        assertThat(base).isEqualTo("checkinobra_catalogo");
    }

    @Test
    void unaEmpresaSuspendidaNoTienePoolYSuTokenDejaDeValer() {
        long id = registrarContraElCatalogo();
        ResolutorPorCatalogo r = resolutor();
        assertThat(r.conoce(id)).isTrue();

        enElCatalogo.update("UPDATE empresas SET estado = 'SUSPENDIDA' WHERE id = ?", id);
        r.refrescar();

        assertThat(r.conoce(id)).isFalse();
        assertThatThrownBy(() -> r.baseDe(id)).isInstanceOf(SinEmpresaEnContextoException.class);
    }

    @Test
    void unaBaseCuyaMigracionFalloNoSeAbre() {
        long id = registrarContraElCatalogo();
        catalogo.marcarMigracion(id, false, "falló la V12");

        ResolutorPorCatalogo r = resolutor();

        assertThat(r.conoce(id)).isFalse();
        assertThatThrownBy(() -> r.baseDe(id)).isInstanceOf(SinEmpresaEnContextoException.class);
    }

    @Test
    void unaEmpresaDadaDeAltaDespuesDelArranqueTienePoolAlRefrescar() {
        ResolutorPorCatalogo r = resolutor();
        long id = registrarContraElCatalogo();
        assertThat(r.conoce(id)).isFalse();

        r.refrescar();

        assertThat(r.conoce(id)).isTrue();
    }

    @Test
    void unaEmpresaMalRegistradaNoImpideQueFuncionenLasDemas() {
        long buena = registrarContraElCatalogo();
        long sinVariable = registrar("otra", usuarioCatalogo, "env:ESTA_VARIABLE_NO_EXISTE_" + s);
        long sinReferencia = registrar("otra2", usuarioCatalogo, "texto-plano");

        ResolutorPorCatalogo r = resolutor();

        assertThat(r.conoce(buena)).isTrue();
        assertThat(r.conoce(sinVariable)).isFalse();
        assertThat(r.conoce(sinReferencia)).isFalse();
    }

    @Test
    void sinEmpresaOConUnaDesconocidaNoHayBase() {
        ResolutorPorCatalogo r = resolutor();

        assertThatThrownBy(() -> r.baseDe(null)).isInstanceOf(SinEmpresaEnContextoException.class);
        assertThatThrownBy(() -> r.baseDe(987_654_321L)).isInstanceOf(SinEmpresaEnContextoException.class);
        assertThat(r.conoce(null)).isFalse();
    }
}
