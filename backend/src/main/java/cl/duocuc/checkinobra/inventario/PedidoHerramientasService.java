package cl.duocuc.checkinobra.inventario;

import cl.duocuc.checkinobra.config.AccesoEmpresa;
import cl.duocuc.checkinobra.config.SesionActual;
import cl.duocuc.checkinobra.config.Texto;
import cl.duocuc.checkinobra.config.Usuario;
import cl.duocuc.checkinobra.config.UsuarioRepository;
import cl.duocuc.checkinobra.obra.Trabajador;
import cl.duocuc.checkinobra.obra.TrabajadorService;
import jakarta.persistence.EntityManager;
import jakarta.persistence.LockModeType;
import org.hibernate.Hibernate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;
import java.util.Comparator;
import java.util.HashSet;
import java.util.List;
import java.util.NoSuchElementException;
import java.util.UUID;

/**
 * El trabajador pide varias herramientas juntas y recibe un QR; el bodeguero lo
 * escanea en el mesón y entrega todo de una vez.
 */
@Service
@Transactional
public class PedidoHerramientasService {

    /** Lo que la app antepone al código para distinguirlo de una credencial. */
    static final String PREFIJO_QR = "PEDIDO:";

    /** Más que esto no cabe en un mesón, y tampoco en una petición razonable. */
    static final int MAXIMO_HERRAMIENTAS = 20;

    private final PedidoHerramientasRepository pedidoHerramientasRepository;
    private final SolicitudHerramientaService solicitudHerramientaService;
    private final PrestamoHerramientaService prestamoHerramientaService;
    private final TrabajadorService trabajadorService;
    private final UsuarioRepository usuarioRepository;
    private final EntityManager entityManager;

    public PedidoHerramientasService(
            PedidoHerramientasRepository pedidoHerramientasRepository,
            SolicitudHerramientaService solicitudHerramientaService,
            PrestamoHerramientaService prestamoHerramientaService,
            TrabajadorService trabajadorService,
            UsuarioRepository usuarioRepository,
            EntityManager entityManager) {
        this.pedidoHerramientasRepository = pedidoHerramientasRepository;
        this.solicitudHerramientaService = solicitudHerramientaService;
        this.prestamoHerramientaService = prestamoHerramientaService;
        this.trabajadorService = trabajadorService;
        this.usuarioRepository = usuarioRepository;
        this.entityManager = entityManager;
    }

    /**
     * Todo o nada: una solicitud pendiente por herramienta, con las mismas
     * validaciones que una solicitud suelta. Si una no pasa, no se guarda
     * ninguna.
     */
    public PedidoHerramientas crear(Long usuarioId, List<Long> herramientaIds, String descripcion) {
        if (herramientaIds == null || herramientaIds.isEmpty()) {
            throw new IllegalArgumentException("Elige al menos una herramienta");
        }
        if (herramientaIds.contains(null)) {
            throw new IllegalArgumentException("Hay una herramienta sin id en el pedido");
        }
        if (herramientaIds.size() > MAXIMO_HERRAMIENTAS) {
            throw new IllegalArgumentException(
                    "Un pedido lleva hasta " + MAXIMO_HERRAMIENTAS + " herramientas");
        }
        if (new HashSet<>(herramientaIds).size() != herramientaIds.size()) {
            throw new IllegalArgumentException("Elegiste la misma herramienta más de una vez");
        }
        String paraQue = Texto.obligatorio(descripcion, "Para qué las necesitas", 3, 300);
        Trabajador trabajador = solicitudHerramientaService.trabajadorQuePide(usuarioId);

        PedidoHerramientas pedido = PedidoHerramientas.builder()
                .codigoQr(UUID.randomUUID().toString())
                .estado(EstadoPedidoHerramientas.PENDIENTE)
                .descripcion(paraQue)
                .fechaSolicitud(LocalDateTime.now())
                .trabajador(trabajador)
                .build();
        for (Long herramientaId : herramientaIds) {
            pedido.agregar(solicitudHerramientaService.nueva(trabajador, herramientaId, paraQue));
        }
        return conSolicitudes(pedidoHerramientasRepository.save(pedido));
    }

    /**
     * La respuesta recorre {@code solicitudes}, que es perezosa. Con
     * {@code open-in-view=false} la sesión ya se cerró cuando el controlador arma
     * la respuesta, así que se carga aquí, dentro de la transacción.
     */
    private static PedidoHerramientas conSolicitudes(PedidoHerramientas pedido) {
        Hibernate.initialize(pedido.getSolicitudes());
        return pedido;
    }

