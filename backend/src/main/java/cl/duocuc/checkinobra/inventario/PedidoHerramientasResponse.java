package cl.duocuc.checkinobra.inventario;

import java.time.LocalDateTime;
import java.util.List;

/**
 * Lo que la API expone de un {@link PedidoHerramientas}. El {@code trabajador}
 * va con nombre y RUT porque es lo que el bodeguero mira para confirmar que la
 * persona frente al mesón es quien pidió.
 */
public record PedidoHerramientasResponse(
        Long id,
        String codigoQr,
        String estado,
        LocalDateTime fechaSolicitud,
        String descripcion,
        Persona trabajador,
        List<SolicitudHerramientaResponse> solicitudes,
        /** Nulos mientras no se entregue. */
        LocalDateTime fechaEntrega,
        Long entregadoPorId,
        String entregadoPorNombre) {

    public record Persona(Long id, String nombre, String rut) {
    }

    public static PedidoHerramientasResponse de(PedidoHerramientas p) {
        boolean entregado = p.getEntregadoPor() != null;
        return new PedidoHerramientasResponse(
                p.getId(),
                p.getCodigoQr(),
                p.getEstado().name(),
                p.getFechaSolicitud(),
                p.getDescripcion(),
                new Persona(p.getTrabajador().getId(), p.getTrabajador().nombre(), p.getTrabajador().rut()),
                p.getSolicitudes().stream().map(SolicitudHerramientaResponse::de).toList(),
                p.getFechaEntrega(),
                entregado ? p.getEntregadoPor().getId() : null,
                entregado ? p.getEntregadoPor().getNombre() : null);
    }
}
