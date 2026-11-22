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
import java.util.function.BiConsumer;
import java.util.function.Consumer;

@Service
@Transactional
public class PedidoEspecialService {

    private final PedidoEspecialRepository pedidoEspecialRepository;
    private final TrabajadorService trabajadorService;
    private final ObraService obraService;
    private final MaterialService materialService;
    private final HerramientaRepository herramientaRepository;
    private final UsuarioRepository usuarioRepository;
    private final EntityManager entityManager;

    public PedidoEspecialService(
            PedidoEspecialRepository pedidoEspecialRepository,
            TrabajadorService trabajadorService,
            ObraService obraService,
            MaterialService materialService,
            HerramientaRepository herramientaRepository,
            UsuarioRepository usuarioRepository,
            EntityManager entityManager) {
        this.pedidoEspecialRepository = pedidoEspecialRepository;
        this.trabajadorService = trabajadorService;
        this.obraService = obraService;
        this.materialService = materialService;
        this.herramientaRepository = herramientaRepository;
        this.usuarioRepository = usuarioRepository;
        this.entityManager = entityManager;
    }

    /**
     * El trabajador pide algo que bodega no le puede pasar hoy. La obra es la de
     * su cuadrilla, igual que en las solicitudes de catálogo.
     *
     * @param materialId o {@code herramientaId}: opcionales, cuando lo pedido
     *     está en el catálogo pero no hay o está prestado; ayuda a bodega a saber
     *     exactamente qué conseguir
     */
    public PedidoEspecial crear(
            Long usuarioId, TipoPedidoEspecial tipo, String nombre, double cantidad, String unidad,
            String descripcion, Long materialId, Long herramientaId) {
        if (tipo == null) {
            throw new IllegalArgumentException("Falta el tipo: MATERIAL o HERRAMIENTA");
        }
        String nombreLimpio = Texto.obligatorio(nombre, "El nombre", 2, 120);
        String paraQue = Texto.obligatorio(descripcion, "Para qué lo necesitas", 3, 300);
        String unidadLimpia = Texto.opcional(unidad, "La unidad", 20);
        if (cantidad <= 0) {
            throw new IllegalArgumentException("La cantidad debe ser mayor a 0");
        }
        if (materialId != null && herramientaId != null) {
            throw new IllegalArgumentException("Un pedido es de un material o de una herramienta, no de los dos");
        }
        if (tipo == TipoPedidoEspecial.HERRAMIENTA && materialId != null) {
            throw new IllegalArgumentException("Un pedido de herramienta no lleva materialId");
        }
        if (tipo == TipoPedidoEspecial.MATERIAL && herramientaId != null) {
            throw new IllegalArgumentException("Un pedido de material no lleva herramientaId");
        }

        Trabajador trabajador = trabajadorService.obtenerPorUsuario(usuarioId);
        Obra obra = trabajadorService.obraAsignada(trabajador);
        if (obra.getEstado() == EstadoObra.CERRADA) {
            throw new ConflictoException(ConflictoException.OBRA_CERRADA,
                    "La obra " + obra.getNombre() + " está cerrada: ya no se reciben pedidos");
        }
        Material material = materialId == null ? null : materialService.obtener(materialId);
        Herramienta herramienta = herramientaId == null ? null : herramientaRepository.findById(herramientaId)
                .filter(AccesoEmpresa::esPropio)
                .orElseThrow(() -> new NoSuchElementException("Herramienta no encontrada: " + herramientaId));

        LocalDateTime ahora = LocalDateTime.now();
        return pedidoEspecialRepository.save(PedidoEspecial.builder()
                .tipo(tipo)
                .nombre(nombreLimpio)
                .cantidad(cantidad)
                .unidad(unidadLimpia)
                .descripcion(paraQue)
                .estado(EstadoPedidoEspecial.PENDIENTE)
                .fechaSolicitud(ahora)
                .fechaActualizacion(ahora)
                .obra(obra)
                .trabajador(trabajador)
                .material(material)
                .herramienta(herramienta)
                .build());
    }

