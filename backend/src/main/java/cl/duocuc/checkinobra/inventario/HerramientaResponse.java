package cl.duocuc.checkinobra.inventario;

/**
 * Lo que la API expone de una {@link Herramienta}.
 *
 * <p>El {@code codigoQr} sí va: está impreso en la herramienta misma, es lo que
 * el bodeguero escanea, y no identifica a ninguna persona. Es lo contrario del
 * QR de credencial de un trabajador.
 */
public record HerramientaResponse(
        Long id,
        String codigoQr,
        String nombre,
        String categoria,
        String estado,
        double valorReposicion,
        Long empresaId) implements HerramientaVista {

    public static HerramientaResponse de(Herramienta h) {
        return new HerramientaResponse(
                h.getId(),
                h.getCodigoQr(),
                h.getNombre(),
                h.getCategoria(),
                h.getEstado().name(),
                h.getValorReposicion(),
                h.getEmpresa().getId());
    }
}
