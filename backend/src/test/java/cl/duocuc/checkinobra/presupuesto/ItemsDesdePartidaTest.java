package cl.duocuc.checkinobra.presupuesto;

import cl.duocuc.checkinobra.config.Empresa;
import cl.duocuc.checkinobra.config.EmpresaRepository;
import cl.duocuc.checkinobra.config.JwtService;
import cl.duocuc.checkinobra.config.RolUsuario;
import cl.duocuc.checkinobra.config.Usuario;
import cl.duocuc.checkinobra.config.UsuarioRepository;
import cl.duocuc.checkinobra.cubicacion.CategoriaMaterial;
import cl.duocuc.checkinobra.cubicacion.ItemCubicado;
import cl.duocuc.checkinobra.cubicacion.ItemCubicadoRepository;
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
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * D5 (#49): agregar al presupuesto los ítems cubicados de una partida, de una
 * vez y en una sola transacción. Por HTTP contra el servidor de verdad.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class ItemsDesdePartidaTest {

    @LocalServerPort
    private int puerto;

    @Autowired private EmpresaRepository empresaRepository;
    @Autowired private UsuarioRepository usuarioRepository;
    @Autowired private ObraRepository obraRepository;
    @Autowired private MaterialRepository materialRepository;
    @Autowired private PartidaRepository partidaRepository;
    @Autowired private ItemCubicadoRepository itemCubicadoRepository;
    @Autowired private PresupuestoRepository presupuestoRepository;
    @Autowired private PresupuestoItemRepository presupuestoItemRepository;
    @Autowired private JwtService jwtService;

    private final HttpClient http = HttpClient.newHttpClient();
    private final JsonMapper json = JsonMapper.builder().build();

    private String s;
    private Empresa empresa;
    private Obra obra;
    private Material volcanita;
    private Material tornillo;
    private Presupuesto presupuesto;
    private Partida partida;
    private String tokenJefe;

    @BeforeEach
    void prepararPartidaCubicada() {
        s = UUID.randomUUID().toString().substring(0, 8);
        empresa = empresaRepository.save(Empresa.builder().nombre("Empresa " + s).rut("R-" + s).build());
        tokenJefe = token(usuario("jefe-" + s, RolUsuario.JEFE_TERRENO, empresa));
        obra = obra("Edificio " + s, empresa);
        volcanita = material("VOL-" + s, 5980, empresa);
        tornillo = material("TOR-" + s, 12, empresa);
        presupuesto = presupuestoRepository.save(
                Presupuesto.builder().estado(EstadoPresupuesto.BORRADOR).total(0).obra(obra).build());
        partida = partidaCubicada(obra, volcanita, 10.5, tornillo, 100);
    }

    @Test
    void agregaTodosLosItemsCubicadosConLaMermaYElPrecioVigente() throws Exception {
        HttpResponse<String> r = desdePartida(presupuesto.getId(), partida.getId(), tokenJefe);

        assertThat(r.statusCode()).isEqualTo(201);
        JsonNode items = json.readTree(r.body());
        assertThat(items).hasSize(2);
        JsonNode deVolcanita = porMaterial(items, volcanita.getId());
        assertThat(deVolcanita.get("cantidad").asDouble()).isEqualTo(10.5);
        assertThat(deVolcanita.get("precioUnitario").asDouble()).isEqualTo(5980);
        assertThat(deVolcanita.get("subtotal").asDouble()).isEqualTo(10.5 * 5980);
        assertThat(porMaterial(items, tornillo.getId()).get("subtotal").asDouble()).isEqualTo(1200);

        Presupuesto actualizado = presupuestoRepository.findById(presupuesto.getId()).orElseThrow();
        assertThat(actualizado.getTotal()).isEqualTo(10.5 * 5980 + 1200);
        assertThat(presupuestoItemRepository.findByPresupuestoId(presupuesto.getId())).hasSize(2);
    }

    @Test
    void elPrecioSeCopiaAlAgregarYNoSigueAlCatalogo() throws Exception {
        desdePartida(presupuesto.getId(), partida.getId(), tokenJefe);

        volcanita.setPrecioUnitario(9999);
        materialRepository.save(volcanita);

        PresupuestoItem item = presupuestoItemRepository.findByPresupuestoId(presupuesto.getId()).stream()
                .filter(i -> i.getMaterial().getId().equals(volcanita.getId())).findFirst().orElseThrow();
        assertThat(item.getPrecioUnitario()).isEqualTo(5980);
    }

    @Test
    void unPresupuestoCongeladoNoAdmiteItemsDeUnaPartida() throws Exception {
        presupuesto.setEstado(EstadoPresupuesto.CONGELADO);
        presupuestoRepository.save(presupuesto);

        HttpResponse<String> r = desdePartida(presupuesto.getId(), partida.getId(), tokenJefe);

        assertThat(r.statusCode()).isEqualTo(409);
        assertThat(json.readTree(r.body()).get("codigo").asString()).isEqualTo("PRESUPUESTO_CONGELADO");
        assertThat(presupuestoItemRepository.findByPresupuestoId(presupuesto.getId())).isEmpty();
    }

    @Test
    void unaPartidaDeOtraObraDeLaMismaEmpresaSeRechaza() throws Exception {
        Obra otraObra = obra("Casa " + s, empresa);
        Partida deOtraObra = partidaCubicada(otraObra, volcanita, 5, tornillo, 50);

        HttpResponse<String> r = desdePartida(presupuesto.getId(), deOtraObra.getId(), tokenJefe);

        assertThat(r.statusCode()).isEqualTo(409);
        assertThat(json.readTree(r.body()).get("codigo").asString()).isEqualTo("PARTIDA_DE_OTRA_OBRA");
        assertThat(presupuestoItemRepository.findByPresupuestoId(presupuesto.getId())).isEmpty();
    }

    @Test
    void unaPartidaSinCubicarSeRechazaConUnMensajeQueDiceQueHacer() throws Exception {
        Partida sinCubicar = partidaRepository.save(Partida.builder()
                .tipo(TipoPartida.TABIQUE).anchoM(3).altoM(2.4).separacionMontantes(0.6).obra(obra).build());

        HttpResponse<String> r = desdePartida(presupuesto.getId(), sinCubicar.getId(), tokenJefe);

        assertThat(r.statusCode()).isEqualTo(409);
        JsonNode cuerpo = json.readTree(r.body());
        assertThat(cuerpo.get("codigo").asString()).isEqualTo("PARTIDA_SIN_CUBICAR");
        assertThat(cuerpo.get("mensaje").asString()).contains("cubic");
    }

    @Test
    void unaEmpresaAjenaNoPuedeUsarElPresupuestoNiLaPartidaDeOtra() throws Exception {
        Empresa otra = empresaRepository.save(Empresa.builder().nombre("Otra " + s).rut("O-" + s).build());
        String tokenAjeno = token(usuario("jefe-b-" + s, RolUsuario.JEFE_TERRENO, otra));
        Obra obraAjena = obra("Obra B " + s, otra);
        Presupuesto presupuestoAjeno = presupuestoRepository.save(
                Presupuesto.builder().estado(EstadoPresupuesto.BORRADOR).total(0).obra(obraAjena).build());

        // Presupuesto de otra empresa.
        assertThat(desdePartida(presupuesto.getId(), partida.getId(), tokenAjeno).statusCode()).isEqualTo(404);
        // Presupuesto propio, pero partida de otra empresa.
        assertThat(desdePartida(presupuestoAjeno.getId(), partida.getId(), tokenAjeno).statusCode()).isEqualTo(404);
        assertThat(presupuestoItemRepository.findByPresupuestoId(presupuesto.getId())).isEmpty();
        assertThat(presupuestoItemRepository.findByPresupuestoId(presupuestoAjeno.getId())).isEmpty();
    }

    @Test
    void sinPartidaIdResponde400EnVezDeUn500() throws Exception {
        HttpRequest r = HttpRequest.newBuilder(URI.create("http://localhost:" + puerto
                        + "/api/presupuestos/" + presupuesto.getId() + "/items/desde-partida"))
                .header("Authorization", "Bearer " + tokenJefe)
                .header("Content-Type", "application/json")
                .POST(HttpRequest.BodyPublishers.ofString("{}")).build();

        assertThat(http.send(r, HttpResponse.BodyHandlers.ofString()).statusCode()).isEqualTo(400);
    }

    @Test
    void soloAdminYJefeDeTerrenoPuedenAgregar() throws Exception {
        for (RolUsuario rol : new RolUsuario[] {RolUsuario.BODEGUERO, RolUsuario.TRABAJADOR}) {
            String token = token(usuario(rol.name().toLowerCase() + "-" + s, rol, empresa));

            assertThat(desdePartida(presupuesto.getId(), partida.getId(), token).statusCode())
                    .as(rol.name()).isEqualTo(403);
        }
        assertThat(presupuestoItemRepository.findByPresupuestoId(presupuesto.getId())).isEmpty();
    }

    // ---------------------------------------------------------------------

    private static JsonNode porMaterial(JsonNode items, Long materialId) {
        for (JsonNode i : items) {
            if (i.get("materialId").asLong() == materialId) {
                return i;
            }
        }
        throw new AssertionError("No hay ítem del material " + materialId);
    }

    private Partida partidaCubicada(Obra deLaObra, Material a, double cantidadA, Material b, double cantidadB) {
        Partida p = partidaRepository.save(Partida.builder()
                .tipo(TipoPartida.TABIQUE).anchoM(4).altoM(2.4).separacionMontantes(0.6).obra(deLaObra).build());
        itemCubicadoRepository.save(ItemCubicado.builder()
                .partida(p).material(a).cantidadCalculada(cantidadA - 0.5).cantidadConMerma(cantidadA).build());
        itemCubicadoRepository.save(ItemCubicado.builder()
                .partida(p).material(b).cantidadCalculada(cantidadB - 5).cantidadConMerma(cantidadB).build());
        return p;
    }

    private Material material(String sku, double precio, Empresa deLaEmpresa) {
        return materialRepository.save(Material.builder()
                .sku(sku).nombre("Material " + sku).categoria(CategoriaMaterial.VOLCANITA)
                .precioUnitario(precio).stockMinimo(0).empresa(deLaEmpresa).build());
    }

    private Usuario usuario(String nombre, RolUsuario rol, Empresa deLaEmpresa) {
        return usuarioRepository.save(Usuario.builder()
                .nombre(nombre).email(nombre + "@test.cl").rol(rol).empresa(deLaEmpresa).build());
    }

    private String token(Usuario u) {
        return jwtService.emitir(u);
    }

    private Obra obra(String nombre, Empresa deLaEmpresa) {
        return obraRepository.save(Obra.builder()
                .nombre(nombre).cliente("Cliente").ubicacion("Santiago")
                .estado(EstadoObra.ACTIVA).empresa(deLaEmpresa).build());
    }

    private HttpResponse<String> desdePartida(Long presupuestoId, Long partidaId, String token) throws Exception {
        HttpRequest r = HttpRequest.newBuilder(URI.create(
                        "http://localhost:" + puerto + "/api/presupuestos/" + presupuestoId + "/items/desde-partida"))
                .header("Authorization", "Bearer " + token)
                .header("Content-Type", "application/json")
                .POST(HttpRequest.BodyPublishers.ofString("{\"partidaId\": %d}".formatted(partidaId))).build();
        return http.send(r, HttpResponse.BodyHandlers.ofString());
    }
}
