package cl.duocuc.checkinobra.cubicacion;

import java.math.BigDecimal;
import java.time.LocalDateTime;

/**
 * Lo que la API expone de un {@link Material}.
 *
 * <p>{@code precioUnitario} es el precio de catálogo que fija el administrador.
 * Los tres campos de costo salen de las recepciones con factura y son nulos
 * mientras no haya ninguna: la app muestra entonces el precio de catálogo.
 */
public record MaterialResponse(
        Long id,
        String sku,
        String codigoBarra,
        String nombre,
        String categoria,
        double precioUnitario,
        double stockMinimo,
        Long empresaId,
        BigDecimal ultimoCostoUnitario,
        LocalDateTime fechaUltimoCosto,
        BigDecimal costoPromedio) implements MaterialVista {

    /** Un material sin compras registradas: recién creado, o sin facturas. */
    public static MaterialResponse de(Material m) {
        return de(m, null);
    }

    public static MaterialResponse de(Material m, CostoMaterial costo) {
        boolean conCosto = costo != null;
        return new MaterialResponse(
                m.getId(),
                m.getSku(),
                m.getCodigoBarra(),
                m.getNombre(),
                m.getCategoria().name(),
                m.getPrecioUnitario(),
                m.getStockMinimo(),
                m.getEmpresa().getId(),
                conCosto ? costo.getUltimoCostoUnitario() : null,
                conCosto ? costo.getFechaUltimoCosto() : null,
                conCosto ? costo.getCostoPromedio() : null);
    }
}
