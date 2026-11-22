package cl.duocuc.checkinobra.inventario;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.Collection;
import java.util.List;

public interface KardexMovimientoRepository extends JpaRepository<KardexMovimiento, Long> {
    List<KardexMovimiento> findByObraId(Long obraId);
    List<KardexMovimiento> findByObraIdAndMaterialId(Long obraId, Long materialId);
    List<KardexMovimiento> findByMaterialId(Long materialId);

    /**
     * Saldo del material en la obra, sumado en la base. Antes se traían todos
     * los movimientos a memoria para sumarlos en Java, y la pantalla de
     * despacho lo consulta en cada escaneo. Lo sostiene idx_kardex_obra_material.
     */
    @Query("""
           SELECT COALESCE(SUM(CASE WHEN k.tipoMovimiento = cl.duocuc.checkinobra.inventario.TipoMovimiento.RECEPCION
                                    THEN k.cantidad ELSE -k.cantidad END), 0)
           FROM KardexMovimiento k
           WHERE k.obra.id = :obraId AND k.material.id = :materialId
           """)
    double calcularStock(@Param("obraId") Long obraId, @Param("materialId") Long materialId);

    /**
     * El saldo de cada material con movimientos en estas obras, en una sola
     * consulta. Un material que nunca entró a una obra no aparece: no tiene
     * saldo ahí, y contarlo como cero pintaría de crítico el catálogo entero.
     */
    @Query("""
           SELECT new cl.duocuc.checkinobra.inventario.SaldoObraMaterial(
                      k.obra.id,
                      k.material.id,
                      COALESCE(SUM(CASE WHEN k.tipoMovimiento = cl.duocuc.checkinobra.inventario.TipoMovimiento.RECEPCION
                                        THEN k.cantidad ELSE -k.cantidad END), 0))
           FROM KardexMovimiento k
           WHERE k.obra.id IN :obraIds
           GROUP BY k.obra.id, k.material.id
           """)
    List<SaldoObraMaterial> saldosPorObra(@Param("obraIds") Collection<Long> obraIds);
}
