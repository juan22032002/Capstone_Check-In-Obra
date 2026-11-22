package cl.duocuc.checkinobra.config;

import cl.duocuc.checkinobra.cubicacion.CategoriaMaterial;
import cl.duocuc.checkinobra.cubicacion.Material;
import cl.duocuc.checkinobra.cubicacion.MaterialRepository;
import cl.duocuc.checkinobra.cubicacion.Partida;
import cl.duocuc.checkinobra.cubicacion.PartidaRepository;
import cl.duocuc.checkinobra.cubicacion.TipoPartida;
import cl.duocuc.checkinobra.inventario.EstadoHerramienta;
import cl.duocuc.checkinobra.inventario.Herramienta;
import cl.duocuc.checkinobra.inventario.HerramientaRepository;
import cl.duocuc.checkinobra.obra.Cuadrilla;
import cl.duocuc.checkinobra.obra.CuadrillaRepository;
import cl.duocuc.checkinobra.obra.EstadoObra;
import cl.duocuc.checkinobra.obra.Obra;
import cl.duocuc.checkinobra.obra.ObraRepository;
import cl.duocuc.checkinobra.obra.Trabajador;
import cl.duocuc.checkinobra.obra.TrabajadorRepository;
import cl.duocuc.checkinobra.presupuesto.EstadoPresupuesto;
import cl.duocuc.checkinobra.presupuesto.Presupuesto;
import cl.duocuc.checkinobra.presupuesto.PresupuestoRepository;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.server.LocalServerPort;
import org.springframework.core.NestedExceptionUtils;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DriverManagerDataSource;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.catchThrowable;

/**
 * MT5 (#108): una empresa no alcanza los datos de otra, probado con <b>dos bases de datos
 * reales</b> registradas en el catálogo y el enrutador de verdad.
 *
 * <p>A diferencia de las demás pruebas, que comparten una base y dependen del filtro por
 * empresa ({@code AccesoEmpresa}), acá los datos de B <b>no están</b> en la base que abre el
 * token de A. Por eso estos casos pasan aunque un endpoint olvide filtrar por empresa, que es
 * justo lo que esta capa existe para cubrir (S-04, S-05, S-06).
 *
 * <p>Necesita la segunda base vacía {@code checkinobra_b} (o la de
 * {@code checkinobra.pruebas.segunda-base}), que crea {@code db/crear-roles.sh} con
 * {@code CHECKINOBRA_BASES_EXTRA}; la CI lo hace. Si no existe, falla con el motivo.
 */
@SpringBootTest(
        webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT,
        properties = {
                "checkinobra.pruebas.conexion-compartida=false",
                // Sin base por defecto, Hibernate no puede conectarse al arrancar (igual que en producción).
                "spring.jpa.hibernate.ddl-auto=none",
                "spring.jpa.properties.hibernate.boot.allow_jdbc_metadata_access=false"})
class AislamientoConDosBasesTest {

    /** Lo que se pide a la API y no debe aparecer en la respuesta de la empresa ajena. */
    private static final long BASE_DE_IDS_DE_B = 800_000_000L;

    @LocalServerPort private int puerto;

    @Autowired private CatalogoDeEmpresas catalogo;
    @Autowired private MigradorDeBases migrador;
    @Autowired private ResolutorDeBases resolutor;
    @Autowired private JwtService jwtService;
    @Autowired private JdbcTemplate jdbc;
    @Autowired private RegistroIdempotencia registroIdempotencia;
    @Autowired private EmpresaRepository empresaRepository;
    @Autowired private UsuarioRepository usuarioRepository;
    @Autowired private ObraRepository obraRepository;
    @Autowired private CuadrillaRepository cuadrillaRepository;
    @Autowired private TrabajadorRepository trabajadorRepository;
    @Autowired private MaterialRepository materialRepository;
    @Autowired private HerramientaRepository herramientaRepository;
    @Autowired private PartidaRepository partidaRepository;
    @Autowired private PresupuestoRepository presupuestoRepository;

    @Value("${checkinobra.pruebas.segunda-base:checkinobra_b}") private String segundaBase;
    @Value("${spring.datasource.username}") private String usuarioApi;
    @Value("${spring.flyway.user}") private String migradorUsuario;
    @Value("${spring.flyway.password}") private String migradorClave;
    @Value("${spring.datasource.url}") private String urlEmpresa;
    @Value("${checkinobra.catalogo.url}") private String urlCatalogo;
    @Value("${checkinobra.catalogo.username}") private String usuarioCatalogo;
    @Value("${checkinobra.catalogo.password}") private String claveCatalogo;

