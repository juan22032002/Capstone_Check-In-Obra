package cl.duocuc.checkinobra.plataforma;

import cl.duocuc.checkinobra.config.AlmacenDeSecretos;
import cl.duocuc.checkinobra.config.CatalogoDeEmpresas;
import cl.duocuc.checkinobra.config.JwtService;
import cl.duocuc.checkinobra.config.MigradorDeBases;
import cl.duocuc.checkinobra.config.ResolutorDeBases;
import cl.duocuc.checkinobra.config.UrlsDeBases;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.server.LocalServerPort;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.crypto.bcrypt.BCrypt;
import org.springframework.test.context.bean.override.mockito.MockitoSpyBean;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.json.JsonMapper;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.sql.DriverManager;
import java.sql.SQLException;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;
import java.util.concurrent.ThreadLocalRandom;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.doReturn;

/**
 * MT7 (#110): el alta de una constructora de punta a punta, contra Postgres real y con el
 * enrutador de verdad: se crea la base y su usuario, se migra, se abre el pool en caliente y el
 * primer ADMIN entra. Si un paso falla, no queda nada. Necesita el rol aprovisionador
 * ({@code DB_APROVISIONADOR_PASSWORD}) y {@code SECRETOS_DIR}; la CI los define.
 */
@SpringBootTest(
        webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT,
        properties = {
                "checkinobra.pruebas.conexion-compartida=false",
                "spring.jpa.hibernate.ddl-auto=none",
                "spring.jpa.properties.hibernate.boot.allow_jdbc_metadata_access=false"})
class AltaDeEmpresaTest {

    private static final String CLAVE_OPERADOR = "clave-del-operador-9";
    private static final String CLAVE_NUEVA = "clave-nueva-del-admin-7";

    @LocalServerPort private int puerto;
    @Autowired private CatalogoDeEmpresas catalogo;
    @Autowired private AprovisionadorDeBases aprovisionador;
    @Autowired private AlmacenDeSecretos secretos;
    @Autowired private ResolutorDeBases resolutor;
    @Autowired private JwtService jwtService;
    @MockitoSpyBean private MigradorDeBases migrador;

    @Value("${spring.datasource.url}") private String urlServidor;
    @Value("${checkinobra.catalogo.url}") private String urlCatalogo;
    @Value("${checkinobra.catalogo.username}") private String usuarioCatalogo;
    @Value("${checkinobra.catalogo.password}") private String claveCatalogo;

    private final HttpClient http = HttpClient.newHttpClient();
    private final JsonMapper json = JsonMapper.builder().build();
    private final List<String> ruts = new ArrayList<>();
    private final List<Long> operadores = new ArrayList<>();

    private String token;
    private JdbcTemplate enElCatalogo;

    @BeforeEach
    void operador() throws Exception {
        enElCatalogo = new JdbcTemplate(new org.springframework.jdbc.datasource.DriverManagerDataSource(
                urlCatalogo, usuarioCatalogo, claveCatalogo));
        String correo = "operador-" + UUID.randomUUID().toString().substring(0, 8) + "@plataforma.cl";
        operadores.add(catalogo.crearOperador(correo, "Operadora", BCrypt.hashpw(CLAVE_OPERADOR, BCrypt.gensalt()))
                .orElseThrow());
        token = json.readTree(enviar("POST", "/api/plataforma/auth/login", null,
                "{\"email\":\"" + correo + "\",\"clave\":\"" + CLAVE_OPERADOR + "\"}").body()).get("token").asString();
    }

    @AfterEach
    void limpiar() {
        // Primero fuera del catálogo y con los pools cerrados: con conexiones abiertas no se borra la base.
        ruts.forEach(rut -> catalogo.buscarPorRut(rut).ifPresent(e -> catalogo.eliminarEmpresa(e.id())));
        resolutor.refrescar();
        for (String rut : ruts) {
            String digitos = rut.replaceAll("[^0-9K]", "").toLowerCase();
            aprovisionador.eliminar("checkinobra_e" + digitos, "app_e" + digitos);
            secretos.borrar("app_e" + digitos);
        }
        operadores.forEach(id -> enElCatalogo.update("DELETE FROM operadores WHERE id = ?", id));
        resolutor.refrescar();
    }

