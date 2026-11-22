package cl.duocuc.checkinobra.cubicacion;

import cl.duocuc.checkinobra.config.AccesoEmpresa;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.ArrayList;
import java.util.List;
import java.util.NoSuchElementException;

/** MotorCubicacion «service» del diagrama — calcular(p: Partida): List&lt;ItemCubicado&gt;. */
@Service
@Transactional
public class MotorCubicacionService {

    private final PartidaRepository partidaRepository;
    private final MaterialRepository materialRepository;
    private final ItemCubicadoRepository itemCubicadoRepository;
    private final ParametroMermaRepository parametroMermaRepository;

    public MotorCubicacionService(
            PartidaRepository partidaRepository,
            MaterialRepository materialRepository,
            ItemCubicadoRepository itemCubicadoRepository,
            ParametroMermaRepository parametroMermaRepository) {
        this.partidaRepository = partidaRepository;
        this.materialRepository = materialRepository;
        this.itemCubicadoRepository = itemCubicadoRepository;
        this.parametroMermaRepository = parametroMermaRepository;
    }

    /**
     * Recalcula por completo los ItemCubicado de una partida: usa
     * RecetaCubicacion.para(tipo) para saber qué categorías de material
     * corresponden, toma el primer Material de esa categoría en el
     * catálogo de la empresa, y aplica el ParametroMerma del material si
     * existe (si no, cantidadConMerma = cantidadCalculada).
     */
    public List<ItemCubicado> calcular(Long partidaId) {
        Partida partida = partidaRepository.findById(partidaId)
                .filter(AccesoEmpresa::esPropio)
                .orElseThrow(() -> new NoSuchElementException("Partida no encontrada: " + partidaId));
        Long empresaId = partida.getObra().getEmpresa().getId();

        // Una partida guardada antes de validar las medidas puede traer una en cero (o
        // negativa): con separación 0 los montantes salían Infinity. Se rechaza antes de
        // borrar la cubicación que ya tenía.
        if (!(partida.getAnchoM() > 0) || !(partida.getAltoM() > 0) || !(partida.getSeparacionMontantes() > 0)) {
            throw new IllegalStateException("La partida tiene medidas inválidas: el ancho, el alto y la separación "
                    + "de montantes deben ser mayores que 0. Corrígelas antes de cubicar");
        }

        itemCubicadoRepository.deleteByPartidaId(partidaId);

        List<ItemCubicado> resultado = new ArrayList<>();
        for (RecetaCubicacion.Coeficiente coef : RecetaCubicacion.para(partida.getTipo())) {
            materialRepository
                    .findFirstByEmpresaIdAndCategoriaOrderByIdAsc(empresaId, coef.categoria())
                    .ifPresent(material -> resultado.add(itemCubicadoRepository.save(
                            construirItem(partida, material, coef))));
        }
        return resultado;
    }

    private ItemCubicado construirItem(Partida partida, Material material, RecetaCubicacion.Coeficiente coef) {
        double cantidadCalculada = coef.porMontante()
                ? Math.ceil(partida.getAnchoM() / partida.getSeparacionMontantes()) + 1
                : coef.cantidadPorM2() * partida.superficieM2();

        double cantidadConMerma = parametroMermaRepository.findByMaterialId(material.getId())
                .map(parametro -> parametro.aplicar(cantidadCalculada))
                .orElse(cantidadCalculada);

        return ItemCubicado.builder()
                .partida(partida)
                .material(material)
                .cantidadCalculada(cantidadCalculada)
                .cantidadConMerma(cantidadConMerma)
                .build();
    }
}
