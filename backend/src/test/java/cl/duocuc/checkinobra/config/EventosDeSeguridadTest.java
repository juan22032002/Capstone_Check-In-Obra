package cl.duocuc.checkinobra.config;

import ch.qos.logback.classic.Level;
import ch.qos.logback.classic.Logger;
import ch.qos.logback.classic.spi.ILoggingEvent;
import ch.qos.logback.core.read.ListAppender;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.server.LocalServerPort;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.json.JsonMapper;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.util.List;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * SEG10 (#98, S-24): los eventos de seguridad quedan registrados con el id del usuario y sin
 * ningún secreto: ni la clave, ni el token, ni el correo.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT,
        properties = "checkinobra.login.ip.max-fallos=100000")
class EventosDeSeguridadTest {

    private static final String CLAVE_ADMIN = "clave-secreta-del-admin-9";
    private static final String CLAVE_MALA = "clave-equivocada-77";

    @LocalServerPort private int puerto;
    @Autowired private EmpresaRepository empresaRepository;
    @Autowired private UsuarioRepository usuarioRepository;
    @Autowired private CatalogoDePrueba catalogoDePrueba;

    private final HttpClient http = HttpClient.newHttpClient();
    private final JsonMapper json = JsonMapper.builder().build();
    private final ListAppender<ILoggingEvent> registro = new ListAppender<>();
    private Logger logger;

    private Usuario admin;
    private Usuario bodeguero;

    @BeforeEach
    void escucharElLogger() {
        logger = (Logger) LoggerFactory.getLogger(EventosDeSeguridad.LOGGER);
        logger.setLevel(Level.INFO);
        registro.start();
        logger.addAppender(registro);

        String s = UUID.randomUUID().toString().substring(0, 8);
        Empresa empresa = empresaRepository.save(Empresa.builder().nombre("E " + s).rut("R-" + s).build());
        catalogoDePrueba.registrar(empresa);
        admin = usuario("admin-" + s, RolUsuario.ADMIN, empresa, CLAVE_ADMIN);
        bodeguero = usuario("bodega-" + s, RolUsuario.BODEGUERO, empresa, "clave-del-bodeguero-1");
    }

    @AfterEach
    void dejarDeEscuchar() {
        logger.detachAppender(registro);
        registro.stop();
    }

    private List<String> eventos() {
        return registro.list.stream().map(ILoggingEvent::getFormattedMessage).toList();
    }

    private boolean hay(String evento, String contiene) {
        return eventos().stream().anyMatch(m -> m.contains("evento=" + evento) && m.contains(contiene));
    }

    @Test
    void elLoginExitosoYElFallidoQuedanRegistradosConElIdDelUsuario() throws Exception {
        post("/api/auth/login", "{\"email\": \"" + admin.getEmail() + "\", \"pin\": \"" + CLAVE_MALA + "\"}", null);
        post("/api/auth/login", "{\"email\": \"" + admin.getEmail() + "\", \"pin\": \"" + CLAVE_ADMIN + "\"}", null);

        assertThat(hay("LOGIN_FALLO", "usuarioId=" + admin.getId())).isTrue();
        assertThat(hay("LOGIN_OK", "usuarioId=" + admin.getId())).isTrue();
        assertThat(hay("LOGIN_OK", "empresaId=" + admin.getEmpresa().getId())).isTrue();
    }

    @Test
    void unaCuentaQueNoExisteSeRegistraSinDecirQueNoExiste() throws Exception {
        post("/api/auth/login", "{\"email\": \"fantasma-" + UUID.randomUUID() + "@test.cl\", \"pin\": \"" + CLAVE_MALA + "\"}", null);

        assertThat(hay("LOGIN_FALLO", "usuarioId=desconocido")).isTrue();
    }

    @Test
    void elRestablecimientoDeClaveYLaAltaDeUsuarioQuedanRegistradas() throws Exception {
        String token = token(admin.getEmail(), CLAVE_ADMIN);
        String sufijo = UUID.randomUUID().toString().substring(0, 8);

        put("/api/usuarios/" + bodeguero.getId() + "/pin", "{\"nuevoPin\": \"nueva-clave-larga-55\"}", token);
        post("/api/usuarios", "{\"nombre\": \"Nuevo\", \"email\": \"nuevo-" + sufijo + "@test.cl\", \"rut\": \""
                + rutValido() + "\", \"rol\": \"BODEGUERO\", \"pinInicial\": \"clave-inicial-larga-1\"}", token);

        assertThat(hay("CLAVE_RESTABLECIDA", "actorId=" + admin.getId())).isTrue();
        assertThat(hay("CLAVE_RESTABLECIDA", "usuarioId=" + bodeguero.getId())).isTrue();
        assertThat(hay("USUARIO_CREADO", "actorId=" + admin.getId())).isTrue();
    }

