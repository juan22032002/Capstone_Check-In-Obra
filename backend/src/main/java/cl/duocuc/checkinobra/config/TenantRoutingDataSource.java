package cl.duocuc.checkinobra.config;

import org.springframework.jdbc.datasource.lookup.AbstractRoutingDataSource;

import javax.sql.DataSource;

/**
 * El {@code DataSource} de la aplicación: cada conexión que pide JPA va a la base
 * de la empresa que está en el {@link TenantContext}, y a ninguna otra (MT2, #105).
 *
 * <p>No tiene base por defecto. Los destinos los pone el {@link ResolutorDeBases}
 * (un pool por empresa, armado desde el catálogo), no un mapa fijo, para que una
 * empresa dada de alta después del arranque tenga su pool sin reiniciar.
 */
public class TenantRoutingDataSource extends AbstractRoutingDataSource {

    private final ResolutorDeBases resolutor;

    public TenantRoutingDataSource(ResolutorDeBases resolutor) {
        this.resolutor = resolutor;
    }

    @Override
    protected Object determineCurrentLookupKey() {
        return TenantContext.actual().orElse(null);
    }

    @Override
    protected DataSource determineTargetDataSource() {
        return resolutor.baseDe(TenantContext.actual().orElse(null));
    }

    /** Los destinos son dinámicos: no hay mapa que resolver al arrancar. */
    @Override
    public void afterPropertiesSet() {
        // Sin conexión por defecto y sin mapa fijo: nada que validar.
    }
}
