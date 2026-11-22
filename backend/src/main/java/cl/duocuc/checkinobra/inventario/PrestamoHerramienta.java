package cl.duocuc.checkinobra.inventario;

import cl.duocuc.checkinobra.config.ConflictoException;
import cl.duocuc.checkinobra.config.PerteneceAEmpresa;
import cl.duocuc.checkinobra.config.Usuario;
import cl.duocuc.checkinobra.obra.Obra;
import cl.duocuc.checkinobra.obra.Trabajador;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
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

@Entity
@Table(name = "prestamos_herramienta")
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class PrestamoHerramienta implements PerteneceAEmpresa {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "fecha_prestamo", nullable = false)
    private LocalDateTime fechaPrestamo;

    @Column(name = "fecha_devol_esperada", nullable = false)
    private LocalDateTime fechaDevolEsperada;

    @Column(name = "fecha_devol_real")
    private LocalDateTime fechaDevolReal;

    @ManyToOne(fetch = FetchType.EAGER, optional = false)
    @JoinColumn(name = "herramienta_id", nullable = false)
    private Herramienta herramienta;

    @ManyToOne(fetch = FetchType.EAGER, optional = false)
    @JoinColumn(name = "trabajador_id", nullable = false)
    private Trabajador trabajador;

    @ManyToOne(fetch = FetchType.EAGER, optional = false)
    @JoinColumn(name = "obra_id", nullable = false)
    private Obra obra;

    /** Usuario "1" -- "N" PrestamoHerramienta : autoriza (bodeguero) > */
    @ManyToOne(fetch = FetchType.EAGER, optional = false)
    @JoinColumn(name = "autorizado_por_id", nullable = false)
    private Usuario autorizadoPor;

    /** PrestamoHerramienta.autorizar() del diagrama. */
    public void autorizar() {
        if (this.fechaPrestamo == null) {
            this.fechaPrestamo = LocalDateTime.now();
        }
    }

    /** PrestamoHerramienta.registrarDevolucion() del diagrama. */
    public void registrarDevolucion() {
        if (this.fechaDevolReal != null) {
            throw new ConflictoException(ConflictoException.YA_DEVUELTO, "Este préstamo ya fue devuelto");
        }
        this.fechaDevolReal = LocalDateTime.now();
    }

    /** PrestamoHerramienta.estaVencido(): boolean del diagrama. */
    public boolean estaVencido() {
        return fechaDevolReal == null && LocalDateTime.now().isAfter(fechaDevolEsperada);
    }

    @Override
    public Long empresaId() {
        return obra.empresaId();
    }
}
