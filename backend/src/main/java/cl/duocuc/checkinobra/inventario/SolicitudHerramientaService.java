package cl.duocuc.checkinobra.inventario;

import cl.duocuc.checkinobra.config.AccesoEmpresa;
import cl.duocuc.checkinobra.config.ConflictoException;
import cl.duocuc.checkinobra.config.SesionActual;
import cl.duocuc.checkinobra.config.Texto;
import cl.duocuc.checkinobra.config.Usuario;
import cl.duocuc.checkinobra.config.UsuarioRepository;
import cl.duocuc.checkinobra.obra.EstadoObra;
import cl.duocuc.checkinobra.obra.Obra;
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
 * El Trabajador crea la solicitud; el Bodeguero (o Admin) la aprueba desde
 * la cola — recién ahí se genera el PrestamoHerramienta (SolicitudHerramienta
 * "1" -- "0..1" PrestamoHerramienta : genera >).
 */
@Service
@Transactional
public class SolicitudHerramientaService {

    private final SolicitudHerramientaRepository solicitudHerramientaRepository;
    private final HerramientaRepository herramientaRepository;
    private final TrabajadorService trabajadorService;
    private final UsuarioRepository usuarioRepository;
    private final PrestamoHerramientaService prestamoHerramientaService;
    private final EntityManager entityManager;

    public SolicitudHerramientaService(
            SolicitudHerramientaRepository solicitudHerramientaRepository,
            HerramientaRepository herramientaRepository,
            TrabajadorService trabajadorService,
            UsuarioRepository usuarioRepository,
            PrestamoHerramientaService prestamoHerramientaService,
            EntityManager entityManager) {
        this.solicitudHerramientaRepository = solicitudHerramientaRepository;
        this.herramientaRepository = herramientaRepository;
        this.trabajadorService = trabajadorService;
        this.usuarioRepository = usuarioRepository;
        this.prestamoHerramientaService = prestamoHerramientaService;
        this.entityManager = entityManager;
    }

    /**
     * @param usuarioId quien pide; el controlador lo saca del token
     * @param cantidad siempre 1: cada herramienta es una pieza con su propio QR.
     *     Nulo se toma como 1.
     * @param descripcion para qué la pide; obligatoria
     */
    public SolicitudHerramienta crear(Long usuarioId, Long herramientaId, Integer cantidad, String descripcion) {
        if (cantidad != null && cantidad != 1) {
            throw new IllegalArgumentException(
                    "Cada solicitud es por una herramienta: cada una tiene su propio código QR");
        }
        String paraQue = Texto.obligatorio(descripcion, "Para qué la necesitas", 3, 300);
        Trabajador trabajador = trabajadorQuePide(usuarioId);
        return solicitudHerramientaRepository.save(nueva(trabajador, herramientaId, paraQue));
    }

    /**
     * Quien pide, bloqueado para que dos solicitudes simultáneas del mismo
     * trabajador —con claves de idempotencia distintas— no pasen las dos el
     * control de duplicado. También lo usa el pedido con QR.
     */
    Trabajador trabajadorQuePide(Long usuarioId) {
        Trabajador trabajador = trabajadorService.obtenerPorUsuario(usuarioId);
        entityManager.refresh(trabajador, LockModeType.PESSIMISTIC_WRITE);

        // Sin cuadrilla, al aprobar no habría obra a la cual cargar el préstamo.
        Obra obra = trabajadorService.obraAsignada(trabajador);
        if (obra.getEstado() == EstadoObra.CERRADA) {
            throw new ConflictoException(ConflictoException.OBRA_CERRADA,
                    "La obra " + obra.getNombre() + " está cerrada: ya no se prestan herramientas");
        }
        return trabajador;
    }

    /**
     * La solicitud armada y validada, sin guardar: la herramienta es de la
     * empresa, está disponible y el trabajador no la tiene ya pedida.
     */
    SolicitudHerramienta nueva(Trabajador trabajador, Long herramientaId, String paraQue) {
        Herramienta herramienta = herramientaRepository.findById(herramientaId)
                .filter(AccesoEmpresa::esPropio)
                .orElseThrow(() -> new NoSuchElementException("Herramienta no encontrada: " + herramientaId));
        if (herramienta.getEstado() != EstadoHerramienta.DISPONIBLE) {
            throw new ConflictoException(ConflictoException.HERRAMIENTA_NO_DISPONIBLE,
                    herramienta.getNombre() + " no está disponible (" + herramienta.getEstado().name().toLowerCase() + ")");
        }
        if (solicitudHerramientaRepository.existsByTrabajadorIdAndHerramientaIdAndEstado(
                trabajador.getId(), herramientaId, EstadoSolicitud.PENDIENTE)) {
            throw new ConflictoException(ConflictoException.SOLICITUD_DUPLICADA,
                    "Ya pediste " + herramienta.getNombre() + " y tu solicitud sigue pendiente");
        }

        return SolicitudHerramienta.builder()
                .trabajador(trabajador)
                .herramienta(herramienta)
                .cantidad(1)
                .descripcion(paraQue)
                .estado(EstadoSolicitud.PENDIENTE)
                .fechaSolicitud(LocalDateTime.now())
                .build();
    }

