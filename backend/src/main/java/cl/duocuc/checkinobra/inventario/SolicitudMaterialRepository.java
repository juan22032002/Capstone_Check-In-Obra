package cl.duocuc.checkinobra.inventario;

import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;

public interface SolicitudMaterialRepository extends JpaRepository<SolicitudMaterial, Long> {
    List<SolicitudMaterial> findByTrabajadorId(Long trabajadorId);
    List<SolicitudMaterial> findByTrabajadorIdOrderByFechaSolicitudDescIdDesc(Long trabajadorId);
    List<SolicitudMaterial> findByObraId(Long obraId);
    List<SolicitudMaterial> findByObraIdAndEstado(Long obraId, EstadoSolicitud estado);
    List<SolicitudMaterial> findByEstado(EstadoSolicitud estado);

    /** ¿Ya tiene el trabajador pedido ese material, para esa obra, y sigue sin resolverse? */
    boolean existsByTrabajadorIdAndMaterialIdAndObraIdAndEstado(
            Long trabajadorId, Long materialId, Long obraId, EstadoSolicitud estado);
}
