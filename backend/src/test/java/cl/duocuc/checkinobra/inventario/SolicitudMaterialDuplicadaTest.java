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
 * Bug #76 (S-16): un trabajador no puede tener dos solicitudes de material
 * idénticas pendientes. La {@code Idempotency-Key} solo protege el reintento con
 * la misma clave; un segundo pedido deliberado, desde otra pantalla o con otra
 * clave, pasaba. Las solicitudes de herramienta ya tenían este control.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class SolicitudMaterialDuplicadaTest {

    @LocalServerPort
    private int puerto;

    @Autowired private EmpresaRepository empresaRepository;
    @Autowired private UsuarioRepository usuarioRepository;
    @Autowired private ObraRepository obraRepository;
    @Autowired private CuadrillaRepository cuadrillaRepository;
    @Autowired private TrabajadorRepository trabajadorRepository;
    @Autowired private MaterialRepository materialRepository;
    @Autowired private SolicitudMaterialRepository solicitudMaterialRepository;
    @Autowired private JwtService jwtService;

    private final HttpClient http = HttpClient.newHttpClient();
    private final JsonMapper json = JsonMapper.builder().build();

    private String s;
    private Empresa empresa;
    private Trabajador yo;
    private Trabajador companero;
    private Material volcanita;
    private Material tornillo;
    private String tokenYo;
    private String tokenBodeguero;
    private String tokenCompanero;

    @BeforeEach
    void prepararCuadrilla() {
        s = UUID.randomUUID().toString().substring(0, 8);
        empresa = empresaRepository.save(Empresa.builder().nombre("Constructora " + s).rut("R-" + s).build());
        Obra obra = obraRepository.save(Obra.builder()
                .nombre("Edificio " + s).cliente("Cliente").ubicacion("Santiago")
                .estado(EstadoObra.ACTIVA).empresa(empresa).build());
        Cuadrilla cuadrilla = cuadrillaRepository.save(Cuadrilla.builder().nombre("Tabiqueros").obra(obra).build());
        yo = trabajador("maestro-" + s, cuadrilla);
        companero = trabajador("companero-" + s, cuadrilla);
        volcanita = material("VOL-" + s);
        tornillo = material("TOR-" + s);
        tokenYo = jwtService.emitir(yo.getUsuario());
        tokenCompanero = jwtService.emitir(companero.getUsuario());
        tokenBodeguero = jwtService.emitir(usuario("bodega-" + s, RolUsuario.BODEGUERO));
    }

    @Test
    void laSegundaSolicitudIdenticaConOtraClaveEs409SolicitudDuplicada() throws Exception {
        assertThat(pedir(volcanita, tokenYo, UUID.randomUUID().toString()).statusCode()).isEqualTo(201);

        HttpResponse<String> segunda = pedir(volcanita, tokenYo, UUID.randomUUID().toString());

        assertThat(segunda.statusCode()).isEqualTo(409);
        JsonNode cuerpo = json.readTree(segunda.body());
        assertThat(cuerpo.get("codigo").asString()).isEqualTo("SOLICITUD_DUPLICADA");
        // La app muestra este mensaje tal cual: tiene que decir qué material es.
        assertThat(cuerpo.get("mensaje").asString()).contains(volcanita.getNombre());
        assertThat(pendientes(yo, volcanita)).isEqualTo(1);
    }

    @Test
    void sinCabeceraDeIdempotenciaTambienSeBloquea() throws Exception {
        assertThat(pedir(volcanita, tokenYo, null).statusCode()).isEqualTo(201);

        assertThat(pedir(volcanita, tokenYo, null).statusCode()).isEqualTo(409);
        assertThat(pendientes(yo, volcanita)).isEqualTo(1);
    }

    @Test
    void conLaMismaClaveElReintentoSigueRecibiendoLaRespuestaDelPrimero() throws Exception {
        String clave = UUID.randomUUID().toString();
        HttpResponse<String> primera = pedir(volcanita, tokenYo, clave);
        HttpResponse<String> reintento = pedir(volcanita, tokenYo, clave);

        // Lo cubre IdempotenciaFilter: no es un duplicado, es el mismo pedido.
        assertThat(primera.statusCode()).isEqualTo(201);
        assertThat(reintento.statusCode()).isEqualTo(201);
        assertThat(json.readTree(reintento.body()).get("id").asLong())
                .isEqualTo(json.readTree(primera.body()).get("id").asLong());
        assertThat(pendientes(yo, volcanita)).isEqualTo(1);
    }

    @Test
    void otroMaterialOOtroTrabajadorNoSeBloquean() throws Exception {
        assertThat(pedir(volcanita, tokenYo, null).statusCode()).isEqualTo(201);

        assertThat(pedir(tornillo, tokenYo, null).statusCode()).isEqualTo(201);
        assertThat(pedir(volcanita, tokenCompanero, null).statusCode()).isEqualTo(201);
    }

    @Test
    void siLaPrimeraYaNoEstaPendienteSePuedeVolverAPedir() throws Exception {
        // Cancelada por el trabajador.
        long cancelada = id(pedir(volcanita, tokenYo, null));
        assertThat(put("/api/solicitudes-material/" + cancelada + "/cancelar", "", tokenYo).statusCode())
                .isEqualTo(200);
        // Rechazada por bodega.
        long rechazada = id(pedir(volcanita, tokenYo, null));
        assertThat(put("/api/solicitudes-material/" + rechazada + "/rechazar",
                "{\"motivo\": \"Sin stock esta semana\"}", tokenBodeguero).statusCode()).isEqualTo(200);
        // Aprobada: se fija el estado, el despacho no es lo que se prueba acá.
        long aprobada = id(pedir(volcanita, tokenYo, null));
        SolicitudMaterial s1 = solicitudMaterialRepository.findById(aprobada).orElseThrow();
        s1.setEstado(EstadoSolicitud.APROBADA);
        solicitudMaterialRepository.save(s1);

        assertThat(pedir(volcanita, tokenYo, null).statusCode()).isEqualTo(201);
        assertThat(pendientes(yo, volcanita)).isEqualTo(1);
    }

    @Test
    void diezPeticionesSimultaneasConClavesDistintasDejanUnaSolaSolicitud() throws Exception {
        List<HttpResponse<String>> respuestas = aLaVez(10, () -> pedir(volcanita, tokenYo, UUID.randomUUID().toString()));

        long creadas = respuestas.stream().filter(r -> r.statusCode() == 201).count();
        long duplicadas = respuestas.stream().filter(r -> r.statusCode() == 409).count();
        assertThat(creadas).as("201").isEqualTo(1);
        assertThat(duplicadas).as("409").isEqualTo(9);
        assertThat(pendientes(yo, volcanita)).isEqualTo(1);
    }

    // ---------------------------------------------------------------------

    private long pendientes(Trabajador t, Material m) {
        return solicitudMaterialRepository.findByTrabajadorId(t.getId()).stream()
                .filter(x -> x.getMaterial().getId().equals(m.getId()))
                .filter(x -> x.getEstado() == EstadoSolicitud.PENDIENTE)
                .count();
    }

    private long id(HttpResponse<String> r) {
        assertThat(r.statusCode()).isEqualTo(201);
        return json.readTree(r.body()).get("id").asLong();
    }

    private HttpResponse<String> pedir(Material m, String token, String clave) throws Exception {
        String cuerpo = "{\"materialId\": %d, \"cantidad\": 5, \"descripcion\": \"Para el tabique del piso 2\"}"
                .formatted(m.getId());
        HttpRequest.Builder b = HttpRequest.newBuilder(URI.create("http://localhost:" + puerto + "/api/solicitudes-material"))
                .header("Authorization", "Bearer " + token).header("Content-Type", "application/json");
        if (clave != null) {
            b.header("Idempotency-Key", clave);
        }
        return http.send(b.POST(HttpRequest.BodyPublishers.ofString(cuerpo)).build(), HttpResponse.BodyHandlers.ofString());
    }

    private HttpResponse<String> put(String ruta, String cuerpo, String token) throws Exception {
        return http.send(HttpRequest.newBuilder(URI.create("http://localhost:" + puerto + ruta))
                .header("Authorization", "Bearer " + token).header("Content-Type", "application/json")
                .PUT(HttpRequest.BodyPublishers.ofString(cuerpo)).build(), HttpResponse.BodyHandlers.ofString());
    }

    private Usuario usuario(String nombre, RolUsuario rol) {
        return usuarioRepository.save(Usuario.builder()
                .nombre(nombre).email(nombre + "@test.cl").rol(rol).empresa(empresa).build());
    }

    private Trabajador trabajador(String nombre, Cuadrilla c) {
        return trabajadorRepository.save(Trabajador.builder()
                .usuario(usuario(nombre, RolUsuario.TRABAJADOR)).cuadrilla(c).credencialQr("QR-" + nombre).build());
    }

    private Material material(String sku) {
        return materialRepository.save(Material.builder()
                .sku(sku).nombre("Material " + sku).categoria(CategoriaMaterial.VOLCANITA)
                .precioUnitario(100).stockMinimo(0).empresa(empresa).build());
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
