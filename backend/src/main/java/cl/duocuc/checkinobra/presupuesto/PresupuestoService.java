package cl.duocuc.checkinobra.presupuesto;

import cl.duocuc.checkinobra.config.AccesoEmpresa;
import cl.duocuc.checkinobra.config.ConflictoException;
import cl.duocuc.checkinobra.cubicacion.ItemCubicado;
import cl.duocuc.checkinobra.cubicacion.Material;
import cl.duocuc.checkinobra.cubicacion.MaterialService;
import cl.duocuc.checkinobra.cubicacion.Partida;
import cl.duocuc.checkinobra.cubicacion.PartidaService;
import cl.duocuc.checkinobra.obra.Obra;
import cl.duocuc.checkinobra.obra.ObraService;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;
import java.util.NoSuchElementException;

@Service
@Transactional
public class PresupuestoService {

    private final PresupuestoRepository presupuestoRepository;
    private final PresupuestoItemRepository presupuestoItemRepository;
    private final ObraService obraService;
    private final MaterialService materialService;
    private final PartidaService partidaService;

    public PresupuestoService(
            PresupuestoRepository presupuestoRepository,
            PresupuestoItemRepository presupuestoItemRepository,
            ObraService obraService,
            MaterialService materialService,
            PartidaService partidaService) {
        this.presupuestoRepository = presupuestoRepository;
        this.presupuestoItemRepository = presupuestoItemRepository;
        this.obraService = obraService;
        this.materialService = materialService;
        this.partidaService = partidaService;
    }

    public Presupuesto crear(Long obraId) {
        // Primero la obra: si es ajena responde el mismo 404 que una inexistente.
        // Preguntar antes por el presupuesto delataba qué obras de otra empresa
        // ya tienen uno (409 frente a 404).
        Obra obra = obraService.obtener(obraId);
        if (presupuestoRepository.findByObraId(obraId).isPresent()) {
            throw new IllegalStateException("La obra ya tiene un presupuesto");
        }
        Presupuesto presupuesto = Presupuesto.builder()
                .estado(EstadoPresupuesto.BORRADOR)
                .total(0)
                .obra(obra)
                .build();
        return presupuestoRepository.save(presupuesto);
    }

    @Transactional(readOnly = true)
    public Presupuesto obtener(Long id) {
        return presupuestoRepository.findById(id)
                .filter(AccesoEmpresa::esPropio)
                .orElseThrow(() -> new NoSuchElementException("Presupuesto no encontrado: " + id));
    }

    @Transactional(readOnly = true)
    public Presupuesto obtenerPorObra(Long obraId) {
        obraService.obtener(obraId);
        return presupuestoRepository.findByObraId(obraId)
                .orElseThrow(() -> new NoSuchElementException("La obra no tiene presupuesto: " + obraId));
    }

    /**
     * Agrega un ítem tomando el precio vigente del catálogo (RN-13). Siempre
     * inserta una fila nueva: no suma a una existente del mismo material.
     */
    public PresupuestoItem agregarItem(Long presupuestoId, Long materialId, double cantidad) {
        Presupuesto presupuesto = obtener(presupuestoId);
        exigirEditable(presupuesto);
        Material material = materialService.obtener(materialId);

        PresupuestoItem guardado = presupuestoItemRepository.save(nuevoItem(presupuesto, material, cantidad));
        recalcularTotal(presupuestoId);
        return guardado;
    }

    /**
     * Agrega al presupuesto todos los ítems cubicados de una partida, con la
     * merma incluida y el precio vigente (D5). Es una sola transacción: o entran
     * todos o no entra ninguno, que es lo que no daba hacerlo con un POST por
     * ítem desde la app. Como {@link #agregarItem}, cada llamada agrega filas
     * nuevas: llamarlo dos veces con la misma partida duplica los ítems.
     *
     * <p>Se comprueba primero la empresa (presupuesto y partida) y recién
     * después el estado, para que un recurso ajeno responda 404 y no un 409
     * que delate que existe.
     */
    public List<PresupuestoItem> agregarItemsDePartida(Long presupuestoId, Long partidaId) {
        if (partidaId == null) {
            throw new IllegalArgumentException("Falta partidaId");
        }
        Presupuesto presupuesto = obtener(presupuestoId);
        Partida partida = partidaService.obtener(partidaId);
        exigirEditable(presupuesto);
        if (!partida.getObra().getId().equals(presupuesto.getObra().getId())) {
            throw new ConflictoException(ConflictoException.PARTIDA_DE_OTRA_OBRA,
                    "La partida pertenece a otra obra que el presupuesto");
        }
        List<ItemCubicado> cubicados = partidaService.itemsCubicados(partidaId).stream()
                .filter(i -> i.getCantidadConMerma() > 0)
                .toList();
        if (cubicados.isEmpty()) {
            throw new ConflictoException(ConflictoException.PARTIDA_SIN_CUBICAR,
                    "La partida no tiene ítems cubicados: cúbicala antes de agregarla al presupuesto");
        }
        List<PresupuestoItem> nuevos = cubicados.stream()
                .map(i -> nuevoItem(presupuesto, i.getMaterial(), i.getCantidadConMerma()))
                .toList();
        List<PresupuestoItem> guardados = presupuestoItemRepository.saveAll(nuevos);
        recalcularTotal(presupuestoId);
        return guardados;
    }

    private static PresupuestoItem nuevoItem(Presupuesto presupuesto, Material material, double cantidad) {
        PresupuestoItem item = PresupuestoItem.builder()
                .presupuesto(presupuesto)
                .material(material)
                .cantidad(cantidad)
                .precioUnitario(material.getPrecioUnitario())
                .build();
        item.recalcularSubtotal();
        return item;
    }

    @Transactional(readOnly = true)
    public List<PresupuestoItem> listarItems(Long presupuestoId) {
        obtener(presupuestoId);
        return presupuestoItemRepository.findByPresupuestoId(presupuestoId);
    }

    public double recalcularTotal(Long presupuestoId) {
        Presupuesto presupuesto = obtener(presupuestoId);
        double total = presupuesto.calcularTotal(presupuestoItemRepository.findByPresupuestoId(presupuestoId));
        presupuestoRepository.save(presupuesto);
        return total;
    }

    /** BORRADOR -> APROBADO. */
    public Presupuesto aprobar(Long presupuestoId) {
        Presupuesto presupuesto = obtener(presupuestoId);
        if (presupuesto.getEstado() != EstadoPresupuesto.BORRADOR) {
            throw new IllegalStateException("Solo se aprueba un presupuesto en BORRADOR");
        }
        presupuesto.setEstado(EstadoPresupuesto.APROBADO);
        return presupuestoRepository.save(presupuesto);
    }

    /** Presupuesto.congelar() del diagrama, vía la propia entidad. */
    public Presupuesto congelar(Long presupuestoId) {
        Presupuesto presupuesto = obtener(presupuestoId);
        presupuesto.congelar();
        return presupuestoRepository.save(presupuesto);
    }

    private void exigirEditable(Presupuesto presupuesto) {
        if (presupuesto.getEstado() == EstadoPresupuesto.CONGELADO) {
            throw new ConflictoException(ConflictoException.PRESUPUESTO_CONGELADO,
                    "El presupuesto está CONGELADO y ya no admite cambios");
        }
    }
}
