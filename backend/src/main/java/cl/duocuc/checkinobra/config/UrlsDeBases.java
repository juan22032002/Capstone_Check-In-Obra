package cl.duocuc.checkinobra.config;

/**
 * Arma la URL JDBC de la base de cada empresa. Las bases están en el mismo servidor, así
 * que se toma la de la base actual y se le cambia el nombre de la base.
 */
public final class UrlsDeBases {

    private final String prefijo;
    private final String parametros;

    /** @param urlDelServidor cualquier URL JDBC del servidor; solo importan su host, puerto y parámetros */
    public UrlsDeBases(String urlDelServidor) {
        int barra = urlDelServidor.lastIndexOf('/');
        int interrogacion = urlDelServidor.indexOf('?', barra);
        this.prefijo = urlDelServidor.substring(0, barra + 1);
        this.parametros = interrogacion < 0 ? "" : urlDelServidor.substring(interrogacion);
    }

    public String de(String nombreBase) {
        return prefijo + nombreBase + parametros;
    }
}
