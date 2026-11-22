package cl.duocuc.checkinobra.obra;

import cl.duocuc.checkinobra.config.Empresa;
import cl.duocuc.checkinobra.config.EmpresaRepository;
import cl.duocuc.checkinobra.config.JwtService;
import cl.duocuc.checkinobra.config.RolUsuario;
import cl.duocuc.checkinobra.config.Usuario;
import cl.duocuc.checkinobra.config.UsuarioRepository;
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
import java.util.List;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * SEG5 (#93, S-05 y S-06): listado y alta de trabajadores aislados por empresa.
 *
 * <p>Por HTTP, con tokens de dos empresas. Antes, el listado por cuadrilla u
 * obra devolvía nombre y RUT de trabajadores de cualquier empresa, y un ADMIN
 * podía crear la ficha de un usuario ajeno y quedarse con su credencial QR.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class TrabajadoresPorEmpresaTest {

    private static final long ID_QUE_NO_EXISTE = 987_654_321L;

    @LocalServerPort
    private int puerto;

    @Autowired private EmpresaRepository empresaRepository;
    @Autowired private UsuarioRepository usuarioRepository;
    @Autowired private ObraRepository obraRepository;
    @Autowired private CuadrillaRepository cuadrillaRepository;
    @Autowired private TrabajadorRepository trabajadorRepository;
    @Autowired private JwtService jwtService;

    private final HttpClient http = HttpClient.newHttpClient();
    private final JsonMapper json = JsonMapper.builder().build();

    private String s;
    private Empresa arauco;
    private Empresa otra;
    private Obra obraDeArauco;
    private Cuadrilla cuadrillaDeArauco;
    private Usuario usuarioDeArauco;
    private Trabajador trabajadorDeArauco;
    private Obra obraAjena;
    private Cuadrilla cuadrillaAjena;
    private Usuario usuarioAjeno;

    private String adminAjeno;
    private String adminPropio;
    private String bodegueroPropio;
    private String jefePropio;
    private String trabajadorPropio;

    @BeforeEach
    void prepararDosEmpresas() {
        s = UUID.randomUUID().toString().substring(0, 8);
        arauco = empresaRepository.save(Empresa.builder().nombre("Arauco " + s).rut("A-" + s).build());
        otra = empresaRepository.save(Empresa.builder().nombre("Otra " + s).rut("O-" + s).build());

        adminPropio = token(usuario("admin-a-" + s, RolUsuario.ADMIN, arauco));
        bodegueroPropio = token(usuario("bodega-a-" + s, RolUsuario.BODEGUERO, arauco));
        jefePropio = token(usuario("jefe-a-" + s, RolUsuario.JEFE_TERRENO, arauco));
        adminAjeno = token(usuario("admin-b-" + s, RolUsuario.ADMIN, otra));

        obraDeArauco = obra("Edificio A " + s, arauco);
        cuadrillaDeArauco = cuadrillaRepository.save(
                Cuadrilla.builder().nombre("Tabiqueros").obra(obraDeArauco).build());
        usuarioDeArauco = usuario("obrero-a-" + s, RolUsuario.TRABAJADOR, arauco);
        trabajadorPropio = token(usuarioDeArauco);
        trabajadorDeArauco = trabajadorRepository.save(Trabajador.builder()
                .usuario(usuarioDeArauco).cuadrilla(cuadrillaDeArauco).credencialQr("QR-" + s).build());

        obraAjena = obra("Casa B " + s, otra);
        cuadrillaAjena = cuadrillaRepository.save(Cuadrilla.builder().nombre("Gasfiteres").obra(obraAjena).build());
        usuarioAjeno = usuario("obrero-b-" + s, RolUsuario.TRABAJADOR, otra);
    }

    // --- listado (S-05) ------------------------------------------------------

    @Test
    void laEmpresaDuenaListaSusTrabajadoresPorCuadrillaYPorObra() throws Exception {
        for (String token : List.of(adminPropio, bodegueroPropio, jefePropio)) {
            for (String ruta : List.of("?cuadrillaId=" + cuadrillaDeArauco.getId(),
                    "?obraId=" + obraDeArauco.getId())) {
                HttpResponse<String> r = get("/api/trabajadores" + ruta, token);

                assertThat(r.statusCode()).as(ruta).isEqualTo(200);
                JsonNode lista = json.readTree(r.body());
                assertThat(lista).hasSize(1);
                assertThat(lista.get(0).get("id").asLong()).isEqualTo(trabajadorDeArauco.getId());
            }
        }
    }

    @Test
    void elListadoPorCuadrillaAjenaRespondeComoUnaCuadrillaQueNoExiste() throws Exception {
        HttpResponse<String> ajena = get("/api/trabajadores?cuadrillaId=" + cuadrillaDeArauco.getId(), adminAjeno);
        HttpResponse<String> inexistente = get("/api/trabajadores?cuadrillaId=" + ID_QUE_NO_EXISTE, adminAjeno);

        assertThat(ajena.statusCode()).isEqualTo(404);
        assertIgualesSalvoElId(ajena, cuadrillaDeArauco.getId(), inexistente, ID_QUE_NO_EXISTE);
        assertThat(ajena.body()).doesNotContain("QR-" + s).doesNotContain(usuarioDeArauco.getNombre());
    }

    @Test
    void elListadoPorObraAjenaRespondeComoUnaObraQueNoExiste() throws Exception {
        HttpResponse<String> ajena = get("/api/trabajadores?obraId=" + obraDeArauco.getId(), adminAjeno);
        HttpResponse<String> inexistente = get("/api/trabajadores?obraId=" + ID_QUE_NO_EXISTE, adminAjeno);

        assertThat(ajena.statusCode()).isEqualTo(404);
        assertIgualesSalvoElId(ajena, obraDeArauco.getId(), inexistente, ID_QUE_NO_EXISTE);
    }

    @Test
    void unTrabajadorNoPuedeListarNiLosDeSuPropiaEmpresa() throws Exception {
        assertThat(get("/api/trabajadores?cuadrillaId=" + cuadrillaDeArauco.getId(), trabajadorPropio)
                .statusCode()).isEqualTo(403);
        assertThat(get("/api/trabajadores?obraId=" + obraDeArauco.getId(), trabajadorPropio)
                .statusCode()).isEqualTo(403);
    }

    // --- alta (S-06) ---------------------------------------------------------

    @Test
    void unAdminAjenoNoPuedeCrearLaFichaDeUnUsuarioDeOtraEmpresa() throws Exception {
        Usuario sinFicha = usuario("sinficha-a-" + s, RolUsuario.TRABAJADOR, arauco);

        HttpResponse<String> ajeno = post("/api/trabajadores", cuerpo(sinFicha.getId(), null), adminAjeno);
        HttpResponse<String> inexistente = post("/api/trabajadores", cuerpo(ID_QUE_NO_EXISTE, null), adminAjeno);

        assertThat(ajeno.statusCode()).isEqualTo(404);
        assertIgualesSalvoElId(ajeno, sinFicha.getId(), inexistente, ID_QUE_NO_EXISTE);
        // Lo que importaba: no hay ficha ni credencial que se haya podido llevar.
        assertThat(ajeno.body()).doesNotContain("credencialQr");
        assertThat(trabajadorRepository.findByUsuarioId(sinFicha.getId())).isEmpty();
    }

    @Test
    void laCuadrillaDeOtraEmpresaTampocoSePuedeUsarEnElAlta() throws Exception {
        HttpResponse<String> ajena = post("/api/trabajadores",
                cuerpo(usuarioAjeno.getId(), cuadrillaDeArauco.getId()), adminAjeno);
        HttpResponse<String> inexistente = post("/api/trabajadores",
                cuerpo(usuarioAjeno.getId(), ID_QUE_NO_EXISTE), adminAjeno);

        assertThat(ajena.statusCode()).isEqualTo(404);
        assertIgualesSalvoElId(ajena, cuadrillaDeArauco.getId(), inexistente, ID_QUE_NO_EXISTE);
        assertThat(trabajadorRepository.findByUsuarioId(usuarioAjeno.getId())).isEmpty();
    }

    @Test
    void elAltaDentroDeLaPropiaEmpresaSigueFuncionando() throws Exception {
        HttpResponse<String> r = post("/api/trabajadores",
                cuerpo(usuarioAjeno.getId(), cuadrillaAjena.getId()), adminAjeno);

        assertThat(r.statusCode()).isEqualTo(201);
        assertThat(json.readTree(r.body()).get("credencialQr").asString()).isNotBlank();
        assertThat(trabajadorRepository.findByUsuarioId(usuarioAjeno.getId())).isPresent();
    }

    @Test
    void elAltaSigueSiendoSoloDeAdmin() throws Exception {
        for (String token : List.of(bodegueroPropio, jefePropio, trabajadorPropio)) {
            assertThat(post("/api/trabajadores", cuerpo(usuarioDeArauco.getId(), null), token).statusCode())
                    .isEqualTo(403);
        }
    }

    // ---------------------------------------------------------------------

    private void assertIgualesSalvoElId(HttpResponse<String> a, long idA, HttpResponse<String> b, long idB) {
        assertThat(a.statusCode()).isEqualTo(b.statusCode());
        JsonNode cuerpoA = json.readTree(a.body());
        JsonNode cuerpoB = json.readTree(b.body());
        assertThat(cuerpoA.get("mensaje").asString().replace(String.valueOf(idA), "<id>"))
                .isEqualTo(cuerpoB.get("mensaje").asString().replace(String.valueOf(idB), "<id>"));
    }

    private static String cuerpo(Long usuarioId, Long cuadrillaId) {
        return "{\"usuarioId\": %d, \"cuadrillaId\": %s}".formatted(usuarioId, cuadrillaId);
    }

    private Usuario usuario(String nombre, RolUsuario rol, Empresa empresa) {
        return usuarioRepository.save(Usuario.builder()
                .nombre(nombre).email(nombre + "@test.cl").rol(rol).empresa(empresa).build());
    }

    private String token(Usuario usuario) {
        return jwtService.emitir(usuario);
    }

    private Obra obra(String nombre, Empresa empresa) {
        return obraRepository.save(Obra.builder()
                .nombre(nombre).cliente("Cliente").ubicacion("Santiago")
                .estado(EstadoObra.ACTIVA).empresa(empresa).build());
    }

    private HttpResponse<String> get(String ruta, String token) throws Exception {
        return http.send(peticion(ruta, token).GET().build(), HttpResponse.BodyHandlers.ofString());
    }

    private HttpResponse<String> post(String ruta, String cuerpo, String token) throws Exception {
        return http.send(peticion(ruta, token).header("Content-Type", "application/json")
                .POST(HttpRequest.BodyPublishers.ofString(cuerpo)).build(), HttpResponse.BodyHandlers.ofString());
    }

    private HttpRequest.Builder peticion(String ruta, String token) {
        return HttpRequest.newBuilder(URI.create("http://localhost:" + puerto + ruta))
                .header("Authorization", "Bearer " + token);
    }
}
