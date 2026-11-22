package cl.duocuc.checkinobra.control;

import cl.duocuc.checkinobra.config.Empresa;
import cl.duocuc.checkinobra.config.EmpresaRepository;
import cl.duocuc.checkinobra.config.JwtService;
import cl.duocuc.checkinobra.config.RolUsuario;
import cl.duocuc.checkinobra.config.Usuario;
import cl.duocuc.checkinobra.config.UsuarioRepository;
import cl.duocuc.checkinobra.cubicacion.CategoriaMaterial;
import cl.duocuc.checkinobra.cubicacion.Material;
import cl.duocuc.checkinobra.cubicacion.MaterialRepository;
import cl.duocuc.checkinobra.inventario.EstadoHerramienta;
import cl.duocuc.checkinobra.inventario.Herramienta;
import cl.duocuc.checkinobra.inventario.HerramientaRepository;
import cl.duocuc.checkinobra.inventario.PrestamoHerramienta;
import cl.duocuc.checkinobra.inventario.PrestamoHerramientaRepository;
import cl.duocuc.checkinobra.obra.Cuadrilla;
import cl.duocuc.checkinobra.obra.CuadrillaRepository;
import cl.duocuc.checkinobra.obra.EstadoObra;
import cl.duocuc.checkinobra.obra.Obra;
import cl.duocuc.checkinobra.obra.ObraRepository;
import cl.duocuc.checkinobra.obra.Trabajador;
import cl.duocuc.checkinobra.obra.TrabajadorRepository;
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
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Costo real de compra, aviso de faltantes y la ficha de una obra.
 *
 * <p>Por HTTP contra el servidor de verdad: las tres cosas se calculan con
 * consultas agregadas en Postgres (una de ellas nativa), y lo que importa es
 * que el número que llega a la app sea el correcto.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class CostosFaltantesYDetalleDeObraTest {

    @LocalServerPort
    private int puerto;

    @Autowired private EmpresaRepository empresaRepository;
    @Autowired private UsuarioRepository usuarioRepository;
    @Autowired private ObraRepository obraRepository;
    @Autowired private CuadrillaRepository cuadrillaRepository;
    @Autowired private TrabajadorRepository trabajadorRepository;
    @Autowired private MaterialRepository materialRepository;
    @Autowired private HerramientaRepository herramientaRepository;
    @Autowired private PrestamoHerramientaRepository prestamoHerramientaRepository;
    @Autowired private AlertaRepository alertaRepository;
    @Autowired private JwtService jwtService;

    private final HttpClient http = HttpClient.newHttpClient();
    private final JsonMapper json = JsonMapper.builder().build();

    private String s;
    private Empresa empresa;
    private Usuario jefe;
    private Usuario bodeguero;
    private String token;
    private Obra obra;
    private Trabajador trabajador;
    private Material volcanita;
    private Material tornillos;

    @BeforeEach
    void prepararObra() {
        // La base de test no se vacía entre corridas: todo lo único lleva sufijo.
        s = UUID.randomUUID().toString().substring(0, 8);
        empresa = empresaRepository.save(Empresa.builder().nombre("Constructora " + s).rut("R-" + s).build());
        jefe = usuario("jefe-" + s, RolUsuario.JEFE_TERRENO);
        bodeguero = usuario("bodega-" + s, RolUsuario.BODEGUERO);
        token = jwtService.emitir(bodeguero);

        obra = obra("Edificio " + s, EstadoObra.ACTIVA);
        obra.setJefeTerreno(jefe);
        obraRepository.save(obra);

        Cuadrilla cuadrilla = cuadrillaRepository.save(Cuadrilla.builder().nombre("Tabiqueros").obra(obra).build());
        trabajador = trabajadorRepository.save(Trabajador.builder()
                .usuario(usuario("maestro-" + s, RolUsuario.TRABAJADOR))
                .cuadrilla(cuadrilla).credencialQr("QR-" + s).build());

        volcanita = material("VOL-" + s, "Volcanita 10mm", 5980, 40);
        tornillos = material("TOR-" + s, "Tornillo 6x1", 12, 0);
    }

    // --- costo real de compra ---------------------------------------------

    @Test
    void laRecepcionGuardaElCostoYElMaterialMuestraUltimoYPromedio() throws Exception {
        assertThat(post("/api/kardex", recepcion(volcanita, 10, "5000")).statusCode()).isEqualTo(201);
        HttpResponse<String> segunda = post("/api/kardex", recepcion(volcanita, 30, "6000.004"));

        assertThat(segunda.statusCode()).isEqualTo(201);
        assertThat(leer(segunda).get("costoUnitario").decimalValue()).isEqualByComparingTo("6000.00");

        JsonNode m = leer(get("/api/materiales/" + volcanita.getId()));
        assertThat(m.get("ultimoCostoUnitario").decimalValue()).isEqualByComparingTo("6000.00");
        assertThat(m.get("fechaUltimoCosto").isNull()).isFalse();
        // Ponderado por cantidad: (10·5000 + 30·6000) / 40.
        assertThat(m.get("costoPromedio").decimalValue()).isEqualByComparingTo("5750.00");
        // El precio de catálogo no se toca.
        assertThat(m.get("precioUnitario").asDouble()).isEqualTo(5980);
    }

    @Test
    void sinRecepcionesConCostoLosTresCamposSonNulos() throws Exception {
        post("/api/kardex", recepcion(volcanita, 10, null));

        JsonNode enLista = buscarPorId(leer(get("/api/materiales")), volcanita.getId());
        assertThat(enLista.get("ultimoCostoUnitario").isNull()).isTrue();
        assertThat(enLista.get("fechaUltimoCosto").isNull()).isTrue();
        assertThat(enLista.get("costoPromedio").isNull()).isTrue();
    }

    @Test
    void elCostoSoloSeAceptaEnUnaRecepcionYPositivo() throws Exception {
        post("/api/kardex", recepcion(volcanita, 10, "5000"));

        String despachoConCosto = """
                {"obraId": %d, "materialId": %d, "trabajadorId": %d, "tipo": "DESPACHO",
                 "cantidad": 1, "costoUnitario": 5000}
                """.formatted(obra.getId(), volcanita.getId(), trabajador.getId());
        assertThat(post("/api/kardex", despachoConCosto).statusCode()).isEqualTo(400);
        assertThat(post("/api/kardex", recepcion(volcanita, 1, "0")).statusCode()).isEqualTo(400);
        assertThat(post("/api/kardex", recepcion(volcanita, 1, "-10")).statusCode()).isEqualTo(400);
    }

    // --- faltantes ----------------------------------------------------------

    @Test
    void faltantesListaCriticosPrimeroYSoloDeObrasActivasConMovimiento() throws Exception {
        Material yeso = material("YES-" + s, "Yeso 25kg", 8000, 10);
        Obra cerrada = obra("Casa cerrada " + s, EstadoObra.ACTIVA);

        post("/api/kardex", recepcion(volcanita, 30, null)); // 30 < 40 → CRITICO
        post("/api/kardex", recepcion(yeso, 12, null));      // 12 < 12.5 → BAJO
        post("/api/kardex", recepcion(tornillos, 1, null));  // sin mínimo → nunca falta
        post("/api/kardex", recepcionEn(cerrada, volcanita, 1));
        cerrada.setEstado(EstadoObra.CERRADA);
        obraRepository.save(cerrada);

        JsonNode faltantes = leer(get("/api/materiales/faltantes"));

        assertThat(faltantes).hasSize(2);
        assertThat(faltantes.get(0).get("materialId").asLong()).isEqualTo(volcanita.getId());
        assertThat(faltantes.get(0).get("estado").asString()).isEqualTo("CRITICO");
        assertThat(faltantes.get(0).get("obraNombre").asString()).isEqualTo(obra.getNombre());
        assertThat(faltantes.get(0).get("stock").asDouble()).isEqualTo(30);
        assertThat(faltantes.get(1).get("materialId").asLong()).isEqualTo(yeso.getId());
        assertThat(faltantes.get(1).get("estado").asString()).isEqualTo("BAJO");
    }

    @Test
    void unTrabajadorNoVeFaltantesNiLaFichaDeLaObra() throws Exception {
        token = jwtService.emitir(trabajador.getUsuario());

        assertThat(get("/api/materiales/faltantes").statusCode()).isEqualTo(403);
        assertThat(get("/api/obras/" + obra.getId() + "/detalle").statusCode()).isEqualTo(403);
    }

    // --- detalle de obra ---------------------------------------------------

    @Test
    void laFichaDeLaObraJuntaPersonasMaterialesYHerramientas() throws Exception {
        post("/api/kardex", recepcion(volcanita, 30, "6000"));
        post("/api/kardex", recepcion(tornillos, 500, null));
        Herramienta taladro = herramienta("Taladro percutor", 90000);
        prestamoHerramientaRepository.save(PrestamoHerramienta.builder()
                .herramienta(taladro).trabajador(trabajador).obra(obra).autorizadoPor(bodeguero)
                .fechaPrestamo(LocalDateTime.now().minusDays(2))
                .fechaDevolEsperada(LocalDateTime.now().minusDays(1)).build());
        alertaRepository.save(Alerta.generar(TipoAlerta.STOCK_CRITICO, "Queda poca volcanita", obra, null));

        token = jwtService.emitir(jefe);
        HttpResponse<String> r = get("/api/obras/" + obra.getId() + "/detalle");

        assertThat(r.statusCode()).isEqualTo(200);
        JsonNode d = leer(r);
        assertThat(d.get("obra").get("id").asLong()).isEqualTo(obra.getId());

        assertThat(d.get("jefes")).hasSize(1);
        assertThat(d.get("jefes").get(0).get("usuarioId").asLong()).isEqualTo(jefe.getId());
        assertThat(d.get("jefes").get(0).get("rol").asString()).isEqualTo("JEFE_TERRENO");

        assertThat(d.get("cuadrillas").get(0).get("cantidadTrabajadores").asLong()).isEqualTo(1);
        assertThat(d.get("trabajadores").get(0).get("id").asLong()).isEqualTo(trabajador.getId());
        assertThat(d.get("trabajadores").get(0).get("cuadrillaNombre").asString()).isEqualTo("Tabiqueros");

        JsonNode materiales = d.get("materiales");
        assertThat(materiales).hasSize(2);
        // El crítico primero; valorizado al último costo real, no al catálogo.
        assertThat(materiales.get(0).get("materialId").asLong()).isEqualTo(volcanita.getId());
        assertThat(materiales.get(0).get("estado").asString()).isEqualTo("CRITICO");
        assertThat(materiales.get(0).get("valorStock").asDouble()).isEqualTo(30 * 6000);
        // Sin costo registrado: al precio de catálogo.
        assertThat(materiales.get(1).get("estado").asString()).isEqualTo("OK");
        assertThat(materiales.get(1).get("valorStock").asDouble()).isEqualTo(500 * 12);

        JsonNode herramienta = d.get("herramientas").get(0);
        assertThat(herramienta.get("herramientaId").asLong()).isEqualTo(taladro.getId());
        assertThat(herramienta.get("prestadaA").get("trabajadorId").asLong()).isEqualTo(trabajador.getId());
        assertThat(herramienta.get("vencida").asBoolean()).isTrue();

        JsonNode resumen = d.get("resumen");
        assertThat(resumen.get("cantidadTrabajadores").asLong()).isEqualTo(1);
        assertThat(resumen.get("cantidadJefes").asLong()).isEqualTo(1);
        assertThat(resumen.get("materialesCriticos").asLong()).isEqualTo(1);
        assertThat(resumen.get("materialesBajos").asLong()).isZero();
        assertThat(resumen.get("valorMateriales").asDouble()).isEqualTo(30 * 6000 + 500 * 12);
        assertThat(resumen.get("herramientasEnObra").asLong()).isEqualTo(1);
        assertThat(resumen.get("herramientasVencidas").asLong()).isEqualTo(1);
        assertThat(resumen.get("valorHerramientas").asDouble()).isEqualTo(90000);
        assertThat(resumen.get("alertasPendientes").asLong()).isEqualTo(1);
    }

    @Test
    void laFichaDeUnaObraAjenaEsUn404() throws Exception {
        Empresa otra = empresaRepository.save(Empresa.builder().nombre("Otra " + s).rut("O-" + s).build());
        Obra ajena = obraRepository.save(Obra.builder()
                .nombre("Ajena " + s).cliente("Cliente").ubicacion("Santiago")
                .estado(EstadoObra.ACTIVA).empresa(otra).build());

        assertThat(get("/api/obras/" + ajena.getId() + "/detalle").statusCode()).isEqualTo(404);
    }

    // ---------------------------------------------------------------------

    private String recepcion(Material m, double cantidad, String costo) {
        return """
                {"obraId": %d, "materialId": %d, "tipo": "RECEPCION", "cantidad": %s%s}
                """.formatted(obra.getId(), m.getId(), cantidad,
                costo == null ? "" : ", \"costoUnitario\": " + costo);
    }

    private String recepcionEn(Obra o, Material m, double cantidad) {
        return """
                {"obraId": %d, "materialId": %d, "tipo": "RECEPCION", "cantidad": %s}
                """.formatted(o.getId(), m.getId(), cantidad);
    }

    private Usuario usuario(String nombre, RolUsuario rol) {
        return usuarioRepository.save(Usuario.builder()
                .nombre(nombre).email(nombre + "@test.cl").rol(rol).empresa(empresa).build());
    }

    private Obra obra(String nombre, EstadoObra estado) {
        return obraRepository.save(Obra.builder()
                .nombre(nombre).cliente("Cliente").ubicacion("Santiago").estado(estado).empresa(empresa).build());
    }

    private Material material(String sku, String nombre, double precio, double minimo) {
        return materialRepository.save(Material.builder()
                .sku(sku).nombre(nombre).categoria(CategoriaMaterial.VOLCANITA)
                .precioUnitario(precio).stockMinimo(minimo).empresa(empresa).build());
    }

    private Herramienta herramienta(String nombre, double valor) {
        return herramientaRepository.save(Herramienta.builder()
                .codigoQr("H-" + UUID.randomUUID()).nombre(nombre).categoria("Eléctrica")
                .estado(EstadoHerramienta.PRESTADA).valorReposicion(valor).empresa(empresa).build());
    }

    private JsonNode buscarPorId(JsonNode lista, Long id) {
        List<JsonNode> encontrados = new ArrayList<>();
        lista.forEach(n -> {
            if (n.get("id").asLong() == id) {
                encontrados.add(n);
            }
        });
        assertThat(encontrados).hasSize(1);
        return encontrados.get(0);
    }

    private JsonNode leer(HttpResponse<String> r) {
        return json.readTree(r.body());
    }

    private HttpResponse<String> get(String ruta) throws Exception {
        return http.send(peticion(ruta).GET().build(), HttpResponse.BodyHandlers.ofString());
    }

    private HttpResponse<String> post(String ruta, String cuerpo) throws Exception {
        return http.send(peticion(ruta)
                        .header("Content-Type", "application/json")
                        .POST(HttpRequest.BodyPublishers.ofString(cuerpo)).build(),
                HttpResponse.BodyHandlers.ofString());
    }

    private HttpRequest.Builder peticion(String ruta) {
        return HttpRequest.newBuilder(URI.create("http://localhost:" + puerto + ruta))
                .header("Authorization", "Bearer " + token);
    }
}
