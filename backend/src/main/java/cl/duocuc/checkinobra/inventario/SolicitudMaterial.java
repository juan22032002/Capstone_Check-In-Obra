package cl.duocuc.checkinobra.inventario;

import cl.duocuc.checkinobra.config.ConflictoException;
import cl.duocuc.checkinobra.config.PerteneceAEmpresa;
import cl.duocuc.checkinobra.config.Usuario;
import cl.duocuc.checkinobra.cubicacion.Material;
import cl.duocuc.checkinobra.obra.Obra;
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
 * SolicitudMaterial — igual que SolicitudHerramienta pero al aprobar genera
 * un KardexMovimiento de DESPACHO en vez de un préstamo.
 */
@Entity
@Table(name = "solicitudes_material")
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class SolicitudMaterial implements PerteneceAEmpresa {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(nullable = false)
    private double cantidad;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 20)
    private EstadoSolicitud estado;

    @Column(name = "fecha_solicitud", nullable = false)
    private LocalDateTime fechaSolicitud;

    /** Ver nota en SolicitudHerramienta.motivoRechazo — no está en el diagrama. */
    /** Para qué lo pide. Nulo solo en las solicitudes anteriores a V9. */
    @Column(length = 300)
    private String descripcion;

    /** Cuándo el trabajador confirmó que lo recibió. */
    @Column(name = "fecha_recepcion")
    private LocalDateTime fechaRecepcion;

    @Column(name = "motivo_rechazo")
    private String motivoRechazo;

    /** Trabajador "1" -- "N" SolicitudMaterial : solicita > */
    @ManyToOne(fetch = FetchType.EAGER, optional = false)
    @JoinColumn(name = "trabajador_id", nullable = false)
    private Trabajador trabajador;

    @ManyToOne(fetch = FetchType.EAGER, optional = false)
    @JoinColumn(name = "material_id", nullable = false)
    private Material material;

    @ManyToOne(fetch = FetchType.EAGER, optional = false)
    @JoinColumn(name = "obra_id", nullable = false)
    private Obra obra;

    @ManyToOne(fetch = FetchType.EAGER)
    @JoinColumn(name = "resuelto_por_id")
    private Usuario resueltoPor;

    /** SolicitudMaterial.aprobar(): KardexMovimiento del diagrama. */
    public void aprobar(Usuario aprobador) {
        exigirPendiente();
        this.estado = EstadoSolicitud.APROBADA;
        this.resueltoPor = aprobador;
    }

    /** SolicitudMaterial.rechazar() del diagrama. */
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
        return obra.empresaId();
    }
}
