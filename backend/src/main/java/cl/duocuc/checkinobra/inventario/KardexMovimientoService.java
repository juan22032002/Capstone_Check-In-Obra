package cl.duocuc.checkinobra.inventario;

import cl.duocuc.checkinobra.obra.TrabajadorService;
import cl.duocuc.checkinobra.obra.Trabajador;
import cl.duocuc.checkinobra.config.AccesoEmpresa;
import cl.duocuc.checkinobra.config.ConflictoException;
import cl.duocuc.checkinobra.config.Usuario;
import cl.duocuc.checkinobra.config.UsuarioRepository;
import cl.duocuc.checkinobra.cubicacion.Material;
import cl.duocuc.checkinobra.cubicacion.MaterialService;
import cl.duocuc.checkinobra.obra.Obra;
import cl.duocuc.checkinobra.obra.ObraService;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.List;
import java.util.NoSuchElementException;

@Service
@Transactional
public class KardexMovimientoService {

    private final KardexMovimientoRepository kardexMovimientoRepository;
    private final ObraService obraService;
    private final MaterialService materialService;
    private final UsuarioRepository usuarioRepository;
    private final TrabajadorService trabajadorService;

    public KardexMovimientoService(
            KardexMovimientoRepository kardexMovimientoRepository,
            ObraService obraService,
            MaterialService materialService,
            UsuarioRepository usuarioRepository,
            TrabajadorService trabajadorService) {
        this.kardexMovimientoRepository = kardexMovimientoRepository;
        this.obraService = obraService;
        this.materialService = materialService;
        this.usuarioRepository = usuarioRepository;
        this.trabajadorService = trabajadorService;
    }

    /**
     * Holgura para comparar saldos: la cantidad es {@code double} y el saldo es
     * una suma de muchas, así que 0,1 + 0,2 no da exactamente 0,3.
     */
    private static final double TOLERANCIA = 1e-6;

    /**
     * KardexMovimiento.registrar() del diagrama, orquestado: valida que
     * un DESPACHO o CONSUMO no deje el stock de la obra en negativo — el
     * mismo bloqueo que ya anticipaba la pantalla de despacho.
     *
     * <p>La obra se bloquea <b>antes</b> de leer el saldo. Sin eso, dos despachos
     * simultáneos del mismo material leían el mismo saldo, los dos pasaban la
     * validación y el stock quedaba negativo.
     *
     * @param usuarioId quien registra; lo pone el controlador desde el token,
     *     nunca desde el cuerpo de la petición
     */
    public KardexMovimiento registrarMovimiento(
            Long obraId,
            Long materialId,
            Long usuarioId,
            Long trabajadorId,
            TipoMovimiento tipo,
            double cantidad) {
        return registrarMovimiento(obraId, materialId, usuarioId, trabajadorId, tipo, cantidad, null);
    }

    /**
     * Igual que el anterior, con el costo real de compra.
     *
     * @param costoUnitario lo que se pagó por unidad según la factura; solo en
     *     una RECEPCION, y opcional también ahí
     */
    public KardexMovimiento registrarMovimiento(
            Long obraId,
            Long materialId,
            Long usuarioId,
            Long trabajadorId,
            TipoMovimiento tipo,
            double cantidad,
            BigDecimal costoUnitario) {
        Obra obra = obraService.obtenerAbiertaParaRegistrar(obraId);
        Material material = materialService.obtener(materialId);
        Usuario usuario = usuarioRepository.findById(usuarioId)
                .filter(AccesoEmpresa::esPropio)
                .orElseThrow(() -> new NoSuchElementException("Usuario no encontrado: " + usuarioId));

        Trabajador receptor = resolverReceptor(tipo, trabajadorId, obraId);

        if (tipo != TipoMovimiento.RECEPCION) {
            double stockActual = kardexMovimientoRepository.calcularStock(obraId, materialId);
            if (cantidad > stockActual + TOLERANCIA) {
                throw new ConflictoException(ConflictoException.STOCK_INSUFICIENTE,
                        "Stock insuficiente: quedan " + stockActual + " y se pidieron " + cantidad);
            }
        }

        KardexMovimiento movimiento = KardexMovimiento.builder()
                .obra(obra)
                .material(material)
                .usuario(usuario)
                .trabajador(receptor)
                .tipoMovimiento(tipo)
                .cantidad(cantidad)
                .costoUnitario(costoUnitario)
                .fecha(LocalDateTime.now())
                .build();
        movimiento.registrar();
        return kardexMovimientoRepository.save(movimiento);
    }

    /**
     * Quién se lleva el material.
     *
     * <p>Un DESPACHO sin receptor deja el kardex sin poder responder "¿a quién se
     * le entregaron esas 36 planchas?", que es justo lo que el bodeguero necesita
     * cuando aparece un descuadre. Un CONSUMO puede no tenerlo —es material que
     * se gastó en la obra, no que alguien se llevó— y una RECEPCION nunca lo
     * tiene, porque el material entra desde un proveedor.
     */
    private Trabajador resolverReceptor(TipoMovimiento tipo, Long trabajadorId, Long obraId) {
        if (tipo == TipoMovimiento.RECEPCION) {
            if (trabajadorId != null) {
                throw new IllegalArgumentException(
                        "Una recepción no tiene trabajador receptor: el material entra desde un proveedor");
            }
            return null;
        }
        if (tipo == TipoMovimiento.DESPACHO && trabajadorId == null) {
            throw new IllegalArgumentException("Un despacho debe indicar a qué trabajador se le entrega");
        }
        if (trabajadorId == null) {
            return null;
        }
        Trabajador receptor = trabajadorService.obtener(trabajadorId);
        trabajadorService.exigirQueSeaDeLaObra(receptor, obraId);
        return receptor;
    }

    /** Stock actual = suma con signo de los movimientos de ese material en esa obra. */
    @Transactional(readOnly = true)
    public double stockActual(Long obraId, Long materialId) {
        obraService.obtener(obraId);
        return kardexMovimientoRepository.calcularStock(obraId, materialId);
    }

    @Transactional(readOnly = true)
    public List<KardexMovimiento> listarPorObra(Long obraId) {
        obraService.obtener(obraId);
        return kardexMovimientoRepository.findByObraId(obraId);
    }
}
