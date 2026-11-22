package cl.duocuc.checkinobra.config;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.server.LocalServerPort;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.json.JsonMapper;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * SEG3 (#91, S-03): el administrador inicial no entra con un PIN publicado.
 *
 * <p>Tres capas: (1) la migración V11 anula la credencial {@code 0000} que
 * sembraba V2, porque quien la conociera del README podía entrar, cambiarla y
 * quedarse con la cuenta; (2) el primer administrador recibe su clave de una
 * variable de entorno, y queda obligado a cambiarla; (3) mientras no la
 * cambie, solo puede llamar a {@code PUT /api/auth/pin}.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class AdminInicialTest {

    private static final String CLAVE_INICIAL = "clave-inicial-de-arranque";
    private static final String CLAVE_NUEVA = "mi-clave-nueva-y-larga-7";

    @LocalServerPort
    private int puerto;

    @Autowired private EmpresaRepository empresaRepository;
    @Autowired private UsuarioRepository usuarioRepository;
    @Autowired private PrimerAdminService primerAdminService;
    @Autowired private CatalogoDePrueba catalogoDePrueba;

    private final HttpClient http = HttpClient.newHttpClient();
    private final JsonMapper json = JsonMapper.builder().build();

    private String s;
    private Usuario admin;

    @BeforeEach
    void crearAdminSinCredencial() {
        s = UUID.randomUUID().toString().substring(0, 8);
        Empresa empresa = empresaRepository.save(Empresa.builder().nombre("Empresa " + s).rut("R-" + s).build());
        catalogoDePrueba.registrar(empresa);
        admin = usuarioRepository.save(Usuario.builder()
                .nombre("admin-" + s).email("admin-" + s + "@test.cl").rol(RolUsuario.ADMIN).empresa(empresa).build());
        catalogoDePrueba.indexar(admin);
    }

    // --- el seed publicado ------------------------------------------------------

    @Test
    void elAdminSemillaYaNoEntraConElPinPublicadoEnElReadme() throws Exception {
        HttpResponse<String> r = loginCorreo("admin@arauco-ltda.cl", "0000");

        assertThat(r.statusCode()).isEqualTo(400);
    }

    // --- el primer administrador ------------------------------------------------

    @Test
    void sinClaveInicialElAdminSinCredencialNoPuedeEntrar() throws Exception {
        assertThat(loginCorreo(admin.getEmail(), "").statusCode()).isEqualTo(400);
        assertThat(loginCorreo(admin.getEmail(), "0000").statusCode()).isEqualTo(400);
    }

    @Test
    void laClaveInicialSoloSeFijaAUnAdminSinCredencial() {
        assertThat(primerAdminService.fijarClaveInicial(admin.getEmail(), CLAVE_INICIAL)).isTrue();

        // Ya tiene credencial: reiniciar la API con la variable puesta no la pisa.
        assertThat(primerAdminService.fijarClaveInicial(admin.getEmail(), "otra-clave-distinta-1")).isFalse();
    }

    @Test
    void laClaveInicialNoTocaAUsuariosQueNoSonAdminNiCuentasInexistentes() {
        Usuario bodeguero = usuarioRepository.save(Usuario.builder()
                .nombre("bodega-" + s).email("bodega-" + s + "@test.cl")
                .rol(RolUsuario.BODEGUERO).empresa(admin.getEmpresa()).build());

        assertThat(primerAdminService.fijarClaveInicial(bodeguero.getEmail(), CLAVE_INICIAL)).isFalse();
        assertThat(primerAdminService.fijarClaveInicial("nadie-" + s + "@test.cl", CLAVE_INICIAL)).isFalse();
        assertThat(usuarioRepository.findById(bodeguero.getId()).orElseThrow().getPinHash()).isNull();
    }

    @Test
    void unMarcadorDeEjemploNuncaSeAplicaComoClaveInicial() {
        assertThatThrownBy(() -> primerAdminService.fijarClaveInicial(admin.getEmail(), "CAMBIAR_generar_una_clave"))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("ejemplo");
        assertThat(usuarioRepository.findById(admin.getId()).orElseThrow().getPinHash()).isNull();
    }

    @Test
    void laClaveInicialDebeCumplirLaPoliticaDeClaves() {
        assertThatThrownBy(() -> primerAdminService.fijarClaveInicial(admin.getEmail(), "1234"))
                .isInstanceOf(IllegalArgumentException.class);
        assertThat(usuarioRepository.findById(admin.getId()).orElseThrow().getPinHash()).isNull();
    }

    // --- obligación de cambiarla --------------------------------------------------

    @Test
    void conLaClaveInicialElAdminSoloPuedeCambiarla() throws Exception {
        primerAdminService.fijarClaveInicial(admin.getEmail(), CLAVE_INICIAL);

        HttpResponse<String> login = loginCorreo(admin.getEmail(), CLAVE_INICIAL);
        assertThat(login.statusCode()).isEqualTo(200);
        JsonNode sesion = json.readTree(login.body());
        assertThat(sesion.get("debeCambiarClave").asBoolean()).isTrue();
        String token = sesion.get("token").asString();

        for (String ruta : new String[] {"/api/obras", "/api/usuarios", "/api/materiales", "/api/empresas/mia"}) {
            HttpResponse<String> r = get(ruta, token);

            assertThat(r.statusCode()).as(ruta).isEqualTo(403);
            assertThat(json.readTree(r.body()).get("codigo").asString()).as(ruta).isEqualTo("DEBE_CAMBIAR_PIN");
        }
        assertThat(put("/api/usuarios/" + admin.getId() + "/pin", "{\"nuevoPin\": \"" + CLAVE_NUEVA + "\"}", token)
                .statusCode()).isEqualTo(403);
    }

    @Test
    void cambiarLaClaveLiberaLaCuentaYDaUnTokenNuevo() throws Exception {
        primerAdminService.fijarClaveInicial(admin.getEmail(), CLAVE_INICIAL);
        String tokenViejo = token(loginCorreo(admin.getEmail(), CLAVE_INICIAL));

        HttpResponse<String> cambio = cambiarPin(tokenViejo, CLAVE_INICIAL, CLAVE_NUEVA);

        assertThat(cambio.statusCode()).isEqualTo(200);
        JsonNode sesion = json.readTree(cambio.body());
        assertThat(sesion.get("debeCambiarClave").asBoolean()).isFalse();
        assertThat(get("/api/obras", sesion.get("token").asString()).statusCode()).isEqualTo(200);

        // La clave inicial ya no vale; la nueva entra sin la obligación.
        assertThat(loginCorreo(admin.getEmail(), CLAVE_INICIAL).statusCode()).isEqualTo(400);
        JsonNode otroLogin = json.readTree(loginCorreo(admin.getEmail(), CLAVE_NUEVA).body());
        assertThat(otroLogin.get("debeCambiarClave").asBoolean()).isFalse();
    }

    @Test
    void elCambioExigeLaClaveActualYUnaNuevaValida() throws Exception {
        primerAdminService.fijarClaveInicial(admin.getEmail(), CLAVE_INICIAL);
        String token = token(loginCorreo(admin.getEmail(), CLAVE_INICIAL));

        assertThat(cambiarPin(token, "no-es-la-clave-actual", CLAVE_NUEVA).statusCode()).isEqualTo(400);
        assertThat(cambiarPin(token, CLAVE_INICIAL, "corta").statusCode()).isEqualTo(400);
        assertThat(cambiarPin(token, CLAVE_INICIAL, CLAVE_INICIAL).statusCode()).isEqualTo(400);
        assertThat(cambiarPin(token, CLAVE_INICIAL, "0000").statusCode()).isEqualTo(400);

        // Nada cambió: la inicial sigue valiendo y sigue obligada.
        assertThat(json.readTree(loginCorreo(admin.getEmail(), CLAVE_INICIAL).body())
                .get("debeCambiarClave").asBoolean()).isTrue();
    }

    @Test
    void sinTokenElCambioDeClaveEs401() throws Exception {
        HttpRequest r = HttpRequest.newBuilder(URI.create("http://localhost:" + puerto + "/api/auth/pin"))
                .header("Content-Type", "application/json")
                .PUT(HttpRequest.BodyPublishers.ofString("{\"pinActual\": \"x\", \"pinNuevo\": \"y\"}")).build();

        assertThat(http.send(r, HttpResponse.BodyHandlers.ofString()).statusCode()).isEqualTo(401);
    }

    @Test
    void unUsuarioSinObligacionTambienPuedeCambiarSuPropiaClave() throws Exception {
        admin.definirPin("clave-vigente-del-admin");
        usuarioRepository.save(admin);
        String token = token(loginCorreo(admin.getEmail(), "clave-vigente-del-admin"));

        HttpResponse<String> cambio = cambiarPin(token, "clave-vigente-del-admin", CLAVE_NUEVA);

        assertThat(cambio.statusCode()).isEqualTo(200);
        assertThat(loginCorreo(admin.getEmail(), CLAVE_NUEVA).statusCode()).isEqualTo(200);
    }

    @Test
    void definirUnaClaveNuevaLimpiaLaObligacion() {
        admin.definirPin(CLAVE_INICIAL);
        admin.setDebeCambiarPin(true);
        admin.definirPin(CLAVE_NUEVA);

        assertThat(admin.isDebeCambiarPin()).isFalse();
    }

    // ---------------------------------------------------------------------

    private String token(HttpResponse<String> login) {
        return json.readTree(login.body()).get("token").asString();
    }

    private HttpResponse<String> loginCorreo(String email, String clave) throws Exception {
        String cuerpo = "{\"email\": \"%s\", \"pin\": \"%s\"}".formatted(email, clave);
        return enviar(HttpRequest.newBuilder(URI.create("http://localhost:" + puerto + "/api/auth/login"))
                .header("Content-Type", "application/json").POST(HttpRequest.BodyPublishers.ofString(cuerpo)));
    }

    private HttpResponse<String> cambiarPin(String token, String actual, String nueva) throws Exception {
        return put("/api/auth/pin", "{\"pinActual\": \"%s\", \"pinNuevo\": \"%s\"}".formatted(actual, nueva), token);
    }

    private HttpResponse<String> get(String ruta, String token) throws Exception {
        return enviar(HttpRequest.newBuilder(URI.create("http://localhost:" + puerto + ruta))
                .header("Authorization", "Bearer " + token).GET());
    }

    private HttpResponse<String> put(String ruta, String cuerpo, String token) throws Exception {
        return enviar(HttpRequest.newBuilder(URI.create("http://localhost:" + puerto + ruta))
                .header("Authorization", "Bearer " + token).header("Content-Type", "application/json")
                .PUT(HttpRequest.BodyPublishers.ofString(cuerpo)));
    }

    private HttpResponse<String> enviar(HttpRequest.Builder peticion) throws Exception {
        return http.send(peticion.build(), HttpResponse.BodyHandlers.ofString());
    }
}