    // ---- el alta completa ---------------------------------------------------------------------

    @Test
    void laEmpresaNuevaQuedaFuncionandoYSuAdminEntraSinReiniciarLaApi() throws Exception {
        String rut = rutNuevo();
        String correo = correoNuevo();

        HttpResponse<String> alta = alta(rut, correo, null, false);

        assertThat(alta.statusCode()).as(alta.body()).isEqualTo(201);
        JsonNode r = json.readTree(alta.body());
        long id = r.get("id").asLong();
        String claveTemporal = r.get("claveTemporal").asString();
        assertThat(resolutor.conoce(id)).isTrue();

        // El ADMIN entra con la clave generada y queda obligado a cambiarla.
        JsonNode login = json.readTree(enviar("POST", "/api/auth/login", null,
                "{\"email\":\"" + correo + "\",\"pin\":\"" + claveTemporal + "\"}").body());
        assertThat(login.get("debeCambiarClave").asBoolean()).isTrue();
        String tokenTemporal = login.get("token").asString();
        assertThat(enviar("GET", "/api/empresas/mia", tokenTemporal, null).statusCode()).isEqualTo(403);

        JsonNode sesion = json.readTree(enviar("PUT", "/api/auth/pin", tokenTemporal,
                "{\"pinActual\":\"" + claveTemporal + "\",\"pinNuevo\":\"" + CLAVE_NUEVA + "\"}").body());
        HttpResponse<String> mia = enviar("GET", "/api/empresas/mia", sesion.get("token").asString(), null);

        // Es la base nueva, con el id y el RUT que tiene en el catálogo.
        assertThat(mia.statusCode()).isEqualTo(200);
        assertThat(json.readTree(mia.body()).get("id").asLong()).isEqualTo(id);
        assertThat(catalogo.buscarPorRut(rut)).get().satisfies(e -> {
            assertThat(e.estado()).isEqualTo("ACTIVA");
            assertThat(e.migracionEstado()).isEqualTo("OK");
            assertThat(e.secretoRef()).startsWith("file:");
        });
    }

    @Test
    void laClaveInicialPuedeIrEnLaPeticionYEntoncesNoSeDevuelve() throws Exception {
        String correo = correoNuevo();

        HttpResponse<String> alta = alta(rutNuevo(), correo, "clave-que-puso-el-operador", false);

        assertThat(alta.statusCode()).isEqualTo(201);
        assertThat(json.readTree(alta.body()).get("claveTemporal").isNull()).isTrue();
        assertThat(enviar("POST", "/api/auth/login", null,
                "{\"email\":\"" + correo + "\",\"pin\":\"clave-que-puso-el-operador\"}").statusCode()).isEqualTo(200);
    }

    @Test
    void laBaseNuevaEsDeVerdadSuyaYElUsuarioSoloTieneDml() throws Exception {
        String rut = rutNuevo();
        long id = json.readTree(alta(rut, correoNuevo(), null, false).body()).get("id").asLong();
        var e = catalogo.buscarPorRut(rut).orElseThrow();
        String clave = secretos.leer(e.usuarioBase());
        String urlPropia = new UrlsDeBases(urlServidor).de(e.nombreBase());

        // Entra a su base y lee su empresa, con el mismo id del catálogo.
        try (var c = DriverManager.getConnection(urlPropia, e.usuarioBase(), clave);
                var rs = c.createStatement().executeQuery("SELECT id FROM empresas")) {
            assertThat(rs.next()).isTrue();
            assertThat(rs.getLong(1)).isEqualTo(id);
        }
        // No cambia el esquema…
        try (var c = DriverManager.getConnection(urlPropia, e.usuarioBase(), clave)) {
            assertThatThrownBy(() -> c.createStatement().execute("CREATE TABLE intruso (id int)"))
                    .isInstanceOf(SQLException.class);
        }
        // …ni se conecta a la base de otra empresa ni al catálogo.
        String urlOtra = new UrlsDeBases(urlServidor).de("checkinobra");
        assertThatThrownBy(() -> DriverManager.getConnection(urlOtra, e.usuarioBase(), clave).close())
                .isInstanceOf(SQLException.class);
        assertThatThrownBy(() -> DriverManager.getConnection(urlCatalogo, e.usuarioBase(), clave).close())
                .isInstanceOf(SQLException.class);
    }

