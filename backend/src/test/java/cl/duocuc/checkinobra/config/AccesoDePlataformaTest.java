package cl.duocuc.checkinobra.config;

import io.jsonwebtoken.Claims;
import io.jsonwebtoken.Jwts;
import io.jsonwebtoken.security.Keys;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.server.LocalServerPort;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.json.JsonMapper;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.util.Date;
import java.util.List;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * MT6 (#109): el operador de plataforma entra por su propio login, con un token sin empresa, y
 * solo llega a {@code /api/plataforma/**}. Un token de empresa no llega ahí, y uno de plataforma
 * no llega a ninguna ruta de empresa.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class AccesoDePlataformaTest {

    private static final String CLAVE = "clave-del-operador-9";

    @LocalServerPort private int puerto;
    @Value("${checkinobra.jwt.secret}") private String secreto;

    @Autowired private EmpresaRepository empresaRepository;
    @Autowired private UsuarioRepository usuarioRepository;
    @Autowired private CatalogoDePrueba catalogoDePrueba;
    @Autowired private CatalogoDeEmpresas catalogo;
    @Autowired private JwtService jwtService;

    private final HttpClient http = HttpClient.newHttpClient();
    private final JsonMapper json = JsonMapper.builder().build();

    private String correoOperador;
    private long operadorId;
    private Usuario admin;

    @BeforeEach
    void prepararOperadorYEmpresa() {
        String s = UUID.randomUUID().toString().substring(0, 8);
        correoOperador = "operador-" + s + "@plataforma.cl";
        operadorId = catalogoDePrueba.operador(correoOperador, CLAVE);
        Empresa empresa = empresaRepository.save(Empresa.builder().nombre("E " + s).rut("R-" + s).build());
        catalogoDePrueba.registrar(empresa);
        Usuario u = Usuario.builder().nombre("admin-" + s).email("admin-" + s + "@test.cl")
                .rol(RolUsuario.ADMIN).empresa(empresa).build();
        u.definirPin("clave-del-admin-123");
        admin = usuarioRepository.save(u);
    }

    // ---- el login y la forma del token --------------------------------------------------------

    @Test
    void elOperadorEntraYSuTokenNoLlevaEmpresa() throws Exception {
        HttpResponse<String> r = loginOperador(correoOperador, CLAVE);

        assertThat(r.statusCode()).isEqualTo(200);
        Claims claims = jwtService.validarYExtraer(json.readTree(r.body()).get("token").asString());
        assertThat(claims.get("rol", String.class)).isEqualTo("PLATAFORMA");
        assertThat(claims.getSubject()).isEqualTo(String.valueOf(operadorId));
        assertThat(claims.containsKey("empresaId")).isFalse();
        assertThat(claims.getIssuer()).isEqualTo(JwtService.EMISOR);
    }

    @Test
    void unaClaveEquivocadaYUnCorreoInexistenteDanLaMismaRespuesta() throws Exception {
        HttpResponse<String> mala = loginOperador(correoOperador, "no-es-la-clave-123");
        HttpResponse<String> inexistente = loginOperador("nadie-" + UUID.randomUUID() + "@plataforma.cl", CLAVE);

        // 400, como el login de empresa: la app distingue "credenciales" por el mensaje, no por el estado.
        assertThat(mala.statusCode()).isEqualTo(400);
        assertThat(inexistente.statusCode()).isEqualTo(400);
        assertThat(json.readTree(mala.body()).get("mensaje")).isEqualTo(json.readTree(inexistente.body()).get("mensaje"));
    }

    @Test
    void unOperadorQueLoGolpeanSeBloqueaIgualQueUnaCuenta() throws Exception {
        for (int i = 0; i < 5; i++) {
            loginOperador(correoOperador, "no-es-la-clave-" + i);
        }

        HttpResponse<String> conLaCorrecta = loginOperador(correoOperador, CLAVE);

        assertThat(conLaCorrecta.statusCode()).isEqualTo(429);
        assertThat(conLaCorrecta.headers().firstValue("Retry-After")).isPresent();
    }

    @Test
    void elLoginDePlataformaNoDependeDeUnaEmpresaNiDeLaIdempotencia() throws Exception {
        // Una cabecera Idempotency-Key haría que el filtro de idempotencia abriera la base de una
        // empresa; en plataforma no hay ninguna en el contexto.
        HttpRequest r = HttpRequest.newBuilder(URI.create(url("/api/plataforma/auth/login")))
                .header("Content-Type", "application/json").header("Idempotency-Key", UUID.randomUUID().toString())
                .POST(HttpRequest.BodyPublishers.ofString(cuerpoLogin(correoOperador, CLAVE))).build();

        assertThat(http.send(r, HttpResponse.BodyHandlers.ofString()).statusCode()).isEqualTo(200);
    }

    // ---- quién llega adónde -------------------------------------------------------------------

    @Test
    void elOperadorLlegaASusRutas() throws Exception {
        String token = tokenOperador();

        HttpResponse<String> yo = get("/api/plataforma/yo", token);
        HttpResponse<String> empresas = get("/api/plataforma/empresas", token);

        assertThat(yo.statusCode()).isEqualTo(200);
        assertThat(json.readTree(yo.body()).get("email").asString()).isEqualTo(correoOperador);
        assertThat(empresas.statusCode()).isEqualTo(200);
        assertThat(json.readTree(empresas.body()).isArray()).isTrue();
        // Lo que sirve para operar, no para entrar a una base: ni usuario de base ni referencia al secreto.
        assertThat(empresas.body()).doesNotContain("secreto").doesNotContain("usuarioBase");
    }

    @Test
    void sinTokenLasRutasDePlataformaDan401() throws Exception {
        assertThat(get("/api/plataforma/yo", null).statusCode()).isEqualTo(401);
        assertThat(get("/api/plataforma/empresas", null).statusCode()).isEqualTo(401);
    }

    @Test
    void unTokenDeEmpresaNoLlegaALasRutasDePlataforma() throws Exception {
        String token = jwtService.emitir(admin);

        for (String ruta : List.of("/api/plataforma/yo", "/api/plataforma/empresas")) {
            assertThat(get(ruta, token).statusCode()).as(ruta).isEqualTo(403);
        }
    }

    @Test
    void unTokenDePlataformaNoLlegaANingunaRutaDeEmpresa() throws Exception {
        String token = tokenOperador();

        for (String ruta : List.of("/api/obras", "/api/materiales", "/api/usuarios", "/api/herramientas",
                "/api/trabajadores/yo", "/api/kardex?obraId=1", "/api/presupuestos?obraId=1", "/api/empresas")) {
            assertThat(get(ruta, token).statusCode()).as(ruta).isEqualTo(403);
        }
        // También las rutas que solo piden "estar autenticado", sin rol.
        assertThat(enviar("PUT", "/api/auth/pin", token, "{\"pinActual\":\"x\",\"pinNuevo\":\"yyyyyyyy\"}")
                .statusCode()).isEqualTo(403);
    }

    @Test
    void unRolDeEmpresaNuncaPuedeSerPlataforma() throws Exception {
        String token = jwtService.emitir(admin);

        HttpResponse<String> r = enviar("POST", "/api/usuarios", token,
                "{\"nombre\":\"Intruso\",\"email\":\"intruso-" + UUID.randomUUID() + "@test.cl\","
                        + "\"rut\":\"11111111-1\",\"rol\":\"PLATAFORMA\",\"pinInicial\":\"clave-larga-123\"}");

        assertThat(r.statusCode()).isIn(400, 403);
    }

    // ---- la validación del token --------------------------------------------------------------

    @Test
    void unTokenDeEmpresaSinEmpresaEsUn401YNoUn500() throws Exception {
        String sinEmpresa = firmado("ADMIN", String.valueOf(admin.getId()), null, 0);

        assertThat(get("/api/obras", sinEmpresa).statusCode()).isEqualTo(401);
        assertThat(get("/api/plataforma/yo", sinEmpresa).statusCode()).isEqualTo(401);
    }

    @Test
    void unTokenDePlataformaConEmpresaEsInvalido() throws Exception {
        String mezclado = firmado("PLATAFORMA", String.valueOf(operadorId), admin.getEmpresa().getId(), 0);

        assertThat(get("/api/plataforma/yo", mezclado).statusCode()).isEqualTo(401);
    }

    @Test
    void unOperadorDesactivadoOConSesionesInvalidadasPierdeSuToken() throws Exception {
        String token = tokenOperador();
        assertThat(get("/api/plataforma/yo", token).statusCode()).isEqualTo(200);

        catalogo.invalidarSesionesDeOperador(operadorId);
        assertThat(get("/api/plataforma/yo", token).statusCode()).isEqualTo(401);

        String nuevo = tokenOperador();
        assertThat(get("/api/plataforma/yo", nuevo).statusCode()).isEqualTo(200);
        catalogo.desactivarOperador(operadorId);
        assertThat(get("/api/plataforma/yo", nuevo).statusCode()).isEqualTo(401);
        assertThat(loginOperador(correoOperador, CLAVE).statusCode()).isEqualTo(400);
    }

    @Test
    void unTokenDePlataformaDeUnOperadorQueNoExisteNoEntra() throws Exception {
        String inventado = firmado("PLATAFORMA", "999999999", null, 0);

        assertThat(get("/api/plataforma/yo", inventado).statusCode()).isEqualTo(401);
    }

    // ---- soporte ------------------------------------------------------------------------------

    private String tokenOperador() throws Exception {
        return json.readTree(loginOperador(correoOperador, CLAVE).body()).get("token").asString();
    }

    private String firmado(String rol, String sujeto, Long empresaId, int version) {
        var b = Jwts.builder().subject(sujeto).claim("email", "x@x.cl").claim("rol", rol).claim("tv", version)
                .issuer(JwtService.EMISOR).audience().add(JwtService.AUDIENCIA).and()
                .issuedAt(new Date()).expiration(new Date(System.currentTimeMillis() + 60_000));
        if (empresaId != null) {
            b.claim("empresaId", empresaId);
        }
        return b.signWith(Keys.hmacShaKeyFor(secreto.getBytes(StandardCharsets.UTF_8))).compact();
    }

    private static String cuerpoLogin(String email, String clave) {
        return "{\"email\": \"" + email + "\", \"clave\": \"" + clave + "\"}";
    }

    private HttpResponse<String> loginOperador(String email, String clave) throws Exception {
        return enviar("POST", "/api/plataforma/auth/login", null, cuerpoLogin(email, clave));
    }

    private HttpResponse<String> get(String ruta, String token) throws Exception {
        return enviar("GET", ruta, token, null);
    }

    private String url(String ruta) {
        return "http://localhost:" + puerto + ruta;
    }

    private HttpResponse<String> enviar(String metodo, String ruta, String token, String cuerpo) throws Exception {
        HttpRequest.Builder b = HttpRequest.newBuilder(URI.create(url(ruta))).header("Content-Type", "application/json");
        if (token != null) {
            b.header("Authorization", "Bearer " + token);
        }
        b.method(metodo, cuerpo == null ? HttpRequest.BodyPublishers.noBody() : HttpRequest.BodyPublishers.ofString(cuerpo));
        return http.send(b.build(), HttpResponse.BodyHandlers.ofString());
    }
}
