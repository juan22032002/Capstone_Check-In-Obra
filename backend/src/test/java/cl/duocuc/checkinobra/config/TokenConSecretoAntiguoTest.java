package cl.duocuc.checkinobra.config;

import io.jsonwebtoken.Jwts;
import io.jsonwebtoken.security.Keys;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.server.LocalServerPort;

import javax.crypto.SecretKey;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.util.Date;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * SEG1 (#89, S-01): reproduce la petición de la auditoría — un token ADMIN de
 * una empresa inexistente, firmado con el secreto que estuvo publicado en el
 * repo — y exige que ya no entre. Antes respondía 200 en {@code /api/obras}.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class TokenConSecretoAntiguoTest {

    private static final String SECRETO_ANTIGUO = "cambiar-por-un-valor-largo-y-aleatorio";

    @LocalServerPort
    private int puerto;

    @Autowired private EmpresaRepository empresaRepository;
    @Autowired private UsuarioRepository usuarioRepository;
    @Autowired private JwtService jwtService;

    private final HttpClient http = HttpClient.newHttpClient();

    @Test
    void unTokenAdminFirmadoConElSecretoAntiguoResponde401() throws Exception {
        String forjado = tokenFirmadoCon(SECRETO_ANTIGUO, "ADMIN", 999L);

        assertThat(statusDeObras(forjado)).isEqualTo(401);
    }

    @Test
    void unTokenFirmadoConOtroSecretoCualquieraResponde401() throws Exception {
        String forjado = tokenFirmadoCon("otro-secreto-de-al-menos-32-bytes-ok", "ADMIN", 999L);

        assertThat(statusDeObras(forjado)).isEqualTo(401);
    }

    @Test
    void elTokenEmitidoPorLaApiConSuSecretoSigueFuncionando() throws Exception {
        String s = UUID.randomUUID().toString().substring(0, 8);
        Empresa empresa = empresaRepository.save(Empresa.builder().nombre("E " + s).rut("R-" + s).build());
        Usuario admin = usuarioRepository.save(Usuario.builder()
                .nombre("admin-" + s).email("admin-" + s + "@test.cl").rol(RolUsuario.ADMIN).empresa(empresa).build());

        assertThat(statusDeObras(jwtService.emitir(admin))).isEqualTo(200);
    }

    private int statusDeObras(String token) throws Exception {
        HttpRequest peticion = HttpRequest.newBuilder(URI.create("http://localhost:" + puerto + "/api/obras"))
                .header("Authorization", "Bearer " + token).GET().build();
        HttpResponse<String> r = http.send(peticion, HttpResponse.BodyHandlers.ofString());
        return r.statusCode();
    }

    private static String tokenFirmadoCon(String secreto, String rol, long empresaId) {
        SecretKey clave = Keys.hmacShaKeyFor(secreto.getBytes(StandardCharsets.UTF_8));
        Date ahora = new Date();
        return Jwts.builder()
                .subject("999999")
                .claim("email", "atacante@example.com")
                .claim("rol", rol)
                .claim("empresaId", empresaId)
                .issuedAt(ahora)
                .expiration(new Date(ahora.getTime() + 3_600_000))
                .signWith(clave)
                .compact();
    }
}
