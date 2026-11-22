package cl.duocuc.checkinobra.cubicacion;

import cl.duocuc.checkinobra.config.Empresa;
import cl.duocuc.checkinobra.config.EmpresaRepository;
import cl.duocuc.checkinobra.config.JwtService;
import cl.duocuc.checkinobra.config.RolUsuario;
import cl.duocuc.checkinobra.config.Usuario;
import cl.duocuc.checkinobra.config.UsuarioRepository;
import cl.duocuc.checkinobra.obra.EstadoObra;
import cl.duocuc.checkinobra.obra.Obra;
import cl.duocuc.checkinobra.obra.ObraRepository;
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

/**
 * D1 (#45): una partida se crea con ancho, alto y separación mayores que 0.
 * Con separación 0 el motor de cubicación divide por cero y los montantes dan
 * Infinity; con una medida negativa, la cubicación sale con cantidades absurdas.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class GeometriaDePartidaTest {

    @LocalServerPort
    private int puerto;

    @Autowired private EmpresaRepository empresaRepository;
    @Autowired private UsuarioRepository usuarioRepository;
    @Autowired private ObraRepository obraRepository;
    @Autowired private PartidaRepository partidaRepository;
    @Autowired private JwtService jwtService;

    private final HttpClient http = HttpClient.newHttpClient();
    private final JsonMapper json = JsonMapper.builder().build();

    private Obra obra;
    private String token;

    @BeforeEach
    void prepararObra() {
        String s = UUID.randomUUID().toString().substring(0, 8);
        Empresa empresa = empresaRepository.save(Empresa.builder().nombre("Empresa " + s).rut("R-" + s).build());
        Usuario jefe = usuarioRepository.save(Usuario.builder()
                .nombre("jefe-" + s).email("jefe-" + s + "@test.cl").rol(RolUsuario.JEFE_TERRENO).empresa(empresa).build());
        token = jwtService.emitir(jefe);
        obra = obraRepository.save(Obra.builder()
                .nombre("Edificio " + s).cliente("Cliente").ubicacion("Santiago")
                .estado(EstadoObra.ACTIVA).empresa(empresa).build());
    }

    @Test
    void unaPartidaConMedidasPositivasSeCreaEnLaObra() throws Exception {
        HttpResponse<String> r = crear(4, 2.4, 0.6);

        assertThat(r.statusCode()).isEqualTo(201);
        JsonNode p = json.readTree(r.body());
        assertThat(p.get("anchoM").asDouble()).isEqualTo(4);
        assertThat(p.get("altoM").asDouble()).isEqualTo(2.4);
        assertThat(p.get("separacionMontantes").asDouble()).isEqualTo(0.6);
        assertThat(partidaRepository.findByObraId(obra.getId())).hasSize(1);
    }

    @Test
    void anchoAltoOSeparacionEnCeroONegativosSeRechazanConUn400() throws Exception {
        double[][] invalidas = {
                {0, 2.4, 0.6}, {4, 0, 0.6}, {4, 2.4, 0},
                {-1, 2.4, 0.6}, {4, -2.4, 0.6}, {4, 2.4, -0.6}};

        for (double[] m : invalidas) {
            HttpResponse<String> r = crear(m[0], m[1], m[2]);

            assertThat(r.statusCode()).as("%s x %s x %s", m[0], m[1], m[2]).isEqualTo(400);
        }
        assertThat(partidaRepository.findByObraId(obra.getId())).isEmpty();
    }

    @Test
    void elMensajeDiceQueMedidaEstaMal() throws Exception {
        assertThat(mensaje(crear(0, 2.4, 0.6))).containsIgnoringCase("ancho");
        assertThat(mensaje(crear(4, 0, 0.6))).containsIgnoringCase("alto");
        assertThat(mensaje(crear(4, 2.4, 0))).containsIgnoringCase("separación");
    }

    @Test
    void lasPartidasDeLaObraSeListan() throws Exception {
        crear(4, 2.4, 0.6);
        crear(3, 2.4, 0.4);

        HttpResponse<String> r = get("/api/partidas?obraId=" + obra.getId());

        assertThat(r.statusCode()).isEqualTo(200);
        assertThat(json.readTree(r.body())).hasSize(2);
    }

    // ---------------------------------------------------------------------

    private String mensaje(HttpResponse<String> r) {
        return json.readTree(r.body()).get("mensaje").asString();
    }

    private HttpResponse<String> crear(double ancho, double alto, double separacion) throws Exception {
        String cuerpo = """
                {"obraId": %d, "tipo": "TABIQUE", "anchoM": %s, "altoM": %s, "separacionMontantes": %s}
                """.formatted(obra.getId(), ancho, alto, separacion);
        HttpRequest r = HttpRequest.newBuilder(URI.create("http://localhost:" + puerto + "/api/partidas"))
                .header("Authorization", "Bearer " + token).header("Content-Type", "application/json")
                .POST(HttpRequest.BodyPublishers.ofString(cuerpo)).build();
        return http.send(r, HttpResponse.BodyHandlers.ofString());
    }

    private HttpResponse<String> get(String ruta) throws Exception {
        return http.send(HttpRequest.newBuilder(URI.create("http://localhost:" + puerto + ruta))
                .header("Authorization", "Bearer " + token).GET().build(), HttpResponse.BodyHandlers.ofString());
    }
}
