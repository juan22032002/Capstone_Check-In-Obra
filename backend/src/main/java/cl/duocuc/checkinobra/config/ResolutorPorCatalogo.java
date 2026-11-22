package cl.duocuc.checkinobra.config;

import com.zaxxer.hikari.HikariConfig;
import com.zaxxer.hikari.HikariDataSource;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.DisposableBean;
import org.springframework.core.env.Environment;

import javax.sql.DataSource;
import java.util.Collection;
import java.util.List;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;

/**
 * Un pool de conexiones por empresa, armado desde el catálogo (MT2, #105).
 *
 * <p>Cada pool tiene las credenciales de una sola base, así que no existe un camino
 * desde él hacia la de otra constructora. Se arman al arrancar y se agrega uno cada vez
 * que se registra una empresa ({@link #refrescar}); una empresa que no es {@code ACTIVA}
 * no tiene pool, y su token deja de valer.
 *
 * <p>La contraseña no está en el catálogo: guarda una referencia {@code env:VARIABLE}
 * que se resuelve acá contra el entorno.
 */
public class ResolutorPorCatalogo implements ResolutorDeBases, DisposableBean {

    private static final Logger log = LoggerFactory.getLogger(ResolutorPorCatalogo.class);
    private static final String PREFIJO_ENV = "env:";

    private final CatalogoDeEmpresas catalogo;
    private final Environment entorno;
    private final UrlsDeBases urls;
    private final int tamanoPool;
    private final ConcurrentHashMap<Long, HikariDataSource> pools = new ConcurrentHashMap<>();
    /** Las empresas suspendidas según el catálogo, para responder 403 sin abrir su base (MT8). */
    private volatile Set<Long> suspendidas = Set.of();

    /**
     * @param urlDelServidor cualquier URL JDBC del servidor; solo se usa su parte de host y
     *     puerto, y la base se reemplaza por la de cada empresa
     */
    public ResolutorPorCatalogo(
            CatalogoDeEmpresas catalogo, Environment entorno, String urlDelServidor, int tamanoPool) {
        this.catalogo = catalogo;
        this.entorno = entorno;
        this.urls = new UrlsDeBases(urlDelServidor);
        this.tamanoPool = tamanoPool;
        refrescar();
    }

    /**
     * Arma el pool de las empresas activas que todavía no tienen y cierra el de las que
     * dejaron de estarlo. Si una base no se puede abrir lo deja en el log y sigue con las
     * demás: una empresa mal registrada no impide que arranquen las otras.
     */
    @Override
    public synchronized void refrescar() {
        List<CatalogoDeEmpresas.EmpresaRegistrada> activas = catalogo.listar().stream()
                .filter(CatalogoDeEmpresas.EmpresaRegistrada::abierta).toList();
        suspendidas = Set.copyOf(catalogo.listar().stream()
                .filter(e -> "SUSPENDIDA".equals(e.estado())).map(CatalogoDeEmpresas.EmpresaRegistrada::id).toList());
        Set<Long> vigentes = Set.copyOf(activas.stream().map(CatalogoDeEmpresas.EmpresaRegistrada::id).toList());
        pools.keySet().removeIf(id -> {
            if (vigentes.contains(id)) {
                return false;
            }
            pools.get(id).close();
            return true;
        });
        for (CatalogoDeEmpresas.EmpresaRegistrada e : activas) {
            if (!pools.containsKey(e.id())) {
                try {
                    pools.put(e.id(), pool(e));
                } catch (RuntimeException ex) {
                    log.error("No se pudo abrir la base de la empresa {} ({}): {}", e.id(), e.nombreBase(),
                            ex.getMessage());
                }
            }
        }
    }

    private HikariDataSource pool(CatalogoDeEmpresas.EmpresaRegistrada e) {
        String clave = secreto(e.secretoRef());
        HikariConfig config = new HikariConfig();
        config.setJdbcUrl(urls.de(e.nombreBase()));
        config.setUsername(e.usuarioBase());
        config.setPassword(clave);
        config.setPoolName("empresa-" + e.id());
        config.setMaximumPoolSize(tamanoPool);
        // Sin conexión al armar el pool: la base puede estar migrándose todavía.
        config.setInitializationFailTimeout(-1);
        return new HikariDataSource(config);
    }

    /** {@code env:VARIABLE} (se lee del entorno) o {@code file:nombre} (del directorio de secretos). */
    private String secreto(String ref) {
        if (ref != null && ref.startsWith(AlmacenDeSecretos.PREFIJO)) {
            return new AlmacenDeSecretos(entorno.getProperty("checkinobra.secretos.directorio", "./secretos"))
                    .leer(ref.substring(AlmacenDeSecretos.PREFIJO.length()));
        }
        if (ref == null || !ref.startsWith(PREFIJO_ENV)) {
            throw new IllegalStateException("La referencia al secreto debe ser env:VARIABLE o file:nombre");
        }
        String variable = ref.substring(PREFIJO_ENV.length());
        String clave = entorno.getProperty(variable);
        if (clave == null) {
            throw new IllegalStateException("No está definida la variable " + variable);
        }
        return clave;
    }

    @Override
    public DataSource baseDe(Long empresaId) {
        if (empresaId == null) {
            throw new SinEmpresaEnContextoException(
                    "No hay empresa en el contexto: esta operación no puede tocar la base de datos");
        }
        HikariDataSource pool = pools.get(empresaId);
        if (pool == null) {
            throw new SinEmpresaEnContextoException("La empresa " + empresaId + " no tiene una base registrada");
        }
        return pool;
    }

    @Override
    public boolean suspendida(Long empresaId) {
        return empresaId != null && suspendidas.contains(empresaId);
    }

    @Override
    public boolean conoce(Long empresaId) {
        return empresaId != null && pools.containsKey(empresaId);
    }

    @Override
    public Collection<Long> empresas() {
        return List.copyOf(pools.keySet());
    }

    @Override
    public void destroy() {
        pools.values().forEach(HikariDataSource::close);
        pools.clear();
    }
}