    public PedidoEspecial gestionar(Long id, String nota) {
        String limpia = Texto.opcional(nota, "La nota", 300);
        return porBodega(id, (p, bodega) -> p.gestionar(bodega, limpia));
    }

    public PedidoEspecial marcarListo(Long id, String nota) {
        String limpia = Texto.opcional(nota, "La nota", 300);
        return porBodega(id, (p, bodega) -> p.marcarListo(bodega, limpia));
    }

    public PedidoEspecial entregar(Long id) {
        return porBodega(id, PedidoEspecial::entregar);
    }

    public PedidoEspecial rechazar(Long id, String motivo) {
        String limpio = Texto.obligatorio(motivo, "El motivo del rechazo", 1, 300);
        return porBodega(id, (p, bodega) -> p.rechazar(bodega, limpio));
    }

    /** El trabajador lo retira. {@code obtener} ya exige que sea suyo. */
    public PedidoEspecial cancelar(Long id) {
        return cambiar(id, PedidoEspecial::cancelar);
    }

    public PedidoEspecial confirmarRecepcion(Long id) {
        return cambiar(id, PedidoEspecial::confirmarRecepcion);
    }

    /** Si quien llama es trabajador, además tiene que ser suyo. */
    @Transactional(readOnly = true)
    public PedidoEspecial obtener(Long id) {
        PedidoEspecial pedido = pedidoEspecialRepository.findById(id)
                .filter(AccesoEmpresa::esPropio)
                .orElseThrow(() -> new NoSuchElementException("Pedido especial no encontrado: " + id));
        trabajadorService.exigirQueSeaPropio(pedido.getTrabajador().getId());
        return pedido;
    }

    @Transactional(readOnly = true)
    public List<PedidoEspecial> listarMios() {
        Trabajador yo = trabajadorService.obtenerPorUsuario(SesionActual.usuarioId());
        return pedidoEspecialRepository.findByTrabajadorIdOrderByFechaSolicitudDescIdDesc(yo.getId());
    }

    /** @param obraId opcional: sin obra, los de toda la empresa */
    @Transactional(readOnly = true)
    public List<PedidoEspecial> listar(Long obraId, boolean soloAbiertos) {
        if (obraId != null) {
            obraService.obtener(obraId);
            return soloAbiertos
                    ? pedidoEspecialRepository.findByObraIdAndEstadoInOrderByFechaSolicitudDescIdDesc(
                            obraId, EstadoPedidoEspecial.ABIERTOS)
                    : pedidoEspecialRepository.findByObraIdOrderByFechaSolicitudDescIdDesc(obraId);
        }
        Long empresaId = SesionActual.empresaId();
        return soloAbiertos
                ? pedidoEspecialRepository.deEmpresaEnEstados(empresaId, EstadoPedidoEspecial.ABIERTOS)
                : pedidoEspecialRepository.deEmpresa(empresaId);
    }

    private PedidoEspecial porBodega(Long id, BiConsumer<PedidoEspecial, Usuario> cambio) {
        Usuario bodega = usuarioRepository.findById(SesionActual.usuarioId())
                .filter(AccesoEmpresa::esPropio)
                .orElseThrow(() -> new NoSuchElementException("Usuario no encontrado"));
        return cambiar(id, p -> cambio.accept(p, bodega));
    }

    /**
     * Con la fila bloqueada: un bodeguero que entrega mientras el trabajador
     * cancela no pueden ver los dos el mismo estado y aplicar los dos cambios.
     */
    private PedidoEspecial cambiar(Long id, Consumer<PedidoEspecial> cambio) {
        PedidoEspecial pedido = obtener(id);
        entityManager.refresh(pedido, LockModeType.PESSIMISTIC_WRITE);
        cambio.accept(pedido);
        return pedidoEspecialRepository.save(pedido);
    }
}
