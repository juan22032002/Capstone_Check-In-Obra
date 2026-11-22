package cl.duocuc.checkinobra.config;

import io.jsonwebtoken.Jwts;
import io.jsonwebtoken.security.Keys;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.server.LocalServerPort;
import org.springframework.jdbc.core.JdbcTemplate;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.json.JsonMapper;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.util.Date;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * SEG10 (#98, S-11): el token no se confía por completo hasta vencer. Lleva emisor y audiencia,
 * dura poco, se revalida contra la versión de sesión del usuario en cada petición, y se renueva
 * con un refresh token que rota y que, si se reutiliza, cierra todas las sesiones.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT,
        properties = "checkinobra.login.ip.max-fallos=100000")
class SesionYTokensTest {

    private static final String CLAVE_ADMIN = "clave-del-admin-123";
    private static final String CLAVE_OBRERO = "4821";

    @LocalServerPort private int puerto;
    @Autowired private EmpresaRepository empresaRepository;
    @Autowired private UsuarioRepository usuarioRepository;
    @Autowired private CatalogoDePrueba catalogoDePrueba;
    @Autowired private JwtService jwtService;
    @Autowired private JdbcTemplate jdbc;
    @Value("${checkinobra.jwt.secret}") private String secreto;

    private final HttpClient http = HttpClient.newHttpClient();
    private final JsonMapper json = JsonMapper.builder().build();

    private Empresa empresa;
    private Usuario admin;
    private Usuario obrero;

    @BeforeEach
    void prepararUsuarios() {
        String s = UUID.randomUUID().toString().substring(0, 8);
        empresa = empresaRepository.save(Empresa.builder().nombre("E " + s).rut("R-" + s).build());
        catalogoDePrueba.registrar(empresa);
        admin = usuario("admin-" + s, RolUsuario.ADMIN, CLAVE_ADMIN);
        obrero = usuario("obrero-" + s, RolUsuario.TRABAJADOR, CLAVE_OBRERO);
    }

    // --- emisor, audiencia y vida del token ---------------------------------------------------

    @Test
    void elTokenLlevaEmisorAudienciaYDuraPoco() throws Exception {
        String token = login(admin.getEmail(), CLAVE_ADMIN).get("token").asString();

        var claims = jwtService.validarYExtraer(token);

        assertThat(claims.getIssuer()).isEqualTo("checkinobra");
        assertThat(claims.getAudience()).containsExactly("checkinobra-api");
        long minutos = (claims.getExpiration().getTime() - claims.getIssuedAt().getTime()) / 60_000;
        // Antes duraba 8 horas (480 min).
        assertThat(minutos).isLessThanOrEqualTo(60);
    }

    @Test
    void unTokenFirmadoPeroSinEmisorONiAudienciaCorrectosNoEntra() throws Exception {
        assertThat(get("/api/obras", firmado(admin, null, null, 0)).statusCode()).isEqualTo(401);
        assertThat(get("/api/obras", firmado(admin, "otro-servicio", "checkinobra-api", 0)).statusCode()).isEqualTo(401);
        assertThat(get("/api/obras", firmado(admin, "checkinobra", "otra-audiencia", 0)).statusCode()).isEqualTo(401);
        // Control: con todo en regla, el mismo token entra.
        assertThat(get("/api/obras", firmado(admin, "checkinobra", "checkinobra-api", 0)).statusCode()).isEqualTo(200);
    }

    @Test
    void unTokenSinVersionDeSesionNoEntra() throws Exception {
        assertThat(get("/api/obras", firmado(admin, "checkinobra", "checkinobra-api", null)).statusCode())
                .isEqualTo(401);
    }

    @Test
    void unTokenFirmadoDeUnUsuarioQueNoExisteNoEntra() throws Exception {
        Usuario fantasma = Usuario.builder().id(987_654_321L).nombre("x").email("x@x.cl").rol(RolUsuario.ADMIN)
                .empresa(empresa).build();

        assertThat(get("/api/obras", firmado(fantasma, "checkinobra", "checkinobra-api", 0)).statusCode())
                .isEqualTo(401);
    }

    // --- la versión de sesión -----------------------------------------------------------------

