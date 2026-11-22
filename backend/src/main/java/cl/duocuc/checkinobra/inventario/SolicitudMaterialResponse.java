package cl.duocuc.checkinobra.inventario;

import java.time.LocalDateTime;

/** Lo que la API expone de una {@link SolicitudMaterial}. */
public record SolicitudMaterialResponse(
        Long id,
        double cantidad,
        String estado,
        LocalDateTime fechaSolicitud,
        String motivoRechazo,
        Long trabajadorId,
        String trabajadorNombre,
        String trabajadorRut,
        Long materialId,
        String materialSku,
        String materialNombre,
        Long obraId,
        Long resueltoPorId,
        String resueltoPorNombre,
        String descripcion,
        LocalDateTime fechaRecepcion) {

    public static SolicitudMaterialResponse de(SolicitudMaterial s) {
        boolean resuelta = s.getResueltoPor() != null;
        return new SolicitudMaterialResponse(
                s.getId(),
                s.getCantidad(),
                s.getEstado().name(),
                s.getFechaSolicitud(),
                s.getMotivoRechazo(),
                s.getTrabajador().getId(),
                s.getTrabajador().nombre(),
                s.getTrabajador().rut(),
                s.getMaterial().getId(),
                s.getMaterial().getSku(),
                s.getMaterial().getNombre(),
                s.getObra().getId(),
                resuelta ? s.getResueltoPor().getId() : null,
                resuelta ? s.getResueltoPor().getNombre() : null,
                s.getDescripcion(),
                s.getFechaRecepcion());
    }
}
