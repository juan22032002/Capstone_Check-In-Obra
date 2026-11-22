package cl.duocuc.checkinobra.inventario;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.List;

public interface SolicitudHerramientaRepository extends JpaRepository<SolicitudHerramienta, Long> {
    List<SolicitudHerramienta> findByTrabajadorId(Long trabajadorId);
    List<SolicitudHerramienta> findByTrabajadorIdOrderByFechaSolicitudDescIdDesc(Long trabajadorId);
    boolean existsByTrabajadorIdAndHerramientaIdAndEstado(
            Long trabajadorId, Long herramientaId, EstadoSolicitud estado);
    List<SolicitudHerramienta> findByEstado(EstadoSolicitud estado);

    @Query("select s from SolicitudHerramienta s where s.trabajador.cuadrilla.obra.id = :obraId")
    List<SolicitudHerramienta> findByObraId(@Param("obraId") Long obraId);

    @Query("select s from SolicitudHerramienta s where s.trabajador.cuadrilla.obra.id = :obraId and s.estado = :estado")
    List<SolicitudHerramienta> findByObraIdAndEstado(@Param("obraId") Long obraId, @Param("estado") EstadoSolicitud estado);
}