    private final HttpClient http = HttpClient.newHttpClient();
    private final List<Long> registradas = new ArrayList<>();

    private String s;
    private long idA;
    private long idB;
    private String tokenA;
    private String tokenB;
    private Obra obraDeB;
    private Obra obraDeA;
    private Material materialDeB;
    private Herramienta herramientaDeB;
    private Usuario trabajadorDeB;
    private Trabajador fichaDeB;
    private Partida partidaDeB;
    private Presupuesto presupuestoDeB;

    @BeforeEach
    void registrarDosEmpresasEnDosBases() {
        s = UUID.randomUUID().toString().substring(0, 8);

        // A vive en la base de esta suite; si ya está registrada (una base de desarrollo con su empresa)
        // se usa esa. B vive en la segunda base, vacía.
        Optional<CatalogoDeEmpresas.EmpresaRegistrada> existente = catalogo.buscarPorBase(catalogo.nombreBaseActual());
        idA = existente.map(CatalogoDeEmpresas.EmpresaRegistrada::id)
                .orElseGet(() -> registrar(900_000_000L + (long) (Math.random() * 1_000_000), "A-" + s, "checkinobra"));
        idB = registrar(idA + 1_000_001L, "B-" + s, segundaBase);
        migrar(idA);
        migrar(idB);
        resolutor.refrescar();
        assertThat(resolutor.conoce(idA)).as("pool de A").isTrue();
        assertThat(resolutor.conoce(idB)).as("pool de B").isTrue();

        // Los ids de lo que se crea en B parten muy arriba, para que no coincidan con nada de A.
        for (String secuencia : List.of("obras", "materiales", "herramientas", "usuarios", "trabajadores",
                "partidas", "presupuestos", "cuadrillas")) {
            // Nunca hacia atrás: pruebas anteriores dejaron filas con ids altos en esta base.
            comoMigrador(segundaBase).execute("SELECT setval('" + secuencia + "_id_seq', GREATEST((SELECT coalesce(max(id), 0) FROM "
                    + secuencia + "), " + BASE_DE_IDS_DE_B + "))");
        }

        Usuario adminA = crearEmpresaYAdmin(idA, "Empresa A " + s, "A-" + s, "admin-a-" + s);
        Usuario adminB = crearEmpresaYAdmin(idB, "Empresa B " + s, "B-" + s, "admin-b-" + s);
        tokenA = jwtService.emitir(adminA);
        tokenB = jwtService.emitir(adminB);

        obraDeA = TenantContext.ejecutarEn(idA, () -> obraRepository.save(obra("Obra-A-" + s, idA)));
        sembrarDatosDeB();
    }

    @AfterEach
    void limpiar() {
        TenantContext.limpiar();
        for (Long id : registradas) {
            JdbcTemplate catalogoJdbc = new JdbcTemplate(
                    new DriverManagerDataSource(urlCatalogo, usuarioCatalogo, claveCatalogo));
            catalogoJdbc.update("DELETE FROM indice_login WHERE empresa_id = ?", id);
            catalogoJdbc.update("DELETE FROM empresas WHERE id = ?", id);
        }
        resolutor.refrescar();
    }

    // --- cada empresa abre solo su base -----------------------------------------------------

    @Test
    void cadaEmpresaAbreSuPropiaBaseYNoTieneLosDatosDeLaOtra() {
        assertThat(TenantContext.ejecutarEn(idA, () -> jdbc.queryForObject("SELECT current_database()", String.class)))
                .isEqualTo(catalogo.nombreBaseActual());
        assertThat(TenantContext.ejecutarEn(idB, () -> jdbc.queryForObject("SELECT current_database()", String.class)))
                .isEqualTo(segundaBase);

        // La empresa B no existe en la base de A, ni la A en la de B: no es que se filtre, es que no está.
        assertThat(TenantContext.ejecutarEn(idA,
                () -> jdbc.queryForObject("SELECT count(*) FROM empresas WHERE id = ?", Integer.class, idB))).isZero();
        assertThat(TenantContext.ejecutarEn(idB,
                () -> jdbc.queryForObject("SELECT count(*) FROM empresas WHERE id = ?", Integer.class, idA))).isZero();
        assertThat(TenantContext.ejecutarEn(idA, () -> obraRepository.findById(obraDeB.getId()))).isEmpty();
        assertThat(TenantContext.ejecutarEn(idB, () -> obraRepository.findById(obraDeA.getId()))).isEmpty();
    }

    // --- GET por id y listados con el token de otra empresa ---------------------------------