    @Test
    void elCatalogoBaseSeCopiaConPreciosPropiosSoloSiSePide() throws Exception {
        var conCatalogo = json.readTree(alta(rutNuevo(), correoNuevo(), null, true).body());
        var sinCatalogo = json.readTree(alta(rutNuevo(), correoNuevo(), null, false).body());

        List<JsonNode> copiados = materiales(conCatalogo);
        assertThat(copiados).hasSize(AprovisionadorDeBases.leerCatalogoBase().size());
        assertThat(copiados).anyMatch(m -> m.get("sku").asString().equals("VOL-ST-10"))
                .allMatch(m -> m.get("precioUnitario").asDouble() > 0);
        assertThat(materiales(sinCatalogo)).isEmpty();
    }

    // ---- validaciones y lo que no se puede ----------------------------------------------------

    @Test
    void unRutRepetidoEsUn409YNoCreaOtraBase() throws Exception {
        String rut = rutNuevo();
        alta(rut, correoNuevo(), null, false);
        int basesAntes = contar("SELECT count(*) FROM pg_database WHERE datname LIKE 'checkinobra_e%'");

        HttpResponse<String> repetida = alta(rut, correoNuevo(), null, false);

        assertThat(repetida.statusCode()).isEqualTo(409);
        assertThat(contar("SELECT count(*) FROM pg_database WHERE datname LIKE 'checkinobra_e%'")).isEqualTo(basesAntes);
    }

    @Test
    void unRutInvalidoOSinFormatoEsUn400YNoDejaNada() throws Exception {
        int empresasAntes = catalogo.listar().size();

        assertThat(alta("12.345.678-0", correoNuevo(), null, false).statusCode()).isEqualTo(400);
        assertThat(alta("no-es-un-rut", correoNuevo(), null, false).statusCode()).isEqualTo(400);

        assertThat(catalogo.listar()).hasSize(empresasAntes);
    }

    @Test
    void unaClaveInicialQueNoCumpleLaPoliticaEsUn400() throws Exception {
        assertThat(alta(rutNuevo(), correoNuevo(), "corta", false).statusCode()).isEqualTo(400);
    }

    @Test
    void conUnCorreoYaUsadoFallaYSeDeshaceTodoLoCreado() throws Exception {
        String correo = correoNuevo();
        alta(rutNuevo(), correo, null, false);
        String rut = rutNuevo();
        ruts.add(rut);

        HttpResponse<String> r = alta(rut, correo, null, false);

        assertThat(r.statusCode()).isEqualTo(409);
        assertQueNoQuedaNada(rut);
    }

    @Test
    void siLaMigracionFallaSeDeshaceTodo() throws Exception {
        String rut = rutNuevo();
        doReturn(new MigradorDeBases.Resultado(1L, "x", false, "boom")).when(migrador).migrar(any());

        HttpResponse<String> r = alta(rut, correoNuevo(), null, false);

        assertThat(r.statusCode()).isEqualTo(500);
        // El error al operador es genérico: no filtra el detalle de la infraestructura.
        assertThat(r.body()).doesNotContain("boom");
        assertQueNoQuedaNada(rut);
    }

    @Test
    void soloUnOperadorDePlataformaDaDeAlta() throws Exception {
        assertThat(enviar("POST", "/api/plataforma/empresas", null, cuerpo(rutNuevo(), correoNuevo(), null, false))
                .statusCode()).isEqualTo(401);
    }

    // ---- soporte ------------------------------------------------------------------------------

