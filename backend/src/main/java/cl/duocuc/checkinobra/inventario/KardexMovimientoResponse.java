package cl.duocuc.checkinobra.inventario;

import java.math.BigDecimal;
import java.time.LocalDateTime;

/**
 * Lo que la API expone de un {@link KardexMovimiento}.
 *
 * <p>Este es el record que cerró la fuga original: devolver la entidad
 * arrastraba la obra, el material, el usuario y su empresa completos, y con el
 * usuario iba el hash del PIN. Acá cada relación queda en su id más la etiqueta
 * mínima para leer el movimiento sin pedir nada más.
 */
public record KardexMovimientoResponse(
        Long id,
        String tipoMovimiento,
        double cantidad,
        LocalDateTime fecha,
        Long obraId,
        Long materialId,
        String materialSku,
        String materialNombre,
        Long usuarioId,
        String usuarioNombre,
        Long trabajadorId,
        String trabajadorNombre,
        String trabajadorRut,
        BigDecimal costoUnitario) {

    public static KardexMovimientoResponse de(KardexMovimiento k) {
        boolean recibio = k.getTrabajador() != null;
        return new KardexMovimientoResponse(
                k.getId(),
                k.getTipoMovimiento().name(),
                k.getCantidad(),
                k.getFecha(),
                k.getObra().getId(),
                k.getMaterial().getId(),
                k.getMaterial().getSku(),
                k.getMaterial().getNombre(),
                k.getUsuario().getId(),
                k.getUsuario().getNombre(),
                // Quién recibió. Nulo en una recepción y en un consumo sin
                // trabajador asignado.
                recibio ? k.getTrabajador().getId() : null,
                recibio ? k.getTrabajador().nombre() : null,
                recibio ? k.getTrabajador().rut() : null,
                // Solo en una recepción con factura; nulo en todo lo demás.
                k.getCostoUnitario());
    }
}
