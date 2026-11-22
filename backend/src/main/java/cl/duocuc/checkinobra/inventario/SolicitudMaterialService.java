package cl.duocuc.checkinobra.inventario;

import cl.duocuc.checkinobra.config.AccesoEmpresa;
import cl.duocuc.checkinobra.config.ConflictoException;
import cl.duocuc.checkinobra.config.SesionActual;
import cl.duocuc.checkinobra.config.Texto;
import cl.duocuc.checkinobra.config.Usuario;
import cl.duocuc.checkinobra.config.UsuarioRepository;
import cl.duocuc.checkinobra.cubicacion.Material;
import cl.duocuc.checkinobra.cubicacion.MaterialService;
import cl.duocuc.checkinobra.obra.EstadoObra;
import cl.duocuc.checkinobra.obra.Obra;
import cl.duocuc.checkinobra.obra.ObraService;
import cl.duocuc.checkinobra.obra.Trabajador;
import cl.duocuc.checkinobra.obra.TrabajadorService;
import jakarta.persistence.EntityManager;
import jakarta.persistence.LockModeType;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;
import java.util.List;
import java.util.NoSuchElementException;

/**
 * Igual flujo que SolicitudHerramienta pero, al aprobar, genera un
 * KardexMovimiento de DESPACHO en vez de un préstamo
 * (SolicitudMaterial "1" -- "0..1" KardexMovimiento : genera >).
 */
@Service
@Transactional
public class SolicitudMaterialService {

    private final SolicitudMaterialRepository solicitudMaterialRepository;
    private final TrabajadorService trabajadorService;
    private final MaterialService materialService;
    private final ObraService obraService;
    private final UsuarioRepository usuarioRepository;
    private final KardexMovimientoService kardexMovimientoService;
    private final EntityManager entityManager;

    public SolicitudMaterialService(
            SolicitudMaterialRepository solicitudMaterialRepository,
            TrabajadorService trabajadorService,
            MaterialService materialService,
            ObraService obraService,
            UsuarioRepository usuarioRepository,
            KardexMovimientoService kardexMovimientoService,
            EntityManager entityManager) {
        this.solicitudMaterialRepository = solicitudMaterialRepository;
        this.trabajadorService = trabajadorService;
        this.materialService = materialService;
        this.obraService = obraService;
        this.usuarioRepository = usuarioRepository;
        this.kardexMovimientoService = kardexMovimientoService;
        this.entityManager = entityManager;
    }

    /**
     * @param usuarioId quien pide; el controlador lo saca del token
     * @param obraId opcional: si no viene, la obra de su cuadrilla, que es la
     *     única desde la que puede pedir
     * @param descripcion para qué lo pide; obligatoria
     */
    public SolicitudMaterial crear(
            Long usuarioId, Long materialId, Long obraId, double cantidad, String descripcion) {
        if (cantidad <= 0) {
            throw new IllegalArgumentException("La cantidad pedida debe ser mayor a 0");
        }
        String paraQue = Texto.obligatorio(descripcion, "Para qué lo necesitas", 3, 300);
        Trabajador trabajador = trabajadorService.obtenerPorUsuario(usuarioId);
        // Quien pide, bloqueado: dos solicitudes simultáneas del mismo trabajador, con
        // claves de idempotencia distintas, no pueden pasar las dos el control de
        // duplicado de más abajo. Es el mismo bloqueo que usa SolicitudHerramientaService.
        entityManager.refresh(trabajador, LockModeType.PESSIMISTIC_WRITE);
        Obra asignada = trabajadorService.obraAsignada(trabajador);
        // Pedir para otra obra sería sacar material de una bodega donde el
        // trabajador no está, y que el bodeguero de allá no lo conoce.
        if (obraId != null && !obraId.equals(asignada.getId())) {
            throw new ConflictoException(ConflictoException.OBRA_NO_ASIGNADA,
                    "Solo puedes pedir material para tu obra, " + asignada.getNombre());
        }
        Obra obra = obraService.obtener(asignada.getId());
        if (obra.getEstado() == EstadoObra.CERRADA) {
            throw new ConflictoException(ConflictoException.OBRA_CERRADA,
                    "La obra " + obra.getNombre() + " está cerrada: ya no se despacha material");
        }
        Material material = materialService.obtener(materialId);
        // Solo bloquea lo que sigue PENDIENTE: una solicitud aprobada, rechazada o
        // cancelada se puede volver a pedir. Va después de validar la obra y el
        // material, para que un material inexistente siga siendo un 404.
        if (solicitudMaterialRepository.existsByTrabajadorIdAndMaterialIdAndObraIdAndEstado(
                trabajador.getId(), material.getId(), obra.getId(), EstadoSolicitud.PENDIENTE)) {
            throw new ConflictoException(ConflictoException.SOLICITUD_DUPLICADA,
                    "Ya pediste " + material.getNombre() + " y tu solicitud sigue pendiente");
        }

        SolicitudMaterial solicitud = SolicitudMaterial.builder()
                .trabajador(trabajador)
                .material(material)
                .obra(obra)
                .cantidad(cantidad)
                .descripcion(paraQue)
                .estado(EstadoSolicitud.PENDIENTE)
                .fechaSolicitud(LocalDateTime.now())
                .build();
        return solicitudMaterialRepository.save(solicitud);
    }

