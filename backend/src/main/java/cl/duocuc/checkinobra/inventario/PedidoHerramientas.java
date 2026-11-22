package cl.duocuc.checkinobra.inventario;

import cl.duocuc.checkinobra.config.ConflictoException;
import cl.duocuc.checkinobra.config.PerteneceAEmpresa;
import cl.duocuc.checkinobra.config.Usuario;
import cl.duocuc.checkinobra.obra.Trabajador;
import jakarta.persistence.CascadeType;
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
import jakarta.persistence.OneToMany;
import jakarta.persistence.OrderBy;
import jakarta.persistence.Table;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;

/**
 * Varias herramientas pedidas de una vez, con un QR para retirarlas.
 *
 * <p>Cada herramienta sigue siendo una {@link SolicitudHerramienta}; el pedido
 * las agrupa y lleva el {@link #codigoQr} que el bodeguero escanea para saber
 * quién es la persona y qué se lleva. Al entregarlo, cada solicitud pendiente
 * se aprueba y genera su propio préstamo, igual que si se aprobara de a una.
 */
@Entity
@Table(name = "pedidos_herramientas")
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class PedidoHerramientas implements PerteneceAEmpresa {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    /** UUID aleatorio; la app lo muestra como {@code PEDIDO:<codigoQr>}. */
    @Column(name = "codigo_qr", nullable = false, unique = true, length = 36)
    private String codigoQr;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 20)
    private EstadoPedidoHerramientas estado;

    /** Para qué las pide; la heredan todas sus solicitudes. */
    @Column(nullable = false, length = 300)
    private String descripcion;

    @Column(name = "fecha_solicitud", nullable = false)
    private LocalDateTime fechaSolicitud;

    @Column(name = "fecha_entrega")
    private LocalDateTime fechaEntrega;

    @ManyToOne(fetch = FetchType.EAGER, optional = false)
    @JoinColumn(name = "trabajador_id", nullable = false)
    private Trabajador trabajador;

    @ManyToOne(fetch = FetchType.EAGER)
    @JoinColumn(name = "entregado_por_id")
    private Usuario entregadoPor;

    @OneToMany(mappedBy = "pedido", cascade = CascadeType.PERSIST)
    @OrderBy("id")
    @Builder.Default
    private List<SolicitudHerramienta> solicitudes = new ArrayList<>();

    public void agregar(SolicitudHerramienta solicitud) {
        solicitud.setPedido(this);
        solicitudes.add(solicitud);
    }

    /**
     * Bodega escaneó el QR: se aprueba cada solicitud que siga pendiente. Hoy
     * son todas, porque la API no deja resolver sueltas las de un pedido
     * ({@code EN_PEDIDO}); el filtro queda por si una ya venía resuelta.
     *
     * @return las recién aprobadas, a las que el servicio les crea el préstamo
     */
    public List<SolicitudHerramienta> entregar(Usuario bodega) {
        exigirPendiente();
        List<SolicitudHerramienta> porEntregar = solicitudes.stream()
                .filter(s -> s.getEstado() == EstadoSolicitud.PENDIENTE)
                .toList();
        if (porEntregar.isEmpty()) {
            throw new ConflictoException(ConflictoException.YA_RESUELTA,
                    "Este pedido ya no tiene herramientas pendientes de entregar");
        }
        porEntregar.forEach(s -> s.aprobar(bodega));
        this.estado = EstadoPedidoHerramientas.ENTREGADO;
        this.entregadoPor = bodega;
        this.fechaEntrega = LocalDateTime.now();
        return porEntregar;
    }

    /** Lo retira quien lo pidió; con él, todas las solicitudes que seguían pendientes. */
    public void cancelar() {
        exigirPendiente();
        solicitudes.stream()
                .filter(s -> s.getEstado() == EstadoSolicitud.PENDIENTE)
                .forEach(SolicitudHerramienta::cancelar);
        this.estado = EstadoPedidoHerramientas.CANCELADO;
    }

    private void exigirPendiente() {
        if (this.estado != EstadoPedidoHerramientas.PENDIENTE) {
            // El QR sirve una vez: un segundo escaneo, o un reintento de la app,
            // cae acá y la app lo lee como "ya estaba hecho".
            throw new ConflictoException(ConflictoException.YA_RESUELTA,
                    "El pedido ya fue " + estado.name().toLowerCase());
        }
    }

    @Override
    public Long empresaId() {
        return trabajador.empresaId();
    }
}
