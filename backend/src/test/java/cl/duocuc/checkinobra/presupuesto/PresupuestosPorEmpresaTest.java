package cl.duocuc.checkinobra.presupuesto;

import cl.duocuc.checkinobra.config.Empresa;
import cl.duocuc.checkinobra.config.EmpresaRepository;
import cl.duocuc.checkinobra.config.JwtService;
import cl.duocuc.checkinobra.config.RolUsuario;
import cl.duocuc.checkinobra.config.Usuario;
import cl.duocuc.checkinobra.config.UsuarioRepository;
import cl.duocuc.checkinobra.cubicacion.CategoriaMaterial;
import cl.duocuc.checkinobra.cubicacion.Material;
import cl.duocuc.checkinobra.cubicacion.MaterialRepository;
import cl.duocuc.checkinobra.cubicacion.Partida;
import cl.duocuc.checkinobra.cubicacion.PartidaRepository;
import cl.duocuc.checkinobra.cubicacion.TipoPartida;
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
import java.util.List;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * SEG4 (#92, S-04 y S-34): presupuestos y partidas aislados por empresa.
 *
 * <p>Por HTTP contra el servidor de verdad y con dos tokens de empresas
 * distintas: la suite de aislamiento anterior solo probaba el guardián y por
 * eso dejó pasar la fuga. Cada prueba recorre un endpoint de
 * {@code /api/presupuestos} o {@code /api/partidas} con el token de la empresa
 * ajena y exige el mismo 404 que daría un id que nunca existió.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class PresupuestosPorEmpresaTest {

    private static final long ID_QUE_NO_EXISTE = 987_654_321L;

    @LocalServerPort
    private int puerto;

    @Autowired private EmpresaRepository empresaRepository;
    @Autowired private UsuarioRepository usuarioRepository;
    @Autowired private ObraRepository obraRepository;
    @Autowired private MaterialRepository materialRepository;
    @Autowired private PresupuestoRepository presupuestoRepository;
    @Autowired private PresupuestoItemRepository presupuestoItemRepository;
    @Autowired private PartidaRepository partidaRepository;
    @Autowired private JwtService jwtService;

    private final HttpClient http = HttpClient.newHttpClient();
    private final JsonMapper json = JsonMapper.builder().build();

    private String s;
    private Empresa arauco;
    private Empresa otraConstructora;
    private Obra obraDeArauco;
    private Obra obraSinPresupuestoDeArauco;
    private Material materialDeArauco;
    private Presupuesto presupuestoDeArauco;
    private Partida partidaDeArauco;

    private String tokenAdminAjeno;
    private String tokenJefeAjeno;
    private String tokenAdminPropio;
    private String tokenBodegueroPropio;
    private String tokenTrabajadorPropio;

    @BeforeEach
    void prepararDosEmpresas() {
        // La base de test no se vacía entre corridas: todo lo único lleva sufijo.
        s = UUID.randomUUID().toString().substring(0, 8);
        arauco = empresaRepository.save(Empresa.builder().nombre("Arauco " + s).rut("A-" + s).build());
        otraConstructora = empresaRepository.save(Empresa.builder().nombre("Otra " + s).rut("O-" + s).build());

        tokenAdminPropio = token(usuario("admin-a-" + s, RolUsuario.ADMIN, arauco));
        tokenBodegueroPropio = token(usuario("bodega-a-" + s, RolUsuario.BODEGUERO, arauco));
        tokenTrabajadorPropio = token(usuario("obrero-a-" + s, RolUsuario.TRABAJADOR, arauco));
        tokenAdminAjeno = token(usuario("admin-b-" + s, RolUsuario.ADMIN, otraConstructora));
        tokenJefeAjeno = token(usuario("jefe-b-" + s, RolUsuario.JEFE_TERRENO, otraConstructora));

        obraDeArauco = obra("Edificio A " + s, arauco);
        obraSinPresupuestoDeArauco = obra("Casa A " + s, arauco);
        materialDeArauco = materialRepository.save(Material.builder()
                .sku("VOL-" + s).nombre("Volcanita").categoria(CategoriaMaterial.VOLCANITA)
                .precioUnitario(5980).stockMinimo(0).empresa(arauco).build());

        presupuestoDeArauco = presupuestoRepository.save(Presupuesto.builder()
                .estado(EstadoPresupuesto.BORRADOR).total(11960).obra(obraDeArauco).build());
        PresupuestoItem item = PresupuestoItem.builder()
                .presupuesto(presupuestoDeArauco).material(materialDeArauco)
                .cantidad(2).precioUnitario(5980).build();
        item.recalcularSubtotal();
        presupuestoItemRepository.save(item);

        partidaDeArauco = partidaRepository.save(Partida.builder()
                .tipo(TipoPartida.TABIQUE).anchoM(4).altoM(2.4).separacionMontantes(0.6).obra(obraDeArauco).build());
    }

    // --- lectura ------------------------------------------------------------

    @Test
    void laEmpresaDuenaLeeSuPresupuestoPorTodasLasRutas() throws Exception {
        Long id = presupuestoDeArauco.getId();

        assertThat(get("/api/presupuestos/" + id, tokenAdminPropio).statusCode()).isEqualTo(200);
        assertThat(get("/api/presupuestos?obraId=" + obraDeArauco.getId(), tokenAdminPropio).statusCode())
                .isEqualTo(200);
        assertThat(get("/api/presupuestos/" + id + "/items", tokenAdminPropio).statusCode()).isEqualTo(200);
        assertThat(get("/api/presupuestos/" + id + "/desviacion", tokenAdminPropio).statusCode()).isEqualTo(200);
    }

    @Test
    void elPresupuestoAjenoRespondeComoUnIdQueNoExisteEnCadaGet() throws Exception {
        for (String sufijo : List.of("", "/items", "/desviacion")) {
            for (String token : List.of(tokenAdminAjeno, tokenJefeAjeno)) {
                HttpResponse<String> ajeno =
                        get("/api/presupuestos/" + presupuestoDeArauco.getId() + sufijo, token);
                HttpResponse<String> inexistente = get("/api/presupuestos/" + ID_QUE_NO_EXISTE + sufijo, token);

                assertIgualesSalvoElId(ajeno, presupuestoDeArauco.getId(), inexistente, ID_QUE_NO_EXISTE);
                assertThat(ajeno.statusCode()).as("GET presupuesto ajeno " + sufijo).isEqualTo(404);
            }
        }
    }

    @Test
    void elPresupuestoDeUnaObraAjenaRespondeComoUnaObraQueNoExiste() throws Exception {
        HttpResponse<String> ajena =
                get("/api/presupuestos?obraId=" + obraDeArauco.getId(), tokenAdminAjeno);
        HttpResponse<String> inexistente =
                get("/api/presupuestos?obraId=" + ID_QUE_NO_EXISTE, tokenAdminAjeno);

        assertThat(ajena.statusCode()).isEqualTo(404);
        assertIgualesSalvoElId(ajena, obraDeArauco.getId(), inexistente, ID_QUE_NO_EXISTE);
    }

    // --- escritura ----------------------------------------------------------

    @Test
    void unAdminOJefeAjenoNoPuedeAprobarCongelarNiAgregarItems() throws Exception {
        Long id = presupuestoDeArauco.getId();
        String agregar = "{\"materialId\": %d, \"cantidad\": 3}".formatted(materialDeArauco.getId());

        for (String token : List.of(tokenAdminAjeno, tokenJefeAjeno)) {
            assertThat(put("/api/presupuestos/" + id + "/aprobar", token).statusCode()).isEqualTo(404);
            assertThat(put("/api/presupuestos/" + id + "/congelar", token).statusCode()).isEqualTo(404);
            assertThat(post("/api/presupuestos/" + id + "/items", agregar, token).statusCode()).isEqualTo(404);
        }

        // Y nada cambió: lo importante no es la respuesta sino el estado.
        Presupuesto intacto = presupuestoRepository.findById(id).orElseThrow();
        assertThat(intacto.getEstado()).isEqualTo(EstadoPresupuesto.BORRADOR);
        assertThat(presupuestoItemRepository.findByPresupuestoId(id)).hasSize(1);
    }

    @Test
    void agregarUnItemConUnMaterialDeOtraEmpresaTambienEsUn404() throws Exception {
        Material ajeno = materialRepository.save(Material.builder()
                .sku("AJ-" + s).nombre("Ajeno").categoria(CategoriaMaterial.VOLCANITA)
                .precioUnitario(1).stockMinimo(0).empresa(otraConstructora).build());

        HttpResponse<String> r = post("/api/presupuestos/" + presupuestoDeArauco.getId() + "/items",
                "{\"materialId\": %d, \"cantidad\": 1}".formatted(ajeno.getId()), tokenAdminPropio);

        assertThat(r.statusCode()).isEqualTo(404);
    }

    @Test
    void crearSobreUnaObraAjenaNoRevelaSiYaTienePresupuesto() throws Exception {
        String conPresupuesto = "{\"obraId\": %d}".formatted(obraDeArauco.getId());
        String sinPresupuesto = "{\"obraId\": %d}".formatted(obraSinPresupuestoDeArauco.getId());
        String inexistente = "{\"obraId\": %d}".formatted(ID_QUE_NO_EXISTE);

        HttpResponse<String> a = post("/api/presupuestos", conPresupuesto, tokenAdminAjeno);
        HttpResponse<String> b = post("/api/presupuestos", sinPresupuesto, tokenAdminAjeno);
        HttpResponse<String> c = post("/api/presupuestos", inexistente, tokenAdminAjeno);

        // Antes: 409 "ya tiene un presupuesto" para la primera y 404 para las
        // otras, que delataba qué obras de la competencia tienen presupuesto.
        assertThat(a.statusCode()).isEqualTo(404);
        assertThat(b.statusCode()).isEqualTo(404);
        assertThat(c.statusCode()).isEqualTo(404);
        assertIgualesSalvoElId(a, obraDeArauco.getId(), c, ID_QUE_NO_EXISTE);
        assertIgualesSalvoElId(b, obraSinPresupuestoDeArauco.getId(), c, ID_QUE_NO_EXISTE);
        assertThat(presupuestoRepository.findByObraId(obraSinPresupuestoDeArauco.getId())).isEmpty();
    }

    @Test
    void laEmpresaDuenaSigueCreandoYRechazandoDuplicadosComoAntes() throws Exception {
        String ya = "{\"obraId\": %d}".formatted(obraDeArauco.getId());
        String nueva = "{\"obraId\": %d}".formatted(obraSinPresupuestoDeArauco.getId());

        assertThat(post("/api/presupuestos", ya, tokenAdminPropio).statusCode()).isEqualTo(409);
        assertThat(post("/api/presupuestos", nueva, tokenAdminPropio).statusCode()).isEqualTo(201);
    }

    // --- partidas -----------------------------------------------------------

    @Test
    void lasPartidasAjenasRespondenComoUnIdQueNoExiste() throws Exception {
        Long id = partidaDeArauco.getId();

        for (String sufijo : List.of("", "/items-cubicados")) {
            HttpResponse<String> ajena = get("/api/partidas/" + id + sufijo, tokenAdminAjeno);
            HttpResponse<String> inexistente = get("/api/partidas/" + ID_QUE_NO_EXISTE + sufijo, tokenAdminAjeno);
            assertThat(ajena.statusCode()).isEqualTo(404);
            assertIgualesSalvoElId(ajena, id, inexistente, ID_QUE_NO_EXISTE);
        }
        assertThat(post("/api/partidas/" + id + "/cubicar", "", tokenJefeAjeno).statusCode()).isEqualTo(404);
        assertThat(get("/api/partidas?obraId=" + obraDeArauco.getId(), tokenAdminAjeno).statusCode())
                .isEqualTo(404);
    }

    // --- roles --------------------------------------------------------------

    @Test
    void elTrabajadorNoLeePresupuestosNiPartidas() throws Exception {
        Long id = presupuestoDeArauco.getId();
        List<String> rutas = List.of(
                "/api/presupuestos/" + id,
                "/api/presupuestos?obraId=" + obraDeArauco.getId(),
                "/api/presupuestos/" + id + "/items",
                "/api/presupuestos/" + id + "/desviacion",
                "/api/partidas?obraId=" + obraDeArauco.getId(),
                "/api/partidas/" + partidaDeArauco.getId(),
                "/api/partidas/" + partidaDeArauco.getId() + "/items-cubicados");

        for (String ruta : rutas) {
            assertThat(get(ruta, tokenTrabajadorPropio).statusCode()).as("TRABAJADOR en " + ruta).isEqualTo(403);
        }
    }

    @Test
    void elBodegueroSiLeePresupuestosYPartidasDeSuEmpresa() throws Exception {
        Long id = presupuestoDeArauco.getId();
        List<String> rutas = List.of(
                "/api/presupuestos/" + id,
                "/api/presupuestos?obraId=" + obraDeArauco.getId(),
                "/api/presupuestos/" + id + "/items",
                "/api/presupuestos/" + id + "/desviacion",
                "/api/partidas?obraId=" + obraDeArauco.getId(),
                "/api/partidas/" + partidaDeArauco.getId(),
                "/api/partidas/" + partidaDeArauco.getId() + "/items-cubicados");

        for (String ruta : rutas) {
            assertThat(get(ruta, tokenBodegueroPropio).statusCode()).as("BODEGUERO en " + ruta).isEqualTo(200);
        }
    }

    // ---------------------------------------------------------------------

    /**
     * Mismo status y mismo cuerpo, descontando el id que el mensaje repite
     * ("Presupuesto no encontrado: 12"): lo único que puede distinguirlas es
     * justamente lo que el cliente ya sabe porque lo pidió.
     */
    private void assertIgualesSalvoElId(
            HttpResponse<String> a, long idA, HttpResponse<String> b, long idB) {
        assertThat(a.statusCode()).isEqualTo(b.statusCode());
        JsonNode cuerpoA = json.readTree(a.body());
        JsonNode cuerpoB = json.readTree(b.body());
        assertThat(cuerpoA.get("status").asInt()).isEqualTo(cuerpoB.get("status").asInt());
        assertThat(cuerpoA.get("mensaje").asString().replace(String.valueOf(idA), "<id>"))
                .isEqualTo(cuerpoB.get("mensaje").asString().replace(String.valueOf(idB), "<id>"));
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

    private HttpResponse<String> put(String ruta, String token) throws Exception {
        return http.send(peticion(ruta, token).PUT(HttpRequest.BodyPublishers.noBody()).build(),
                HttpResponse.BodyHandlers.ofString());
    }

    private HttpResponse<String> post(String ruta, String cuerpo, String token) throws Exception {
        return http.send(peticion(ruta, token)
                        .header("Content-Type", "application/json")
                        .POST(HttpRequest.BodyPublishers.ofString(cuerpo)).build(),
                HttpResponse.BodyHandlers.ofString());
    }

    private HttpRequest.Builder peticion(String ruta, String token) {
        return HttpRequest.newBuilder(URI.create("http://localhost:" + puerto + ruta))
                .header("Authorization", "Bearer " + token);
    }
}
