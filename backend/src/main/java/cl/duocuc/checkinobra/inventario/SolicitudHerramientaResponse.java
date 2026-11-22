package cl.duocuc.checkinobra.inventario;

import java.time.LocalDateTime;

/** Lo que la API expone de una {@link SolicitudHerramienta}. */
public record SolicitudHerramientaResponse(
        Long id,
        int cantidad,
        String estado,
        LocalDateTime fechaSolicitud,
        String motivoRechazo,
        Long trabajadorId,
        String trabajadorNombre,
        String trabajadorRut,
        Long herramientaId,
        String herramientaNombre,
        Long resueltoPorId,
        String resueltoPorNombre,
        String descripcion,
        LocalDateTime fechaRecepcion,
        /** Nulo si se pidió sola, fuera de un pedido con QR. */
        Long pedidoId) {

    public static SolicitudHerramientaResponse de(SolicitudHerramienta s) {
        // Ambos nulos mientras la solicitud siga pendiente.
        boolean resuelta = s.getResueltoPor() != null;
        return new SolicitudHerramientaResponse(
                s.getId(),
                s.getCantidad(),
                s.getEstado().name(),
                s.getFechaSolicitud(),
                s.getMotivoRechazo(),
                s.getTrabajador().getId(),
                s.getTrabajador().nombre(),
                s.getTrabajador().rut(),
                s.getHerramienta().getId(),
                s.getHerramienta().getNombre(),
                resuelta ? s.getResueltoPor().getId() : null,
                resuelta ? s.getResueltoPor().getNombre() : null,
                s.getDescripcion(),
                s.getFechaRecepcion(),
                s.getPedido() == null ? null : s.getPedido().getId());
    }
}
