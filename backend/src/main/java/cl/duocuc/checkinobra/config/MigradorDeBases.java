package cl.duocuc.checkinobra.config;

import org.flywaydb.core.Flyway;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import java.util.ArrayList;
import java.util.List;

/**
 * Migra la base de cada empresa del catálogo a la última versión (MT3, #106).
 *
 * <p>Corre con el usuario migrador, que es dueño del esquema; la API en ejecución no tiene
 * permisos de DDL. Es Flyway programático, no el de Spring Boot: ese migra una sola base,
 * y acá hay una por empresa. Una base que falla queda con su error anotado en el catálogo
 * y sin pool, y no impide que se migren ni arranquen las demás.
 *
 * <p>Las migraciones de cada base son las mismas ({@code db/migration}), así que todas
 * quedan en la misma versión. Una base vacía, recién registrada, queda con el esquema
 * completo en este mismo paso.
 */
@Component
public class MigradorDeBases {

    private static final Logger log = LoggerFactory.getLogger(MigradorDeBases.class);

    /** El resultado de migrar la base de una empresa. */
    public record Resultado(Long empresaId, String nombreBase, boolean ok, String error) {
    }

    private final CatalogoDeEmpresas catalogo;
    private final UrlsDeBases urls;
    private final String usuario;
    private final String clave;

    public MigradorDeBases(
            CatalogoDeEmpresas catalogo,
            @Value("${spring.datasource.url}") String urlDelServidor,
            @Value("${spring.flyway.user}") String usuario,
            @Value("${spring.flyway.password}") String clave) {
        this.catalogo = catalogo;
        this.urls = new UrlsDeBases(urlDelServidor);
        this.usuario = usuario;
        this.clave = clave;
    }

    /** Migra la base de cada empresa activa, una por una, y anota el resultado de cada una en el catálogo. */
    public List<Resultado> migrarTodas() {
        List<Resultado> resultados = new ArrayList<>();
        for (CatalogoDeEmpresas.EmpresaRegistrada e : catalogo.listar()) {
            if ("ACTIVA".equals(e.estado())) {
                resultados.add(migrar(e));
            }
        }
        return resultados;
    }

    /** Migra la base de una empresa. Nunca lanza: el fallo queda en el resultado y en el catálogo. */
    public Resultado migrar(CatalogoDeEmpresas.EmpresaRegistrada empresa) {
        try {
            migrarUrl(urls.de(empresa.nombreBase()));
            catalogo.marcarMigracion(empresa.id(), true, null);
            return new Resultado(empresa.id(), empresa.nombreBase(), true, null);
        } catch (RuntimeException e) {
            String causa = causaRaiz(e);
            log.error("No se pudo migrar la base «{}» de la empresa {}; queda sin abrir y las demás siguen: {}",
                    empresa.nombreBase(), empresa.id(), causa);
            catalogo.marcarMigracion(empresa.id(), false, causa);
            return new Resultado(empresa.id(), empresa.nombreBase(), false, causa);
        }
    }

    /** Aplica las migraciones pendientes a la base de esta URL. Es el paso de bajo nivel. */
    void migrarUrl(String url) {
        Flyway.configure()
                .dataSource(url, usuario, clave)
                .locations("classpath:db/migration")
                // V2__seed_admin.sql salió de db/migration (MT1): las bases que la aplicaron antes la
                // conservan en su historial, y Flyway no debe fallar por una migración que ya no está.
                .ignoreMigrationPatterns("*:missing")
                .load()
                .migrate();
    }

    private static String causaRaiz(Throwable e) {
        Throwable causa = e;
        while (causa.getCause() != null && causa.getCause() != causa) {
            causa = causa.getCause();
        }
        return causa.getMessage() != null ? causa.getMessage() : e.getClass().getSimpleName();
    }
}