    @Test
    void restablecerLaClaveDeUnUsuarioInvalidaSusTokensYSusRefresh() throws Exception {
        JsonNode sesion = login(obrero.getEmail(), CLAVE_OBRERO);
        String token = sesion.get("token").asString();
        String refresh = sesion.get("refreshToken").asString();
        assertThat(get("/api/materiales", token).statusCode()).isEqualTo(200);
        String tokenAdmin = login(admin.getEmail(), CLAVE_ADMIN).get("token").asString();

        HttpResponse<String> reset = put("/api/usuarios/" + obrero.getId() + "/pin", "{\"nuevoPin\": \"1357\"}", tokenAdmin);

        assertThat(reset.statusCode()).isEqualTo(200);
        assertThat(get("/api/materiales", token).statusCode()).isEqualTo(401);
        assertThat(post("/api/auth/refresh", "{\"refreshToken\": \"" + refresh + "\"}", null).statusCode()).isEqualTo(401);
        // La clave nueva sí entra, con una sesión nueva.
        assertThat(login(obrero.getEmail(), "1357").get("token").asString()).isNotBlank();
    }

    @Test
    void cambiarLaPropiaClaveCierraLasOtrasSesionesPeroNoLaNueva() throws Exception {
        String t1 = login(admin.getEmail(), CLAVE_ADMIN).get("token").asString();
        String t2 = login(admin.getEmail(), CLAVE_ADMIN).get("token").asString();

        HttpResponse<String> cambio = put("/api/auth/pin",
                "{\"pinActual\": \"" + CLAVE_ADMIN + "\", \"pinNuevo\": \"otra-clave-larga-456\"}", t1);

        assertThat(cambio.statusCode()).isEqualTo(200);
        String nuevo = json.readTree(cambio.body()).get("token").asString();
        assertThat(get("/api/obras", nuevo).statusCode()).isEqualTo(200);
        assertThat(get("/api/obras", t1).statusCode()).isEqualTo(401);
        assertThat(get("/api/obras", t2).statusCode()).isEqualTo(401);
    }

    // --- refresh tokens ------------------------------------------------------------------------

    @Test
    void refrescarDaUnParNuevoYElAnteriorYaNoSirve() throws Exception {
        String refresh = login(admin.getEmail(), CLAVE_ADMIN).get("refreshToken").asString();

        HttpResponse<String> r = post("/api/auth/refresh", "{\"refreshToken\": \"" + refresh + "\"}", null);

        assertThat(r.statusCode()).isEqualTo(200);
        JsonNode nuevo = json.readTree(r.body());
        assertThat(get("/api/obras", nuevo.get("token").asString()).statusCode()).isEqualTo(200);
        assertThat(nuevo.get("refreshToken").asString()).isNotEqualTo(refresh);
        assertThat(nuevo.get("empresaId").asLong()).isEqualTo(empresa.getId());
        // El presentado quedó revocado.
        assertThat(post("/api/auth/refresh", "{\"refreshToken\": \"" + refresh + "\"}", null).statusCode())
                .isEqualTo(401);
    }

    @Test
    void reutilizarUnRefreshYaUsadoCierraTodasLasSesionesDelUsuario() throws Exception {
        String viejo = login(admin.getEmail(), CLAVE_ADMIN).get("refreshToken").asString();
        String vigente = json.readTree(post("/api/auth/refresh", "{\"refreshToken\": \"" + viejo + "\"}", null).body())
                .get("refreshToken").asString();

        // Quien tiene la copia robada presenta el viejo: se asume robo.
        assertThat(post("/api/auth/refresh", "{\"refreshToken\": \"" + viejo + "\"}", null).statusCode()).isEqualTo(401);

        // Y el que era legítimo también queda fuera: tiene que pedir la clave otra vez.
        assertThat(post("/api/auth/refresh", "{\"refreshToken\": \"" + vigente + "\"}", null).statusCode()).isEqualTo(401);
    }

