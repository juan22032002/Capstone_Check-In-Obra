package cl.duocuc.checkinobra.cubicacion;

/**
 * El catálogo de materiales sin precios ni costos, para el TRABAJADOR (S-08): lo
 * que necesita para elegir qué pedir y nada de lo comercial. La matriz de
 * permisos reserva los precios al administrador.
 */
public record MaterialBasicoResponse(
        Long id,
        String sku,
        String codigoBarra,
        String nombre,
        String categoria,
        double stockMinimo,
        Long empresaId) implements MaterialVista {

    public static MaterialBasicoResponse de(Material m) {
        return new MaterialBasicoResponse(
                m.getId(),
                m.getSku(),
                m.getCodigoBarra(),
                m.getNombre(),
                m.getCategoria().name(),
                m.getStockMinimo(),
                m.getEmpresa().getId());
    }
}
