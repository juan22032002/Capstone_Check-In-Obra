package cl.duocuc.checkinobra.config;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Primary;
import org.springframework.core.env.Environment;

import javax.sql.DataSource;

/**
 * El {@code DataSource} de la aplicación es el enrutador por empresa (MT2, #105), no el
 * pool único que armaba Spring Boot desde {@code spring.datasource.*}. Esas propiedades
 * siguen sirviendo, pero solo para saber en qué servidor están las bases y para
 * registrar la base actual.
 *
 * <p>La propiedad {@code checkinobra.pruebas.conexion-compartida} existe para que la
 * suite de pruebas ponga su propio resolutor (una sola base compartida): quien no la
 * define, y es el caso de todo despliegue, usa el del catálogo.
 */
@Configuration
public class TenantDataSourceConfig {

    @Bean
    @ConditionalOnProperty(name = "checkinobra.pruebas.conexion-compartida", havingValue = "false", matchIfMissing = true)
    public ResolutorDeBases resolutorPorCatalogo(
            CatalogoDeEmpresas catalogo,
            Environment entorno,
            @Value("${spring.datasource.url}") String urlDelServidor,
            @Value("${checkinobra.tenant.tamano-pool:5}") int tamanoPool) {
        return new ResolutorPorCatalogo(catalogo, entorno, urlDelServidor, tamanoPool);
    }

    @Bean
    @Primary
    public DataSource dataSource(ResolutorDeBases resolutor) {
        return new TenantRoutingDataSource(resolutor);
    }
}