    /** SolicitudHerramienta.aprobar(): PrestamoHerramienta del diagrama. */
    public PrestamoHerramienta aprobar(Long solicitudId, Long aprobadorId, LocalDateTime fechaDevolEsperada) {
        SolicitudHerramienta solicitud = bloquearSuelta(solicitudId);
        Usuario aprobador = usuarioRepository.findById(aprobadorId)
                .filter(AccesoEmpresa::esPropio)
                .orElseThrow(() -> new NoSuchElementException("Usuario no encontrado: " + aprobadorId));

        solicitud.aprobar(aprobador);
        solicitudHerramientaRepository.save(solicitud);

        Long obraId = solicitud.getTrabajador().getCuadrilla().getObra().getId();
        return prestamoHerramientaService.prestarDirecto(
                solicitud.getHerramienta().getId(),
                solicitud.getTrabajador().getId(),
                obraId,
                aprobadorId,
                fechaDevolEsperada);
    }

    /** SolicitudHerramienta.rechazar() del diagrama. */
    public SolicitudHerramienta rechazar(Long solicitudId, Long rechazadorId, String motivo) {
        SolicitudHerramienta solicitud = bloquearSuelta(solicitudId);
        Usuario rechazador = usuarioRepository.findById(rechazadorId)
                .filter(AccesoEmpresa::esPropio)
                .orElseThrow(() -> new NoSuchElementException("Usuario no encontrado: " + rechazadorId));
        solicitud.rechazar(rechazador, motivo);
        return solicitudHerramientaRepository.save(solicitud);
    }

    /** El trabajador retira su propia solicitud mientras sigue pendiente. */
    public SolicitudHerramienta cancelar(Long solicitudId) {
        // obtener() ya exige que sea suya cuando quien llama es trabajador.
        SolicitudHerramienta solicitud = bloquearSuelta(solicitudId);
        solicitud.cancelar();
        return solicitudHerramientaRepository.save(solicitud);
    }

    /** El trabajador confirma que recibió la herramienta que bodega le prestó. */
    public SolicitudHerramienta confirmarRecepcion(Long solicitudId) {
        // obtener() ya exige que sea suya cuando quien llama es trabajador.
        SolicitudHerramienta solicitud = bloquear(solicitudId);
        solicitud.confirmarRecepcion();
        return solicitudHerramientaRepository.save(solicitud);
    }

    /**
     * Dos aprobaciones simultáneas de la misma solicitud —un doble tap, o dos
     * bodegueros con la cola abierta— la veían PENDIENTE las dos y generaban
     * dos despachos. Con la fila bloqueada, la segunda espera y ve la solicitud
     * ya resuelta.
     */
    private SolicitudHerramienta bloquear(Long solicitudId) {
        var solicitud = obtener(solicitudId);
        entityManager.refresh(solicitud, LockModeType.PESSIMISTIC_WRITE);
        return solicitud;
    }

    /**
     * Aprobar, rechazar o cancelar una por una es solo para las sueltas. Una
     * que va en un pedido con QR se resuelve con el pedido: si no, el QR
     * quedaría prometiendo herramientas que ya no entrega.
     */
    private SolicitudHerramienta bloquearSuelta(Long solicitudId) {
        SolicitudHerramienta solicitud = bloquear(solicitudId);
        if (solicitud.getPedido() != null) {
            throw new ConflictoException(ConflictoException.EN_PEDIDO,
                    "Esta solicitud es parte de un pedido con QR: se entrega o se cancela el pedido completo");
        }
        return solicitud;
    }

    /** Si quien llama es trabajador, además tiene que ser suya. */
    @Transactional(readOnly = true)
    public SolicitudHerramienta obtener(Long id) {
        SolicitudHerramienta solicitud = solicitudHerramientaRepository.findById(id)
                .filter(AccesoEmpresa::esPropio)
                .orElseThrow(() -> new NoSuchElementException("Solicitud no encontrada: " + id));
        trabajadorService.exigirQueSeaPropio(solicitud.getTrabajador().getId());
        return solicitud;
    }

    @Transactional(readOnly = true)
    public List<SolicitudHerramienta> listarPorTrabajador(Long trabajadorId) {
        trabajadorService.obtener(trabajadorId);
        trabajadorService.exigirQueSeaPropio(trabajadorId);
        return solicitudHerramientaRepository.findByTrabajadorId(trabajadorId);
    }

    /** Las de quien llama, la más nueva primero. */
    @Transactional(readOnly = true)
    public List<SolicitudHerramienta> listarMias() {
        Trabajador yo = trabajadorService.obtenerPorUsuario(SesionActual.usuarioId());
        return solicitudHerramientaRepository.findByTrabajadorIdOrderByFechaSolicitudDescIdDesc(yo.getId());
    }

    @Transactional(readOnly = true)
    public List<SolicitudHerramienta> listarPorObra(Long obraId) {
        prestamoHerramientaService.listarPorObra(obraId);
        return solicitudHerramientaRepository.findByObraId(obraId);
    }

    @Transactional(readOnly = true)
    public List<SolicitudHerramienta> listarPendientesPorObra(Long obraId) {
        prestamoHerramientaService.listarPorObra(obraId);
        return solicitudHerramientaRepository.findByObraIdAndEstado(obraId, EstadoSolicitud.PENDIENTE);
    }
}
