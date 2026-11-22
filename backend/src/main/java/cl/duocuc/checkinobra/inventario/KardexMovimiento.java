package cl.duocuc.checkinobra.inventario;

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

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.LocalDateTime;

/**
 * KardexMovimiento — el libro mayor de inventario. El stock de un Material
 * NO se guarda como columna: es la suma con signo de sus movimientos
 * (RECEPCION +, DESPACHO/CONSUMO −), calculada por
 * KardexMovimientoService.stockActual(materialId).
 */
@Entity
@Table(name = "kardex_movimientos")
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class KardexMovimiento implements PerteneceAEmpresa {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Enumerated(EnumType.STRING)
    @Column(name = "tipo_movimiento", nullable = false, length = 20)
    private TipoMovimiento tipoMovimiento;

    @Column(nullable = false)
    private double cantidad;

    @Column(nullable = false)
    private LocalDateTime fecha;

    @ManyToOne(fetch = FetchType.EAGER, optional = false)
    @JoinColumn(name = "obra_id", nullable = false)
    private Obra obra;

    @ManyToOne(fetch = FetchType.EAGER, optional = false)
    @JoinColumn(name = "material_id", nullable = false)
    private Material material;

    /** Usuario "1" -- "N" KardexMovimiento : registra > */
    @ManyToOne(fetch = FetchType.EAGER, optional = false)
    @JoinColumn(name = "usuario_id", nullable = false)
    private Usuario usuario;

    /**
     * Quién RECIBE el material, que no es lo mismo que quién lo registra. En un
     * despacho son dos personas: el bodeguero anota y el trabajador se lleva.
     * Nulo en una recepción, porque ahí el material entra desde un proveedor.
     */
    @ManyToOne(fetch = FetchType.EAGER)
    @JoinColumn(name = "trabajador_id")
    private Trabajador trabajador;

    /**
     * Lo que se pagó por unidad en esta compra, según la factura. Solo existe en
     * una RECEPCION, y aun ahí es opcional. No es el precio de catálogo del
     * material: ese lo fija el administrador y alimenta el presupuesto; este es
     * el costo real, y de él salen el último costo y el promedio ponderado.
     */
    @Column(name = "costo_unitario", precision = 14, scale = 2)
    private BigDecimal costoUnitario;

    /** KardexMovimiento.registrar() del diagrama — valida y sella la fecha. */
    public void registrar() {
        if (cantidad <= 0) {
            throw new IllegalStateException("La cantidad de un movimiento debe ser mayor a 0");
        }
        if (costoUnitario != null) {
            if (tipoMovimiento != TipoMovimiento.RECEPCION) {
                throw new IllegalArgumentException(
                        "El costo unitario solo se registra en una recepción: el material ya está pagado");
            }
            if (costoUnitario.signum() <= 0) {
                throw new IllegalArgumentException("El costo unitario debe ser mayor a 0");
            }
            this.costoUnitario = costoUnitario.setScale(2, RoundingMode.HALF_UP);
        }
        if (this.fecha == null) {
            this.fecha = LocalDateTime.now();
        }
    }

    /** Signo del movimiento sobre el stock: +1 recepción, −1 despacho/consumo. */
    public int signo() {
        return tipoMovimiento == TipoMovimiento.RECEPCION ? 1 : -1;
    }

    @Override
    public Long empresaId() {
        return obra.empresaId();
    }
}
