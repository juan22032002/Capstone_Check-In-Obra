package cl.duocuc.checkinobra.cubicacion;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.Collection;
import java.util.List;
import java.util.Optional;

public interface MaterialRepository extends JpaRepository<Material, Long> {
    List<Material> findByEmpresaId(Long empresaId);
    List<Material> findByEmpresaIdAndCategoria(Long empresaId, CategoriaMaterial categoria);
    Optional<Material> findFirstByEmpresaIdAndCategoriaOrderByIdAsc(Long empresaId, CategoriaMaterial categoria);
    /**
     * Las dos búsquedas del escáner. Van por empresa y no por el código suelto
     * a propósito: un SKU es único en toda la base, así que buscarlo sin filtrar
     * dejaría a un bodeguero resolviendo códigos de otra constructora con solo
     * apuntar la cámara.
     */
    Optional<Material> findByEmpresaIdAndSku(Long empresaId, String sku);

    Optional<Material> findByEmpresaIdAndCodigoBarra(Long empresaId, String codigoBarra);

    /**
     * El SKU es único dentro de la empresa (V13), no en toda la base: dos constructoras pueden
     * usar el mismo. Con ignore-case por si hay filas anteriores a la normalización.
     */
    Optional<Material> findByEmpresaIdAndSkuIgnoreCase(Long empresaId, String sku);

    /**
     * Los que ya existen de una tanda de códigos. Es lo que usa la importación
     * masiva para no preguntar fila por fila: con el tope de 2.000 filas, una
     * consulta por fila son miles de idas a la base para responder algo que
     * cabe en una.
     */
    List<Material> findByEmpresaIdAndSkuIn(Long empresaId, Collection<String> skus);

    List<Material> findByEmpresaIdAndCodigoBarraIn(Long empresaId, Collection<String> codigosBarra);

    /**
     * Último costo y costo promedio de cada material de la empresa, en una sola
     * pasada por el kardex. El listado del catálogo lo pide para todos a la vez,
     * y una consulta por material serían cientos.
     *
     * <p>Nativa por dos cosas que JPQL no tiene: tomar el costo de la fila más
     * reciente de cada grupo ({@code ARRAY_AGG ... ORDER BY}) y promediar en
     * NUMERIC. La sostiene {@code idx_kardex_material_costo} (V8).
     */
    @Query(value = CONSULTA_COSTOS + " WHERE m.empresa_id = :empresaId " + AGRUPAR_COSTOS, nativeQuery = true)
    List<CostoMaterial> costosPorEmpresa(@Param("empresaId") Long empresaId);

    @Query(value = CONSULTA_COSTOS + " WHERE m.id = :materialId " + AGRUPAR_COSTOS, nativeQuery = true)
    Optional<CostoMaterial> costoDe(@Param("materialId") Long materialId);

    String CONSULTA_COSTOS = """
            SELECT k.material_id AS materialId,
                   (ARRAY_AGG(k.costo_unitario ORDER BY k.fecha DESC, k.id DESC))[1] AS ultimoCostoUnitario,
                   MAX(k.fecha) AS fechaUltimoCosto,
                   ROUND(SUM(CAST(k.cantidad AS NUMERIC) * k.costo_unitario)
                         / NULLIF(SUM(CAST(k.cantidad AS NUMERIC)), 0), 2) AS costoPromedio
            FROM kardex_movimientos k
            JOIN materiales m ON m.id = k.material_id
            """;

    String AGRUPAR_COSTOS = " AND k.costo_unitario IS NOT NULL GROUP BY k.material_id";
}
