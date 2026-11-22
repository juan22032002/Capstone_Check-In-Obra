package cl.duocuc.checkinobra.cubicacion;

import cl.duocuc.checkinobra.config.Empresa;
import cl.duocuc.checkinobra.config.EmpresaRepository;
import cl.duocuc.checkinobra.config.JwtService;
import cl.duocuc.checkinobra.config.RolUsuario;
import cl.duocuc.checkinobra.config.Usuario;
import cl.duocuc.checkinobra.config.UsuarioRepository;
import cl.duocuc.checkinobra.inventario.EstadoHerramienta;
import cl.duocuc.checkinobra.inventario.Herramienta;
import cl.duocuc.checkinobra.inventario.HerramientaRepository;
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
 * SEG7 (#95, S-08): el trabajador no ve precios ni costos. La matriz de permisos
 * los reserva al administrador, y los costos de compra (V8) son información
 * comercial sensible; el catálogo, en cambio, el trabajador sí lo necesita para
 * pedir material y herramientas.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class TrabajadorSinCostosTest {

    /** Todo campo de precio, costo o valor que la API expone en el catálogo. */
    private static final List<String> CAMPOS_DE_COSTO = List.of(
            "precioUnitario", "ultimoCostoUnitario", "fechaUltimoCosto", "costoPromedio", "valorReposicion");

    @LocalServerPort
    private int puerto;

    @Autowired private EmpresaRepository empresaRepository;
    @Autowired private UsuarioRepository usuarioRepository;
    @Autowired private ObraRepository obraRepository;
    @Autowired private MaterialRepository materialRepository;
    @Autowired private HerramientaRepository herramientaRepository;
    @Autowired private JwtService jwtService;

    private final HttpClient http = HttpClient.newHttpClient();
    private final JsonMapper json = JsonMapper.builder().build();

    private String s;
    private Empresa empresa;
    private Material volcanita;
    private Herramienta taladro;
    private String tokenTrabajador;
    private String tokenAdmin;
    private String tokenJefe;

    @BeforeEach
    void prepararCatalogoConCostos() throws Exception {
        s = UUID.randomUUID().toString().substring(0, 8);
        empresa = empresaRepository.save(Empresa.builder().nombre("Constructora " + s).rut("R-" + s).build());
        tokenTrabajador = token(RolUsuario.TRABAJADOR);
        tokenAdmin = token(RolUsuario.ADMIN);
        tokenJefe = token(RolUsuario.JEFE_TERRENO);
        String tokenBodeguero = token(RolUsuario.BODEGUERO);

        Obra obra = obraRepository.save(Obra.builder()
                .nombre("Edificio " + s).cliente("Cliente").ubicacion("Santiago")
                .estado(EstadoObra.ACTIVA).empresa(empresa).build());
        volcanita = materialRepository.save(Material.builder()
                .sku(("VOL-" + s).toUpperCase()).nombre("Volcanita 10mm").categoria(CategoriaMaterial.VOLCANITA)
                .precioUnitario(5980).stockMinimo(40).empresa(empresa).build());
        taladro = herramientaRepository.save(Herramienta.builder()
                .codigoQr(("H-" + s).toUpperCase()).nombre("Taladro percutor").categoria("Eléctrica")
                .estado(EstadoHerramienta.DISPONIBLE).valorReposicion(90000).empresa(empresa).build());

        // Una recepción con factura: es lo que llena ultimoCosto y costoPromedio.
        String recepcion = """
                {"obraId": %d, "materialId": %d, "tipo": "RECEPCION", "cantidad": 30, "costoUnitario": 5500}
                """.formatted(obra.getId(), volcanita.getId());
        assertThat(enviar("POST", "/api/kardex", recepcion, tokenBodeguero).statusCode()).isEqualTo(201);
    }

    @Test
    void elAdminYElJefeSiguenViendoLosPreciosYCostos() throws Exception {
        for (String token : List.of(tokenAdmin, tokenJefe)) {
            JsonNode m = json.readTree(get("/api/materiales/" + volcanita.getId(), token).body());
            assertThat(m.get("precioUnitario").asDouble()).isEqualTo(5980);
            assertThat(m.get("ultimoCostoUnitario").decimalValue()).isEqualByComparingTo("5500");
            assertThat(m.get("costoPromedio").decimalValue()).isEqualByComparingTo("5500");

            JsonNode h = json.readTree(get("/api/herramientas/" + taladro.getId(), token).body());
            assertThat(h.get("valorReposicion").asDouble()).isEqualTo(90000);
        }
    }

    @Test
    void ningunaRespuestaDelCatalogoParaUnTrabajadorTraeCamposDeCosto() throws Exception {
        List<String> rutas = List.of(
                "/api/materiales",
                "/api/materiales?categoria=VOLCANITA",
                "/api/materiales/" + volcanita.getId(),
                "/api/materiales/por-codigo/" + volcanita.getSku(),
                "/api/herramientas",
                "/api/herramientas/" + taladro.getId(),
                "/api/herramientas/por-codigo/" + taladro.getCodigoQr());

        for (String ruta : rutas) {
            HttpResponse<String> r = get(ruta, tokenTrabajador);

            assertThat(r.statusCode()).as(ruta).isEqualTo(200);
            for (String campo : CAMPOS_DE_COSTO) {
                assertThat(r.body()).as("%s no debe traer %s", ruta, campo).doesNotContain("\"" + campo + "\"");
            }
        }
    }

    @Test
    void elTrabajadorSigueViendoLoQueNecesitaParaPedir() throws Exception {
        JsonNode m = json.readTree(get("/api/materiales/" + volcanita.getId(), tokenTrabajador).body());
        assertThat(m.get("id").asLong()).isEqualTo(volcanita.getId());
        assertThat(m.get("sku").asString()).isEqualTo(volcanita.getSku());
        assertThat(m.get("nombre").asString()).isEqualTo("Volcanita 10mm");
        assertThat(m.get("categoria").asString()).isEqualTo("VOLCANITA");
        assertThat(m.get("empresaId").asLong()).isEqualTo(empresa.getId());

        JsonNode h = json.readTree(get("/api/herramientas/" + taladro.getId(), tokenTrabajador).body());
        assertThat(h.get("codigoQr").asString()).isEqualTo(("H-" + s).toUpperCase());
        assertThat(h.get("nombre").asString()).isEqualTo("Taladro percutor");
        assertThat(h.get("estado").asString()).isEqualTo("DISPONIBLE");
    }

    @Test
    void laListaDelTrabajadorTraeLosMismosMaterialesQueLaDelAdmin() throws Exception {
        JsonNode delTrabajador = json.readTree(get("/api/materiales", tokenTrabajador).body());
        JsonNode delAdmin = json.readTree(get("/api/materiales", tokenAdmin).body());

        assertThat(delTrabajador).hasSize(delAdmin.size());
        assertThat(delTrabajador.get(0).get("id").asLong()).isEqualTo(delAdmin.get(0).get("id").asLong());
    }

    // ---------------------------------------------------------------------

    private String token(RolUsuario rol) {
        Usuario u = usuarioRepository.save(Usuario.builder()
                .nombre(rol.name().toLowerCase() + "-" + s).email(rol.name().toLowerCase() + "-" + s + "@test.cl")
                .rol(rol).empresa(empresa).build());
        return jwtService.emitir(u);
    }

    private HttpResponse<String> get(String ruta, String token) throws Exception {
        return enviar("GET", ruta, null, token);
    }

    private HttpResponse<String> enviar(String metodo, String ruta, String cuerpo, String token) throws Exception {
        HttpRequest.Builder b = HttpRequest.newBuilder(URI.create("http://localhost:" + puerto + ruta))
                .header("Authorization", "Bearer " + token).header("Content-Type", "application/json");
        b.method(metodo, cuerpo == null
                ? HttpRequest.BodyPublishers.noBody() : HttpRequest.BodyPublishers.ofString(cuerpo));
        return http.send(b.build(), HttpResponse.BodyHandlers.ofString());
    }
}
