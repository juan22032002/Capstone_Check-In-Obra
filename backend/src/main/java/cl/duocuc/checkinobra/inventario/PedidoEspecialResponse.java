package cl.duocuc.checkinobra.inventario;

import java.time.LocalDateTime;

/** Lo que la API expone de un {@link PedidoEspecial}. */
public record PedidoEspecialResponse(
        Long id,
        String tipo,
        String nombre,
        double cantidad,
        String unidad,
        String descripcion,
        Long materialId,
        Long herramientaId,
        String estado,
        Long obraId,
        String obraNombre,
        Long trabajadorId,
        String trabajadorNombre,
        String trabajadorRut,
        LocalDateTime fechaSolicitud,
        LocalDateTime fechaActualizacion,
        String notaBodega,
        String motivoRechazo,
        String gestionadoPorNombre,
        LocalDateTime fechaEntrega,
        LocalDateTime fechaRecepcion) {

    public static PedidoEspecialResponse de(PedidoEspecial p) {
        return new PedidoEspecialResponse(
                p.getId(),
                p.getTipo().name(),
                p.getNombre(),
                p.getCantidad(),
                p.getUnidad(),
                p.getDescripcion(),
                p.getMaterial() == null ? null : p.getMaterial().getId(),
                p.getHerramienta() == null ? null : p.getHerramienta().getId(),
                p.getEstado().name(),
                p.getObra().getId(),
                p.getObra().getNombre(),
                p.getTrabajador().getId(),
                p.getTrabajador().nombre(),
                p.getTrabajador().rut(),
                p.getFechaSolicitud(),
                p.getFechaActualizacion(),
                p.getNotaBodega(),
                p.getMotivoRechazo(),
                p.getGestionadoPor() == null ? null : p.getGestionadoPor().getNombre(),
                p.getFechaEntrega(),
                p.getFechaRecepcion());
    }
}
