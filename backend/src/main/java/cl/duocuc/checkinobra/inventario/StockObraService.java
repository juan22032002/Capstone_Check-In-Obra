package cl.duocuc.checkinobra.inventario;

import cl.duocuc.checkinobra.config.AccesoEmpresa;
import cl.duocuc.checkinobra.cubicacion.Material;
import cl.duocuc.checkinobra.cubicacion.MaterialService;
import cl.duocuc.checkinobra.obra.EstadoObra;
import cl.duocuc.checkinobra.obra.Obra;
import cl.duocuc.checkinobra.obra.ObraService;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.Comparator;
import java.util.List;
import java.util.Map;
import java.util.function.Function;
import java.util.stream.Collectors;

/**
 * Saldos de material por obra, leídos de a muchos.
 *
 * <p>{@link KardexMovimientoService#stockActual} responde por un par
 * obra-material, que es lo que necesita el despacho. Las pantallas de resumen
 * necesitan todos los pares a la vez, y pedirlos uno por uno serían cientos de
 * consultas; acá se suman en una.
 */
@Service
@Transactional(readOnly = true)
public class StockObraService {

    private final KardexMovimientoRepository kardexMovimientoRepository;
    private final ObraService obraService;
    private final MaterialService materialService;

    public StockObraService(
            KardexMovimientoRepository kardexMovimientoRepository,
            ObraService obraService,
            MaterialService materialService) {
        this.kardexMovimientoRepository = kardexMovimientoRepository;
        this.obraService = obraService;
        this.materialService = materialService;
    }

    /** Saldo de cada material con movimientos en la obra. */
    public List<SaldoObraMaterial> saldosDeObra(Long obraId) {
        obraService.obtener(obraId);
        return kardexMovimientoRepository.saldosPorObra(List.of(obraId));
    }

    /**
     * Lo que se está acabando en las obras activas de la empresa: CRITICO bajo
     * el mínimo, BAJO dentro del 25 % sobre él. Los críticos primero.
     */
    public List<Faltante> faltantes(Long empresaId) {
        AccesoEmpresa.exigirEmpresa(empresaId);
        Map<Long, Obra> obras = obraService.listarPorEmpresa(empresaId).stream()
                .filter(o -> o.getEstado() == EstadoObra.ACTIVA)
                .collect(Collectors.toMap(Obra::getId, Function.identity()));
        if (obras.isEmpty()) {
            return List.of();
        }
        Map<Long, Material> materiales = materialService.listarPorEmpresa(empresaId).stream()
                .collect(Collectors.toMap(Material::getId, Function.identity()));

        return kardexMovimientoRepository.saldosPorObra(obras.keySet()).stream()
                // Las obras son de la empresa, así que sus movimientos también;
                // el material se busca en el catálogo propio de todos modos.
                .filter(s -> materiales.containsKey(s.materialId()))
                .map(s -> {
                    Material m = materiales.get(s.materialId());
                    return new Faltante(obras.get(s.obraId()), m, s.stock(),
                            EstadoStock.de(s.stock(), m.getStockMinimo()));
                })
                .filter(f -> f.estado() != EstadoStock.OK)
                .sorted(Comparator.comparing(Faltante::estado)
                        .thenComparing(f -> f.obra().getNombre())
                        .thenComparing(f -> f.material().getNombre()))
                .toList();
    }

    public record Faltante(Obra obra, Material material, double stock, EstadoStock estado) {
    }
}
