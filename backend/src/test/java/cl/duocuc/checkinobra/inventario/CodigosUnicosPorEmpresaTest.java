package cl.duocuc.checkinobra.inventario;

import cl.duocuc.checkinobra.config.Empresa;
import cl.duocuc.checkinobra.config.EmpresaRepository;
import cl.duocuc.checkinobra.config.JwtService;
import cl.duocuc.checkinobra.config.RolUsuario;
import cl.duocuc.checkinobra.config.Usuario;
import cl.duocuc.checkinobra.config.UsuarioRepository;
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
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * SEG12 (#100, S-22): el SKU de un material y el código QR de una herramienta son únicos dentro de
 * la empresa, no en toda la base. Con una base por empresa ya era así; este es el respaldo para una
 * base que reúne a más de una (como la de las pruebas) y para el día en que se configure así.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class CodigosUnicosPorEmpresaTest {

    @LocalServerPort private int puerto;

    @Autowired private EmpresaRepository empresaRepository;
    @Autowired private UsuarioRepository usuarioRepository;
    @Autowired private JwtService jwtService;

    private final HttpClient http = HttpClient.newHttpClient();
    private final JsonMapper json = JsonMapper.builder().build();

    private String sufijo;
    private String tokenA;
    private String tokenB;

    @BeforeEach
    void dosEmpresas() {
        sufijo = UUID.randomUUID().toString().substring(0, 8);
        tokenA = tokenAdmin(empresaRepository.save(Empresa.builder().nombre("A " + sufijo).rut("RA-" + sufijo).build()), "a");
        tokenB = tokenAdmin(empresaRepository.save(Empresa.builder().nombre("B " + sufijo).rut("RB-" + sufijo).build()), "b");
    }

    @Test
    void dosEmpresasPuedenTenerElMismoSku() throws Exception {
        assertThat(crearMaterial(tokenA, "VOL-" + sufijo).statusCode()).isEqualTo(201);

        assertThat(crearMaterial(tokenB, "vol-" + sufijo).statusCode()).isEqualTo(201);
    }

    @Test
    void dentroDeUnaEmpresaElSkuSigueSiendoUnico() throws Exception {
        crearMaterial(tokenA, "VOL-" + sufijo);

        HttpResponse<String> repetido = crearMaterial(tokenA, "vol-" + sufijo);

        assertThat(repetido.statusCode()).isEqualTo(409);
        assertThat(repetido.body()).contains("SKU");
    }

    @Test
    void dosEmpresasPuedenTenerElMismoCodigoDeHerramienta() throws Exception {
        assertThat(crearHerramienta(tokenA, "TAL-" + sufijo).statusCode()).isEqualTo(201);

        assertThat(crearHerramienta(tokenB, "tal-" + sufijo).statusCode()).isEqualTo(201);
    }

    @Test
    void dentroDeUnaEmpresaElCodigoDeHerramientaSigueSiendoUnico() throws Exception {
        crearHerramienta(tokenA, "TAL-" + sufijo);

        HttpResponse<String> repetida = crearHerramienta(tokenA, "tal-" + sufijo);

        assertThat(repetida.statusCode()).isEqualTo(409);
        assertThat(repetida.body()).contains("código");
    }

    /** Con el mismo código en dos empresas, el escáner de cada una resuelve el suyo y no falla. */
    @Test
    void elEscanerResuelveLaHerramientaDeSuPropiaEmpresa() throws Exception {
        long deA = idDe(crearHerramienta(tokenA, "TAL-" + sufijo));
        long deB = idDe(crearHerramienta(tokenB, "TAL-" + sufijo));

        HttpResponse<String> enA = enviar("GET", "/api/herramientas/por-codigo/TAL-" + sufijo, tokenA, null);
        HttpResponse<String> enB = enviar("GET", "/api/herramientas/por-codigo/TAL-" + sufijo, tokenB, null);

        assertThat(deA).isNotEqualTo(deB);
        assertThat(enA.statusCode()).isEqualTo(200);
        assertThat(idDe(enA)).isEqualTo(deA);
        assertThat(enB.statusCode()).isEqualTo(200);
        assertThat(idDe(enB)).isEqualTo(deB);
    }

    private String tokenAdmin(Empresa empresa, String letra) {
        return jwtService.emitir(usuarioRepository.save(Usuario.builder()
                .nombre("admin-" + letra).email("admin-" + letra + "-" + sufijo + "@test.cl")
                .rol(RolUsuario.ADMIN).empresa(empresa).build()));
    }

    private HttpResponse<String> crearMaterial(String token, String sku) throws Exception {
        return enviar("POST", "/api/materiales", token, """
                {"sku": "%s", "nombre": "Volcanita", "categoria": "VOLCANITA", "precioUnitario": 100, "stockMinimo": 0}
                """.formatted(sku));
    }

    private HttpResponse<String> crearHerramienta(String token, String codigo) throws Exception {
        return enviar("POST", "/api/herramientas", token, """
                {"codigoQr": "%s", "nombre": "Taladro", "categoria": "Eléctrica", "valorReposicion": 50000}
                """.formatted(codigo));
    }

    private long idDe(HttpResponse<String> r) {
        return json.readTree(r.body()).get("id").asLong();
    }

    private HttpResponse<String> enviar(String metodo, String ruta, String token, String cuerpo) throws Exception {
        HttpRequest.Builder b = HttpRequest.newBuilder(URI.create("http://localhost:" + puerto + ruta))
                .header("Authorization", "Bearer " + token).header("Content-Type", "application/json");
        b.method(metodo, cuerpo == null ? HttpRequest.BodyPublishers.noBody() : HttpRequest.BodyPublishers.ofString(cuerpo));
        return http.send(b.build(), HttpResponse.BodyHandlers.ofString());
    }
}