    @Test
    void unRefreshVencidoNoSirveYElErrorNoDicePorQue() throws Exception {
        String refresh = login(admin.getEmail(), CLAVE_ADMIN).get("refreshToken").asString();
        jdbc.update("UPDATE refresh_tokens SET expira_en = now() - interval '1 minute' WHERE usuario_id = ?", admin.getId());

        HttpResponse<String> r = post("/api/auth/refresh", "{\"refreshToken\": \"" + refresh + "\"}", null);

        assertThat(r.statusCode()).isEqualTo(401);
        assertThat(json.readTree(r.body()).get("codigo").asString()).isEqualTo("SESION_INVALIDA");
    }

    @Test
    void unRefreshInventadoMalFormadoOUnTokenDeAccesoDanLoMismo() throws Exception {
        String accesoComoRefresh = login(admin.getEmail(), CLAVE_ADMIN).get("token").asString();
        for (String valor : new String[] {"inventado", empresa.getId() + ".inventado", "x.y", "." + "abc", accesoComoRefresh}) {
            HttpResponse<String> r = post("/api/auth/refresh", "{\"refreshToken\": \"" + valor + "\"}", null);

            assertThat(r.statusCode()).as(valor).isEqualTo(401);
            assertThat(json.readTree(r.body()).get("codigo").asString()).as(valor).isEqualTo("SESION_INVALIDA");
        }
    }

    @Test
    void cerrarSesionRevocaElRefreshYSiempreResponde204() throws Exception {
        String refresh = login(admin.getEmail(), CLAVE_ADMIN).get("refreshToken").asString();

        assertThat(post("/api/auth/logout", "{\"refreshToken\": \"" + refresh + "\"}", null).statusCode()).isEqualTo(204);
        assertThat(post("/api/auth/refresh", "{\"refreshToken\": \"" + refresh + "\"}", null).statusCode()).isEqualTo(401);
        // Con uno que no existe responde igual: no revela cuáles hay.
        assertThat(post("/api/auth/logout", "{\"refreshToken\": \"inventado\"}", null).statusCode()).isEqualTo(204);
    }

    @Test
    void elRefreshSeGuardaSoloComoHash() throws Exception {
        String refresh = login(admin.getEmail(), CLAVE_ADMIN).get("refreshToken").asString();
        String secretoDelRefresh = refresh.substring(refresh.indexOf('.') + 1);

        Integer enClaro = jdbc.queryForObject(
                "SELECT count(*) FROM refresh_tokens WHERE hash = ?", Integer.class, secretoDelRefresh);

        assertThat(enClaro).isZero();
        assertThat(jdbc.queryForObject("SELECT count(*) FROM refresh_tokens WHERE usuario_id = ? AND length(hash) = 64",
                Integer.class, admin.getId())).isEqualTo(1);
    }

    // ---------------------------------------------------------------------------------------------

    private Usuario usuario(String nombre, RolUsuario rol, String clave) {
        Usuario u = Usuario.builder().nombre(nombre).email(nombre + "@test.cl").rol(rol).empresa(empresa).build();
        u.definirPin(clave);
        Usuario guardado = usuarioRepository.save(u);
        catalogoDePrueba.indexar(guardado);
        return guardado;
    }

    /** Un token firmado con la clave real, para probar lo que el filtro exige de cada parte. */
    private String firmado(Usuario u, String emisor, String audiencia, Integer version) {
        var b = Jwts.builder().subject(u.getId().toString()).claim("email", u.getEmail())
                .claim("rol", u.getRol().name()).claim("empresaId", u.getEmpresa().getId())
                .issuedAt(new Date()).expiration(new Date(System.currentTimeMillis() + 60_000));
        if (emisor != null) {
            b.issuer(emisor);
        }
        if (audiencia != null) {
            b.audience().add(audiencia);
        }
        if (version != null) {
            b.claim("tv", version);
        }
        return b.signWith(Keys.hmacShaKeyFor(secreto.getBytes(StandardCharsets.UTF_8))).compact();
    }

    private JsonNode login(String email, String clave) throws Exception {
        HttpResponse<String> r = post("/api/auth/login", "{\"email\": \"" + email + "\", \"pin\": \"" + clave + "\"}", null);
        assertThat(r.statusCode()).as("login de " + email).isEqualTo(200);
        return json.readTree(r.body());
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
