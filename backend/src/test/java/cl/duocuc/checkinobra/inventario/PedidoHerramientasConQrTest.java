package cl.duocuc.checkinobra.inventario;

import cl.duocuc.checkinobra.config.Empresa;
import cl.duocuc.checkinobra.config.EmpresaRepository;
import cl.duocuc.checkinobra.config.JwtService;
import cl.duocuc.checkinobra.config.RolUsuario;
import cl.duocuc.checkinobra.config.Usuario;
import cl.duocuc.checkinobra.config.UsuarioRepository;
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
import java.util.concurrent.Callable;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * El trabajador marca varias herramientas, recibe un QR, y el bodeguero lo
 * escanea en el mesón y entrega todo junto.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class PedidoHerramientasConQrTest {

    @LocalServerPort
    private int puerto;

    @Autowired private EmpresaRepository empresaRepository;
    @Autowired private UsuarioRepository usuarioRepository;
    @Autowired private ObraRepository obraRepository;
    @Autowired private CuadrillaRepository cuadrillaRepository;
    @Autowired private TrabajadorRepository trabajadorRepository;
    @Autowired private HerramientaRepository herramientaRepository;
    @Autowired private SolicitudHerramientaRepository solicitudHerramientaRepository;
    @Autowired private PrestamoHerramientaRepository prestamoHerramientaRepository;
    @Autowired private JwtService jwtService;

    private final HttpClient http = HttpClient.newHttpClient();
    private final JsonMapper json = JsonMapper.builder().build();

    private String s;
    private Empresa empresa;
    private Obra obra;
    private Trabajador yo;
    private Trabajador companero;
    private Usuario bodeguero;
    private Herramienta taladro;
    private Herramienta atornillador;
    private Herramienta nivel;
    private String token;

    @BeforeEach
    void preparar() {
        s = UUID.randomUUID().toString().substring(0, 8);
        empresa = empresaRepository.save(Empresa.builder().nombre("Constructora " + s).rut("R-" + s).build());
        bodeguero = usuario(empresa, "bodega-" + s, RolUsuario.BODEGUERO);
        obra = obra(empresa, "Edificio " + s);
        Cuadrilla cuadrilla = cuadrillaRepository.save(Cuadrilla.builder().nombre("Tabiqueros").obra(obra).build());
        yo = trabajador(empresa, "maestro-" + s, cuadrilla);
        companero = trabajador(empresa, "companero-" + s, cuadrilla);
        taladro = herramienta(empresa, "Taladro percutor", EstadoHerramienta.DISPONIBLE);
        atornillador = herramienta(empresa, "Atornillador", EstadoHerramienta.DISPONIBLE);
        nivel = herramienta(empresa, "Nivel láser", EstadoHerramienta.DISPONIBLE);
        token = jwtService.emitir(yo.getUsuario());
    }

    @Test
    void tresHerramientasSePidenJuntasYSeEntreganConElQr() throws Exception {
        HttpResponse<String> creado = post("/api/pedidos-herramienta", pedidoDe(taladro, atornillador, nivel));
        assertThat(creado.statusCode()).as(creado.body()).isEqualTo(201);
        JsonNode pedido = leer(creado);
        String qr = pedido.get("codigoQr").asString();
        assertThat(UUID.fromString(qr)).isNotNull();
        assertThat(pedido.get("estado").asString()).isEqualTo("PENDIENTE");
        assertThat(pedido.get("descripcion").asString()).isEqualTo("Tabiques del piso 4");
        assertThat(pedido.get("trabajador").get("id").asLong()).isEqualTo(yo.getId());
        assertThat(pedido.get("trabajador").get("nombre").asString()).isEqualTo(yo.nombre());
        JsonNode solicitudes = pedido.get("solicitudes");
        assertThat(solicitudes).hasSize(3);
        for (JsonNode sol : solicitudes) {
            assertThat(sol.get("estado").asString()).isEqualTo("PENDIENTE");
            assertThat(sol.get("pedidoId").asLong()).isEqualTo(pedido.get("id").asLong());
            assertThat(sol.get("descripcion").asString()).isEqualTo("Tabiques del piso 4");
        }

        // Puede volver a mostrar el QR.
        JsonNode mios = leer(get("/api/pedidos-herramienta/mios"));
        assertThat(mios).hasSize(1);
        assertThat(mios.get(0).get("codigoQr").asString()).isEqualTo(qr);

        // El bodeguero escanea y ve a quién le entrega.
        token = jwtService.emitir(bodeguero);
        JsonNode escaneado = leer(get("/api/pedidos-herramienta/qr/" + qr));
        assertThat(escaneado.get("trabajador").get("nombre").asString()).isEqualTo(yo.nombre());
        assertThat(escaneado.get("solicitudes")).hasSize(3);

        HttpResponse<String> entrega = put("/api/pedidos-herramienta/qr/" + qr + "/entregar", devolucion());
        assertThat(entrega.statusCode()).as(entrega.body()).isEqualTo(200);
        JsonNode e = leer(entrega);
        assertThat(e.get("pedido").get("estado").asString()).isEqualTo("ENTREGADO");
        assertThat(e.get("pedido").get("entregadoPorNombre").asString()).isEqualTo(bodeguero.getNombre());
        for (JsonNode sol : e.get("pedido").get("solicitudes")) {
            assertThat(sol.get("estado").asString()).isEqualTo("APROBADA");
            assertThat(sol.get("resueltoPorId").asLong()).isEqualTo(bodeguero.getId());
        }
        JsonNode prestamos = e.get("prestamos");
        assertThat(prestamos).hasSize(3);
        for (JsonNode p : prestamos) {
            assertThat(p.get("trabajadorId").asLong()).isEqualTo(yo.getId());
            assertThat(p.get("obraId").asLong()).isEqualTo(obra.getId());
            assertThat(p.get("herramientaEstado").asString()).isEqualTo("PRESTADA");
        }
        assertThat(prestamoHerramientaRepository.findAll().stream()
                .filter(p -> p.getTrabajador().getId().equals(yo.getId()))).hasSize(3);
        for (Herramienta h : List.of(taladro, atornillador, nivel)) {
            assertThat(herramientaRepository.findById(h.getId()).orElseThrow().getEstado())
                    .isEqualTo(EstadoHerramienta.PRESTADA);
        }
    }

    @Test
    void siUnaNoEstaDisponibleNoSePideNinguna() throws Exception {
        Herramienta prestada = herramienta(empresa, "Sierra circular", EstadoHerramienta.PRESTADA);

        assertThat(codigo(post("/api/pedidos-herramienta", pedidoDe(taladro, prestada, nivel))))
                .isEqualTo("HERRAMIENTA_NO_DISPONIBLE");
        assertThat(solicitudesDe(yo)).isEmpty();
        assertThat(leer(get("/api/pedidos-herramienta/mios"))).isEmpty();

        // Una que ya tiene pedida y pendiente también tumba el pedido entero.
        assertThat(post("/api/solicitudes-herramienta", """
                {"herramientaId": %d, "descripcion": "Perforar losa"}
                """.formatted(atornillador.getId())).statusCode()).isEqualTo(201);
        assertThat(codigo(post("/api/pedidos-herramienta", pedidoDe(taladro, atornillador))))
                .isEqualTo("SOLICITUD_DUPLICADA");
        assertThat(solicitudesDe(yo)).hasSize(1);
    }

    @Test
    void validaLaListaAntesDeTocarNada() throws Exception {
        assertThat(post("/api/pedidos-herramienta", """
                {"herramientaIds": [], "descripcion": "Tabiques del piso 4"}
                """).statusCode()).isEqualTo(400);
        assertThat(post("/api/pedidos-herramienta", """
                {"descripcion": "Tabiques del piso 4"}
                """).statusCode()).isEqualTo(400);
        assertThat(post("/api/pedidos-herramienta", """
                {"herramientaIds": [%d, %d], "descripcion": "Tabiques del piso 4"}
                """.formatted(taladro.getId(), taladro.getId())).statusCode()).isEqualTo(400);
        assertThat(post("/api/pedidos-herramienta", """
                {"herramientaIds": [%d], "descripcion": " "}
                """.formatted(taladro.getId())).statusCode()).isEqualTo(400);
        assertThat(solicitudesDe(yo)).isEmpty();

        // Pedir es del trabajador.
        token = jwtService.emitir(bodeguero);
        assertThat(post("/api/pedidos-herramienta", pedidoDe(taladro)).statusCode()).isEqualTo(403);
    }

    @Test
    void elQrSirveUnaSolaVez() throws Exception {
        String qr = crearPedido(taladro, atornillador);
        token = jwtService.emitir(bodeguero);

        assertThat(put("/api/pedidos-herramienta/qr/" + qr + "/entregar", devolucion()).statusCode())
                .isEqualTo(200);
        assertThat(codigo(put("/api/pedidos-herramienta/qr/" + qr + "/entregar", devolucion())))
                .isEqualTo("YA_RESUELTA");
        assertThat(prestamosDe(yo)).hasSize(2);
    }

    @Test
    void dosBodeguerosConElMismoQrNoPrestanDosVeces() throws Exception {
        String qr = crearPedido(taladro, atornillador, nivel);
        Usuario otroBodeguero = usuario(empresa, "bodega2-" + s, RolUsuario.BODEGUERO);
        String ruta = "/api/pedidos-herramienta/qr/" + qr + "/entregar";

        List<HttpResponse<String>> respuestas = aLaVez(List.of(
                () -> enviar(peticion(ruta, jwtService.emitir(bodeguero)), devolucion()),
                () -> enviar(peticion(ruta, jwtService.emitir(otroBodeguero)), devolucion()),
                () -> enviar(peticion(ruta, jwtService.emitir(bodeguero)), devolucion())));

        assertThat(respuestas.stream().filter(r -> r.statusCode() == 200)).hasSize(1);
        assertThat(respuestas.stream().filter(r -> r.statusCode() == 409)).hasSize(2);
        assertThat(prestamosDe(yo)).hasSize(3);
    }

    @Test
    void unQrDeOtraEmpresaEsIgualAUnoQueNoExiste() throws Exception {
        String qr = crearPedido(taladro);

        Empresa otra = empresaRepository.save(Empresa.builder().nombre("Competencia " + s).rut("C-" + s).build());
        token = jwtService.emitir(usuario(otra, "intruso-" + s, RolUsuario.BODEGUERO));

        HttpResponse<String> ajeno = get("/api/pedidos-herramienta/qr/" + qr);
        HttpResponse<String> inventado = get("/api/pedidos-herramienta/qr/" + UUID.randomUUID());
        assertThat(ajeno.statusCode()).isEqualTo(404);
        assertThat(inventado.statusCode()).isEqualTo(404);
        assertThat(leer(ajeno).get("mensaje").asString()).isEqualTo(leer(inventado).get("mensaje").asString());

        assertThat(put("/api/pedidos-herramienta/qr/" + qr + "/entregar", devolucion()).statusCode())
                .isEqualTo(404);
        assertThat(prestamosDe(yo)).isEmpty();
    }

    @Test
    void elPrefijoDeLaAppNoConfundeAlBackend() throws Exception {
        String qr = crearPedido(taladro);
        token = jwtService.emitir(bodeguero);
        assertThat(get("/api/pedidos-herramienta/qr/PEDIDO:" + qr).statusCode()).isEqualTo(200);
    }

    @Test
    void cancelarEsDelDuenioYSoloMientrasEstaPendiente() throws Exception {
        String qr = crearPedido(taladro, atornillador);
        long id = leer(get("/api/pedidos-herramienta/mios")).get(0).get("id").asLong();

        token = jwtService.emitir(companero.getUsuario());
        assertThat(put("/api/pedidos-herramienta/" + id + "/cancelar", null).statusCode()).isEqualTo(403);
        assertThat(leer(get("/api/pedidos-herramienta/mios"))).isEmpty();

        token = jwtService.emitir(yo.getUsuario());
        JsonNode cancelado = leer(put("/api/pedidos-herramienta/" + id + "/cancelar", null));
        assertThat(cancelado.get("estado").asString()).isEqualTo("CANCELADO");
        for (JsonNode sol : cancelado.get("solicitudes")) {
            assertThat(sol.get("estado").asString()).isEqualTo("CANCELADA");
        }
        assertThat(codigo(put("/api/pedidos-herramienta/" + id + "/cancelar", null))).isEqualTo("YA_RESUELTA");

        // Un QR cancelado no se entrega.
        token = jwtService.emitir(bodeguero);
        assertThat(codigo(put("/api/pedidos-herramienta/qr/" + qr + "/entregar", devolucion())))
                .isEqualTo("YA_RESUELTA");
        assertThat(prestamosDe(yo)).isEmpty();
    }

    @Test
    void losPendientesVanPrimeroEnMisPedidos() throws Exception {
        crearPedido(taladro);
        long cancelado = leer(get("/api/pedidos-herramienta/mios")).get(0).get("id").asLong();
        put("/api/pedidos-herramienta/" + cancelado + "/cancelar", null);
        String vigente = crearPedido(atornillador);

        // Uno más viejo pero pendiente debe quedar sobre uno más nuevo y cerrado.
        JsonNode mios = leer(get("/api/pedidos-herramienta/mios"));
        assertThat(mios).hasSize(2);
        assertThat(mios.get(0).get("codigoQr").asString()).isEqualTo(vigente);
        assertThat(mios.get(1).get("estado").asString()).isEqualTo("CANCELADO");
    }

    @Test
    void unaSolicitudDelPedidoNoSeResuelveSuelta() throws Exception {
        String qr = crearPedido(taladro, atornillador);
        long taladroSolicitud = solicitudesDe(yo).stream()
                .filter(sol -> sol.getHerramienta().getId().equals(taladro.getId()))
                .findFirst().orElseThrow().getId();
        String ruta = "/api/solicitudes-herramienta/" + taladroSolicitud;

        // Ni el trabajador desde su lista, ni bodega desde la cola: el QR
        // quedaría prometiendo algo que ya no entrega.
        assertThat(codigo(put(ruta + "/cancelar", null))).isEqualTo("EN_PEDIDO");
        token = jwtService.emitir(bodeguero);
        assertThat(codigo(put(ruta + "/aprobar", devolucion()))).isEqualTo("EN_PEDIDO");
        assertThat(codigo(put(ruta + "/rechazar", "{\"motivo\": \"En mantención\"}"))).isEqualTo("EN_PEDIDO");
        assertThat(prestamosDe(yo)).isEmpty();

        JsonNode e = leer(put("/api/pedidos-herramienta/qr/" + qr + "/entregar", devolucion()));
        assertThat(e.get("prestamos")).hasSize(2);

        // Ya entregado, confirmar la recepción sí es de a una.
        token = jwtService.emitir(yo.getUsuario());
        assertThat(put(ruta + "/confirmar-recepcion", null).statusCode()).isEqualTo(200);
    }

    // ---------------------------------------------------------------------

    private String crearPedido(Herramienta... herramientas) throws Exception {
        HttpResponse<String> r = post("/api/pedidos-herramienta", pedidoDe(herramientas));
        assertThat(r.statusCode()).as(r.body()).isEqualTo(201);
        return leer(r).get("codigoQr").asString();
    }

    private String pedidoDe(Herramienta... herramientas) {
        List<String> ids = new ArrayList<>();
        for (Herramienta h : herramientas) {
            ids.add(String.valueOf(h.getId()));
        }
        return """
                {"herramientaIds": [%s], "descripcion": "Tabiques del piso 4"}
                """.formatted(String.join(", ", ids));
    }

    private String devolucion() {
        return """
                {"fechaDevolEsperada": "%s"}
                """.formatted(LocalDateTime.now().plusDays(1).withNano(0));
    }

    private List<SolicitudHerramienta> solicitudesDe(Trabajador t) {
        return solicitudHerramientaRepository.findByTrabajadorId(t.getId());
    }

    private List<PrestamoHerramienta> prestamosDe(Trabajador t) {
        return prestamoHerramientaRepository.findAll().stream()
                .filter(p -> p.getTrabajador().getId().equals(t.getId()))
                .toList();
    }

    private Usuario usuario(Empresa e, String nombre, RolUsuario rol) {
        return usuarioRepository.save(Usuario.builder()
                .nombre(nombre).email(nombre + "@test.cl").rol(rol).empresa(e).build());
    }

    private Obra obra(Empresa e, String nombre) {
        return obraRepository.save(Obra.builder()
                .nombre(nombre).cliente("Cliente").ubicacion("Santiago")
                .estado(EstadoObra.ACTIVA).empresa(e).build());
    }

    private Trabajador trabajador(Empresa e, String nombre, Cuadrilla c) {
        return trabajadorRepository.save(Trabajador.builder()
                .usuario(usuario(e, nombre, RolUsuario.TRABAJADOR)).cuadrilla(c)
                .credencialQr("QR-" + UUID.randomUUID()).build());
    }

    private Herramienta herramienta(Empresa e, String nombre, EstadoHerramienta estado) {
        return herramientaRepository.save(Herramienta.builder()
                .codigoQr("H-" + UUID.randomUUID()).nombre(nombre).categoria("Eléctrica")
                .estado(estado).valorReposicion(90000).empresa(e).build());
    }

    private <T> List<T> aLaVez(List<Callable<T>> tareas) throws Exception {
        ExecutorService hilos = Executors.newFixedThreadPool(tareas.size());
        try {
            CountDownLatch largada = new CountDownLatch(1);
            List<Future<T>> futuros = new ArrayList<>();
            for (Callable<T> tarea : tareas) {
                futuros.add(hilos.submit(() -> {
                    largada.await();
                    return tarea.call();
                }));
            }
            largada.countDown();
            List<T> resultados = new ArrayList<>();
            for (Future<T> f : futuros) {
                resultados.add(f.get());
            }
            return resultados;
        } finally {
            hilos.shutdown();
        }
    }

    private String codigo(HttpResponse<String> r) {
        assertThat(r.statusCode()).as(r.body()).isEqualTo(409);
        return leer(r).get("codigo").asString();
    }

    private JsonNode leer(HttpResponse<String> r) {
        return json.readTree(r.body());
    }

    private HttpResponse<String> get(String ruta) throws Exception {
        return http.send(peticion(ruta, token).GET().build(), HttpResponse.BodyHandlers.ofString());
    }

    private HttpResponse<String> put(String ruta, String cuerpo) throws Exception {
        return enviar(peticion(ruta, token), cuerpo);
    }

    private HttpResponse<String> enviar(HttpRequest.Builder p, String cuerpo) throws Exception {
        if (cuerpo == null) {
            p.PUT(HttpRequest.BodyPublishers.noBody());
        } else {
            p.header("Content-Type", "application/json").PUT(HttpRequest.BodyPublishers.ofString(cuerpo));
        }
        return http.send(p.build(), HttpResponse.BodyHandlers.ofString());
    }

    private HttpResponse<String> post(String ruta, String cuerpo) throws Exception {
        return http.send(peticion(ruta, token)
                        .header("Content-Type", "application/json")
                        .POST(HttpRequest.BodyPublishers.ofString(cuerpo)).build(),
                HttpResponse.BodyHandlers.ofString());
    }

    private HttpRequest.Builder peticion(String ruta, String jwt) {
        return HttpRequest.newBuilder(URI.create("http://localhost:" + puerto + ruta))
                .header("Authorization", "Bearer " + jwt);
    }
}
