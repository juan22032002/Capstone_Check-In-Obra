package cl.duocuc.checkinobra.config;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.core.NestedExceptionUtils;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DriverManagerDataSource;

import java.util.ArrayList;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.catchThrowable;

/**
 * MT1 (#104): base de catálogo con las empresas y los datos de conexión de cada
 * una. Contra el Postgres real de la suite, que tiene que haberse creado con
 * {@code db/crear-roles.sh} (crea checkinobra_catalogo y su rol).
 */
@SpringBootTest
class CatalogoDeEmpresasTest {

    @Autowired private CatalogoDeEmpresas catalogo;
    @Autowired private BaseInicialInicializador baseInicial;
    @Autowired private SincronizadorDeCatalogo sincronizador;
    @Autowired private EmpresaRepository empresaRepository;
    @Autowired private UsuarioRepository usuarioRepository;
    @Autowired private JdbcTemplate baseDeLaEmpresa;

    @Value("${checkinobra.catalogo.url}") private String url;
    @Value("${checkinobra.catalogo.username}") private String usuario;
    @Value("${checkinobra.catalogo.password}") private String clave;
    @Value("${spring.datasource.url}") private String urlDeLaEmpresa;
    @Value("${spring.datasource.username}") private String usuarioDeLaApi;
    @Value("${spring.datasource.password}") private String claveDeLaApi;

    /** Conexión directa al catálogo, como la plataforma, para mirar lo que quedó guardado. */
    private JdbcTemplate enElCatalogo;
    private String s;
    private Empresa empresa;
    private final List<Long> registradas = new ArrayList<>();

    @BeforeEach
    void prepararEmpresa() {
        enElCatalogo = new JdbcTemplate(new DriverManagerDataSource(url, usuario, clave));
        s = UUID.randomUUID().toString().substring(0, 8);
        empresa = empresaRepository.save(Empresa.builder().nombre("Empresa " + s).rut("R-" + s).build());
        registradas.add(empresa.getId());
    }

    @AfterEach
    void limpiarElCatalogo() {
        // El catálogo es compartido entre corridas y nombre_base es único.
        for (Long id : registradas) {
            enElCatalogo.update("DELETE FROM indice_login WHERE empresa_id = ?", id);
            enElCatalogo.update("DELETE FROM empresas WHERE id = ?", id);
        }
    }

    /** El arranque real: registra la base actual si tiene a la empresa, y completa el índice. */
    private Optional<CatalogoDeEmpresas.EmpresaRegistrada> registrarBaseActual(String rut) {
        String nombre = empresaRepository.findByRut(rut).map(Empresa::getNombre).orElse("Sin nombre");
        Optional<Long> id = baseInicial.asegurar(rut, nombre, false);
        id.ifPresent(sincronizador::sincronizarIndiceDeLogin);
        return id.flatMap(i -> catalogo.listar().stream().filter(r -> r.id().equals(i)).findFirst());
    }

    // --- esquema ------------------------------------------------------------------

    @Test
    void elCatalogoTieneSusTablasYUnPlanInicial() {
        List<String> tablas = enElCatalogo.queryForList(
                "SELECT table_name FROM information_schema.tables WHERE table_schema = 'public'", String.class);

        assertThat(tablas).contains("empresas", "planes", "operadores", "indice_login");
        assertThat(enElCatalogo.queryForObject("SELECT count(*) FROM planes", Integer.class)).isPositive();
    }

    @Test
    void lasMigracionesDelCatalogoLasAplicaElMigrador() {
        List<String> quienes = enElCatalogo.queryForList(
                "SELECT DISTINCT installed_by FROM flyway_schema_history", String.class);

        assertThat(quienes).containsExactly("checkinobra_migrador");
    }

    @Test
    void laPlataformaSoloPuedeLeerYEscribirDatosDelCatalogo() {
        Throwable error = catchThrowable(() -> enElCatalogo.execute("CREATE TABLE no_debe_existir (id int)"));

        assertThat(error).isNotNull();
        assertThat(NestedExceptionUtils.getMostSpecificCause(error).getMessage()).contains("permission denied");
        assertThat(enElCatalogo.queryForObject("SELECT current_user", String.class))
                .isEqualTo("checkinobra_plataforma");
    }

    @Test
    void laApiDeUnaEmpresaNoPuedeConectarseAlCatalogoNiLaPlataformaALaDeUnaEmpresa() {
        Throwable apiAlCatalogo = catchThrowable(() ->
                new JdbcTemplate(new DriverManagerDataSource(url, usuarioDeLaApi, claveDeLaApi))
                        .queryForObject("SELECT 1", Integer.class));
        Throwable plataformaALaEmpresa = catchThrowable(() ->
                new JdbcTemplate(new DriverManagerDataSource(urlDeLaEmpresa, usuario, clave))
                        .queryForObject("SELECT 1", Integer.class));

        // Un fallo en la API de una empresa no alcanza al catálogo, y el catálogo no
        // abre la base de nadie.
        assertThat(apiAlCatalogo).isNotNull();
        assertThat(NestedExceptionUtils.getMostSpecificCause(apiAlCatalogo).getMessage())
                .contains("permission denied");
        assertThat(plataformaALaEmpresa).isNotNull();
        assertThat(NestedExceptionUtils.getMostSpecificCause(plataformaALaEmpresa).getMessage())
                .contains("permission denied");
    }

    // --- la base actual queda registrada -----------------------------------------

