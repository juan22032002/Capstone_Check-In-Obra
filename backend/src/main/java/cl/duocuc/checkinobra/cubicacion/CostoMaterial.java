package cl.duocuc.checkinobra.cubicacion;

import java.math.BigDecimal;
import java.time.LocalDateTime;

/**
 * Lo que costó de verdad un material, derivado de las recepciones con factura
 * del kardex. Igual que el stock, no se guarda: se calcula.
 *
 * <p>Es una proyección de {@link MaterialRepository#costosPorEmpresa}; un
 * material sin ninguna recepción con costo simplemente no aparece.
 */
public interface CostoMaterial {

    Long getMaterialId();

    /** El de la recepción más reciente. */
    BigDecimal getUltimoCostoUnitario();

    LocalDateTime getFechaUltimoCosto();

    /** Promedio ponderado por cantidad de todas las recepciones con costo. */
    BigDecimal getCostoPromedio();
}
