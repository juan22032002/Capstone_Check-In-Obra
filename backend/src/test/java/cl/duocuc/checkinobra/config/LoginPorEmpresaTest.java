package cl.duocuc.checkinobra.config;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.server.LocalServerPort;
import tools.jackson.databind.json.JsonMapper;

import javax.sql.DataSource;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Clock;
import java.time.Duration;
import java.util.Collection;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.when;

/**
 * MT4 (#107): el login resuelve la empresa antes del JWT y no la toma por buena. Los ids de
 * usuario se repiten entre bases, así que un usuario encontrado en una base solo vale si es
 * de la empresa que se pidió; si no, es una cuenta que no existe.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT,
        properties = "checkinobra.login.ip.max-fallos=100000")
class LoginPorEmpresaTest {

    private static final String PIN = "4821";
    private static final String CLAVE = "clave-larga-segura-9";

    @LocalServerPort private int puerto;
    @Autowired private EmpresaRepository empresaRepository;
    @Autowired private UsuarioRepository usuarioRepository;
    @Autowired private CatalogoDePrueba catalogoDePrueba;
    @Autowired private CatalogoDeEmpresas catalogo;

    private final HttpClient http = HttpClient.newHttpClient();
    private final JsonMapper json = JsonMapper.builder().build();

    private Empresa a;
    private Empresa b;
    private Usuario obrero;
    private Usuario admin;

    @BeforeEach
    void prepararDosEmpresas() {
        String s = UUID.randomUUID().toString().substring(0, 8);
        a = empresaRepository.save(Empresa.builder().nombre("A " + s).rut("A-" + s).build());
        b = empresaRepository.save(Empresa.builder().nombre("B " + s).rut("B-" + s).build());
        catalogoDePrueba.registrar(a);
        catalogoDePrueba.registrar(b);
        obrero = usuario("obrero-" + s, RolUsuario.TRABAJADOR, a, PIN);
        admin = usuario("admin-" + s, RolUsuario.ADMIN, a, CLAVE);
    }

    @Test
    void elPinSoloEntraEnLaEmpresaDelUsuario() throws Exception {
        HttpResponse<String> pinMalo = loginPin(obrero.getId(), a.getId(), "0000");

        HttpResponse<String> deOtraEmpresa = loginPin(obrero.getId(), b.getId(), PIN);

        // El usuario existe y el PIN es el correcto, pero no es de la empresa B: es una cuenta
        // que no existe, con el mismo mensaje que un PIN equivocado.
        assertThat(deOtraEmpresa.statusCode()).isEqualTo(400);
        assertThat(mensaje(deOtraEmpresa)).isEqualTo(mensaje(pinMalo));
        assertThat(loginPin(obrero.getId(), a.getId(), PIN).statusCode()).isEqualTo(200);
    }

    @Test
    void conUnaEmpresaCualquieraTampocoEntra() throws Exception {
        assertThat(loginPin(obrero.getId(), 987_654_321L, PIN).statusCode()).isEqualTo(400);
    }

    @Test
    void elTokenDelLoginPorCorreoLlevaLaEmpresaDelIndice() throws Exception {
        HttpResponse<String> r = loginCorreo(admin.getEmail(), CLAVE);

        assertThat(r.statusCode()).isEqualTo(200);
        assertThat(json.readTree(r.body()).get("empresaId").asLong()).isEqualTo(a.getId());
    }

    @Test
    void siElIndiceApuntaAOtraEmpresaElUsuarioNoEntra() throws Exception {
        // El índice dice que el correo es de B, pero el usuario está en A.
        catalogo.liberarCorreo(admin.getEmail(), a.getId());
        catalogo.reservarCorreo(admin.getEmail(), b.getId());

        assertThat(loginCorreo(admin.getEmail(), CLAVE).statusCode()).isEqualTo(400);
    }

    @Test
    void unCorreoQueNoEstaEnElIndiceNoEntra() throws Exception {
        catalogo.liberarCorreo(admin.getEmail(), a.getId());

        assertThat(loginCorreo(admin.getEmail(), CLAVE).statusCode()).isEqualTo(400);
    }

    private Usuario usuario(String nombre, RolUsuario rol, Empresa empresa, String clave) {
        Usuario u = Usuario.builder().nombre(nombre).email(nombre + "@test.cl").rol(rol).empresa(empresa).build();
        u.definirPin(clave);
        Usuario guardado = usuarioRepository.save(u);
        catalogoDePrueba.indexar(guardado);
        return guardado;
    }

    private String mensaje(HttpResponse<String> r) {
        return json.readTree(r.body()).get("mensaje").asString();
    }

    private HttpResponse<String> loginPin(long usuarioId, long empresaId, String pin) throws Exception {
        return post("/api/auth/login-pin",
                "{\"usuarioId\": %d, \"empresaId\": %d, \"pin\": \"%s\"}".formatted(usuarioId, empresaId, pin));
    }

    private HttpResponse<String> loginCorreo(String email, String clave) throws Exception {
        return post("/api/auth/login", "{\"email\": \"%s\", \"pin\": \"%s\"}".formatted(email, clave));
    }

    private HttpResponse<String> post(String ruta, String cuerpo) throws Exception {
        return http.send(HttpRequest.newBuilder(URI.create("http://localhost:" + puerto + ruta))
                .header("Content-Type", "application/json")
                .POST(HttpRequest.BodyPublishers.ofString(cuerpo)).build(), HttpResponse.BodyHandlers.ofString());
    }
}
