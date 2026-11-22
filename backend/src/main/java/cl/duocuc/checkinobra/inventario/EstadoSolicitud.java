package cl.duocuc.checkinobra.inventario;

public enum EstadoSolicitud {
    PENDIENTE,
    APROBADA,
    RECHAZADA,
    ENTREGADA,
    /** La retiró el mismo trabajador mientras seguía pendiente. */
    CANCELADA
}
