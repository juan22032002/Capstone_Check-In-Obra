package cl.duocuc.checkinobra.config;

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
import java.util.Collections;
import java.util.List;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * SEG2 (#90, S-02 y S-23): límite de intentos, login-pin solo para
 * trabajadores, clave larga para los demás roles y tiempo parejo ante cuentas
 * inexistentes. Por HTTP contra el servidor de verdad.
 *
 * <p>El tope por IP se sube aquí: todas las peticiones salen de 127.0.0.1 y lo
 * que se prueba es el bloqueo por cuenta. El de IP tiene su propia clase.
 */
@SpringBootTest(
        webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT,
        properties = "checkinobra.login.ip.max-fallos=100000")
class LoginSeguroTest {

    private static final String PIN = "4821";
    private static final String CLAVE_LARGA = "clave-larga-segura-9";

    @LocalServerPort
    private int puerto;

    @Autowired private EmpresaRepository empresaRepository;
    @Autowired private UsuarioRepository usuarioRepository;
    @Autowired private JwtService jwtService;
    @Autowired private CatalogoDePrueba catalogoDePrueba;

    private final HttpClient http = HttpClient.newHttpClient();
    private final JsonMapper json = JsonMapper.builder().build();

    private String s;
    private Empresa empresa;
    private Usuario trabajador;
    private Usuario admin;

    @BeforeEach
    void prepararUsuarios() {
        s = UUID.randomUUID().toString().substring(0, 8);
        empresa = empresaRepository.save(Empresa.builder().nombre("Empresa " + s).rut("R-" + s).build());
        catalogoDePrueba.registrar(empresa);
        trabajador = usuario("obrero-" + s, RolUsuario.TRABAJADOR, PIN);
        admin = usuario("admin-" + s, RolUsuario.ADMIN, CLAVE_LARGA);
    }

    // --- bloqueo por cuenta (S-02) -----------------------------------------

    @Test
    void veinteIntentosFallidosNuncaLlegaAValidarElPinCorrecto() throws Exception {
        List<Integer> estados = new ArrayList<>();
        for (int i = 0; i < 20; i++) {
            estados.add(loginPin(trabajador.getId(), "000" + (i % 10)).statusCode());
        }

        // Los cinco primeros se validan y fallan; desde el sexto ni se mira el PIN.
        assertThat(estados.subList(0, 5)).containsOnly(400);
        assertThat(estados.subList(5, 20)).containsOnly(429);

        // Con el PIN correcto, por la misma ruta y por la otra, sigue bloqueada.
        assertThat(loginPin(trabajador.getId(), PIN).statusCode()).isEqualTo(429);
        assertThat(loginCorreo(trabajador.getEmail(), PIN).statusCode()).isEqualTo(429);
    }

    @Test
    void laRespuesta429IndicaCuantoEsperar() throws Exception {
        for (int i = 0; i < 5; i++) {
            loginPin(trabajador.getId(), "0000");
        }

        HttpResponse<String> r = loginPin(trabajador.getId(), "0000");

        assertThat(r.statusCode()).isEqualTo(429);
        long segundos = Long.parseLong(r.headers().firstValue("Retry-After").orElseThrow());
        assertThat(segundos).isBetween(1L, 60L);
        JsonNode cuerpo = json.readTree(r.body());
        assertThat(cuerpo.get("codigo").asString()).isEqualTo("DEMASIADOS_INTENTOS");
        assertThat(cuerpo.get("mensaje").asString()).doesNotContain(trabajador.getEmail());
    }

    @Test
    void unAciertoReiniciaElContadorDeLaCuenta() throws Exception {
        for (int i = 0; i < 4; i++) {
            assertThat(loginPin(trabajador.getId(), "0000").statusCode()).isEqualTo(400);
        }
        assertThat(loginPin(trabajador.getId(), PIN).statusCode()).isEqualTo(200);

        for (int i = 0; i < 4; i++) {
            assertThat(loginPin(trabajador.getId(), "0000").statusCode()).isEqualTo(400);
        }
    }

    @Test
    void elBloqueoDeUnaCuentaNoAfectaALasOtras() throws Exception {
        for (int i = 0; i < 6; i++) {
            loginPin(trabajador.getId(), "0000");
        }

        assertThat(loginCorreo(admin.getEmail(), CLAVE_LARGA).statusCode()).isEqualTo(200);
    }

    @Test
    void unCorreoQueNoExisteSeBloqueaIgualQueUnoQueExiste() throws Exception {
        String fantasma = "fantasma-" + s + "@test.cl";
        List<Integer> estados = new ArrayList<>();
        for (int i = 0; i < 7; i++) {
            estados.add(loginCorreo(fantasma, "0000").statusCode());
        }

        // Misma secuencia que una cuenta real: si solo las reales se bloquearan,
        // el 429 delataría qué correos existen.
        assertThat(estados).containsExactly(400, 400, 400, 400, 400, 429, 429);
    }

    @Test
    void unIdQueNoExisteSeBloqueaIgualQueUnoQueExiste() throws Exception {
        long idInexistente = 900_000_000L + (long) (Math.random() * 1_000_000);
        List<Integer> estados = new ArrayList<>();
        for (int i = 0; i < 7; i++) {
            estados.add(loginPin(idInexistente, "0000").statusCode());
        }

        assertThat(estados).containsExactly(400, 400, 400, 400, 400, 429, 429);
    }

    // --- login-pin solo para TRABAJADOR -------------------------------------

    @Test
    void loginPinSoloAceptaTrabajadoresAunqueElPinseaCorrecto() throws Exception {
        // Un PIN de 4 dígitos en un rol que no es TRABAJADOR solo existe como herencia
        // de antes de la política de claves largas: se fija directo, porque definirPin
        // ya no lo permite. Es justo el caso que login-pin no debe aceptar.
        Usuario jefe = conPinHeredado(usuario("jefe-" + s, RolUsuario.JEFE_TERRENO, CLAVE_LARGA));
        Usuario bodeguero = conPinHeredado(usuario("bodega-" + s, RolUsuario.BODEGUERO, CLAVE_LARGA));
        Usuario adminHeredado = conPinHeredado(usuario("admin-h-" + s, RolUsuario.ADMIN, CLAVE_LARGA));

        HttpResponse<String> pinMalo = loginPin(trabajador.getId(), "0000");
        for (Usuario u : List.of(adminHeredado, jefe, bodeguero)) {
            HttpResponse<String> r = loginPin(u.getId(), PIN);

            // Mismo status y mismo mensaje que un PIN equivocado: no se revela
            // que el id existe ni qué rol tiene.
            assertThat(r.statusCode()).as(u.getRol().name()).isEqualTo(400);
            assertThat(mensaje(r)).isEqualTo(mensaje(pinMalo));
        }
        assertThat(loginPin(trabajador.getId(), PIN).statusCode()).isEqualTo(200);
    }

    @Test
    void loginPinSoloRecibePinesDeCuatroDigitosYNoMiraClavesLargas() throws Exception {
        // La clave larga de un administrador ni siquiera llega al servicio por esta ruta.
        HttpResponse<String> r = loginPin(admin.getId(), CLAVE_LARGA);

        assertThat(r.statusCode()).isEqualTo(400);
        assertThat(mensaje(r)).contains("pin");
    }

    private Usuario conPinHeredado(Usuario u) {
        u.setPinHash(org.springframework.security.crypto.bcrypt.BCrypt.hashpw(PIN, org.springframework.security.crypto.bcrypt.BCrypt.gensalt()));
        return usuarioRepository.save(u);
    }

    @Test
    void probarLoginPinContraUnAdminTambienCuentaParaSuBloqueo() throws Exception {
        for (int i = 0; i < 5; i++) {
            loginPin(admin.getId(), "0000");
        }

        assertThat(loginCorreo(admin.getEmail(), CLAVE_LARGA).statusCode()).isEqualTo(429);
    }

    // --- clave larga para ADMIN, JEFE_TERRENO y BODEGUERO -------------------

    @Test
    void unAdminEntraPorCorreoConSuClaveLargaYTambienConElAliasClave() throws Exception {
        assertThat(loginCorreo(admin.getEmail(), CLAVE_LARGA).statusCode()).isEqualTo(200);
        assertThat(post("/api/auth/login",
                "{\"email\": \"%s\", \"clave\": \"%s\"}".formatted(admin.getEmail(), CLAVE_LARGA), null)
                .statusCode()).isEqualTo(200);
    }

    @Test
    void crearUnUsuarioNoTrabajadorExigeClaveDeAlMenos8Caracteres() throws Exception {
        String token = jwtService.emitir(admin);

        for (RolUsuario rol : List.of(RolUsuario.ADMIN, RolUsuario.JEFE_TERRENO, RolUsuario.BODEGUERO)) {
            assertThat(crearUsuario(token, rol, "1234").statusCode()).as("PIN corto " + rol).isEqualTo(400);
            assertThat(crearUsuario(token, rol, "1234567").statusCode()).as("7 caracteres " + rol).isEqualTo(400);
            assertThat(crearUsuario(token, rol, "x".repeat(73)).statusCode()).as("más de 72 " + rol).isEqualTo(400);
            assertThat(crearUsuario(token, rol, "12345678").statusCode()).as("8 caracteres " + rol).isEqualTo(201);
        }
    }

    @Test
    void elTrabajadorSigueConPinDe4Digitos() throws Exception {
        String token = jwtService.emitir(admin);

        assertThat(crearUsuario(token, RolUsuario.TRABAJADOR, "12345678").statusCode()).isEqualTo(400);
        assertThat(crearUsuario(token, RolUsuario.TRABAJADOR, "123").statusCode()).isEqualTo(400);
        assertThat(crearUsuario(token, RolUsuario.TRABAJADOR, "9137").statusCode()).isEqualTo(201);
    }

    @Test
    void redefinirLaClaveDeUnAdminConUnPinCortoSeRechaza() throws Exception {
        String token = jwtService.emitir(admin);

        HttpResponse<String> corto = put("/api/usuarios/" + admin.getId() + "/pin",
                "{\"nuevoPin\": \"0000\"}", token);
        HttpResponse<String> largo = put("/api/usuarios/" + admin.getId() + "/pin",
                "{\"nuevoPin\": \"otra-clave-larga-7\"}", token);

        assertThat(corto.statusCode()).isEqualTo(400);
        assertThat(largo.statusCode()).isEqualTo(200);
        assertThat(loginCorreo(admin.getEmail(), "otra-clave-larga-7").statusCode()).isEqualTo(200);
    }

    // --- tiempo parejo (S-23) ----------------------------------------------

    @Test
    void unaCuentaInexistenteTardaLoMismoQueUnaQueExiste() throws Exception {
        List<Long> conocidas = new ArrayList<>();
        List<Long> desconocidas = new ArrayList<>();
        for (int i = 0; i < 4; i++) {
            Usuario u = usuario("t" + i + "-" + s, RolUsuario.TRABAJADOR, PIN);
            conocidas.add(nanosDe(() -> loginCorreo(u.getEmail(), "0000")));
            desconocidas.add(nanosDe(() -> loginCorreo("nadie" + UUID.randomUUID() + "@test.cl", "0000")));
        }

        // Sin el BCrypt de relleno, el correo inexistente respondía en un
        // milisegundo y el existente en ~70: la diferencia delataba las cuentas.
        long medianaConocida = mediana(conocidas);
        long medianaDesconocida = mediana(desconocidas);
        assertThat(medianaDesconocida).isGreaterThan(medianaConocida / 2);
    }

    // ---------------------------------------------------------------------

    private interface Llamada {
        HttpResponse<String> hacer() throws Exception;
    }

    private long nanosDe(Llamada llamada) throws Exception {
        long inicio = System.nanoTime();
        llamada.hacer();
        return System.nanoTime() - inicio;
    }

    private static long mediana(List<Long> valores) {
        List<Long> orden = new ArrayList<>(valores);
        Collections.sort(orden);
        return orden.get(orden.size() / 2);
    }

    private String mensaje(HttpResponse<String> r) {
        return json.readTree(r.body()).get("mensaje").asString();
    }

    private Usuario usuario(String nombre, RolUsuario rol, String clave) {
        Usuario u = Usuario.builder()
                .nombre(nombre).email(nombre + "@test.cl").rol(rol).empresa(empresa).build();
        u.definirPin(clave);
        Usuario guardado = usuarioRepository.save(u);
        catalogoDePrueba.indexar(guardado);
        return guardado;
    }

    private HttpResponse<String> crearUsuario(String token, RolUsuario rol, String clave) throws Exception {
        String sufijo = UUID.randomUUID().toString().substring(0, 8);
        String cuerpo = """
                {"nombre": "Nuevo %1$s", "email": "nuevo-%1$s@test.cl", "rut": "%2$s",
                 "rol": "%3$s", "pinInicial": "%4$s"}
                """.formatted(sufijo, rutAleatorio(), rol, clave);
        return post("/api/usuarios", cuerpo, token);
    }

    private static String rutAleatorio() {
        String cuerpo = String.valueOf(10_000_000 + (long) (Math.random() * 80_000_000));
        return cuerpo + "-" + Rut.digitoVerificador(cuerpo);
    }

    private HttpResponse<String> loginPin(long usuarioId, String pin) throws Exception {
        return post("/api/auth/login-pin",
                "{\"usuarioId\": %d, \"empresaId\": %d, \"pin\": \"%s\"}".formatted(usuarioId, empresa.getId(), pin), null);
    }

    private HttpResponse<String> loginCorreo(String email, String clave) throws Exception {
        return post("/api/auth/login", "{\"email\": \"%s\", \"pin\": \"%s\"}".formatted(email, clave), null);
    }

    private HttpResponse<String> post(String ruta, String cuerpo, String token) throws Exception {
        return http.send(peticion(ruta, token).header("Content-Type", "application/json")
                .POST(HttpRequest.BodyPublishers.ofString(cuerpo)).build(), HttpResponse.BodyHandlers.ofString());
    }

    private HttpResponse<String> put(String ruta, String cuerpo, String token) throws Exception {
        return http.send(peticion(ruta, token).header("Content-Type", "application/json")
                .PUT(HttpRequest.BodyPublishers.ofString(cuerpo)).build(), HttpResponse.BodyHandlers.ofString());
    }

    private HttpRequest.Builder peticion(String ruta, String token) {
        HttpRequest.Builder b = HttpRequest.newBuilder(URI.create("http://localhost:" + puerto + ruta));
        return token == null ? b : b.header("Authorization", "Bearer " + token);
    }
}
