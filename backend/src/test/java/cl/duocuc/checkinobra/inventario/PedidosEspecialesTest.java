package cl.duocuc.checkinobra.inventario;

import cl.duocuc.checkinobra.config.Empresa;
import cl.duocuc.checkinobra.config.EmpresaRepository;
import cl.duocuc.checkinobra.config.JwtService;
import cl.duocuc.checkinobra.config.RolUsuario;
import cl.duocuc.checkinobra.config.Usuario;
import cl.duocuc.checkinobra.config.UsuarioRepository;
import cl.duocuc.checkinobra.cubicacion.CategoriaMaterial;
import cl.duocuc.checkinobra.cubicacion.Material;
import cl.duocuc.checkinobra.cubicacion.MaterialRepository;
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
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Lo que no está en bodega y hay que conseguir: el trabajador lo pide, bodega
 * lo gestiona y lo entrega, el trabajador confirma.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class PedidosEspecialesTest {

    @LocalServerPort
    private int puerto;

    @Autowired private EmpresaRepository empresaRepository;
    @Autowired private UsuarioRepository usuarioRepository;
    @Autowired private ObraRepository obraRepository;
    @Autowired private CuadrillaRepository cuadrillaRepository;
    @Autowired private TrabajadorRepository trabajadorRepository;
    @Autowired private MaterialRepository materialRepository;
    @Autowired private KardexMovimientoRepository kardexMovimientoRepository;
    @Autowired private JwtService jwtService;

    private final HttpClient http = HttpClient.newHttpClient();
    private final JsonMapper json = JsonMapper.builder().build();

    private String s;
    private Empresa empresa;
    private Obra obra;
    private Trabajador yo;
    private Trabajador companero;
    private Usuario bodeguero;
    private Material volcanita;
    private String token;

    @BeforeEach
    void preparar() {
        s = UUID.randomUUID().toString().substring(0, 8);
        empresa = empresaRepository.save(Empresa.builder().nombre("Constructora " + s).rut("R-" + s).build());
        bodeguero = usuario("bodega-" + s, RolUsuario.BODEGUERO);
        obra = obraRepository.save(Obra.builder()
                .nombre("Edificio " + s).cliente("Cliente").ubicacion("Santiago")
                .estado(EstadoObra.ACTIVA).empresa(empresa).build());
        Cuadrilla cuadrilla = cuadrillaRepository.save(Cuadrilla.builder().nombre("Tabiqueros").obra(obra).build());
        yo = trabajador("maestro-" + s, cuadrilla);
        companero = trabajador("companero-" + s, cuadrilla);
        volcanita = materialRepository.save(Material.builder()
                .sku("VOL-" + s).nombre("Volcanita 10mm").categoria(CategoriaMaterial.VOLCANITA)
                .precioUnitario(5980).stockMinimo(0).empresa(empresa).build());
        token = jwtService.emitir(yo.getUsuario());
    }

    @Test
    void elCaminoCompletoDeUnPedido() throws Exception {
        HttpResponse<String> creado = post("/api/pedidos-especiales", """
                {"tipo": "MATERIAL", "nombre": "  Volcanita RH 15mm ", "cantidad": 12, "unidad": "pl",
                 "descripcion": "Baño del depto 402", "materialId": %d}
                """.formatted(volcanita.getId()));
        assertThat(creado.statusCode()).as(creado.body()).isEqualTo(201);
        JsonNode p = leer(creado);
        long id = p.get("id").asLong();
        assertThat(p.get("nombre").asString()).isEqualTo("Volcanita RH 15mm");
        assertThat(p.get("estado").asString()).isEqualTo("PENDIENTE");
        assertThat(p.get("obraId").asLong()).isEqualTo(obra.getId());
        assertThat(p.get("trabajadorId").asLong()).isEqualTo(yo.getId());

        token = jwtService.emitir(bodeguero);
        JsonNode gestion = leer(put("/api/pedidos-especiales/" + id + "/gestionar", "{\"nota\": \"Llega el jueves\"}"));
        assertThat(gestion.get("estado").asString()).isEqualTo("EN_GESTION");
        assertThat(gestion.get("notaBodega").asString()).isEqualTo("Llega el jueves");
        assertThat(gestion.get("gestionadoPorNombre").asString()).isEqualTo(bodeguero.getNombre());

        // Sin nota, se conserva la anterior.
        JsonNode listo = leer(put("/api/pedidos-especiales/" + id + "/listo", null));
        assertThat(listo.get("estado").asString()).isEqualTo("LISTO_PARA_RETIRO");
        assertThat(listo.get("notaBodega").asString()).isEqualTo("Llega el jueves");

        JsonNode entregado = leer(put("/api/pedidos-especiales/" + id + "/entregar", null));
        assertThat(entregado.get("estado").asString()).isEqualTo("ENTREGADO");
        assertThat(entregado.get("fechaEntrega").isNull()).isFalse();
        // El pedido no mueve stock: la volcanita entra y sale por el kardex de siempre.
        assertThat(kardexMovimientoRepository.findByMaterialId(volcanita.getId())).isEmpty();

        token = jwtService.emitir(yo.getUsuario());
        JsonNode recibido = leer(put("/api/pedidos-especiales/" + id + "/confirmar-recepcion", null));
        assertThat(recibido.get("estado").asString()).isEqualTo("RECIBIDO");
        assertThat(recibido.get("fechaRecepcion").isNull()).isFalse();
        // Confirmar no cambia quién lo gestionó.
        assertThat(recibido.get("gestionadoPorNombre").asString()).isEqualTo(bodeguero.getNombre());
    }

    @Test
    void soloHaciaAdelante() throws Exception {
        long id = crear();
        token = jwtService.emitir(bodeguero);

        assertThat(put("/api/pedidos-especiales/" + id + "/listo", null).statusCode()).isEqualTo(200);
        assertThat(codigo(put("/api/pedidos-especiales/" + id + "/gestionar", null))).isEqualTo("TRANSICION_INVALIDA");
        assertThat(codigo(put("/api/pedidos-especiales/" + id + "/listo", null))).isEqualTo("TRANSICION_INVALIDA");

        // Listo para retiro ya no lo cancela el trabajador.
        token = jwtService.emitir(yo.getUsuario());
        assertThat(codigo(put("/api/pedidos-especiales/" + id + "/cancelar", null))).isEqualTo("TRANSICION_INVALIDA");
        assertThat(codigo(put("/api/pedidos-especiales/" + id + "/confirmar-recepcion", null)))
                .isEqualTo("TRANSICION_INVALIDA");
    }

    @Test
    void rechazarExigeMotivoYCancelarEsDelDuenio() throws Exception {
        long id = crear();

        token = jwtService.emitir(companero.getUsuario());
        assertThat(put("/api/pedidos-especiales/" + id + "/cancelar", null).statusCode()).isEqualTo(403);
        assertThat(get("/api/pedidos-especiales/" + id).statusCode()).isEqualTo(403);
        assertThat(leer(get("/api/pedidos-especiales/mios"))).isEmpty();

        token = jwtService.emitir(bodeguero);
        assertThat(put("/api/pedidos-especiales/" + id + "/rechazar", "{\"motivo\": \" \"}").statusCode())
                .isEqualTo(400);
        JsonNode rechazado = leer(put("/api/pedidos-especiales/" + id + "/rechazar",
                "{\"motivo\": \"Descontinuado\"}"));
        assertThat(rechazado.get("estado").asString()).isEqualTo("RECHAZADO");
        assertThat(rechazado.get("motivoRechazo").asString()).isEqualTo("Descontinuado");
    }

    @Test
    void validaElPedidoAlCrearlo() throws Exception {
        assertThat(post("/api/pedidos-especiales", """
                {"tipo": "MATERIAL", "nombre": "X", "cantidad": 1, "descripcion": "Baño 402"}
                """).statusCode()).isEqualTo(400);
        assertThat(post("/api/pedidos-especiales", """
                {"tipo": "MATERIAL", "nombre": "Sello", "cantidad": 0, "descripcion": "Baño 402"}
                """).statusCode()).isEqualTo(400);
        assertThat(post("/api/pedidos-especiales", """
                {"tipo": "HERRAMIENTA", "nombre": "Sierra", "cantidad": 1, "descripcion": "Corte",
                 "materialId": %d}
                """.formatted(volcanita.getId())).statusCode()).isEqualTo(400);

        yo.setCuadrilla(null);
        trabajadorRepository.save(yo);
        assertThat(codigo(post("/api/pedidos-especiales", """
                {"tipo": "MATERIAL", "nombre": "Sello", "cantidad": 1, "descripcion": "Baño 402"}
                """))).isEqualTo("SIN_CUADRILLA");
    }

    @Test
    void laBandejaDeBodegaFiltraAbiertosYSinObraTraeLaEmpresa() throws Exception {
        long abierto = crear();
        long cancelado = crear();
        put("/api/pedidos-especiales/" + cancelado + "/cancelar", null);

        token = jwtService.emitir(bodeguero);
        JsonNode abiertos = leer(get("/api/pedidos-especiales?obraId=" + obra.getId() + "&soloAbiertos=true"));
        assertThat(abiertos).hasSize(1);
        assertThat(abiertos.get(0).get("id").asLong()).isEqualTo(abierto);

        JsonNode empresaEntera = leer(get("/api/pedidos-especiales"));
        assertThat(empresaEntera).hasSize(2);
        // El más nuevo primero.
        assertThat(empresaEntera.get(0).get("id").asLong()).isEqualTo(cancelado);

        token = jwtService.emitir(yo.getUsuario());
        assertThat(get("/api/pedidos-especiales").statusCode()).isEqualTo(403);
        assertThat(leer(get("/api/pedidos-especiales/mios"))).hasSize(2);
    }

    // ---------------------------------------------------------------------

    private long crear() throws Exception {
        return leer(post("/api/pedidos-especiales", """
                {"tipo": "HERRAMIENTA", "nombre": "Sierra caladora", "cantidad": 1, "descripcion": "Cortes curvos"}
                """)).get("id").asLong();
    }

    private Usuario usuario(String nombre, RolUsuario rol) {
        return usuarioRepository.save(Usuario.builder()
                .nombre(nombre).email(nombre + "@test.cl").rol(rol).empresa(empresa).build());
    }

    private Trabajador trabajador(String nombre, Cuadrilla c) {
        return trabajadorRepository.save(Trabajador.builder()
                .usuario(usuario(nombre, RolUsuario.TRABAJADOR)).cuadrilla(c)
                .credencialQr("QR-" + UUID.randomUUID()).build());
    }

    private String codigo(HttpResponse<String> r) {
        assertThat(r.statusCode()).as(r.body()).isEqualTo(409);
        return leer(r).get("codigo").asString();
    }

    private JsonNode leer(HttpResponse<String> r) {
        return json.readTree(r.body());
    }

    private HttpResponse<String> get(String ruta) throws Exception {
        return http.send(peticion(ruta).GET().build(), HttpResponse.BodyHandlers.ofString());
    }

    private HttpResponse<String> put(String ruta, String cuerpo) throws Exception {
        var p = peticion(ruta);
        if (cuerpo == null) {
            p.PUT(HttpRequest.BodyPublishers.noBody());
        } else {
            p.header("Content-Type", "application/json").PUT(HttpRequest.BodyPublishers.ofString(cuerpo));
        }
        return http.send(p.build(), HttpResponse.BodyHandlers.ofString());
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
