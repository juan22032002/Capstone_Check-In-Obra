package cl.duocuc.checkinobra.inventario;

import cl.duocuc.checkinobra.config.AccesoEmpresa;
import cl.duocuc.checkinobra.config.ConflictoException;
import cl.duocuc.checkinobra.config.SesionActual;
import cl.duocuc.checkinobra.config.Usuario;
import cl.duocuc.checkinobra.config.UsuarioRepository;
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

@Service
@Transactional
public class PrestamoHerramientaService {

    private final PrestamoHerramientaRepository prestamoHerramientaRepository;
    private final HerramientaRepository herramientaRepository;
    private final TrabajadorService trabajadorService;
    private final ObraService obraService;
    private final UsuarioRepository usuarioRepository;
    private final EntityManager entityManager;

    public PrestamoHerramientaService(
            PrestamoHerramientaRepository prestamoHerramientaRepository,
            HerramientaRepository herramientaRepository,
            TrabajadorService trabajadorService,
            ObraService obraService,
            UsuarioRepository usuarioRepository,
            EntityManager entityManager) {
        this.prestamoHerramientaRepository = prestamoHerramientaRepository;
        this.herramientaRepository = herramientaRepository;
        this.trabajadorService = trabajadorService;
        this.obraService = obraService;
        this.usuarioRepository = usuarioRepository;
        this.entityManager = entityManager;
    }

    /**
     * Préstamo directo del bodeguero, sin pasar por una SolicitudHerramienta
     * (la otra vía es SolicitudHerramientaService.aprobar()).
     *
     * <p>La herramienta se bloquea antes de mirar su estado: dos préstamos
     * simultáneos de la misma herramienta la veían DISPONIBLE los dos y la
     * entregaban dos veces.
     *
     * @param autorizadorId quien entrega; lo pone el controlador desde el token
     */
    public PrestamoHerramienta prestarDirecto(
            Long herramientaId, Long trabajadorId, Long obraId, Long autorizadorId, LocalDateTime fechaDevolEsperada) {
        if (fechaDevolEsperada == null) {
            throw new IllegalArgumentException("Falta la fecha de devolución esperada");
        }
        if (fechaDevolEsperada.isBefore(LocalDateTime.now())) {
            throw new IllegalArgumentException("La fecha de devolución esperada ya pasó: " + fechaDevolEsperada);
        }
        Herramienta herramienta = herramientaRepository.findById(herramientaId)
                .filter(AccesoEmpresa::esPropio)
                .orElseThrow(() -> new NoSuchElementException("Herramienta no encontrada: " + herramientaId));
        entityManager.refresh(herramienta, LockModeType.PESSIMISTIC_WRITE);
        if (herramienta.getEstado() != EstadoHerramienta.DISPONIBLE) {
            throw new ConflictoException(ConflictoException.HERRAMIENTA_NO_DISPONIBLE,
                    "La herramienta no está DISPONIBLE (estado actual: " + herramienta.getEstado() + ")");
        }
        Trabajador trabajador = trabajadorService.obtener(trabajadorId);
        trabajadorService.exigirQueSeaDeLaObra(trabajador, obraId);
        Obra obra = obraService.obtenerAbiertaParaRegistrar(obraId);
        Usuario autorizador = usuarioRepository.findById(autorizadorId)
                .filter(AccesoEmpresa::esPropio)
                .orElseThrow(() -> new NoSuchElementException("Usuario no encontrado: " + autorizadorId));

        PrestamoHerramienta prestamo = PrestamoHerramienta.builder()
                .herramienta(herramienta)
                .trabajador(trabajador)
                .obra(obra)
                .autorizadoPor(autorizador)
                .fechaDevolEsperada(fechaDevolEsperada)
                .build();
        prestamo.autorizar();

        herramienta.setEstado(EstadoHerramienta.PRESTADA);
        herramientaRepository.save(herramienta);
        return prestamoHerramientaRepository.save(prestamo);
    }

    /**
     * PrestamoHerramienta.registrarDevolucion() del diagrama, orquestado:
     * también decide el nuevo EstadoHerramienta (DISPONIBLE o MANTENCION).
     */
    public PrestamoHerramienta registrarDevolucion(Long prestamoId, EstadoHerramienta nuevoEstadoHerramienta) {
        if (nuevoEstadoHerramienta == EstadoHerramienta.PRESTADA) {
            throw new IllegalArgumentException("El estado de devolución no puede ser PRESTADA");
        }
        PrestamoHerramienta prestamo = obtener(prestamoId);
        // Dos devoluciones simultáneas del mismo préstamo pasaban las dos.
        entityManager.refresh(prestamo, LockModeType.PESSIMISTIC_WRITE);
        prestamo.registrarDevolucion();

        Herramienta herramienta = prestamo.getHerramienta();
        herramienta.setEstado(nuevoEstadoHerramienta);
        herramientaRepository.save(herramienta);

        return prestamoHerramientaRepository.save(prestamo);
    }

    /** Si quien llama es trabajador, además tiene que ser suyo. */
    @Transactional(readOnly = true)
    public PrestamoHerramienta obtener(Long id) {
        PrestamoHerramienta prestamo = prestamoHerramientaRepository.findById(id)
                .filter(AccesoEmpresa::esPropio)
                .orElseThrow(() -> new NoSuchElementException("Préstamo no encontrado: " + id));
        trabajadorService.exigirQueSeaPropio(prestamo.getTrabajador().getId());
        return prestamo;
    }

    @Transactional(readOnly = true)
    public List<PrestamoHerramienta> listarPorObra(Long obraId) {
        TrabajadorService.exigirQueNoSeaTrabajador();
        obraService.obtener(obraId);
        return prestamoHerramientaRepository.findByObraId(obraId);
    }

    @Transactional(readOnly = true)
    public List<PrestamoHerramienta> listarPorTrabajador(Long trabajadorId) {
        trabajadorService.obtener(trabajadorId);
        trabajadorService.exigirQueSeaPropio(trabajadorId);
        return prestamoHerramientaRepository.findByTrabajadorId(trabajadorId);
    }

    /** Los de quien llama, abiertos y cerrados, el más nuevo primero. */
    @Transactional(readOnly = true)
    public List<PrestamoHerramienta> listarMios() {
        Trabajador yo = trabajadorService.obtenerPorUsuario(SesionActual.usuarioId());
        return prestamoHerramientaRepository.findByTrabajadorIdOrderByFechaPrestamoDescIdDesc(yo.getId());
    }

    @Transactional(readOnly = true)
    public List<PrestamoHerramienta> listarVencidos() {
        TrabajadorService.exigirQueNoSeaTrabajador();
        // Esta consulta no lleva obra ni empresa: barría los préstamos vencidos de
        // todas las constructoras del sistema. Acá se filtra, no se rechaza:
        // pedir "los vencidos" es legítimo, lo que no corresponde es ver los
        // ajenos.
        Long empresa = SesionActual.empresaId();
        return prestamoHerramientaRepository
                .findByFechaDevolRealIsNullAndFechaDevolEsperadaBefore(LocalDateTime.now()).stream()
                .filter(p -> empresa.equals(p.empresaId()))
                .toList();
    }
}
