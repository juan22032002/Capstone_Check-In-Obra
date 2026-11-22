package cl.duocuc.checkinobra.inventario;

import cl.duocuc.checkinobra.config.Empresa;
import cl.duocuc.checkinobra.control.AlertaRepository;
import cl.duocuc.checkinobra.config.EmpresaRepository;
import cl.duocuc.checkinobra.config.JwtService;
import cl.duocuc.checkinobra.config.RolUsuario;
import cl.duocuc.checkinobra.config.Usuario;
import cl.duocuc.checkinobra.config.UsuarioRepository;
import cl.duocuc.checkinobra.cubicacion.CategoriaMaterial;
import cl.duocuc.checkinobra.cubicacion.FilaMaterial;
import cl.duocuc.checkinobra.cubicacion.Material;
import cl.duocuc.checkinobra.cubicacion.MaterialRepository;
import cl.duocuc.checkinobra.importacion.PlantillaExcel;
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

import java.io.ByteArrayOutputStream;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
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
 * Lo que pasa cuando la misma operación llega dos veces: un doble tap, un
 * reintento del móvil después de un timeout, dos bodegueros a la vez.
 *
 * <p>Contra el servidor de verdad y por HTTP, no con MockMvc: lo que se prueba
 * es el orden de los filtros (el de idempotencia tiene que ver el usuario del
 * token) y los bloqueos de fila en Postgres, y ninguna de las dos cosas existe
 * en un test de unidad.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class DobleTapYConcurrenciaTest {

    @LocalServerPort
    private int puerto;

    @Autowired private EmpresaRepository empresaRepository;
    @Autowired private UsuarioRepository usuarioRepository;
    @Autowired private ObraRepository obraRepository;
    @Autowired private CuadrillaRepository cuadrillaRepository;
    @Autowired private TrabajadorRepository trabajadorRepository;
    @Autowired private MaterialRepository materialRepository;
    @Autowired private KardexMovimientoRepository kardexMovimientoRepository;
    @Autowired private SolicitudMaterialRepository solicitudMaterialRepository;
    @Autowired private HerramientaRepository herramientaRepository;
    @Autowired private PrestamoHerramientaRepository prestamoHerramientaRepository;
    @Autowired private AlertaRepository alertaRepository;
    @Autowired private JwtService jwtService;

    private final HttpClient http = HttpClient.newHttpClient();
    private final JsonMapper json = JsonMapper.builder().build();

    private Usuario bodeguero;
    private Usuario otroBodeguero;
    private String token;
    private Obra obra;
    private Material material;
    private Trabajador trabajador;

    @BeforeEach
    void prepararObraConTreintaPlanchas() {
        // La base de test no se vacía entre corridas: todo lo único lleva sufijo.
        String s = UUID.randomUUID().toString().substring(0, 8);
        Empresa empresa = empresaRepository.save(Empresa.builder().nombre("Constructora " + s).rut("R-" + s).build());
        bodeguero = usuario(empresa, "bodega-" + s, RolUsuario.BODEGUERO);
        otroBodeguero = usuario(empresa, "bodega2-" + s, RolUsuario.BODEGUERO);
        token = jwtService.emitir(bodeguero);

        obra = obraRepository.save(Obra.builder()
                .nombre("Edificio " + s).cliente("Cliente").ubicacion("Santiago")
                .estado(EstadoObra.ACTIVA).empresa(empresa).build());
        Cuadrilla cuadrilla = cuadrillaRepository.save(Cuadrilla.builder().nombre("Tabiqueros").obra(obra).build());
        trabajador = trabajadorRepository.save(Trabajador.builder()
                .usuario(usuario(empresa, "maestro-" + s, RolUsuario.TRABAJADOR))
                .cuadrilla(cuadrilla).credencialQr("QR-" + s).build());
        material = materialRepository.save(Material.builder()
                .sku("VOL-" + s).nombre("Volcanita 10mm").categoria(CategoriaMaterial.VOLCANITA)
                .precioUnitario(5980).stockMinimo(0).empresa(empresa).build());

        kardexMovimientoRepository.save(KardexMovimiento.builder()
                .obra(obra).material(material).usuario(bodeguero)
                .tipoMovimiento(TipoMovimiento.RECEPCION).cantidad(30).fecha(LocalDateTime.now()).build());
    }

    @Test
    void elReintentoConLaMismaClaveNoDespachaDosVeces() throws Exception {
        String clave = UUID.randomUUID().toString();
        String cuerpo = despacho(10);

        HttpResponse<String> primera = post("/api/kardex", cuerpo, clave);
        HttpResponse<String> reintento = post("/api/kardex", cuerpo, clave);

        assertThat(primera.statusCode()).isEqualTo(201);
        assertThat(reintento.statusCode()).isEqualTo(201);
        assertThat(reintento.body()).isEqualTo(primera.body());
        assertThat(reintento.headers().firstValue("Idempotency-Replayed")).contains("true");
        assertThat(primera.headers().firstValue("Idempotency-Replayed")).isEmpty();
        assertThat(stock()).isEqualTo(20);
    }

    @Test
    void elDobleTapSimultaneoConLaMismaClaveTambienDespachaUnaVez() throws Exception {
        String clave = UUID.randomUUID().toString();
        String cuerpo = despacho(10);

        List<HttpResponse<String>> respuestas = aLaVez(6, () -> post("/api/kardex", cuerpo, clave));

        // Cada una recibe la respuesta de la primera, o "en curso" si llegó
        // mientras la primera se ejecutaba. Ninguna despacha otra vez.
        for (HttpResponse<String> r : respuestas) {
            if (r.statusCode() == 409) {
                assertThat(codigo(r)).isEqualTo("IDEMPOTENCIA_EN_CURSO");
            } else {
                assertThat(r.statusCode()).isEqualTo(201);
            }
        }
        assertThat(stock()).isEqualTo(20);
    }

    @Test
    void laMismaClaveConOtroCuerpoEsUnErrorDeLaApp() throws Exception {
        String clave = UUID.randomUUID().toString();
        post("/api/kardex", despacho(10), clave);

        HttpResponse<String> otra = post("/api/kardex", despacho(5), clave);

        assertThat(otra.statusCode()).isEqualTo(422);
        assertThat(codigo(otra)).isEqualTo("IDEMPOTENCIA_CLAVE_REUTILIZADA");
        assertThat(stock()).isEqualTo(20);
    }

    @Test
    void unaClaveQueNoEsUuidSeRechaza() throws Exception {
        HttpResponse<String> r = post("/api/kardex", despacho(10), "doble-tap-1");

        assertThat(r.statusCode()).isEqualTo(400);
        assertThat(stock()).isEqualTo(30);
    }

    @Test
    void elRechazoPorStockTambienSeRepiteIgual() throws Exception {
        String clave = UUID.randomUUID().toString();

        HttpResponse<String> primera = post("/api/kardex", despacho(50), clave);
        HttpResponse<String> reintento = post("/api/kardex", despacho(50), clave);

        assertThat(primera.statusCode()).isEqualTo(409);
        assertThat(codigo(primera)).isEqualTo("STOCK_INSUFICIENTE");
        assertThat(reintento.body()).isEqualTo(primera.body());
        assertThat(reintento.headers().firstValue("Idempotency-Replayed")).contains("true");
    }

    /**
     * El hueco del kardex que la clave no cubre: dos bodegueros distintos,
     * cada uno con su clave, despachando el mismo material a la vez. Antes los
     * dos leían el mismo saldo, pasaban la validación y el stock quedaba
     * negativo.
     *
     * <p>Cuarenta y no dos: con pocos hilos las peticiones llegan en fila y la
     * carrera no aparece. Sin el bloqueo de la obra, con cuarenta, falla en
     * todas las corridas.
     */
    @Test
    void despachosSimultaneosNoDejanElStockNegativo() throws Exception {
        List<HttpResponse<String>> respuestas =
                aLaVez(40, () -> post("/api/kardex", despacho(10), UUID.randomUUID().toString()));

        long despachados = respuestas.stream().filter(r -> r.statusCode() == 201).count();
        List<String> rechazos = respuestas.stream().filter(r -> r.statusCode() != 201).map(this::codigo).toList();

        assertThat(despachados).isEqualTo(3);
        assertThat(rechazos).hasSize(37).containsOnly("STOCK_INSUFICIENTE");
        assertThat(stock()).isZero();
    }

    @Test
    void quienRegistraSaleDelTokenAunqueElCuerpoDigaOtraCosa() throws Exception {
        String cuerpo = """
                {"obraId": %d, "materialId": %d, "usuarioId": %d, "trabajadorId": %d,
                 "tipo": "DESPACHO", "cantidad": 1}
                """.formatted(obra.getId(), material.getId(), otroBodeguero.getId(), trabajador.getId());

        HttpResponse<String> r = post("/api/kardex", cuerpo, null);

        assertThat(r.statusCode()).isEqualTo(201);
        assertThat(json.readTree(r.body()).get("usuarioId").asLong()).isEqualTo(bodeguero.getId());
    }

    @Test
    void enUnaObraCerradaNoSeRegistraNada() throws Exception {
        obra.setEstado(EstadoObra.CERRADA);
        obraRepository.save(obra);

        HttpResponse<String> r = post("/api/kardex", despacho(1), null);

        assertThat(r.statusCode()).isEqualTo(409);
        assertThat(codigo(r)).isEqualTo("OBRA_CERRADA");
    }

    /**
     * Dos bodegueros aprueban la misma solicitud desde la cola al mismo tiempo.
     * Antes los dos la veían PENDIENTE y salían dos despachos.
     */
    @Test
    void unaSolicitudAprobadaDosVecesALaVezDespachaUnaSola() throws Exception {
        SolicitudMaterial solicitud = solicitudMaterialRepository.save(SolicitudMaterial.builder()
                .trabajador(trabajador).material(material).obra(obra).cantidad(4)
                .estado(EstadoSolicitud.PENDIENTE).fechaSolicitud(LocalDateTime.now()).build());
        String ruta = "/api/solicitudes-material/" + solicitud.getId() + "/aprobar";

        List<HttpResponse<String>> respuestas =
                aLaVez(10, () -> put(ruta, "{\"cantidadAEntregar\": 4}", UUID.randomUUID().toString()));

        assertThat(respuestas.stream().filter(r -> r.statusCode() == 200)).hasSize(1);
        assertThat(respuestas.stream().filter(r -> r.statusCode() != 200).map(this::codigo))
                .hasSize(9).containsOnly("YA_RESUELTA");
        assertThat(stock()).isEqualTo(26);
    }

    /**
     * Un reintento de la misma planilla llega con otro separador de multipart
     * —el cliente lo inventa en cada envío—, así que la huella no puede ser la
     * de los bytes crudos. Tiene que reconocerse como la misma petición.
     */
    @Test
    void laMismaPlanillaConOtroSeparadorEsLaMismaPeticion() throws Exception {
        String admin = jwtService.emitir(usuario(bodeguero.getEmpresa(), "admin-" + UUID.randomUUID(), RolUsuario.ADMIN));
        byte[] planilla = PlantillaExcel.generar("Materiales", FilaMaterial.ENCABEZADOS, FilaMaterial.EJEMPLOS);
        String clave = UUID.randomUUID().toString();

        HttpResponse<String> primera = subirPlanilla(admin, planilla, "----separador-uno", clave);
        HttpResponse<String> reintento = subirPlanilla(admin, planilla, "----separador-dos", clave);

        assertThat(primera.statusCode()).isEqualTo(200);
        assertThat(reintento.statusCode()).isEqualTo(200);
        assertThat(reintento.headers().firstValue("Idempotency-Replayed")).contains("true");
        assertThat(reintento.body()).isEqualTo(primera.body());
    }

    /** La app abre la pantalla de alertas dos veces seguidas: una sola alerta por préstamo. */
    @Test
    void detectarDosVecesALaVezNoDuplicaLaAlerta() throws Exception {
        Herramienta taladro = herramientaRepository.save(Herramienta.builder()
                .codigoQr("TAL-" + UUID.randomUUID()).nombre("Taladro").categoria("Eléctrica")
                .estado(EstadoHerramienta.PRESTADA).valorReposicion(90000).empresa(bodeguero.getEmpresa()).build());
        prestamoHerramientaRepository.save(PrestamoHerramienta.builder()
                .herramienta(taladro).trabajador(trabajador).obra(obra).autorizadoPor(bodeguero)
                .fechaPrestamo(LocalDateTime.now().minusDays(2))
                .fechaDevolEsperada(LocalDateTime.now().minusDays(1)).build());
        String ruta = "/api/alertas/detectar-no-devueltas?obraId=" + obra.getId();

        aLaVez(6, () -> post(ruta, "", null));

        assertThat(alertaRepository.findByObraIdAndResueltoFalse(obra.getId())).hasSize(1);
    }

    @Test
    void unTokenVencidoOMalFirmadoEs401YUnRolInsuficienteEs403() throws Exception {
        token = "no.es.un-jwt";
        assertThat(post("/api/kardex", despacho(1), null).statusCode()).isEqualTo(401);

        token = jwtService.emitir(bodeguero);
        // La plantilla del catálogo es de ADMIN: el token es válido, el rol no
        // alcanza. Una ruta sin cuerpo, porque @Valid corre antes que
        // @PreAuthorize y un cuerpo inválido daría 400.
        assertThat(enviar(peticion("/api/materiales/plantilla-importacion", null).GET()).statusCode())
                .isEqualTo(403);
        assertThat(stock()).isEqualTo(30);
    }

    // ---------------------------------------------------------------------

    /** Simulación (sin {@code confirmar}): se prueba la huella, no la importación. */
    private HttpResponse<String> subirPlanilla(String jwt, byte[] planilla, String separador, String clave)
            throws Exception {
        ByteArrayOutputStream cuerpo = new ByteArrayOutputStream();
        cuerpo.write(("--" + separador + "\r\n"
                + "Content-Disposition: form-data; name=\"archivo\"; filename=\"materiales.xlsx\"\r\n"
                + "Content-Type: application/vnd.openxmlformats-officedocument.spreadsheetml.sheet\r\n\r\n")
                .getBytes(StandardCharsets.UTF_8));
        cuerpo.write(planilla);
        cuerpo.write(("\r\n--" + separador + "--\r\n").getBytes(StandardCharsets.UTF_8));

        return enviar(HttpRequest.newBuilder(URI.create("http://localhost:" + puerto + "/api/materiales/importar"))
                .header("Authorization", "Bearer " + jwt)
                .header("Content-Type", "multipart/form-data; boundary=" + separador)
                .header("Idempotency-Key", clave)
                .POST(HttpRequest.BodyPublishers.ofByteArray(cuerpo.toByteArray())));
    }

    private Usuario usuario(Empresa empresa, String nombre, RolUsuario rol) {
        return usuarioRepository.save(Usuario.builder()
                .nombre(nombre).email(nombre + "@test.cl").rol(rol).empresa(empresa).build());
    }

    private String despacho(double cantidad) {
        return """
                {"obraId": %d, "materialId": %d, "trabajadorId": %d, "tipo": "DESPACHO", "cantidad": %s}
                """.formatted(obra.getId(), material.getId(), trabajador.getId(), cantidad);
    }

    private double stock() {
        return kardexMovimientoRepository.calcularStock(obra.getId(), material.getId());
    }

    private String codigo(HttpResponse<String> r) {
        JsonNode codigo = json.readTree(r.body()).get("codigo");
        return codigo == null || codigo.isNull() ? null : codigo.asString();
    }

    private HttpResponse<String> post(String ruta, String cuerpo, String clave) throws Exception {
        return enviar(peticion(ruta, clave).POST(HttpRequest.BodyPublishers.ofString(cuerpo)));
    }

    private HttpResponse<String> put(String ruta, String cuerpo, String clave) throws Exception {
        return enviar(peticion(ruta, clave).PUT(HttpRequest.BodyPublishers.ofString(cuerpo)));
    }

    private HttpRequest.Builder peticion(String ruta, String clave) {
        HttpRequest.Builder b = HttpRequest.newBuilder(URI.create("http://localhost:" + puerto + ruta))
                .header("Authorization", "Bearer " + token)
                .header("Content-Type", "application/json");
        return clave == null ? b : b.header("Idempotency-Key", clave);
    }

    private HttpResponse<String> enviar(HttpRequest.Builder b) throws Exception {
        return http.send(b.build(), HttpResponse.BodyHandlers.ofString());
    }

    /** Suelta {@code n} peticiones a la vez, detrás de una misma largada. */
    private <T> List<T> aLaVez(int n, Callable<T> tarea) throws Exception {
        ExecutorService hilos = Executors.newFixedThreadPool(n);
        try {
            CountDownLatch largada = new CountDownLatch(1);
            List<Future<T>> futuros = new ArrayList<>();
            for (int i = 0; i < n; i++) {
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
}