    /** Bodega escaneó el QR: aprueba lo pendiente y crea un préstamo por herramienta. */
    public Entrega entregar(String codigoQr, LocalDateTime fechaDevolEsperada) {
        PedidoHerramientas pedido = obtenerPorQr(codigoQr);
        // Dos bodegueros con el mismo QR, o un doble toque: el segundo espera
        // acá y encuentra el pedido ya entregado.
        entityManager.refresh(pedido, LockModeType.PESSIMISTIC_WRITE);
        // Y cada solicitud, por si alguien la aprueba suelta desde la cola al
        // mismo tiempo.
        pedido.getSolicitudes().forEach(s -> entityManager.refresh(s, LockModeType.PESSIMISTIC_WRITE));

        Usuario bodega = usuarioRepository.findById(SesionActual.usuarioId())
                .filter(AccesoEmpresa::esPropio)
                .orElseThrow(() -> new NoSuchElementException("Usuario no encontrado"));
        List<SolicitudHerramienta> aprobadas = pedido.entregar(bodega);

        Long obraId = trabajadorService.obraAsignada(pedido.getTrabajador()).getId();
        List<PrestamoHerramienta> prestamos = aprobadas.stream()
                .map(s -> prestamoHerramientaService.prestarDirecto(
                        s.getHerramienta().getId(),
                        pedido.getTrabajador().getId(),
                        obraId,
                        bodega.getId(),
                        fechaDevolEsperada))
                .toList();
        return new Entrega(conSolicitudes(pedidoHerramientasRepository.save(pedido)), prestamos);
    }

    /** El trabajador lo retira. {@code obtener} ya exige que sea suyo. */
    public PedidoHerramientas cancelar(Long id) {
        PedidoHerramientas pedido = obtener(id);
        entityManager.refresh(pedido, LockModeType.PESSIMISTIC_WRITE);
        pedido.getSolicitudes().forEach(s -> entityManager.refresh(s, LockModeType.PESSIMISTIC_WRITE));
        pedido.cancelar();
        return conSolicitudes(pedidoHerramientasRepository.save(pedido));
    }

    /**
     * Lo que ve el bodeguero al escanear. Un código de otra empresa da el mismo
     * 404, con el mismo mensaje, que uno inventado.
     *
     * @param codigoQr el UUID; si llega con el prefijo {@code PEDIDO:}, se le quita
     */
    @Transactional(readOnly = true)
    public PedidoHerramientas obtenerPorQr(String codigoQr) {
        String codigo = codigoQr == null ? "" : codigoQr.trim();
        if (codigo.startsWith(PREFIJO_QR)) {
            codigo = codigo.substring(PREFIJO_QR.length());
        }
        return conSolicitudes(pedidoHerramientasRepository.findByCodigoQr(codigo)
                .filter(AccesoEmpresa::esPropio)
                .orElseThrow(() -> new NoSuchElementException("Pedido no encontrado")));
    }

    /** Si quien llama es trabajador, además tiene que ser suyo. */
    @Transactional(readOnly = true)
    public PedidoHerramientas obtener(Long id) {
        PedidoHerramientas pedido = pedidoHerramientasRepository.findById(id)
                .filter(AccesoEmpresa::esPropio)
                .orElseThrow(() -> new NoSuchElementException("Pedido no encontrado: " + id));
        trabajadorService.exigirQueSeaPropio(pedido.getTrabajador().getId());
        return conSolicitudes(pedido);
    }

    /** Los de quien llama: primero los pendientes, que son los que tienen un QR vigente. */
    @Transactional(readOnly = true)
    public List<PedidoHerramientas> listarMios() {
        Trabajador yo = trabajadorService.obtenerPorUsuario(SesionActual.usuarioId());
        // La consulta ya los trae del más nuevo al más viejo; el orden estable
        // lo conserva dentro de cada grupo.
        return pedidoHerramientasRepository.findByTrabajadorIdOrderByFechaSolicitudDescIdDesc(yo.getId()).stream()
                .sorted(Comparator.comparing(p -> p.getEstado() != EstadoPedidoHerramientas.PENDIENTE))
                .map(PedidoHerramientasService::conSolicitudes)
                .toList();
    }

    /** El pedido ya entregado y los préstamos que salieron de él. */
    public record Entrega(PedidoHerramientas pedido, List<PrestamoHerramienta> prestamos) {
    }
}
