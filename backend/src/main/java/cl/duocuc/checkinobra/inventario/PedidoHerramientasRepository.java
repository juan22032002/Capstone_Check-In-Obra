package cl.duocuc.checkinobra.inventario;

import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.Optional;

public interface PedidoHerramientasRepository extends JpaRepository<PedidoHerramientas, Long> {
    Optional<PedidoHerramientas> findByCodigoQr(String codigoQr);
    List<PedidoHerramientas> findByTrabajadorIdOrderByFechaSolicitudDescIdDesc(Long trabajadorId);
}
