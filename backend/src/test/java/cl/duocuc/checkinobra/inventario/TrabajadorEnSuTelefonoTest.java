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
import java.time.LocalDateTime;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Lo que hace un trabajador desde su teléfono: ver su credencial, pedir
 * material y herramientas, seguir lo que pidió y retirarlo.
 *
 * <p>La mitad de estas pruebas son de lo que <em>no</em> puede hacer. El rol
 * TRABAJADOR es el único cuyo acceso depende de quién es el dueño del dato, y
 * antes un trabajador listaba las solicitudes de un compañero, o renovaba su
 * credencial y se quedaba con el código nuevo.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class TrabajadorEnSuTelefonoTest {

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
    @Autowired private JwtService jwtService;

    private final HttpClient http = HttpClient.newHttpClient();
    private final JsonMapper json = JsonMapper.builder().build();

    private String s;
    private Empresa empresa;
    private Usuario bodeguero;
    private Obra obra;
    private Cuadrilla cuadrilla;
    private Trabajador yo;
    private Trabajador companero;
    private Material volcanita;
    private Herramienta taladro;
    private String token;

    @BeforeEach
    void prepararCuadrilla() {
        // La base de test no se vacía entre corridas: todo lo único lleva sufijo.
        s = UUID.randomUUID().toString().substring(0, 8);
        empresa = empresaRepository.save(Empresa.builder().nombre("Constructora " + s).rut("R-" + s).build());
        bodeguero = usuario("bodega-" + s, RolUsuario.BODEGUERO);
        obra = obra("Edificio " + s);
        cuadrilla = cuadrillaRepository.save(Cuadrilla.builder().nombre("Tabiqueros").obra(obra).build());
        yo = trabajador("maestro-" + s, cuadrilla, "QR-" + s);
        companero = trabajador("companero-" + s, cuadrilla, "QR2-" + s);
        volcanita = materialRepository.save(Material.builder()
                .sku("VOL-" + s).nombre("Volcanita 10mm").categoria(CategoriaMaterial.VOLCANITA)
                .precioUnitario(5980).stockMinimo(0).empresa(empresa).build());
        taladro = herramienta("Taladro percutor", EstadoHerramienta.DISPONIBLE);
        token = jwtService.emitir(yo.getUsuario());
    }

    // --- perfil y credencial -----------------------------------------------

    @Test
    void elTrabajadorVeSuFichaConSuObraYSuCredencial() throws Exception {
        JsonNode ficha = leer(get("/api/trabajadores/yo"));

        assertThat(ficha.get("id").asLong()).isEqualTo(yo.getId());
        assertThat(ficha.get("cuadrillaNombre").asString()).isEqualTo("Tabiqueros");
        assertThat(ficha.get("obraId").asLong()).isEqualTo(obra.getId());
        assertThat(ficha.get("obraEstado").asString()).isEqualTo("ACTIVA");
        assertThat(ficha.get("credencialQr").asString()).isEqualTo("QR-" + s);
    }

    @Test
    void sinCredencialSeLeEmiteAlAbrirSuFicha() throws Exception {
        yo.setCredencialQr(null);
        trabajadorRepository.save(yo);

        String emitida = leer(get("/api/trabajadores/yo")).get("credencialQr").asString();

        assertThat(emitida).isNotBlank();
        // Y es estable: abrir la pantalla otra vez no la cambia.
        assertThat(leer(get("/api/trabajadores/yo")).get("credencialQr").asString()).isEqualTo(emitida);
    }

    @Test
    void renuevaLaSuyaPeroNoLaDeUnCompanero() throws Exception {
        HttpResponse<String> propia = put("/api/trabajadores/yo/credencial");
        assertThat(propia.statusCode()).isEqualTo(200);
        assertThat(leer(propia).get("credencialQr").asString()).isNotEqualTo("QR-" + s);

        // Con el id de otro: la respuesta traería el código nuevo del compañero.
        assertThat(put("/api/trabajadores/" + companero.getId() + "/credencial").statusCode()).isEqualTo(403);
        assertThat(trabajadorRepository.findById(companero.getId()).orElseThrow().getCredencialQr())
                .isEqualTo("QR2-" + s);
    }

    // --- lo mío ------------------------------------------------------------

    @Test
    void veSoloLoSuyoYLaMasNuevaPrimero() throws Exception {
        Herramienta esmeril = herramienta("Esmeril", EstadoHerramienta.DISPONIBLE);
        post("/api/solicitudes-herramienta", herramienta(taladro));
        long segunda = leer(post("/api/solicitudes-herramienta", herramienta(esmeril)))
                .get("id").asLong();
        token = jwtService.emitir(companero.getUsuario());
        post("/api/solicitudes-material", "{\"materialId\": " + volcanita.getId() + ", \"cantidad\": 3, \"descripcion\": \"Tabique eje 3\"}");
        prestamo(companero);
        token = jwtService.emitir(yo.getUsuario());

        JsonNode mias = leer(get("/api/solicitudes-herramienta/mias"));
        assertThat(mias).hasSize(2);
        assertThat(mias.get(0).get("id").asLong()).isEqualTo(segunda);
        assertThat(leer(get("/api/solicitudes-material/mias"))).isEmpty();
        assertThat(leer(get("/api/prestamos-herramienta/mios"))).isEmpty();
    }

    @Test
    void loDeUnCompaneroNoSeVeNiPorIdNiPorObra() throws Exception {
        token = jwtService.emitir(companero.getUsuario());
        long ajena = leer(post("/api/solicitudes-material",
                "{\"materialId\": " + volcanita.getId() + ", \"cantidad\": 3, \"descripcion\": \"Tabique eje 3\"}")).get("id").asLong();
        long prestamo = prestamo(companero).getId();
        token = jwtService.emitir(yo.getUsuario());

        assertThat(get("/api/solicitudes-material?trabajadorId=" + companero.getId()).statusCode()).isEqualTo(403);
        assertThat(get("/api/solicitudes-material/" + ajena).statusCode()).isEqualTo(403);
        assertThat(get("/api/solicitudes-material?obraId=" + obra.getId()).statusCode()).isEqualTo(403);
        assertThat(get("/api/prestamos-herramienta/" + prestamo).statusCode()).isEqualTo(403);
        assertThat(get("/api/prestamos-herramienta?soloVencidos=true").statusCode()).isEqualTo(403);
        assertThat(get("/api/solicitudes-herramienta?obraId=" + obra.getId()).statusCode()).isEqualTo(403);
        // Lo suyo por id sí.
        assertThat(get("/api/solicitudes-material?trabajadorId=" + yo.getId()).statusCode()).isEqualTo(200);

        // El bodeguero sigue viendo la obra entera.
        token = jwtService.emitir(bodeguero);
        assertThat(leer(get("/api/solicitudes-material?obraId=" + obra.getId()))).hasSize(1);
        assertThat(get("/api/solicitudes-material/" + ajena).statusCode()).isEqualTo(200);
    }

    // --- pedir material ----------------------------------------------------

    @Test
    void sinObraEnElPedidoSeUsaLaDeSuCuadrilla() throws Exception {
        HttpResponse<String> r = post("/api/solicitudes-material",
                "{\"materialId\": " + volcanita.getId() + ", \"cantidad\": 3, \"descripcion\": \"Tabique eje 3\"}");

        assertThat(r.statusCode()).isEqualTo(201);
        assertThat(leer(r).get("obraId").asLong()).isEqualTo(obra.getId());
    }

    @Test
    void noPidePorOtraObraNiSinCuadrillaNiEnUnaCerradaNiEnCero() throws Exception {
        Obra otra = obra("Otra " + s);
        assertThat(codigo(post("/api/solicitudes-material",
                "{\"materialId\": %d, \"obraId\": %d, \"cantidad\": 3, \"descripcion\": \"Tabique eje 3\"}".formatted(volcanita.getId(), otra.getId()))))
                .isEqualTo("OBRA_NO_ASIGNADA");
        assertThat(post("/api/solicitudes-material",
                "{\"materialId\": " + volcanita.getId() + ", \"cantidad\": 0, \"descripcion\": \"Tabique eje 3\"}").statusCode()).isEqualTo(400);

        obra.setEstado(EstadoObra.CERRADA);
        obraRepository.save(obra);
        assertThat(codigo(post("/api/solicitudes-material",
                "{\"materialId\": " + volcanita.getId() + ", \"cantidad\": 3, \"descripcion\": \"Tabique eje 3\"}"))).isEqualTo("OBRA_CERRADA");

        yo.setCuadrilla(null);
        trabajadorRepository.save(yo);
        assertThat(codigo(post("/api/solicitudes-material",
                "{\"materialId\": " + volcanita.getId() + ", \"cantidad\": 3, \"descripcion\": \"Tabique eje 3\"}"))).isEqualTo("SIN_CUADRILLA");
    }

    // --- pedir herramienta -------------------------------------------------

    @Test
    void noPideUnaHerramientaPrestadaNiDosVecesLaMismaNiVarias() throws Exception {
        Herramienta prestada = herramienta("Rotomartillo", EstadoHerramienta.PRESTADA);
        assertThat(codigo(post("/api/solicitudes-herramienta", herramienta(prestada))))
                .isEqualTo("HERRAMIENTA_NO_DISPONIBLE");

        assertThat(post("/api/solicitudes-herramienta",
                "{\"herramientaId\": " + taladro.getId() + ", \"cantidad\": 2, \"descripcion\": \"Tabique eje 3\"}").statusCode()).isEqualTo(400);

        HttpResponse<String> primera = post("/api/solicitudes-herramienta",
                "{\"herramientaId\": " + taladro.getId() + ", \"cantidad\": 1, \"descripcion\": \"Tabique eje 3\"}");
        assertThat(primera.statusCode()).isEqualTo(201);
        assertThat(leer(primera).get("cantidad").asInt()).isEqualTo(1);
        assertThat(codigo(post("/api/solicitudes-herramienta", herramienta(taladro))))
                .isEqualTo("SOLICITUD_DUPLICADA");
    }

    // --- cancelar ----------------------------------------------------------

    @Test
    void cancelaLaSuyaPendienteUnaSolaVez() throws Exception {
        long id = leer(post("/api/solicitudes-herramienta", herramienta(taladro)))
                .get("id").asLong();

        HttpResponse<String> cancelada = put("/api/solicitudes-herramienta/" + id + "/cancelar");
        assertThat(cancelada.statusCode()).isEqualTo(200);
        assertThat(leer(cancelada).get("estado").asString()).isEqualTo("CANCELADA");
        assertThat(codigo(put("/api/solicitudes-herramienta/" + id + "/cancelar"))).isEqualTo("YA_RESUELTA");

        // Cancelada ya no cuenta como duplicado: puede volver a pedirla.
        assertThat(post("/api/solicitudes-herramienta", herramienta(taladro)).statusCode())
                .isEqualTo(201);
    }

    @Test
    void noCancelaLaDeUnCompanero() throws Exception {
        token = jwtService.emitir(companero.getUsuario());
        long ajena = leer(post("/api/solicitudes-material",
                "{\"materialId\": " + volcanita.getId() + ", \"cantidad\": 3, \"descripcion\": \"Tabique eje 3\"}")).get("id").asLong();
        token = jwtService.emitir(yo.getUsuario());

        assertThat(put("/api/solicitudes-material/" + ajena + "/cancelar").statusCode()).isEqualTo(403);
    }

    // --- para qué y recepción ----------------------------------------------

    @Test
    void sinParaQueNoSePide() throws Exception {
        assertThat(post("/api/solicitudes-material",
                "{\"materialId\": " + volcanita.getId() + ", \"cantidad\": 3}").statusCode()).isEqualTo(400);
        assertThat(post("/api/solicitudes-herramienta",
                "{\"herramientaId\": " + taladro.getId() + ", \"descripcion\": \"   \"}").statusCode())
                .isEqualTo(400);

        HttpResponse<String> r = post("/api/solicitudes-material",
                "{\"materialId\": " + volcanita.getId() + ", \"cantidad\": 3, \"descripcion\": \"  Tabique eje 3 \"}");
        assertThat(leer(r).get("descripcion").asString()).isEqualTo("Tabique eje 3");
    }

    @Test
    void confirmaLaRecepcionSoloDeLoQueBodegaYaAprobo() throws Exception {
        long id = leer(post("/api/solicitudes-herramienta", herramienta(taladro))).get("id").asLong();
        assertThat(codigo(put("/api/solicitudes-herramienta/" + id + "/confirmar-recepcion")))
                .isEqualTo("NO_ENTREGADA");

        token = jwtService.emitir(bodeguero);
        assertThat(http.send(peticion("/api/solicitudes-herramienta/" + id + "/aprobar")
                        .header("Content-Type", "application/json")
                        .PUT(HttpRequest.BodyPublishers.ofString(
                                "{\"fechaDevolEsperada\": \"" + LocalDateTime.now().plusDays(3) + "\"}"))
                        .build(), HttpResponse.BodyHandlers.ofString()).statusCode())
                .isEqualTo(200);
        // El bodeguero no confirma por el trabajador.
        assertThat(put("/api/solicitudes-herramienta/" + id + "/confirmar-recepcion").statusCode()).isEqualTo(403);

        token = jwtService.emitir(yo.getUsuario());
        HttpResponse<String> recibida = put("/api/solicitudes-herramienta/" + id + "/confirmar-recepcion");
        assertThat(recibida.statusCode()).isEqualTo(200);
        assertThat(leer(recibida).get("estado").asString()).isEqualTo("ENTREGADA");
        assertThat(leer(recibida).get("fechaRecepcion").isNull()).isFalse();
        assertThat(codigo(put("/api/solicitudes-herramienta/" + id + "/confirmar-recepcion")))
                .isEqualTo("NO_ENTREGADA");
    }

    // ---------------------------------------------------------------------

    /** Cuerpo de una solicitud de herramienta, con su "para qué". */
    private static String herramienta(Herramienta h) {
        return "{\"herramientaId\": " + h.getId() + ", \"descripcion\": \"Perforar losa\"}";
    }

    private PrestamoHerramienta prestamo(Trabajador t) {
        return prestamoHerramientaRepository.save(PrestamoHerramienta.builder()
                .herramienta(herramienta("Nivel", EstadoHerramienta.PRESTADA))
                .trabajador(t).obra(obra).autorizadoPor(bodeguero)
                .fechaPrestamo(LocalDateTime.now().minusDays(2))
                .fechaDevolEsperada(LocalDateTime.now().minusDays(1)).build());
    }

    private Usuario usuario(String nombre, RolUsuario rol) {
        return usuarioRepository.save(Usuario.builder()
                .nombre(nombre).email(nombre + "@test.cl").rol(rol).empresa(empresa).build());
    }

    private Trabajador trabajador(String nombre, Cuadrilla c, String qr) {
        return trabajadorRepository.save(Trabajador.builder()
                .usuario(usuario(nombre, RolUsuario.TRABAJADOR)).cuadrilla(c).credencialQr(qr).build());
    }

    private Obra obra(String nombre) {
        return obraRepository.save(Obra.builder()
                .nombre(nombre).cliente("Cliente").ubicacion("Santiago")
                .estado(EstadoObra.ACTIVA).empresa(empresa).build());
    }

    private Herramienta herramienta(String nombre, EstadoHerramienta estado) {
        return herramientaRepository.save(Herramienta.builder()
                .codigoQr("H-" + UUID.randomUUID()).nombre(nombre).categoria("Eléctrica")
                .estado(estado).valorReposicion(90000).empresa(empresa).build());
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

    private HttpResponse<String> put(String ruta) throws Exception {
        return http.send(peticion(ruta).PUT(HttpRequest.BodyPublishers.noBody()).build(),
                HttpResponse.BodyHandlers.ofString());
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
