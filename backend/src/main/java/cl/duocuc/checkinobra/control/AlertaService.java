package cl.duocuc.checkinobra.control;

import cl.duocuc.checkinobra.config.AccesoEmpresa;
import cl.duocuc.checkinobra.cubicacion.Material;
import cl.duocuc.checkinobra.inventario.KardexMovimientoService;
import cl.duocuc.checkinobra.inventario.PrestamoHerramienta;
import cl.duocuc.checkinobra.inventario.PrestamoHerramientaRepository;
import cl.duocuc.checkinobra.cubicacion.MaterialService;
import cl.duocuc.checkinobra.obra.Obra;
import cl.duocuc.checkinobra.obra.ObraService;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;
import java.util.NoSuchElementException;

/**
 * control depende de inventario/cubicacion/obra (nunca al revés) para
 * poder detectar las condiciones que disparan cada TipoAlerta. El
 * diagrama no modela un "detector" — Alerta.generar()/resolver() son los
 * únicos métodos propios; el resto es orquestación de este servicio.
 */
@Service
@Transactional
public class AlertaService {

    private final AlertaRepository alertaRepository;
    private final ObraService obraService;
    private final MaterialService materialService;
    private final KardexMovimientoService kardexMovimientoService;
    private final PrestamoHerramientaRepository prestamoHerramientaRepository;

    public AlertaService(
            AlertaRepository alertaRepository,
            ObraService obraService,
            MaterialService materialService,
            KardexMovimientoService kardexMovimientoService,
            PrestamoHerramientaRepository prestamoHerramientaRepository) {
        this.alertaRepository = alertaRepository;
        this.obraService = obraService;
        this.materialService = materialService;
        this.kardexMovimientoService = kardexMovimientoService;
        this.prestamoHerramientaRepository = prestamoHerramientaRepository;
    }

    /** Revisa los préstamos abiertos de la obra y genera NO_DEVUELTA para los vencidos que aún no tienen alerta. */
    public List<Alerta> detectarNoDevueltas(Long obraId) {
        // obtenerBloqueada() filtra por empresa (404 si la obra es ajena) y
        // además serializa las detecciones: la app las dispara cada vez que se
        // abre la pantalla de alertas, y dos a la vez leían la misma lista de
        // "existentes" y creaban la misma alerta dos veces.
        Obra obra = obraService.obtenerBloqueada(obraId);
        List<PrestamoHerramienta> abiertos = prestamoHerramientaRepository.findByObraIdAndFechaDevolRealIsNull(obraId);
        List<Alerta> existentes = alertaRepository.findByObraIdAndResueltoFalse(obraId);

        return abiertos.stream()
                .filter(PrestamoHerramienta::estaVencido)
                .filter(p -> existentes.stream().noneMatch(a ->
                        a.getPrestamoHerramienta() != null && a.getPrestamoHerramienta().getId().equals(p.getId())))
                .map(p -> alertaRepository.save(Alerta.generar(
                        TipoAlerta.NO_DEVUELTA,
                        // Nombre y RUT: la alerta tiene que decir a quién ir a
                        // buscar, no solo qué falta.
                        p.getHerramienta().getNombre() + " sin devolver — "
                                + p.getTrabajador().nombre() + " (" + p.getTrabajador().rut() + ")",
                        obra,
                        p)))
                .toList();
    }

    /** Revisa el catálogo de la obra y genera STOCK_CRITICO para lo que quedó bajo el mínimo. */
    public List<Alerta> detectarStockCritico(Long obraId) {
        // obtenerBloqueada() filtra por empresa (404 si la obra es ajena) y
        // además serializa las detecciones: la app las dispara cada vez que se
        // abre la pantalla de alertas, y dos a la vez leían la misma lista de
        // "existentes" y creaban la misma alerta dos veces.
        Obra obra = obraService.obtenerBloqueada(obraId);
        List<Material> materiales = materialService.listarPorEmpresa(obra.getEmpresa().getId());
        List<Alerta> existentes = alertaRepository.findByObraIdAndResueltoFalse(obraId);

        return materiales.stream()
                .filter(m -> kardexMovimientoService.stockActual(obraId, m.getId()) < m.getStockMinimo())
                .filter(m -> existentes.stream().noneMatch(a ->
                        a.getTipo() == TipoAlerta.STOCK_CRITICO && a.getMensaje().contains(m.getSku())))
                .map(m -> alertaRepository.save(Alerta.generar(
                        TipoAlerta.STOCK_CRITICO,
                        m.getNombre() + " (" + m.getSku() + ") bajo el mínimo",
                        obra,
                        null)))
                .toList();
    }

    /** Alerta.generar() manual al cerrar turno (pantalla BodCierreTurno). */
    public Alerta generarCierreTurno(Long obraId, String mensaje) {
        Obra obra = obraService.obtener(obraId);
        return alertaRepository.save(Alerta.generar(TipoAlerta.CIERRE_TURNO, mensaje, obra, null));
    }

    /** Alerta.resolver() del diagrama. */
    public Alerta resolver(Long alertaId) {
        Alerta alerta = obtener(alertaId);
        alerta.resolver();
        return alertaRepository.save(alerta);
    }

    @Transactional(readOnly = true)
    public Alerta obtener(Long id) {
        return alertaRepository.findById(id)
                .filter(AccesoEmpresa::esPropio)
                .orElseThrow(() -> new NoSuchElementException("Alerta no encontrada: " + id));
    }

    @Transactional(readOnly = true)
    public List<Alerta> listarPorObra(Long obraId) {
        obraService.obtener(obraId);
        return alertaRepository.findByObraId(obraId);
    }

    @Transactional(readOnly = true)
    public List<Alerta> listarSinResolver(Long obraId) {
        obraService.obtener(obraId);
        return alertaRepository.findByObraIdAndResueltoFalse(obraId);
    }
}