    private void assertQueNoQuedaNada(String rut) {
        String digitos = rut.replaceAll("[^0-9K]", "").toLowerCase();
        assertThat(catalogo.buscarPorRut(rut)).isEmpty();
        assertThat(aprovisionador.existeBase("checkinobra_e" + digitos)).isFalse();
        assertThat(contar("SELECT count(*) FROM pg_roles WHERE rolname = 'app_e" + digitos + "'")).isZero();
        assertThat(secretos.existe("app_e" + digitos)).isFalse();
    }

    private int contar(String sql) {
        return enElCatalogo.queryForObject(sql, Integer.class);
    }

    private List<JsonNode> materiales(JsonNode alta) throws Exception {
        // Entra como el ADMIN de esa empresa con su clave temporal, la cambia y lista.
        String correo = alta.get("adminEmail").asString();
        String temporal = alta.get("claveTemporal").asString();
        JsonNode login = json.readTree(enviar("POST", "/api/auth/login", null,
                "{\"email\":\"" + correo + "\",\"pin\":\"" + temporal + "\"}").body());
        JsonNode sesion = json.readTree(enviar("PUT", "/api/auth/pin", login.get("token").asString(),
                "{\"pinActual\":\"" + temporal + "\",\"pinNuevo\":\"" + CLAVE_NUEVA + "\"}").body());
        JsonNode lista = json.readTree(enviar("GET", "/api/materiales", sesion.get("token").asString(), null).body());
        List<JsonNode> out = new ArrayList<>();
        lista.forEach(out::add);
        return out;
    }

    private static String usuarioDe(String base) {
        return "app_e" + base.substring("checkinobra_e".length());
    }

    private String rutNuevo() {
        String cuerpo = String.valueOf(10_000_000 + ThreadLocalRandom.current().nextInt(80_000_000));
        int suma = 0;
        int factor = 2;
        for (int i = cuerpo.length() - 1; i >= 0; i--) {
            suma += (cuerpo.charAt(i) - '0') * factor;
            factor = factor == 7 ? 2 : factor + 1;
        }
        int resto = 11 - suma % 11;
        char dv = resto == 11 ? '0' : resto == 10 ? 'K' : (char) ('0' + resto);
        String rut = cuerpo.substring(0, 2) + "." + cuerpo.substring(2, 5) + "." + cuerpo.substring(5) + "-" + dv;
        ruts.add(rut);
        return rut;
    }

    private static String correoNuevo() {
        return "admin-" + UUID.randomUUID().toString().substring(0, 10) + "@constructora.cl";
    }

    private static String cuerpo(String rut, String correo, String clave, boolean catalogoBase) {
        return "{\"rut\":\"" + rut + "\",\"nombre\":\"Constructora de prueba\",\"adminEmail\":\"" + correo + "\""
                + (clave == null ? "" : ",\"adminClave\":\"" + clave + "\"")
                + ",\"copiarCatalogoBase\":" + catalogoBase + "}";
    }

    private HttpResponse<String> alta(String rut, String correo, String clave, boolean catalogoBase) throws Exception {
        HttpResponse<String> r = enviar("POST", "/api/plataforma/empresas", token, cuerpo(rut, correo, clave, catalogoBase));
        if (r.statusCode() == 201) {
            // Para el alta feliz el AfterEach limpia por RUT canónico (el de la respuesta).
            ruts.add(json.readTree(r.body()).get("rut").asString());
        }
        return r;
    }

    private HttpResponse<String> enviar(String metodo, String ruta, String jwt, String cuerpo) throws Exception {
        HttpRequest.Builder b = HttpRequest.newBuilder(URI.create("http://localhost:" + puerto + ruta))
                .header("Content-Type", "application/json");
        if (jwt != null) {
            b.header("Authorization", "Bearer " + jwt);
        }
        b.method(metodo, cuerpo == null ? HttpRequest.BodyPublishers.noBody() : HttpRequest.BodyPublishers.ofString(cuerpo));
        return http.send(b.build(), HttpResponse.BodyHandlers.ofString());
    }
}
