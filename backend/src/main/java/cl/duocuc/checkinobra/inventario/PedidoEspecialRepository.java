package cl.duocuc.checkinobra.inventario;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.Collection;
import java.util.List;

public interface PedidoEspecialRepository extends JpaRepository<PedidoEspecial, Long> {

    List<PedidoEspecial> findByTrabajadorIdOrderByFechaSolicitudDescIdDesc(Long trabajadorId);

    List<PedidoEspecial> findByObraIdOrderByFechaSolicitudDescIdDesc(Long obraId);

    List<PedidoEspecial> findByObraIdAndEstadoInOrderByFechaSolicitudDescIdDesc(
            Long obraId, Collection<EstadoPedidoEspecial> estados);

    /** Los de todas las obras de la empresa: la pestaña del administrador. */
    @Query("""
           SELECT p FROM PedidoEspecial p
           WHERE p.obra.empresa.id = :empresaId
           ORDER BY p.fechaSolicitud DESC, p.id DESC
           """)
    List<PedidoEspecial> deEmpresa(@Param("empresaId") Long empresaId);

    @Query("""
           SELECT p FROM PedidoEspecial p
           WHERE p.obra.empresa.id = :empresaId AND p.estado IN :estados
           ORDER BY p.fechaSolicitud DESC, p.id DESC
           """)
    List<PedidoEspecial> deEmpresaEnEstados(
            @Param("empresaId") Long empresaId, @Param("estados") Collection<EstadoPedidoEspecial> estados);
}
