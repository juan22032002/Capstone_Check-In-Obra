package cl.duocuc.checkinobra.inventario;

import java.util.EnumSet;
import java.util.Set;

/**
 * El camino de un pedido especial, solo hacia adelante:
 *
 * <pre>
 * PENDIENTE → EN_GESTION → LISTO_PARA_RETIRO → ENTREGADO → RECIBIDO
 *     └──────────────┴──────────┴→ RECHAZADO (bodega)
 * PENDIENTE, EN_GESTION → CANCELADO (el trabajador)
 * </pre>
 *
 * <p>Se puede saltar hacia adelante —si bodega ya lo tiene, no pasa por "en
 * gestión"—, nunca volver.
 */
public enum EstadoPedidoEspecial {
    PENDIENTE,
    EN_GESTION,
    LISTO_PARA_RETIRO,
    ENTREGADO,
    RECIBIDO,
    RECHAZADO,
    CANCELADO;

    /** Lo que todavía espera algo de alguien: la bandeja de bodega. */
    public static final Set<EstadoPedidoEspecial> ABIERTOS =
            EnumSet.of(PENDIENTE, EN_GESTION, LISTO_PARA_RETIRO, ENTREGADO);

    /** Desde qué estados se llega a este. */
    Set<EstadoPedidoEspecial> desde() {
        return switch (this) {
            case PENDIENTE -> EnumSet.noneOf(EstadoPedidoEspecial.class);
            case EN_GESTION -> EnumSet.of(PENDIENTE);
            case LISTO_PARA_RETIRO -> EnumSet.of(PENDIENTE, EN_GESTION);
            case ENTREGADO, RECHAZADO -> EnumSet.of(PENDIENTE, EN_GESTION, LISTO_PARA_RETIRO);
            case RECIBIDO -> EnumSet.of(ENTREGADO);
            case CANCELADO -> EnumSet.of(PENDIENTE, EN_GESTION);
        };
    }
}
