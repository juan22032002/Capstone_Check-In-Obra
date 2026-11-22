package cl.duocuc.checkinobra.plataforma;

import cl.duocuc.checkinobra.config.AlmacenDeSecretos;
import cl.duocuc.checkinobra.config.CatalogoDeEmpresas;
import cl.duocuc.checkinobra.config.JwtService;
import cl.duocuc.checkinobra.config.ResolutorDeBases;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.server.LocalServerPort;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.crypto.bcrypt.BCrypt;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.json.JsonMapper;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;
import java.util.concurrent.ThreadLocalRandom;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * MT8 (#111): una empresa suspendida recibe 403 en cada petición, sin que se abra su base; las
 * demás siguen igual; reactivarla la devuelve a como estaba. Contra Postgres real y el enrutador
 * real, con una empresa dada de alta por la propia API.
 */
@SpringBootTest(
        webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT,
        properties = {
                "checkinobra.pruebas.conexion-compartida=false",
                "spring.jpa.hibernate.ddl-auto=none",
                "spring.jpa.properties.hibernate.boot.allow_jdbc_metadata_access=false"})
class SuspensionDeEmpresaTest {

    private static final String CLAVE_OPERADOR = "clave-del-operador-9";
    private static final String CLAVE_ADMIN = "clave-nueva-del-admin-7";

    @LocalServerPort private int puerto;
    @Autowired private CatalogoDeEmpresas catalogo;
    @Autowired private AprovisionadorDeBases aprovisionador;
    @Autowired private AlmacenDeSecretos secretos;
    @Autowired private ResolutorDeBases resolutor;
    @Autowired private JwtService jwtService;

    @Value("${checkinobra.catalogo.url}") private String urlCatalogo;
    @Value("${checkinobra.catalogo.username}") private String usuarioCatalogo;
    @Value("${checkinobra.catalogo.password}") private String claveCatalogo;

    private final HttpClient http = HttpClient.newHttpClient();
    private final JsonMapper json = JsonMapper.builder().build();
    private final List<String> ruts = new ArrayList<>();
    private JdbcTemplate enElCatalogo;
    private long operadorId;
    private String tokenOperador;

    private long empresaId;
    private String correoAdmin;
    private String tokenAdmin;

    @BeforeEach
    void empresaConAdminYOperador() throws Exception {
        enElCatalogo = new JdbcTemplate(new org.springframework.jdbc.datasource.DriverManagerDataSource(
                urlCatalogo, usuarioCatalogo, claveCatalogo));
        String correoOperador = "operador-" + UUID.randomUUID().toString().substring(0, 8) + "@plataforma.cl";
        operadorId = catalogo.crearOperador(correoOperador, "Operadora", BCrypt.hashpw(CLAVE_OPERADOR, BCrypt.gensalt()))
                .orElseThrow();
        tokenOperador = json.readTree(enviar("POST", "/api/plataforma/auth/login", null,
                "{\"email\":\"" + correoOperador + "\",\"clave\":\"" + CLAVE_OPERADOR + "\"}").body()).get("token").asString();

        String rut = rutNuevo();
        correoAdmin = "admin-" + UUID.randomUUID().toString().substring(0, 10) + "@constructora.cl";
        HttpResponse<String> alta = enviar("POST", "/api/plataforma/empresas", tokenOperador,
                "{\"rut\":\"" + rut + "\",\"nombre\":\"Constructora suspendible\",\"adminEmail\":\"" + correoAdmin
                        + "\",\"adminClave\":\"" + "clave-inicial-1234" + "\"}");
        assertThat(alta.statusCode()).as(alta.body()).isEqualTo(201);
        empresaId = json.readTree(alta.body()).get("id").asLong();
        tokenAdmin = sesionDelAdmin();
    }

    @AfterEach
    void limpiar() {
        ruts.forEach(rut -> catalogo.buscarPorRut(rut).ifPresent(e -> catalogo.eliminarEmpresa(e.id())));
        resolutor.refrescar();
        for (String rut : ruts) {
            String digitos = rut.replaceAll("[^0-9K]", "").toLowerCase();
            aprovisionador.eliminar("checkinobra_e" + digitos, "app_e" + digitos);
            secretos.borrar("app_e" + digitos);
        }
        enElCatalogo.update("DELETE FROM operadores WHERE id = ?", operadorId);
        resolutor.refrescar();
    }

    @Test
    void unaEmpresaSuspendidaRecibe403EnCadaPeticionConSuCodigo() throws Exception {
        assertThat(get("/api/empresas/mia", tokenAdmin).statusCode()).isEqualTo(200);

        assertThat(suspender(empresaId).statusCode()).isEqualTo(200);

        for (String ruta : List.of("/api/empresas/mia", "/api/obras", "/api/materiales", "/api/usuarios", "/api/herramientas")) {
            HttpResponse<String> r = get(ruta, tokenAdmin);
            assertThat(r.statusCode()).as(ruta).isEqualTo(403);
            assertThat(json.readTree(r.body()).get("codigo").asString()).as(ruta).isEqualTo("EMPRESA_SUSPENDIDA");
        }
        assertThat(enviar("PUT", "/api/auth/pin", tokenAdmin, "{\"pinActual\":\"x\",\"pinNuevo\":\"yyyyyyyy\"}")
                .statusCode()).isEqualTo(403);
    }

    @Test
    void laSuspensionCierraElPoolYQuedaEnElCatalogo() throws Exception {
        assertThat(resolutor.conoce(empresaId)).isTrue();

        suspender(empresaId);

        assertThat(resolutor.conoce(empresaId)).isFalse();
        assertThat(catalogo.listar()).filteredOn(e -> e.id() == empresaId).singleElement()
                .satisfies(e -> assertThat(e.estado()).isEqualTo("SUSPENDIDA"));
    }

    @Test
    void unAdminSuspendidoNoPuedeEntrarDeNuevo() throws Exception {
        suspender(empresaId);

        HttpResponse<String> login = enviar("POST", "/api/auth/login", null,
                "{\"email\":\"" + correoAdmin + "\",\"pin\":\"" + CLAVE_ADMIN + "\"}");

        // Igual que una cuenta inexistente: no se abre la base de una empresa suspendida.
        assertThat(login.statusCode()).isEqualTo(400);
    }

    @Test
    void lasDemasEmpresasNoSeAfectan() throws Exception {
        String rut = rutNuevo();
        String correo = "otro-" + UUID.randomUUID().toString().substring(0, 10) + "@constructora.cl";
        HttpResponse<String> alta = enviar("POST", "/api/plataforma/empresas", tokenOperador,
                "{\"rut\":\"" + rut + "\",\"nombre\":\"Otra\",\"adminEmail\":\"" + correo
                        + "\",\"adminClave\":\"clave-inicial-1234\"}");
        long otra = json.readTree(alta.body()).get("id").asLong();
        String tokenOtra = json.readTree(enviar("POST", "/api/auth/login", null,
                "{\"email\":\"" + correo + "\",\"pin\":\"clave-inicial-1234\"}").body()).get("token").asString();

        suspender(empresaId);

        assertThat(resolutor.conoce(otra)).isTrue();
        // Su admin tiene que cambiar la clave primero (403 con otro código), no está suspendida.
        HttpResponse<String> r = get("/api/empresas/mia", tokenOtra);
        assertThat(json.readTree(r.body()).get("codigo").asString()).isEqualTo("DEBE_CAMBIAR_PIN");
    }

    @Test
    void reactivarLaDevuelveAComoEstaba() throws Exception {
        suspender(empresaId);
        assertThat(get("/api/empresas/mia", tokenAdmin).statusCode()).isEqualTo(403);

        HttpResponse<String> r = cambiarEstado(empresaId, "ACTIVA");

        assertThat(r.statusCode()).isEqualTo(200);
        assertThat(resolutor.conoce(empresaId)).isTrue();
        assertThat(get("/api/empresas/mia", tokenAdmin).statusCode()).isEqualTo(200);
    }

    @Test
    void suspenderDosVecesEsIdempotente() throws Exception {
        assertThat(suspender(empresaId).statusCode()).isEqualTo(200);
        assertThat(suspender(empresaId).statusCode()).isEqualTo(200);
        assertThat(cambiarEstado(empresaId, "ACTIVA").statusCode()).isEqualTo(200);
        assertThat(cambiarEstado(empresaId, "ACTIVA").statusCode()).isEqualTo(200);
    }

    @Test
    void unaEmpresaQueNoExisteEsUn404YUnEstadoInvalidoUn400() throws Exception {
        assertThat(suspender(987_654_321L).statusCode()).isEqualTo(404);
        assertThat(cambiarEstado(empresaId, "BORRADA").statusCode()).isEqualTo(400);
        assertThat(cambiarEstado(empresaId, null).statusCode()).isEqualTo(400);
    }

    @Test
    void soloElOperadorDePlataformaPuedeCambiarElEstado() throws Exception {
        assertThat(enviar("PUT", "/api/plataforma/empresas/" + empresaId + "/estado", tokenAdmin,
                "{\"estado\":\"SUSPENDIDA\"}").statusCode()).isEqualTo(403);
        assertThat(enviar("PUT", "/api/plataforma/empresas/" + empresaId + "/estado", null,
                "{\"estado\":\"SUSPENDIDA\"}").statusCode()).isEqualTo(401);
        assertThat(resolutor.conoce(empresaId)).isTrue();
    }

    @Test
    void elListadoDePlataformaMuestraElEstado() throws Exception {
        suspender(empresaId);

        JsonNode lista = json.readTree(get("/api/plataforma/empresas", tokenOperador).body());

        boolean suspendida = false;
        for (JsonNode e : lista) {
            if (e.get("id").asLong() == empresaId) {
                suspendida = e.get("estado").asString().equals("SUSPENDIDA");
            }
        }
        assertThat(suspendida).isTrue();
    }

    // ---- soporte ------------------------------------------------------------------------------

    private String sesionDelAdmin() throws Exception {
        JsonNode login = json.readTree(enviar("POST", "/api/auth/login", null,
                "{\"email\":\"" + correoAdmin + "\",\"pin\":\"clave-inicial-1234\"}").body());
        JsonNode sesion = json.readTree(enviar("PUT", "/api/auth/pin", login.get("token").asString(),
                "{\"pinActual\":\"clave-inicial-1234\",\"pinNuevo\":\"" + CLAVE_ADMIN + "\"}").body());
        return sesion.get("token").asString();
    }

    private HttpResponse<String> suspender(long id) throws Exception {
        return cambiarEstado(id, "SUSPENDIDA");
    }

    private HttpResponse<String> cambiarEstado(long id, String estado) throws Exception {
        return enviar("PUT", "/api/plataforma/empresas/" + id + "/estado", tokenOperador,
                estado == null ? "{}" : "{\"estado\":\"" + estado + "\"}");
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

    private HttpResponse<String> get(String ruta, String jwt) throws Exception {
        return enviar("GET", ruta, jwt, null);
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
