package cl.duocuc.checkinobra.config;

import jakarta.validation.Valid;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.config.BeanDefinition;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.server.LocalServerPort;
import org.springframework.context.annotation.ClassPathScanningCandidateComponentProvider;
import org.springframework.core.type.filter.AnnotationTypeFilter;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;
import tools.jackson.databind.json.JsonMapper;

import java.lang.reflect.Method;
import java.lang.reflect.Parameter;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * SEG8 (#96, S-09 y S-18): las anotaciones de validación de los DTO nunca se
 * ejecutaban porque ningún {@code @RequestBody} llevaba {@code @Valid}. Una
 * prueba estructural exige que todos lo lleven, y otra recorre cada DTO con
 * valores inválidos y espera un 400 que nombre el campo.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class ValidacionDeEntradasTest {

    @LocalServerPort
    private int puerto;

    @Autowired private EmpresaRepository empresaRepository;
    @Autowired private UsuarioRepository usuarioRepository;
    @Autowired private JwtService jwtService;

    private final HttpClient http = HttpClient.newHttpClient();
    private final JsonMapper json = JsonMapper.builder().build();

    @Autowired private cl.duocuc.checkinobra.obra.ObraRepository obraRepository;
    @Autowired private cl.duocuc.checkinobra.cubicacion.PartidaRepository partidaRepository;
    @Autowired private cl.duocuc.checkinobra.cubicacion.MaterialRepository materialRepository;
    @Autowired private cl.duocuc.checkinobra.cubicacion.ItemCubicadoRepository itemCubicadoRepository;

    private String token;
    private Empresa empresa;

    @BeforeEach
    void entrarComoAdmin() {
        String s = UUID.randomUUID().toString().substring(0, 8);
        empresa = empresaRepository.save(Empresa.builder().nombre("Empresa " + s).rut("R-" + s).build());
        Usuario admin = usuarioRepository.save(Usuario.builder()
                .nombre("admin-" + s).email("admin-" + s + "@test.cl").rol(RolUsuario.ADMIN).empresa(empresa).build());
        token = jwtService.emitir(admin);
    }

    // --- estructura ---------------------------------------------------------------

    @Test
    void todoRequestBodyLlevaValid() throws Exception {
        var scanner = new ClassPathScanningCandidateComponentProvider(false);
        scanner.addIncludeFilter(new AnnotationTypeFilter(RestController.class));
        List<String> sinValid = new ArrayList<>();
        int conCuerpo = 0;

        for (BeanDefinition definicion : scanner.findCandidateComponents("cl.duocuc.checkinobra")) {
            Class<?> controlador = Class.forName(definicion.getBeanClassName());
            for (Method metodo : controlador.getDeclaredMethods()) {
                for (Parameter parametro : metodo.getParameters()) {
                    if (parametro.isAnnotationPresent(RequestBody.class)) {
                        conCuerpo++;
                        if (!parametro.isAnnotationPresent(Valid.class)) {
                            sinValid.add(controlador.getSimpleName() + "." + metodo.getName());
                        }
                    }
                }
            }
        }

        assertThat(conCuerpo).isGreaterThan(25);
        assertThat(sinValid).as("@RequestBody sin @Valid: sus anotaciones no se ejecutan").isEmpty();
    }

    // --- por DTO -------------------------------------------------------------------

    private record Caso(String metodo, String ruta, String cuerpo, String campo) {
    }

    private static final String USUARIO = "\"nombre\":\"Ana\",\"email\":\"ana@x.cl\",\"rut\":\"14.109.556-0\"";
    private static String material() {
        // El SKU es único en toda la base y esta no se vacía entre corridas.
        return "\"sku\":\"V-" + UUID.randomUUID().toString().substring(0, 8).toUpperCase() + "\","
                + "\"nombre\":\"Volcanita\",\"categoria\":\"VOLCANITA\",\"precioUnitario\":5980,\"stockMinimo\":10";
    }

    private static List<Caso> casosInvalidos() {
        String sku51 = "X".repeat(51);
        return List.of(
                // Usuarios: una rol nula daba un 409 engañoso.
                new Caso("POST", "/api/usuarios", "{" + USUARIO + ",\"rol\":null}", "rol"),
                new Caso("POST", "/api/usuarios", "{\"nombre\":\"Ana\",\"email\":\"no-es-un-correo\",\"rut\":\"14.109.556-0\",\"rol\":\"BODEGUERO\"}", "email"),
                new Caso("POST", "/api/usuarios", "{\"nombre\":\"\",\"email\":\"ana@x.cl\",\"rut\":\"14.109.556-0\",\"rol\":\"BODEGUERO\"}", "nombre"),
                new Caso("PUT", "/api/usuarios/1/pin", "{\"nuevoPin\":\"\"}", "nuevoPin"),
                // Materiales: precios y stock negativos.
                new Caso("POST", "/api/materiales", "{\"sku\":\"\",\"nombre\":\"V\",\"categoria\":\"VOLCANITA\",\"precioUnitario\":1,\"stockMinimo\":1}", "sku"),
                new Caso("POST", "/api/materiales", "{\"sku\":\"" + sku51 + "\",\"nombre\":\"V\",\"categoria\":\"VOLCANITA\",\"precioUnitario\":1,\"stockMinimo\":1}", "sku"),
                new Caso("POST", "/api/materiales", "{\"sku\":\"A\",\"nombre\":\"V\",\"categoria\":null,\"precioUnitario\":1,\"stockMinimo\":1}", "categoria"),
                new Caso("POST", "/api/materiales", "{\"sku\":\"A\",\"nombre\":\"V\",\"categoria\":\"VOLCANITA\",\"precioUnitario\":-1,\"stockMinimo\":1}", "precioUnitario"),
                new Caso("POST", "/api/materiales", "{\"sku\":\"A\",\"nombre\":\"V\",\"categoria\":\"VOLCANITA\",\"precioUnitario\":1,\"stockMinimo\":-1}", "stockMinimo"),
                new Caso("POST", "/api/materiales", "{\"sku\":\"A\",\"nombre\":\"V\",\"categoria\":\"VOLCANITA\",\"precioUnitario\":1e15,\"stockMinimo\":1}", "precioUnitario"),
                new Caso("PUT", "/api/materiales/1/precio", "{\"nuevoPrecio\":-5}", "nuevoPrecio"),
                // Merma: entre 0 % y un máximo razonable.
                new Caso("PUT", "/api/materiales/1/merma", "{\"porcentaje\":-1}", "porcentaje"),
                new Caso("PUT", "/api/materiales/1/merma", "{\"porcentaje\":150}", "porcentaje"),
                // Partidas: ancho, alto y separación mayores que 0 (con 0 el motor divide por cero).
                new Caso("POST", "/api/partidas", "{\"obraId\":1,\"tipo\":\"TABIQUE\",\"anchoM\":0,\"altoM\":2.4,\"separacionMontantes\":0.6}", "anchoM"),
                new Caso("POST", "/api/partidas", "{\"obraId\":1,\"tipo\":\"TABIQUE\",\"anchoM\":4,\"altoM\":-1,\"separacionMontantes\":0.6}", "altoM"),
                new Caso("POST", "/api/partidas", "{\"obraId\":1,\"tipo\":\"TABIQUE\",\"anchoM\":4,\"altoM\":2.4,\"separacionMontantes\":0}", "separacionMontantes"),
                new Caso("POST", "/api/partidas", "{\"obraId\":null,\"tipo\":\"TABIQUE\",\"anchoM\":4,\"altoM\":2.4,\"separacionMontantes\":0.6}", "obraId"),
                new Caso("POST", "/api/partidas", "{\"obraId\":1,\"tipo\":null,\"anchoM\":4,\"altoM\":2.4,\"separacionMontantes\":0.6}", "tipo"),
                // Presupuestos: cantidades negativas.
                new Caso("POST", "/api/presupuestos", "{\"obraId\":null}", "obraId"),
                new Caso("POST", "/api/presupuestos/1/items", "{\"materialId\":1,\"cantidad\":-1}", "cantidad"),
                new Caso("POST", "/api/presupuestos/1/items", "{\"materialId\":1,\"cantidad\":0}", "cantidad"),
                new Caso("POST", "/api/presupuestos/1/items", "{\"materialId\":null,\"cantidad\":1}", "materialId"),
                // Kardex.
                new Caso("POST", "/api/kardex", "{\"obraId\":1,\"materialId\":1,\"tipo\":\"RECEPCION\",\"cantidad\":0}", "cantidad"),
                new Caso("POST", "/api/kardex", "{\"obraId\":1,\"materialId\":1,\"tipo\":\"RECEPCION\",\"cantidad\":-3}", "cantidad"),
                new Caso("POST", "/api/kardex", "{\"obraId\":1,\"materialId\":1,\"tipo\":null,\"cantidad\":1}", "tipo"),
                new Caso("POST", "/api/kardex", "{\"obraId\":null,\"materialId\":1,\"tipo\":\"RECEPCION\",\"cantidad\":1}", "obraId"),
                new Caso("POST", "/api/kardex", "{\"obraId\":1,\"materialId\":null,\"tipo\":\"RECEPCION\",\"cantidad\":1}", "materialId"),
                new Caso("POST", "/api/kardex", "{\"obraId\":1,\"materialId\":1,\"tipo\":\"RECEPCION\",\"cantidad\":1,\"costoUnitario\":-5}", "costoUnitario"),
                // Solicitudes de material.
                new Caso("POST", "/api/solicitudes-material", "{\"materialId\":1,\"cantidad\":0,\"descripcion\":\"Para el piso 2\"}", "cantidad"),
                new Caso("POST", "/api/solicitudes-material", "{\"materialId\":1,\"cantidad\":1,\"descripcion\":\"\"}", "descripcion"),
                new Caso("POST", "/api/solicitudes-material", "{\"materialId\":null,\"cantidad\":1,\"descripcion\":\"Para el piso 2\"}", "materialId"),
                new Caso("PUT", "/api/solicitudes-material/1/aprobar", "{\"cantidadAEntregar\":0}", "cantidadAEntregar"),
                new Caso("PUT", "/api/solicitudes-material/1/rechazar", "{\"motivo\":\"\"}", "motivo"),
                // Herramientas.
                new Caso("POST", "/api/herramientas", "{\"codigoQr\":\"H1\",\"nombre\":\"T\",\"categoria\":\"E\",\"valorReposicion\":-1}", "valorReposicion"),
                new Caso("POST", "/api/herramientas", "{\"codigoQr\":\"\",\"nombre\":\"T\",\"categoria\":\"E\",\"valorReposicion\":1}", "codigoQr"),
                new Caso("POST", "/api/herramientas", "{\"codigoQr\":\"H1\",\"nombre\":\"\",\"categoria\":\"E\",\"valorReposicion\":1}", "nombre"),
                new Caso("POST", "/api/herramientas", "{\"codigoQr\":\"H1\",\"nombre\":\"T\",\"categoria\":\"\",\"valorReposicion\":1}", "categoria"),
                new Caso("POST", "/api/solicitudes-herramienta", "{\"herramientaId\":null,\"cantidad\":1,\"descripcion\":\"Para el piso 2\"}", "herramientaId"),
                new Caso("POST", "/api/solicitudes-herramienta", "{\"herramientaId\":1,\"cantidad\":1,\"descripcion\":\"\"}", "descripcion"),
                new Caso("PUT", "/api/solicitudes-herramienta/1/rechazar", "{\"motivo\":\"\"}", "motivo"),
                new Caso("POST", "/api/pedidos-herramienta", "{\"herramientaIds\":[],\"descripcion\":\"Para el piso 2\"}", "herramientaIds"),
                new Caso("POST", "/api/pedidos-herramienta", "{\"herramientaIds\":[1],\"descripcion\":\"\"}", "descripcion"),
                new Caso("POST", "/api/prestamos-herramienta", "{\"herramientaId\":null,\"trabajadorId\":1,\"obraId\":1,\"fechaDevolEsperada\":\"2999-01-01T10:00:00\"}", "herramientaId"),
                new Caso("POST", "/api/prestamos-herramienta", "{\"herramientaId\":1,\"trabajadorId\":null,\"obraId\":1,\"fechaDevolEsperada\":\"2999-01-01T10:00:00\"}", "trabajadorId"),
                new Caso("POST", "/api/prestamos-herramienta", "{\"herramientaId\":1,\"trabajadorId\":1,\"obraId\":null,\"fechaDevolEsperada\":\"2999-01-01T10:00:00\"}", "obraId"),
                new Caso("PUT", "/api/prestamos-herramienta/1/devolucion", "{\"nuevoEstadoHerramienta\":null}", "nuevoEstadoHerramienta"),
                // Pedidos especiales.
                new Caso("POST", "/api/pedidos-especiales", "{\"tipo\":\"MATERIAL\",\"nombre\":\"Cinta\",\"cantidad\":0,\"descripcion\":\"Para el piso 2\"}", "cantidad"),
                new Caso("POST", "/api/pedidos-especiales", "{\"tipo\":null,\"nombre\":\"Cinta\",\"cantidad\":1,\"descripcion\":\"Para el piso 2\"}", "tipo"),
                new Caso("POST", "/api/pedidos-especiales", "{\"tipo\":\"MATERIAL\",\"nombre\":\"\",\"cantidad\":1,\"descripcion\":\"Para el piso 2\"}", "nombre"),
                new Caso("POST", "/api/pedidos-especiales", "{\"tipo\":\"MATERIAL\",\"nombre\":\"Cinta\",\"cantidad\":1,\"descripcion\":\"\"}", "descripcion"),
                new Caso("PUT", "/api/pedidos-especiales/1/rechazar", "{\"motivo\":\"\"}", "motivo"),
                // Obras, cuadrillas, trabajadores y alertas.
                new Caso("POST", "/api/obras", "{\"nombre\":\"\",\"cliente\":\"C\",\"ubicacion\":\"U\"}", "nombre"),
                new Caso("POST", "/api/obras", "{\"nombre\":\"O\",\"cliente\":\"\",\"ubicacion\":\"U\"}", "cliente"),
                new Caso("POST", "/api/obras", "{\"nombre\":\"O\",\"cliente\":\"C\",\"ubicacion\":\"\"}", "ubicacion"),
                new Caso("POST", "/api/cuadrillas", "{\"obraId\":null,\"nombre\":\"Tabiqueros\"}", "obraId"),
                new Caso("POST", "/api/cuadrillas", "{\"obraId\":1,\"nombre\":\"\"}", "nombre"),
                new Caso("POST", "/api/trabajadores", "{\"usuarioId\":null}", "usuarioId"),
                new Caso("POST", "/api/alertas/cierre-turno", "{\"obraId\":null,\"mensaje\":\"Cierre\"}", "obraId"),
                new Caso("POST", "/api/alertas/cierre-turno", "{\"obraId\":1,\"mensaje\":\"\"}", "mensaje"),
                // Auth.
                new Caso("POST", "/api/auth/login", "{\"email\":\"\",\"pin\":\"1234\"}", "email"),
                new Caso("POST", "/api/auth/login-pin", "{\"usuarioId\":null,\"pin\":\"1234\"}", "usuarioId"));
    }

    @Test
    void cadaDtoConValoresInvalidosResponde400ConElNombreDelCampo() throws Exception {
        List<String> fallas = new ArrayList<>();
        for (Caso c : casosInvalidos()) {
            HttpResponse<String> r = enviar(c);
            String mensaje = "";
            try {
                mensaje = json.readTree(r.body()).get("mensaje").asString();
            } catch (RuntimeException ignorada) {
                // cuerpo sin mensaje: se informa abajo
            }
            if (r.statusCode() != 400 || !mensaje.contains(c.campo())) {
                fallas.add("%s %s %s → %d «%s» (esperaba 400 con «%s»)".formatted(
                        c.metodo(), c.ruta(), c.cuerpo(), r.statusCode(), mensaje, c.campo()));
            }
        }
        assertThat(fallas).as("DTO que no rechaza su valor inválido").isEmpty();
    }

    @Test
    void unaPartidaAntiguaConMedidasEnCeroNoSeCubicaYNoPierdeSusItems() throws Exception {
        // Filas anteriores a la validación: con separación 0 el motor dividía por cero
        // y los montantes salían Infinity.
        var obra = obraRepository.save(cl.duocuc.checkinobra.obra.Obra.builder()
                .nombre("Obra " + UUID.randomUUID()).cliente("C").ubicacion("U")
                .estado(cl.duocuc.checkinobra.obra.EstadoObra.ACTIVA).empresa(empresa).build());
        var partida = partidaRepository.save(cl.duocuc.checkinobra.cubicacion.Partida.builder()
                .tipo(cl.duocuc.checkinobra.cubicacion.TipoPartida.TABIQUE)
                .anchoM(4).altoM(2.4).separacionMontantes(0).obra(obra).build());
        var material = materialRepository.save(cl.duocuc.checkinobra.cubicacion.Material.builder()
                .sku("M-" + UUID.randomUUID().toString().substring(0, 8).toUpperCase()).nombre("Montante")
                .categoria(cl.duocuc.checkinobra.cubicacion.CategoriaMaterial.METALCOM)
                .precioUnitario(1).stockMinimo(0).empresa(empresa).build());
        itemCubicadoRepository.save(cl.duocuc.checkinobra.cubicacion.ItemCubicado.builder()
                .partida(partida).material(material).cantidadCalculada(5).cantidadConMerma(6).build());

        HttpResponse<String> r = enviar(new Caso("POST", "/api/partidas/" + partida.getId() + "/cubicar", "", ""));

        assertThat(r.statusCode()).isEqualTo(409);
        assertThat(json.readTree(r.body()).get("mensaje").asString()).contains("separación");
        // La cubicación anterior sigue ahí: no se borra antes de validar.
        assertThat(itemCubicadoRepository.findByPartidaId(partida.getId())).hasSize(1);
    }

    @Test
    void unCuerpoValidoSigueLlegandoAlServicio() throws Exception {
        HttpResponse<String> r = enviar(new Caso("POST", "/api/materiales", "{" + material() + "}", ""));

        assertThat(r.statusCode()).isEqualTo(201);
    }

    private HttpResponse<String> enviar(Caso c) throws Exception {
        HttpRequest.Builder b = HttpRequest.newBuilder(URI.create("http://localhost:" + puerto + c.ruta()))
                .header("Authorization", "Bearer " + token).header("Content-Type", "application/json");
        b.method(c.metodo(), HttpRequest.BodyPublishers.ofString(c.cuerpo()));
        return http.send(b.build(), HttpResponse.BodyHandlers.ofString());
    }
}