    @Test
    void unRolQueNoAlcanzaQuedaRegistradoComoAccesoDenegado() throws Exception {
        String token = token(bodeguero.getEmail(), "clave-del-bodeguero-1");

        HttpResponse<String> r = get("/api/usuarios", token);

        assertThat(r.statusCode()).isEqualTo(403);
        assertThat(hay("ACCESO_DENEGADO", "usuarioId=" + bodeguero.getId())).isTrue();
        assertThat(hay("ACCESO_DENEGADO", "ruta=/api/usuarios")).isTrue();
    }

    @Test
    void elRegistroNuncaLlevaClavesTokensNiCorreos() throws Exception {
        post("/api/auth/login", "{\"email\": \"" + admin.getEmail() + "\", \"pin\": \"" + CLAVE_MALA + "\"}", null);
        JsonNode sesion = json.readTree(post("/api/auth/login",
                "{\"email\": \"" + admin.getEmail() + "\", \"pin\": \"" + CLAVE_ADMIN + "\"}", null).body());
        String token = sesion.get("token").asString();
        put("/api/usuarios/" + bodeguero.getId() + "/pin", "{\"nuevoPin\": \"nueva-clave-larga-55\"}", token);
        // El bodeguero entra con su clave nueva y toca algo que su rol no permite: queda un 403 registrado.
        get("/api/usuarios", token(bodeguero.getEmail(), "nueva-clave-larga-55"));

        String todo = String.join("\n", eventos());

        assertThat(eventos()).isNotEmpty();
        assertThat(todo)
                .doesNotContain(CLAVE_ADMIN).doesNotContain(CLAVE_MALA).doesNotContain("nueva-clave-larga-55")
                .doesNotContain(token).doesNotContain(sesion.get("refreshToken").asString())
                .doesNotContain(admin.getEmail()).doesNotContain(bodeguero.getEmail())
                .doesNotContain("eyJ");
    }

    // ---------------------------------------------------------------------------------------------

    private Usuario usuario(String nombre, RolUsuario rol, Empresa empresa, String clave) {
        Usuario u = Usuario.builder().nombre(nombre).email(nombre + "@test.cl").rol(rol).empresa(empresa).build();
        u.definirPin(clave);
        Usuario guardado = usuarioRepository.save(u);
        catalogoDePrueba.indexar(guardado);
        return guardado;
    }

    private static String rutValido() {
        String cuerpo = String.valueOf(10_000_000 + (long) (Math.random() * 80_000_000));
        return cuerpo + "-" + Rut.digitoVerificador(cuerpo);
    }

    private String token(String email, String clave) throws Exception {
        return json.readTree(post("/api/auth/login", "{\"email\": \"" + email + "\", \"pin\": \"" + clave + "\"}", null).body())
                .get("token").asString();
    }

    private HttpResponse<String> get(String ruta, String token) throws Exception {
        return enviar("GET", ruta, null, token);
    }

    private HttpResponse<String> put(String ruta, String cuerpo, String token) throws Exception {
        return enviar("PUT", ruta, cuerpo, token);
    }

    private HttpResponse<String> post(String ruta, String cuerpo, String token) throws Exception {
        return enviar("POST", ruta, cuerpo, token);
    }

    private HttpResponse<String> enviar(String metodo, String ruta, String cuerpo, String token) throws Exception {
        HttpRequest.Builder b = HttpRequest.newBuilder(URI.create("http://localhost:" + puerto + ruta))
                .header("Content-Type", "application/json");
        if (token != null) {
            b.header("Authorization", "Bearer " + token);
        }
        b.method(metodo, cuerpo == null ? HttpRequest.BodyPublishers.noBody() : HttpRequest.BodyPublishers.ofString(cuerpo));
        return http.send(b.build(), HttpResponse.BodyHandlers.ofString());
    }
}
