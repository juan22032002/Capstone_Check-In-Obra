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
import tools.jackson.databind.json.JsonMapper;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.LocalDateTime;
import java.util.List;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * SEG12 (#100, S-17, S-19, S-26): las reglas de negocio que faltaban, probadas por HTTP contra el
 * servidor real, con la misma petición que la auditoría mostró aceptada y ahora bloqueada.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class ReglasDeNegocioPorHttpTest {

    @LocalServerPort private int puerto;

    @Autowired private EmpresaRepository empresaRepository;
    @Autowired private UsuarioRepository usuarioRepository;
    @Autowired private ObraRepository obraRepository;
    @Autowired private CuadrillaRepository cuadrillaRepository;
    @Autowired private TrabajadorRepository trabajadorRepository;
    @Autowired private MaterialRepository materialRepository;
    @Autowired private HerramientaRepository herramientaRepository;
    @Autowired private KardexMovimientoRepository kardexMovimientoRepository;
    @Autowired private SolicitudMaterialRepository solicitudMaterialRepository;
    @Autowired private JwtService jwtService;

    private final HttpClient http = HttpClient.newHttpClient();
    private final JsonMapper json = JsonMapper.builder().build();

    private Empresa empresa;
    private Usuario bodeguero;
    private Usuario jefe;
    private Usuario admin;
    private Usuario usuarioTrabajador;
    private Obra obra;
    private Obra otraObra;
    private Cuadrilla cuadrilla;
    private Cuadrilla cuadrillaDeOtraObra;
    private Material material;
    private Trabajador trabajador;
    private Trabajador trabajadorDeOtraObra;
    private Trabajador trabajadorSinCuadrilla;

    @BeforeEach
    void preparar() {
        String s = UUID.randomUUID().toString().substring(0, 8);
        empresa = empresaRepository.save(Empresa.builder().nombre("Constructora " + s).rut("R-" + s).build());
        bodeguero = usuario("bodega-" + s, RolUsuario.BODEGUERO);
        jefe = usuario("jefe-" + s, RolUsuario.JEFE_TERRENO);
        admin = usuario("admin-" + s, RolUsuario.ADMIN);
        usuarioTrabajador = usuario("maestro-" + s, RolUsuario.TRABAJADOR);

        obra = obra("Edificio " + s);
        otraObra = obra("Casa " + s);
        cuadrilla = cuadrillaRepository.save(Cuadrilla.builder().nombre("Tabiqueros").obra(obra).build());
        cuadrillaDeOtraObra = cuadrillaRepository.save(Cuadrilla.builder().nombre("Pintores").obra(otraObra).build());

        trabajador = trabajador(usuarioTrabajador, cuadrilla, "QR-A-" + s);
        trabajadorDeOtraObra = trabajador(usuario("otro-" + s, RolUsuario.TRABAJADOR), cuadrillaDeOtraObra, "QR-B-" + s);
        trabajadorSinCuadrilla = trabajador(usuario("libre-" + s, RolUsuario.TRABAJADOR), null, "QR-C-" + s);

        material = materialRepository.save(Material.builder()
                .sku("VOL-" + s).nombre("Volcanita 10mm").categoria(CategoriaMaterial.VOLCANITA)
                .precioUnitario(5980).stockMinimo(0).empresa(empresa).build());
        kardexMovimientoRepository.save(KardexMovimiento.builder()
                .obra(obra).material(material).usuario(bodeguero)
                .tipoMovimiento(TipoMovimiento.RECEPCION).cantidad(30).fecha(LocalDateTime.now()).build());
    }

    // ---- S-17: lo que se entrega no puede pasar de lo pedido ----------------------------------

    @Test
    void noSePuedeAprobarMasDeLoSolicitado() throws Exception {
        long solicitud = solicitar(10);

        HttpResponse<String> r = aprobar(solicitud, 30);

        assertThat(r.statusCode()).isEqualTo(400);
        assertThat(stock()).isEqualTo(30);
        assertThat(solicitudMaterialRepository.findById(solicitud).orElseThrow().getEstado())
                .isEqualTo(EstadoSolicitud.PENDIENTE);
    }

    @Test
    void unaCantidadACeroONegativaTampocoSeAprueba() throws Exception {
        long solicitud = solicitar(10);

        assertThat(aprobar(solicitud, 0).statusCode()).isEqualTo(400);
        assertThat(aprobar(solicitud, -5).statusCode()).isEqualTo(400);
        assertThat(stock()).isEqualTo(30);
    }

    @Test
    void sePuedeAprobarLoPedidoOMenos() throws Exception {
        // Una a la vez: develop ya no deja pedir lo mismo mientras hay una pendiente (#76).
        long completa = solicitar(10);
        assertThat(aprobar(completa, 10).statusCode()).isEqualTo(200);
        long parcial = solicitar(8);
        assertThat(aprobar(parcial, 5).statusCode()).isEqualTo(200);
        assertThat(stock()).isEqualTo(15);
    }

    // ---- S-26: el trabajador tiene que ser de la obra -----------------------------------------

    @Test
    void unDespachoNoPuedeNombrarAUnTrabajadorDeOtraObra() throws Exception {
        HttpResponse<String> r = despachar(trabajadorDeOtraObra.getId(), 5);

        assertThat(r.statusCode()).isEqualTo(409);
        assertThat(codigo(r)).isEqualTo("OBRA_NO_ASIGNADA");
        assertThat(stock()).isEqualTo(30);
    }

    @Test
    void unDespachoANombreDeUnTrabajadorSinCuadrillaSeRechaza() throws Exception {
        HttpResponse<String> r = despachar(trabajadorSinCuadrilla.getId(), 5);

        assertThat(r.statusCode()).isEqualTo(409);
        assertThat(codigo(r)).isEqualTo("SIN_CUADRILLA");
        assertThat(stock()).isEqualTo(30);
    }

    @Test
    void unDespachoAUnTrabajadorDeLaObraSigueFuncionando() throws Exception {
        assertThat(despachar(trabajador.getId(), 5).statusCode()).isEqualTo(201);
        assertThat(stock()).isEqualTo(25);
    }

    @Test
    void unPrestamoNoPuedeNombrarAUnTrabajadorDeOtraObra() throws Exception {
        Herramienta herramienta = herramienta("TAL-" + UUID.randomUUID().toString().substring(0, 6));

        HttpResponse<String> r = prestar(herramienta.getId(), trabajadorDeOtraObra.getId());

        assertThat(r.statusCode()).isEqualTo(409);
        assertThat(codigo(r)).isEqualTo("OBRA_NO_ASIGNADA");
        assertThat(herramientaRepository.findById(herramienta.getId()).orElseThrow().getEstado())
                .isEqualTo(EstadoHerramienta.DISPONIBLE);
    }

    @Test
    void unPrestamoAUnTrabajadorDeLaObraSigueFuncionando() throws Exception {
        Herramienta herramienta = herramienta("TAL-" + UUID.randomUUID().toString().substring(0, 6));

        assertThat(prestar(herramienta.getId(), trabajador.getId()).statusCode()).isEqualTo(201);
    }

    // ---- S-19: los GET de la gestión no son del trabajador ------------------------------------

    @Test
    void unTrabajadorNoLeeFichasAlertasPartidasNiCuadrillas() throws Exception {
        String token = jwtService.emitir(usuarioTrabajador);

        for (String ruta : rutasDeGestion()) {
            assertThat(get(ruta, token).statusCode()).as(ruta).isEqualTo(403);
        }
    }

    @Test
    void ladministracionLaJefaturaYBodegaSiLasLeen() throws Exception {
        for (Usuario quien : List.of(admin, jefe, bodeguero)) {
            String token = jwtService.emitir(quien);
            for (String ruta : rutasDeGestion()) {
                int estado = get(ruta, token).statusCode();
                // 200, o 404 si el id de la ruta no existe: lo que no puede ser es un 403.
                assertThat(estado).as(quien.getRol() + " " + ruta).isIn(200, 404);
            }
        }
    }

    @Test
    void laFichaPropiaDelTrabajadorSigueDisponible() throws Exception {
        assertThat(get("/api/trabajadores/yo", jwtService.emitir(usuarioTrabajador)).statusCode()).isEqualTo(200);
    }

    private List<String> rutasDeGestion() {
        return List.of(
                "/api/trabajadores/" + trabajador.getId(),
                "/api/trabajadores?obraId=" + obra.getId(),
                "/api/alertas?obraId=" + obra.getId(),
                "/api/partidas?obraId=" + obra.getId(),
                "/api/partidas/999999",
                "/api/partidas/999999/items-cubicados",
                "/api/cuadrillas?obraId=" + obra.getId(),
                "/api/cuadrillas/" + cuadrilla.getId());
    }

    // ---- soporte ------------------------------------------------------------------------------

    private Usuario usuario(String nombre, RolUsuario rol) {
        return usuarioRepository.save(Usuario.builder()
                .nombre(nombre).email(nombre + "@test.cl").rol(rol).empresa(empresa).build());
    }

    private Obra obra(String nombre) {
        return obraRepository.save(Obra.builder()
                .nombre(nombre).cliente("Cliente").ubicacion("Santiago")
                .estado(EstadoObra.ACTIVA).empresa(empresa).build());
    }

    private Trabajador trabajador(Usuario usuario, Cuadrilla cuadrilla, String credencial) {
        return trabajadorRepository.save(
                Trabajador.builder().usuario(usuario).cuadrilla(cuadrilla).credencialQr(credencial).build());
    }

    private Herramienta herramienta(String codigo) {
        return herramientaRepository.save(Herramienta.builder()
                .codigoQr(codigo).nombre("Taladro").categoria("Eléctrica").valorReposicion(50000)
                .estado(EstadoHerramienta.DISPONIBLE).empresa(empresa).build());
    }

    private long solicitar(double cantidad) throws Exception {
        HttpResponse<String> r = enviar("POST", "/api/solicitudes-material", jwtService.emitir(usuarioTrabajador),
                """
                {"materialId": %d, "obraId": %d, "cantidad": %s, "descripcion": "Para el tabique del piso 2"}
                """.formatted(material.getId(), obra.getId(), cantidad));
        assertThat(r.statusCode()).as(r.body()).isEqualTo(201);
        return json.readTree(r.body()).get("id").asLong();
    }

    private HttpResponse<String> aprobar(long solicitud, double cantidad) throws Exception {
        return enviar("PUT", "/api/solicitudes-material/" + solicitud + "/aprobar", jwtService.emitir(bodeguero),
                "{\"cantidadAEntregar\": " + cantidad + "}");
    }

    private HttpResponse<String> despachar(Long trabajadorId, double cantidad) throws Exception {
        return enviar("POST", "/api/kardex", jwtService.emitir(bodeguero),
                """
                {"obraId": %d, "materialId": %d, "trabajadorId": %d, "tipo": "DESPACHO", "cantidad": %s}
                """.formatted(obra.getId(), material.getId(), trabajadorId, cantidad));
    }

    private HttpResponse<String> prestar(Long herramientaId, Long trabajadorId) throws Exception {
        return enviar("POST", "/api/prestamos-herramienta", jwtService.emitir(bodeguero),
                """
                {"herramientaId": %d, "trabajadorId": %d, "obraId": %d, "fechaDevolEsperada": "%s"}
                """.formatted(herramientaId, trabajadorId, obra.getId(), LocalDateTime.now().plusDays(2)));
    }

    private double stock() {
        return kardexMovimientoRepository.calcularStock(obra.getId(), material.getId());
    }

    private String codigo(HttpResponse<String> r) {
        return json.readTree(r.body()).path("codigo").asString();
    }

    private HttpResponse<String> get(String ruta, String token) throws Exception {
        return enviar("GET", ruta, token, null);
    }

    private HttpResponse<String> enviar(String metodo, String ruta, String token, String cuerpo) throws Exception {
        HttpRequest.Builder b = HttpRequest.newBuilder(URI.create("http://localhost:" + puerto + ruta))
                .header("Authorization", "Bearer " + token)
                .header("Content-Type", "application/json");
        if ("POST".equals(metodo) && ruta.equals("/api/kardex")) {
            b.header("Idempotency-Key", UUID.randomUUID().toString());
        }
        b.method(metodo, cuerpo == null ? HttpRequest.BodyPublishers.noBody() : HttpRequest.BodyPublishers.ofString(cuerpo));
        return http.send(b.build(), HttpResponse.BodyHandlers.ofString());
    }
}
