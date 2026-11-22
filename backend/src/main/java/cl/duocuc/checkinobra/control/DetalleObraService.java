package cl.duocuc.checkinobra.control;

import cl.duocuc.checkinobra.cubicacion.CostoMaterial;
import cl.duocuc.checkinobra.cubicacion.Material;
import cl.duocuc.checkinobra.cubicacion.MaterialService;
import cl.duocuc.checkinobra.inventario.EstadoStock;
import cl.duocuc.checkinobra.inventario.PrestamoHerramienta;
import cl.duocuc.checkinobra.inventario.PrestamoHerramientaRepository;
import cl.duocuc.checkinobra.inventario.SaldoObraMaterial;
import cl.duocuc.checkinobra.inventario.StockObraService;
import cl.duocuc.checkinobra.obra.Cuadrilla;
import cl.duocuc.checkinobra.obra.CuadrillaRepository;
import cl.duocuc.checkinobra.obra.Obra;
import cl.duocuc.checkinobra.obra.ObraService;
import cl.duocuc.checkinobra.obra.Trabajador;
import cl.duocuc.checkinobra.obra.TrabajadorRepository;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.Comparator;
import java.util.List;
import java.util.Map;
import java.util.function.Function;
import java.util.stream.Collectors;

/**
 * Todo lo de una obra en una sola respuesta: quién la dirige, quién trabaja
 * ahí, qué material le queda y qué herramientas tiene afuera.
 *
 * <p>Vive en {@code control} porque junta a todos los demás —obra, inventario,
 * catálogo y alertas— y {@code control} es el único paquete que puede depender
 * de todos sin crear un ciclo.
 */
@Service
@Transactional(readOnly = true)
public class DetalleObraService {

    private final ObraService obraService;
    private final CuadrillaRepository cuadrillaRepository;
    private final TrabajadorRepository trabajadorRepository;
    private final StockObraService stockObraService;
    private final MaterialService materialService;
    private final PrestamoHerramientaRepository prestamoHerramientaRepository;
    private final AlertaRepository alertaRepository;

    public DetalleObraService(
            ObraService obraService,
            CuadrillaRepository cuadrillaRepository,
            TrabajadorRepository trabajadorRepository,
            StockObraService stockObraService,
            MaterialService materialService,
            PrestamoHerramientaRepository prestamoHerramientaRepository,
            AlertaRepository alertaRepository) {
        this.obraService = obraService;
        this.cuadrillaRepository = cuadrillaRepository;
        this.trabajadorRepository = trabajadorRepository;
        this.stockObraService = stockObraService;
        this.materialService = materialService;
        this.prestamoHerramientaRepository = prestamoHerramientaRepository;
        this.alertaRepository = alertaRepository;
    }

    public DetalleObraResponse detalle(Long obraId) {
        // Primero la obra: si es de otra empresa, revienta acá con el mismo 404
        // que una inexistente, y nada de lo que cuelga de ella se consulta.
        Obra obra = obraService.obtener(obraId);

        List<Cuadrilla> cuadrillas = cuadrillaRepository.findByObraId(obraId);
        List<Trabajador> trabajadores = trabajadorRepository.findByCuadrilla_ObraId(obraId);
        Map<Long, Long> trabajadoresPorCuadrilla = trabajadores.stream()
                .collect(Collectors.groupingBy(t -> t.getCuadrilla().getId(), Collectors.counting()));

        List<DetalleObraResponse.MaterialEnObra> materiales = materialesDe(obra);
        List<PrestamoHerramienta> prestamos = prestamoHerramientaRepository.findByObraIdAndFechaDevolRealIsNull(obraId);
        long alertasPendientes = alertaRepository.findByObraIdAndResueltoFalse(obraId).size();

        return DetalleObraResponse.de(
                obra,
                cuadrillas.stream()
                        .sorted(Comparator.comparing(Cuadrilla::getNombre))
                        .map(c -> DetalleObraResponse.CuadrillaEnObra.de(
                                c, trabajadoresPorCuadrilla.getOrDefault(c.getId(), 0L)))
                        .toList(),
                trabajadores.stream()
                        .sorted(Comparator.comparing(Trabajador::nombre))
                        .map(DetalleObraResponse.TrabajadorEnObra::de)
                        .toList(),
                materiales,
                prestamos.stream()
                        .sorted(Comparator.comparing((PrestamoHerramienta p) -> p.getHerramienta().getNombre())
                                .thenComparing(PrestamoHerramienta::getFechaDevolEsperada))
                        .map(DetalleObraResponse.HerramientaEnObra::de)
                        .toList(),
                alertasPendientes);
    }

    /**
     * Cada material con movimientos en la obra, con su saldo y lo que vale. Los
     * críticos primero, que es lo primero que hay que ver.
     */
    private List<DetalleObraResponse.MaterialEnObra> materialesDe(Obra obra) {
        List<SaldoObraMaterial> saldos = stockObraService.saldosDeObra(obra.getId());
        if (saldos.isEmpty()) {
            return List.of();
        }
        Long empresaId = obra.empresaId();
        Map<Long, Material> catalogo = materialService.listarPorEmpresa(empresaId).stream()
                .collect(Collectors.toMap(Material::getId, Function.identity()));
        Map<Long, CostoMaterial> costos = materialService.costosPorMaterial(empresaId);

        return saldos.stream()
                .filter(s -> catalogo.containsKey(s.materialId()))
                .map(s -> {
                    Material m = catalogo.get(s.materialId());
                    return DetalleObraResponse.MaterialEnObra.de(
                            m, s.stock(), EstadoStock.de(s.stock(), m.getStockMinimo()), costos.get(m.getId()));
                })
                .sorted(Comparator.comparing(DetalleObraResponse.MaterialEnObra::estado,
                                Comparator.comparing(EstadoStock::valueOf))
                        .thenComparing(DetalleObraResponse.MaterialEnObra::nombre))
                .toList();
    }
}
