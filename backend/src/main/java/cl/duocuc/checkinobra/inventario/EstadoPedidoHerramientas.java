package cl.duocuc.checkinobra.inventario;

public enum EstadoPedidoHerramientas {
    /** El trabajador tiene el QR y todavía no pasa por bodega. */
    PENDIENTE,
    /** Bodega escaneó el QR y prestó lo que seguía pendiente. */
    ENTREGADO,
    /** Lo retiró el mismo trabajador antes de pasar por bodega. */
    CANCELADO
}