    @Test
    void cadaGetPorIdDeOtraEmpresaResponde404() throws Exception {
        List<String> rutas = List.of(
                "/api/obras/" + obraDeB.getId(),
                "/api/obras/" + obraDeB.getId() + "/detalle",
                "/api/materiales/" + materialDeB.getId(),
                "/api/herramientas/" + herramientaDeB.getId(),
                "/api/usuarios/" + trabajadorDeB.getId(),
                "/api/trabajadores/" + fichaDeB.getId(),
                "/api/partidas/" + partidaDeB.getId(),
                "/api/partidas/" + partidaDeB.getId() + "/items-cubicados",
                "/api/presupuestos/" + presupuestoDeB.getId(),
                "/api/presupuestos/" + presupuestoDeB.getId() + "/desviacion");

        for (String ruta : rutas) {
            assertThat(get(ruta, tokenA).statusCode()).as("GET %s con el token de A", ruta).isEqualTo(404);
        }
    }

    @Test
    void cadaListadoDeOtraEmpresaResponde404OVacio() throws Exception {
        // Algunos de estos endpoints todavía no validan la empresa del id (S-04 y S-05 en esta rama):
        // con una sola base filtraban datos ajenos. Con una base por empresa, o dan 404 o dan una
        // lista vacía, porque lo de B no está en la base que abre el token de A.
        for (String ruta : List.of(
                "/api/partidas?obraId=" + obraDeB.getId(),
                "/api/trabajadores?obraId=" + obraDeB.getId(),
                "/api/presupuestos?obraId=" + obraDeB.getId(),
                "/api/cuadrillas?obraId=" + obraDeB.getId(),
                "/api/presupuestos/" + presupuestoDeB.getId() + "/items")) {
            HttpResponse<String> r = get(ruta, tokenA);

            boolean ausente = r.statusCode() == 404 || (r.statusCode() == 200 && r.body().strip().equals("[]"));
            assertThat(ausente).as("GET %s con el token de A: %d %s", ruta, r.statusCode(), r.body()).isTrue();
            assertThat(r.body()).doesNotContain("-B-" + s);
        }
    }

    @Test
    void ningunListadoGeneralDeUnaEmpresaTraeNadaDeLaOtra() throws Exception {
        for (String ruta : List.of("/api/obras", "/api/materiales", "/api/herramientas", "/api/usuarios")) {
            HttpResponse<String> r = get(ruta, tokenA);

            assertThat(r.statusCode()).as(ruta).isEqualTo(200);
            assertThat(r.body()).as("%s con el token de A", ruta)
                    .doesNotContain("-B-" + s).doesNotContain("Empresa B " + s).doesNotContain("admin-b-" + s);
        }
    }

    @Test
    void ysiguenFuncionandoParaQuienSiLosTiene() throws Exception {
        assertThat(get("/api/obras/" + obraDeB.getId(), tokenB).statusCode()).isEqualTo(200);
        assertThat(get("/api/materiales/" + materialDeB.getId(), tokenB).statusCode()).isEqualTo(200);
        assertThat(get("/api/obras/" + obraDeA.getId(), tokenA).statusCode()).isEqualTo(200);
        // Y al revés: B tampoco alcanza lo de A.
        assertThat(get("/api/obras/" + obraDeA.getId(), tokenB).statusCode()).isEqualTo(404);
    }

    @Test
    void unTokenDeUnaEmpresaSinBaseRegistradaNoEntra() throws Exception {
        Usuario fantasma = Usuario.builder().id(1L).nombre("x").email("x@x.cl").rol(RolUsuario.ADMIN)
                .empresa(Empresa.builder().id(987_654_321L).nombre("Fantasma").rut("0-0").build()).build();

        assertThat(get("/api/obras", jwtService.emitir(fantasma)).statusCode()).isEqualTo(401);
    }

    // --- sin empresa en el contexto ----------------------------------------------------------

    @Test
    void sinEmpresaEnElContextoLaPeticionFallaYNoCaeEnNingunaBase() {
        TenantContext.limpiar();

        Throwable porJdbc = catchThrowable(() -> jdbc.queryForObject("SELECT 1", Integer.class));
        Throwable porJpa = catchThrowable(() -> empresaRepository.findAll());

        assertThat(NestedExceptionUtils.getMostSpecificCause(porJdbc)).isInstanceOf(SinEmpresaEnContextoException.class);
        assertThat(NestedExceptionUtils.getMostSpecificCause(porJpa)).isInstanceOf(SinEmpresaEnContextoException.class);
    }

    @Test
    void unaTareaProgramadaSinEmpresaFijadaFalla() {
        TenantContext.limpiar();

        // Lo que hacía purgarVencidas antes de recorrer las empresas: tocar la base sin contexto.
        Throwable sinEmpresa = catchThrowable(() -> registroIdempotencia.liberar(1L, UUID.randomUUID()));

        assertThat(NestedExceptionUtils.getMostSpecificCause(sinEmpresa))
                .isInstanceOf(SinEmpresaEnContextoException.class);
    }