    /**
     * SolicitudMaterial.aprobar(): KardexMovimiento del diagrama. Si la
     * cantidad pedida supera el stock, el bodeguero debe volver a llamar
     * con la cantidad efectivamente disponible (igual que en la pantalla
     * de despacho: no hay aprobación parcial automática).
     */
    public KardexMovimiento aprobar(Long solicitudId, Long aprobadorId, double cantidadAEntregar) {
        SolicitudMaterial solicitud = bloquear(solicitudId);
        Usuario aprobador = usuarioRepository.findById(aprobadorId)
                .filter(AccesoEmpresa::esPropio)
                .orElseThrow(() -> new NoSuchElementException("Usuario no encontrado: " + aprobadorId));
        exigirCantidadEntregable(solicitud, cantidadAEntregar);

        solicitud.aprobar(aprobador);
        solicitudMaterialRepository.save(solicitud);

        // El receptor no hay que preguntarlo: quien pidió el material es quien
        // se lo lleva. Por eso la cola de solicitudes deja mejor trazabilidad
        // que un despacho directo.
        return kardexMovimientoService.registrarMovimiento(
                solicitud.getObra().getId(),
                solicitud.getMaterial().getId(),
                aprobadorId,
                solicitud.getTrabajador().getId(),
                TipoMovimiento.DESPACHO,
                cantidadAEntregar);
    }

    /**
     * Lo que se entrega es mayor que cero y no pasa de lo que el trabajador pidió: la solicitud es
     * la autorización de esa cantidad, y aprobar más sacaría de la bodega material que nadie pidió.
     * Aprobar menos sí vale (entrega parcial por falta de stock).
     */
    private static void exigirCantidadEntregable(SolicitudMaterial solicitud, double cantidadAEntregar) {
        if (!(cantidadAEntregar > 0) || !Double.isFinite(cantidadAEntregar)) {
            throw new IllegalArgumentException("La cantidad a entregar debe ser mayor a 0");
        }
        if (cantidadAEntregar > solicitud.getCantidad() + 1e-6) {
            throw new IllegalArgumentException(
                    "No se puede entregar más de lo solicitado: se pidieron " + solicitud.getCantidad());
        }
    }

    /** SolicitudMaterial.rechazar() del diagrama. */
    public SolicitudMaterial rechazar(Long solicitudId, Long rechazadorId, String motivo) {
        SolicitudMaterial solicitud = bloquear(solicitudId);
        Usuario rechazador = usuarioRepository.findById(rechazadorId)
                .filter(AccesoEmpresa::esPropio)
                .orElseThrow(() -> new NoSuchElementException("Usuario no encontrado: " + rechazadorId));
        solicitud.rechazar(rechazador, motivo);
        return solicitudMaterialRepository.save(solicitud);
    }

    /** El trabajador retira su propia solicitud mientras sigue pendiente. */
    public SolicitudMaterial cancelar(Long solicitudId) {
        // obtener() ya exige que sea suya cuando quien llama es trabajador.
        SolicitudMaterial solicitud = bloquear(solicitudId);
        solicitud.cancelar();
        return solicitudMaterialRepository.save(solicitud);
    }

    /** El trabajador confirma que recibió lo que bodega aprobó. */
    public SolicitudMaterial confirmarRecepcion(Long solicitudId) {
        // obtener() ya exige que sea suya cuando quien llama es trabajador.
        SolicitudMaterial solicitud = bloquear(solicitudId);
        solicitud.confirmarRecepcion();
        return solicitudMaterialRepository.save(solicitud);
    }

    /**
     * Dos aprobaciones simultáneas de la misma solicitud —un doble tap, o dos
     * bodegueros con la cola abierta— la veían PENDIENTE las dos y generaban
     * dos despachos. Con la fila bloqueada, la segunda espera y ve la solicitud
     * ya resuelta.
     */
    private SolicitudMaterial bloquear(Long solicitudId) {
        var solicitud = obtener(solicitudId);
        entityManager.refresh(solicitud, LockModeType.PESSIMISTIC_WRITE);
        return solicitud;
    }

    /** Si quien llama es trabajador, además tiene que ser suya. */
    @Transactional(readOnly = true)
    public SolicitudMaterial obtener(Long id) {
        SolicitudMaterial solicitud = solicitudMaterialRepository.findById(id)
                .filter(AccesoEmpresa::esPropio)
                .orElseThrow(() -> new NoSuchElementException("Solicitud no encontrada: " + id));
        trabajadorService.exigirQueSeaPropio(solicitud.getTrabajador().getId());
        return solicitud;
    }

    @Transactional(readOnly = true)
    public List<SolicitudMaterial> listarPorTrabajador(Long trabajadorId) {
        trabajadorService.obtener(trabajadorId);
        trabajadorService.exigirQueSeaPropio(trabajadorId);
        return solicitudMaterialRepository.findByTrabajadorId(trabajadorId);
    }

    /** Las de quien llama, la más nueva primero. */
    @Transactional(readOnly = true)
    public List<SolicitudMaterial> listarMias() {
        Trabajador yo = trabajadorService.obtenerPorUsuario(SesionActual.usuarioId());
        return solicitudMaterialRepository.findByTrabajadorIdOrderByFechaSolicitudDescIdDesc(yo.getId());
    }

    @Transactional(readOnly = true)
    public List<SolicitudMaterial> listarPorObra(Long obraId) {
        TrabajadorService.exigirQueNoSeaTrabajador();
        obraService.obtener(obraId);
        return solicitudMaterialRepository.findByObraId(obraId);
    }

    @Transactional(readOnly = true)
    public List<SolicitudMaterial> listarPendientesPorObra(Long obraId) {
        TrabajadorService.exigirQueNoSeaTrabajador();
        obraService.obtener(obraId);
        return solicitudMaterialRepository.findByObraIdAndEstado(obraId, EstadoSolicitud.PENDIENTE);
    }
}
