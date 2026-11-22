package cl.duocuc.checkinobra.inventario;

import org.springframework.data.jpa.repository.JpaRepository;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;

public interface PrestamoHerramientaRepository extends JpaRepository<PrestamoHerramienta, Long> {
    List<PrestamoHerramienta> findByObraId(Long obraId);
    List<PrestamoHerramienta> findByTrabajadorId(Long trabajadorId);
    List<PrestamoHerramienta> findByTrabajadorIdOrderByFechaPrestamoDescIdDesc(Long trabajadorId);
    List<PrestamoHerramienta> findByObraIdAndFechaDevolRealIsNull(Long obraId);
    Optional<PrestamoHerramienta> findFirstByHerramientaIdAndFechaDevolRealIsNull(Long herramientaId);
    List<PrestamoHerramienta> findByFechaDevolRealIsNullAndFechaDevolEsperadaBefore(LocalDateTime instante);
}
