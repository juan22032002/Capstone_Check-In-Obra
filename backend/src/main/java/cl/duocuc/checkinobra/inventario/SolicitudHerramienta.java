package cl.duocuc.checkinobra.inventario;

import cl.duocuc.checkinobra.config.ConflictoException;
import cl.duocuc.checkinobra.config.PerteneceAEmpresa;
import cl.duocuc.checkinobra.config.Usuario;
import cl.duocuc.checkinobra.obra.Trabajador;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.FetchType;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.Table;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

import java.time.LocalDateTime;

/**
 * SolicitudHerramienta — la crea el Trabajador, la aprueba/rechaza el
 * Bodeguero (o Admin); recién al aprobar se genera un PrestamoHerramienta
 * (orquestado por SolicitudHerramientaService.aprobar(), porque construir
 * el préstamo necesita la Obra, que se deriva de trabajador.cuadrilla.obra).
 */
@Entity
@Table(name = "solicitudes_herramienta")
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class SolicitudHerramienta implements PerteneceAEmpresa {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(nullable = false)
    private int cantidad;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 20)
    private EstadoSolicitud estado;

    @Column(name = "fecha_solicitud", nullable = false)
    private LocalDateTime fechaSolicitud;

    /**
     * Motivo de rechazo — no está en el diagrama de clases, se agrega
     * porque la pantalla de rechazo del bodeguero (BodRechazo) lo exige
     * como dato obligatorio para que el trabajador entienda por qué.
     */
    /** Para qué lo pide. Nulo solo en las solicitudes anteriores a V9. */
    @Column(length = 300)
    private String descripcion;

    /** Cuándo el trabajador confirmó que lo recibió. */
    @Column(name = "fecha_recepcion")
    private LocalDateTime fechaRecepcion;

    @Column(name = "motivo_rechazo")
    private String motivoRechazo;

    /** Trabajador "1" -- "N" SolicitudHerramienta : solicita > */
    @ManyToOne(fetch = FetchType.EAGER, optional = false)
    @JoinColumn(name = "trabajador_id", nullable = false)
    private Trabajador trabajador;

    @ManyToOne(fetch = FetchType.EAGER, optional = false)
    @JoinColumn(name = "herramienta_id", nullable = false)
    private Herramienta herramienta;

    /** Usuario "1" -- "N" SolicitudHerramienta : aprueba/rechaza > */
    @ManyToOne(fetch = FetchType.EAGER)
    @JoinColumn(name = "resuelto_por_id")
    private Usuario resueltoPor;

    /**
     * El pedido con QR que la trajo. Nulo si se pidió sola, o antes de V10.
     * LAZY porque la respuesta solo lleva su id, que el proxy ya conoce.
     */
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "pedido_id")
    private PedidoHerramientas pedido;

    /**
     * SolicitudHerramienta.aprobar(): PrestamoHerramienta del diagrama.
     * Transición pura de estado; el PrestamoHerramienta lo construye y
     * persiste el servicio inmediatamente después.
     */
    public void aprobar(Usuario aprobador) {
        exigirPendiente();
        this.estado = EstadoSolicitud.APROBADA;
        this.resueltoPor = aprobador;
    }

    /** SolicitudHerramienta.rechazar() del diagrama. */
    public void rechazar(Usuario rechazador, String motivo) {
        exigirPendiente();
        this.estado = EstadoSolicitud.RECHAZADA;
        this.resueltoPor = rechazador;
        this.motivoRechazo = motivo;
    }

    /**
     * La retira quien la pidió, antes de que bodega la resuelva. No lleva
     * {@code resueltoPor}: nadie de bodega la tocó.
     */
    public void cancelar() {
        exigirPendiente();
        this.estado = EstadoSolicitud.CANCELADA;
    }

    /**
     * El trabajador confirma que tiene en la mano lo que bodega aprobó. APROBADA
     * ya significa que bodega lo despachó o prestó en el mesón; esto cierra el
     * ciclo con la palabra de quien lo recibió.
     */
    public void confirmarRecepcion() {
        if (this.estado != EstadoSolicitud.APROBADA) {
            throw new ConflictoException(ConflictoException.NO_ENTREGADA,
                    "Solo se confirma lo que bodega ya entregó, y esta solicitud está "
                            + estado.name().toLowerCase());
        }
        this.estado = EstadoSolicitud.ENTREGADA;
        this.fechaRecepcion = LocalDateTime.now();
    }

    private void exigirPendiente() {
        if (this.estado != EstadoSolicitud.PENDIENTE) {
            // "Ya fue aprobada", no un error genérico: si llega acá por un
            // reintento, la app lo trata como "ya estaba hecho".
            throw new ConflictoException(ConflictoException.YA_RESUELTA,
                    "La solicitud ya fue " + estado.name().toLowerCase());
        }
    }

    @Override
    public Long empresaId() {
        return trabajador.empresaId();
    }
}
