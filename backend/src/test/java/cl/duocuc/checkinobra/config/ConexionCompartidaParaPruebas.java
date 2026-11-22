package cl.duocuc.checkinobra.config;

import com.zaxxer.hikari.HikariConfig;
import com.zaxxer.hikari.HikariDataSource;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

import javax.sql.DataSource;
import java.util.Collection;
import java.util.List;

/**
 * El resolutor de la suite de pruebas: una sola base para todas las empresas.
 *
 * <p>Las pruebas existentes crean muchas empresas de prueba en una misma base y dan por
 * hecho el filtro por empresa ({@code AccesoEmpresa}), que es la segunda capa de la
 * defensa. Con el resolutor del catálogo cada una necesitaría su propia base. Este
 * resolutor las manda todas a la misma, y solo existe con
 * {@code checkinobra.pruebas.conexion-compartida=true}, que fija el {@code pom.xml} para
 * las pruebas: ningún despliegue lo trae.
 *
 * <p>Lo que enruta de verdad (una base por empresa, y fallar sin empresa) se prueba en
 * {@code TenantRoutingDataSourceTest}, con dos bases distintas.
 */
@Configuration
@ConditionalOnProperty(name = "checkinobra.pruebas.conexion-compartida", havingValue = "true")
class ConexionCompartidaParaPruebas {

    static final class Compartido implements ResolutorDeBases, AutoCloseable {

        private final HikariDataSource base;

        Compartido(HikariDataSource base) {
            this.base = base;
        }

        @Override
        public DataSource baseDe(Long empresaId) {
            return base;
        }

        @Override
        public boolean conoce(Long empresaId) {
            return empresaId != null;
        }

        @Override
        public Collection<Long> empresas() {
            // Sin empresas registradas: las tareas que las recorren no tienen nada que hacer.
            return List.of();
        }

        @Override
        public void close() {
            base.close();
        }
    }

    @Bean(destroyMethod = "close")
    Compartido resolutorCompartido(
            @Value("${spring.datasource.url}") String url,
            @Value("${spring.datasource.username}") String usuario,
            @Value("${spring.datasource.password}") String clave,
            @Value("${spring.flyway.user}") String migrador,
            @Value("${spring.flyway.password}") String claveMigrador) {
        // En una base de despliegue migra MigradorDeBases al arrancar; aquí la base compartida de
        // la suite se migra antes de que Hibernate valide el mapeo contra ella.
        org.flywaydb.core.Flyway.configure()
                .dataSource(url, migrador, claveMigrador)
                .locations("classpath:db/migration")
                .ignoreMigrationPatterns("*:missing")
                .load()
                .migrate();
        HikariConfig config = new HikariConfig();
        config.setJdbcUrl(url);
        config.setUsername(usuario);
        config.setPassword(clave);
        config.setPoolName("pruebas-compartido");
        config.setMaximumPoolSize(10);
        return new Compartido(new HikariDataSource(config));
    }
}