    @Test
    void laPurgaRecorreLasDosEmpresasYNoDejaContexto() {
        registroIdempotencia.purgarVencidas();

        assertThat(TenantContext.actual()).isEmpty();
    }

    // ------------------------------------------------------------------------------------------

    private long registrar(long id, String rut, String base) {
        long registrado = catalogo.registrar(id, rut, "Empresa " + rut, base, usuarioApi, "env:SPRING_DATASOURCE_PASSWORD");
        registradas.add(registrado);
        return registrado;
    }

    private void migrar(long id) {
        var e = catalogo.listar().stream().filter(x -> x.id() == id).findFirst().orElseThrow();
        MigradorDeBases.Resultado r = migrador.migrar(e);
        assertThat(r.ok()).as("migración de la base %s: %s", e.nombreBase(), r.error()).isTrue();
    }

    private JdbcTemplate comoMigrador(String base) {
        String url = urlEmpresa.substring(0, urlEmpresa.lastIndexOf('/') + 1) + base;
        return new JdbcTemplate(new DriverManagerDataSource(url, migradorUsuario, migradorClave));
    }

    /** La fila de la empresa en su propia base (con el id del catálogo) y su administrador. */
    private Usuario crearEmpresaYAdmin(long idEmpresa, String nombre, String rut, String nombreAdmin) {
        return TenantContext.ejecutarEn(idEmpresa, () -> {
            jdbc.update("INSERT INTO empresas (id, nombre, rut) VALUES (?, ?, ?) ON CONFLICT (id) DO NOTHING",
                    idEmpresa, nombre, rut);
            Empresa empresa = empresaRepository.findById(idEmpresa).orElseThrow();
            Usuario admin = usuarioRepository.save(Usuario.builder().nombre(nombreAdmin)
                    .email(nombreAdmin + "@test.cl").rol(RolUsuario.ADMIN).empresa(empresa).build());
            return admin;
        });
    }

    private Obra obra(String nombre, long idEmpresa) {
        Empresa empresa = empresaRepository.findById(idEmpresa).orElseThrow();
        return Obra.builder().nombre(nombre).cliente("Cliente").ubicacion("Santiago")
                .estado(EstadoObra.ACTIVA).empresa(empresa).build();
    }

    private void sembrarDatosDeB() {
        TenantContext.ejecutarEn(idB, () -> {
            Empresa empresa = empresaRepository.findById(idB).orElseThrow();
            obraDeB = obraRepository.save(obra("Obra-B-" + s, idB));
            Cuadrilla cuadrilla = cuadrillaRepository.save(Cuadrilla.builder().nombre("Cuadrilla-B-" + s).obra(obraDeB).build());
            trabajadorDeB = usuarioRepository.save(Usuario.builder().nombre("obrero-B-" + s)
                    .email("obrero-B-" + s + "@test.cl").rol(RolUsuario.TRABAJADOR).empresa(empresa).build());
            fichaDeB = trabajadorRepository.save(Trabajador.builder()
                    .usuario(trabajadorDeB).cuadrilla(cuadrilla).credencialQr("QR-B-" + s).build());
            materialDeB = materialRepository.save(Material.builder().sku(("MAT-B-" + s).toUpperCase())
                    .nombre("Material-B-" + s).categoria(CategoriaMaterial.VOLCANITA)
                    .precioUnitario(5980).stockMinimo(0).empresa(empresa).build());
            herramientaDeB = herramientaRepository.save(Herramienta.builder().codigoQr(("H-B-" + s).toUpperCase())
                    .nombre("Herramienta-B-" + s).categoria("Eléctrica").estado(EstadoHerramienta.DISPONIBLE)
                    .valorReposicion(90000).empresa(empresa).build());
            partidaDeB = partidaRepository.save(Partida.builder().tipo(TipoPartida.TABIQUE)
                    .anchoM(4).altoM(2.4).separacionMontantes(0.6).obra(obraDeB).build());
            presupuestoDeB = presupuestoRepository.save(Presupuesto.builder()
                    .estado(EstadoPresupuesto.BORRADOR).total(0).obra(obraDeB).build());
        });
    }

    private HttpResponse<String> get(String ruta, String token) throws Exception {
        return http.send(HttpRequest.newBuilder(URI.create("http://localhost:" + puerto + ruta))
                .header("Authorization", "Bearer " + token).GET().build(), HttpResponse.BodyHandlers.ofString());
    }
}
