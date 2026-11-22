package cl.duocuc.checkinobra.config;

import com.zaxxer.hikari.HikariConfig;
import com.zaxxer.hikari.HikariDataSource;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.core.annotation.Order;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Component;

import java.util.Optional;

/**
 * Deja registrada en el catálogo a la empresa de la base actual, y abre su pool (MT2, #105).
 *
 * <p>Es el "alta de empresa" del sistema de una sola empresa. Corre antes que todo lo que
 * usa la base por JPA, y por eso lee con una conexión directa y no con el enrutador: el
 * enrutador necesita este registro para saber qué base abrir.
 *
 * <ul>
 *   <li>Si la base ya está en el catálogo, no hace nada.</li>
 *   <li>Si no, y la base tiene a la empresa, la registra con su mismo id (el que ya viaja en
 *       los JWT y referencian las FKs).</li>
 *   <li>Si la base está vacía y hay una clave inicial, la catálogo asigna el id y se crea la
 *       empresa con él (ya no la siembra la migración V2).</li>
 * </ul>
 */
@Component
@Order(0)
public class BaseInicialInicializador implements ApplicationRunner {

    private static final Logger log = LoggerFactory.getLogger(BaseInicialInicializador.class);

    private final CatalogoDeEmpresas catalogo;
    private final ResolutorDeBases resolutor;
    private final MigradorDeBases migrador;
    private final String url;
    private final String usuario;
    private final String clave;
    private final String rutEmpresa;
    private final String nombreEmpresa;
    private final String claveInicial;

    public BaseInicialInicializador(
            CatalogoDeEmpresas catalogo,
            ResolutorDeBases resolutor,
            MigradorDeBases migrador,
            @Value("${spring.datasource.url}") String url,
            @Value("${spring.datasource.username}") String usuario,
            @Value("${spring.datasource.password}") String clave,
            @Value("${checkinobra.primera-empresa.rut:76.412.330-9}") String rutEmpresa,
            @Value("${checkinobra.primera-empresa.nombre:Constructora Arauco Ltda.}") String nombreEmpresa,
            @Value("${checkinobra.primer-admin.clave:}") String claveInicial) {
        this.catalogo = catalogo;
        this.resolutor = resolutor;
        this.migrador = migrador;
        this.url = url;
        this.usuario = usuario;
        this.clave = clave;
        this.rutEmpresa = rutEmpresa;
        this.nombreEmpresa = nombreEmpresa;
        this.claveInicial = claveInicial;
    }

    @Override
    public void run(ApplicationArguments args) {
        asegurar(rutEmpresa, nombreEmpresa, claveInicial != null && !claveInicial.isBlank());
    }

    /**
     * @param crearSiFalta crear la empresa si la base está vacía
     * @return el id de la empresa de la base actual en el catálogo, o vacío si no hay
     */
    public Optional<Long> asegurar(String rut, String nombre, boolean crearSiFalta) {
        Optional<CatalogoDeEmpresas.EmpresaRegistrada> yaRegistrada =
                catalogo.buscarPorBase(catalogo.nombreBaseActual());
        if (yaRegistrada.isPresent()) {
            resolutor.refrescar();
            return yaRegistrada.map(CatalogoDeEmpresas.EmpresaRegistrada::id);
        }
        Optional<Long> id = registrarDesdeLaBase(rut, nombre, crearSiFalta);
        resolutor.refrescar();
        return id;
    }

    private Optional<Long> registrarDesdeLaBase(String rut, String nombre, boolean crearSiFalta) {
        HikariConfig config = new HikariConfig();
        config.setJdbcUrl(url);
        config.setUsername(usuario);
        config.setPassword(clave);
        config.setMaximumPoolSize(1);
        config.setPoolName("base-inicial");
        try (HikariDataSource conexion = new HikariDataSource(config)) {
            JdbcClient base = JdbcClient.create(conexion);
            // Una base recién creada no tiene esquema: se migra más abajo, antes de crear la empresa.
            boolean hayEsquema = base.sql("SELECT to_regclass('public.empresas') IS NOT NULL")
                    .query(Boolean.class).single();
            Optional<Long> existente = hayEsquema
                    ? base.sql("SELECT id FROM empresas WHERE rut = :rut").param("rut", rut).query(Long.class).optional()
                    : Optional.empty();
            if (existente.isPresent()) {
                return Optional.of(catalogo.registrar(existente.get(), rut, nombreDe(base, existente.get(), nombre),
                        catalogo.nombreBaseActual(), catalogo.usuarioBaseActual(), catalogo.secretoBaseActual()));
            }
            Long empresas = hayEsquema ? base.sql("SELECT count(*) FROM empresas").query(Long.class).single() : 0L;
            if (!crearSiFalta || empresas > 0) {
                log.warn("La base «{}» no tiene a la empresa {} y no se registró en el catálogo. Define "
                        + "PRIMER_ADMIN_CLAVE para crearla en una base vacía.", catalogo.nombreBaseActual(), rut);
                return Optional.empty();
            }
            long id = catalogo.registrar(null, rut, nombre, catalogo.nombreBaseActual(),
                    catalogo.usuarioBaseActual(), catalogo.secretoBaseActual());
            // La base puede estar vacía: se migra antes de insertar la empresa. Las demás bases del
            // catálogo las migra MigracionInicializador.
            var registrada = catalogo.buscarPorBase(catalogo.nombreBaseActual()).orElseThrow();
            MigradorDeBases.Resultado migracion = migrador.migrar(registrada);
            if (!migracion.ok()) {
                throw new IllegalStateException("No se pudo migrar la base inicial: " + migracion.error());
            }
            base.sql("INSERT INTO empresas (id, nombre, rut) VALUES (:id, :nombre, :rut)")
                    .param("id", id).param("nombre", nombre).param("rut", rut).update();
            // No se adelanta la secuencia de empresas.id: la API no tiene permiso sobre ella (solo
            // DML) y no hace falta, porque la base de una empresa tiene una sola fila en esa tabla.
            log.info("Se creó la empresa {} con el id {} en la base «{}».", rut, id, catalogo.nombreBaseActual());
            return Optional.of(id);
        }
    }

    /** El nombre que ya tiene la empresa en su base manda sobre el de la configuración. */
    private static String nombreDe(JdbcClient base, long id, String porDefecto) {
        return base.sql("SELECT nombre FROM empresas WHERE id = :id").param("id", id)
                .query(String.class).optional().orElse(porDefecto);
    }
}