    @Test
    void laBaseActualQuedaRegistradaConLosDatosParaConectarse() {
        Optional<CatalogoDeEmpresas.EmpresaRegistrada> registrada = registrarBaseActual(empresa.getRut());

        assertThat(registrada).isPresent();
        CatalogoDeEmpresas.EmpresaRegistrada r = registrada.get();
        String baseActual = baseDeLaEmpresa.queryForObject("SELECT current_database()", String.class);
        // El id del catálogo es el de la copia en la base: es el que viaja en el JWT.
        assertThat(r.id()).isEqualTo(empresa.getId());
        assertThat(r.rut()).isEqualTo(empresa.getRut());
        assertThat(r.nombre()).isEqualTo(empresa.getNombre());
        assertThat(r.nombreBase()).isEqualTo(baseActual);
        assertThat(r.usuarioBase()).isEqualTo(usuarioDeLaApi);
        assertThat(r.plan()).isEqualTo("ESTANDAR");
        assertThat(r.estado()).isEqualTo("ACTIVA");
    }

    @Test
    void elCatalogoGuardaUnaReferenciaAlSecretoNuncaElSecreto() {
        registrarBaseActual(empresa.getRut());

        List<String> fila = enElCatalogo.queryForList(
                "SELECT concat_ws('|', rut, nombre, nombre_base, usuario_base, secreto_ref) FROM empresas WHERE id = ?",
                String.class, empresa.getId());

        assertThat(fila).hasSize(1);
        assertThat(fila.get(0)).contains("env:SPRING_DATASOURCE_PASSWORD").doesNotContain(claveDeLaApi);
    }

    @Test
    void registrarDosVecesNoDuplicaNiFalla() {
        registrarBaseActual(empresa.getRut());
        registrarBaseActual(empresa.getRut());

        assertThat(enElCatalogo.queryForObject(
                "SELECT count(*) FROM empresas WHERE id = ?", Integer.class, empresa.getId())).isEqualTo(1);
        assertThat(catalogo.listar()).extracting(CatalogoDeEmpresas.EmpresaRegistrada::id).contains(empresa.getId());
    }

    @Test
    void soloSeRegistraLaEmpresaQueSePide() {
        Empresa otra = empresaRepository.save(Empresa.builder().nombre("Otra " + s).rut("O-" + s).build());

        registrarBaseActual(empresa.getRut());

        assertThat(catalogo.listar()).extracting(CatalogoDeEmpresas.EmpresaRegistrada::id)
                .contains(empresa.getId()).doesNotContain(otra.getId());
    }

    @Test
    void siLaEmpresaNoEstaEnLaBaseNoSeRegistraNada() {
        assertThat(registrarBaseActual("no-existe-" + s)).isEmpty();
    }

    @Test
    void laAltaDelCatalogoNoMueveElPlanNiElEstadoQueFijeLaPlataforma() {
        registrarBaseActual(empresa.getRut());
        enElCatalogo.update("UPDATE empresas SET estado = 'SUSPENDIDA' WHERE id = ?", empresa.getId());

        registrarBaseActual(empresa.getRut());

        assertThat(enElCatalogo.queryForObject(
                "SELECT estado FROM empresas WHERE id = ?", String.class, empresa.getId())).isEqualTo("SUSPENDIDA");
    }

    // --- índice de login ----------------------------------------------------------

    @Test
    void elIndiceDeLoginTraeLosCorreosDeLaEmpresaEnMinusculas() {
        usuarioRepository.save(Usuario.builder().nombre("Jefe").email("Jefe-" + s + "@Test.cl")
                .rol(RolUsuario.JEFE_TERRENO).empresa(empresa).build());

        registrarBaseActual(empresa.getRut());

        assertThat(catalogo.empresaDeCorreo("jefe-" + s + "@test.cl")).contains(empresa.getId());
        assertThat(catalogo.empresaDeCorreo("JEFE-" + s + "@TEST.CL")).contains(empresa.getId());
        assertThat(catalogo.empresaDeCorreo("nadie-" + s + "@test.cl")).isEmpty();
    }

    @Test
    void unCorreoQueYaEsDeOtraEmpresaNoSePisa() {
        // Otra empresa del catálogo, con su propia base, ya tiene ese correo.
        long idAjeno = empresa.getId() + 1_000_000;
        registradas.add(idAjeno);
        enElCatalogo.update("""
                INSERT INTO empresas (id, rut, nombre, plan_id, nombre_base, usuario_base, secreto_ref)
                VALUES (?, ?, 'Ajena', (SELECT id FROM planes LIMIT 1), ?, 'u_ajena', 'env:X')
                """, idAjeno, "AJ-" + s, "base_ajena_" + s);
        String correo = "compartido-" + s + "@test.cl";
        enElCatalogo.update("INSERT INTO indice_login (email, empresa_id) VALUES (?, ?)", correo, idAjeno);
        usuarioRepository.save(Usuario.builder().nombre("Repetido").email(correo)
                .rol(RolUsuario.BODEGUERO).empresa(empresa).build());

        registrarBaseActual(empresa.getRut());

        assertThat(catalogo.empresaDeCorreo(correo)).contains(idAjeno);
    }

    @Test
    void sincronizarDosVecesNoDuplicaElIndice() {
        usuarioRepository.save(Usuario.builder().nombre("Uno").email("uno-" + s + "@test.cl")
                .rol(RolUsuario.BODEGUERO).empresa(empresa).build());

        registrarBaseActual(empresa.getRut());
        registrarBaseActual(empresa.getRut());

        assertThat(enElCatalogo.queryForObject(
                "SELECT count(*) FROM indice_login WHERE empresa_id = ?", Integer.class, empresa.getId()))
                .isEqualTo(1);
    }
}
