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
 * Lo que un trabajador necesita y bodega no tiene: algo fuera del catálogo, o
 * del catálogo pero sin stock o prestado. Bodega lo consigue y avisa por el
 * estado.
 *
 * <p><b>No toca el kardex.</b> Si lo conseguido es un material del catálogo,
 * entra con una recepción normal y sale con un despacho normal, que son los
 * únicos caminos hacia el stock. El pedido solo cuenta en qué va la gestión;
 * {@link #material} y {@link #herramienta} son una referencia para bodega, no
 * un movimiento.
 */
@Entity
@Table(name = "pedidos_especiales")
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class PedidoEspecial implements PerteneceAEmpresa {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 20)
    private TipoPedidoEspecial tipo;

    /** Cómo lo llama quien lo pide; texto libre porque puede no estar en el catálogo. */
    @Column(nullable = false, length = 120)
    private String nombre;

    @Column(nullable = false)
    private double cantidad;

    @Column(length = 20)
    private String unidad;

    /** Para qué lo necesita. */
    @Column(nullable = false, length = 300)
    private String descripcion;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 20)
    private EstadoPedidoEspecial estado;

    @Column(name = "fecha_solicitud", nullable = false)
    private LocalDateTime fechaSolicitud;

    @Column(name = "fecha_actualizacion", nullable = false)
    private LocalDateTime fechaActualizacion;

    /** Lo que bodega le cuenta al trabajador: "llega el jueves", "retirar en bodega 2". */
    @Column(name = "nota_bodega", length = 300)
    private String notaBodega;

    @Column(name = "motivo_rechazo", length = 300)
    private String motivoRechazo;

    @Column(name = "fecha_entrega")
    private LocalDateTime fechaEntrega;

    @Column(name = "fecha_recepcion")
    private LocalDateTime fechaRecepcion;

    @ManyToOne(fetch = FetchType.EAGER, optional = false)
    @JoinColumn(name = "obra_id", nullable = false)
    private Obra obra;

    @ManyToOne(fetch = FetchType.EAGER, optional = false)
    @JoinColumn(name = "trabajador_id", nullable = false)
    private Trabajador trabajador;

    @ManyToOne(fetch = FetchType.EAGER)
    @JoinColumn(name = "material_id")
    private Material material;

    @ManyToOne(fetch = FetchType.EAGER)
    @JoinColumn(name = "herramienta_id")
    private Herramienta herramienta;

    /** El último de bodega que movió el estado. */
    @ManyToOne(fetch = FetchType.EAGER)
    @JoinColumn(name = "gestionado_por_id")
    private Usuario gestionadoPor;

    /** Bodega lo tomó y lo está consiguiendo. */
    public void gestionar(Usuario bodega, String nota) {
        pasarA(EstadoPedidoEspecial.EN_GESTION);
        anotar(bodega, nota);
    }

    /** Bodega ya lo tiene y el trabajador puede pasar a buscarlo. */
    public void marcarListo(Usuario bodega, String nota) {
        pasarA(EstadoPedidoEspecial.LISTO_PARA_RETIRO);
        anotar(bodega, nota);
    }

    public void entregar(Usuario bodega) {
        pasarA(EstadoPedidoEspecial.ENTREGADO);
        this.gestionadoPor = bodega;
        this.fechaEntrega = fechaActualizacion;
    }

    public void rechazar(Usuario bodega, String motivo) {
        pasarA(EstadoPedidoEspecial.RECHAZADO);
        this.gestionadoPor = bodega;
        this.motivoRechazo = motivo;
    }

    /** Lo retira quien lo pidió, mientras bodega no lo tenga listo. */
    public void cancelar() {
        pasarA(EstadoPedidoEspecial.CANCELADO);
    }

    /** Quien lo pidió confirma que lo tiene. */
    public void confirmarRecepcion() {
        pasarA(EstadoPedidoEspecial.RECIBIDO);
        this.fechaRecepcion = fechaActualizacion;
    }

    private void pasarA(EstadoPedidoEspecial nuevo) {
        if (!nuevo.desde().contains(estado)) {
            throw new ConflictoException(ConflictoException.TRANSICION_INVALIDA,
                    "El pedido está " + legible(estado) + " y no puede pasar a " + legible(nuevo));
        }
        this.estado = nuevo;
        this.fechaActualizacion = LocalDateTime.now();
    }

    /** Una nota nueva reemplaza la anterior; sin nota, queda la que había. */
    private void anotar(Usuario bodega, String nota) {
        this.gestionadoPor = bodega;
        if (nota != null) {
            this.notaBodega = nota;
        }
    }

    private static String legible(EstadoPedidoEspecial e) {
        return e.name().toLowerCase().replace('_', ' ');
    }

    @Override
    public Long empresaId() {
        return obra.empresaId();
    }
}
