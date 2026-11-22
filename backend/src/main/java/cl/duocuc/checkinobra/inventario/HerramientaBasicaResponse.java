package cl.duocuc.checkinobra.inventario;

/**
 * La herramienta sin su valor de reposición, para el TRABAJADOR (S-08). Conserva el
 * {@code codigoQr}: está impreso en la herramienta y no identifica a nadie.
 */
public record HerramientaBasicaResponse(
        Long id,
        String codigoQr,
        String nombre,
        String categoria,
        String estado,
        Long empresaId) implements HerramientaVista {

    public static HerramientaBasicaResponse de(Herramienta h) {
        return new HerramientaBasicaResponse(
                h.getId(),
                h.getCodigoQr(),
                h.getNombre(),
                h.getCategoria(),
                h.getEstado().name(),
                h.getEmpresa().getId());
    }
}
