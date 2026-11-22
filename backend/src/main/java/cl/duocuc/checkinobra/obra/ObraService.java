package cl.duocuc.checkinobra.obra;

import cl.duocuc.checkinobra.config.UsuarioService;
import cl.duocuc.checkinobra.config.Usuario;
import cl.duocuc.checkinobra.config.RolUsuario;
import cl.duocuc.checkinobra.config.AccesoEmpresa;
import cl.duocuc.checkinobra.config.Empresa;
import cl.duocuc.checkinobra.config.EmpresaService;
import cl.duocuc.checkinobra.config.ConflictoException;
import cl.duocuc.checkinobra.control.AlertaRepository;
import cl.duocuc.checkinobra.inventario.PrestamoHerramientaRepository;
import jakarta.persistence.EntityManager;
import jakarta.persistence.LockModeType;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;
import java.util.NoSuchElementException;

@Service
@Transactional
public class ObraService {

    private final ObraRepository obraRepository;
    private final EmpresaService empresaService;
    private final PrestamoHerramientaRepository prestamoHerramientaRepository;
    private final AlertaRepository alertaRepository;
    private final UsuarioService usuarioService;
    private final EntityManager entityManager;

    public ObraService(
            ObraRepository obraRepository,
            EmpresaService empresaService,
            PrestamoHerramientaRepository prestamoHerramientaRepository,
            AlertaRepository alertaRepository,
            UsuarioService usuarioService,
            EntityManager entityManager) {
        this.obraRepository = obraRepository;
        this.empresaService = empresaService;
        this.prestamoHerramientaRepository = prestamoHerramientaRepository;
        this.alertaRepository = alertaRepository;
        this.usuarioService = usuarioService;
        this.entityManager = entityManager;
    }

    public Obra crear(
            Long empresaId, String nombre, String cliente, String ubicacion, Long jefeTerrenoId) {
        AccesoEmpresa.exigirEmpresa(empresaId);
        Empresa empresa = empresaService.obtener(empresaId);
        Obra obra = Obra.builder()
                .nombre(nombre)
                .cliente(cliente)
                .ubicacion(ubicacion)
                .estado(EstadoObra.ACTIVA)
                .empresa(empresa)
                .jefeTerreno(jefeTerrenoId == null ? null : jefeDeTerrenoValido(jefeTerrenoId))
                .build();
        return obraRepository.save(obra);
    }

    /** Asigna o cambia el jefe a cargo. Pasar {@code null} lo deja sin jefe. */
    public Obra asignarJefeDeTerreno(Long obraId, Long jefeTerrenoId) {
        Obra obra = obtener(obraId);
        obra.setJefeTerreno(jefeTerrenoId == null ? null : jefeDeTerrenoValido(jefeTerrenoId));
        return obraRepository.save(obra);
    }

    /**
     * Solo un JEFE_TERRENO o un ADMIN puede dirigir una obra. Un bodeguero o un
     * trabajador a cargo no tendrían los permisos que el puesto necesita —
     * cubicar, congelar el presupuesto— así que asignarlos sería crear una obra
     * que nadie puede llevar.
     */
    private Usuario jefeDeTerrenoValido(Long usuarioId) {
        Usuario candidato = usuarioService.obtener(usuarioId);
        if (candidato.getRol() != RolUsuario.JEFE_TERRENO && candidato.getRol() != RolUsuario.ADMIN) {
            throw new IllegalStateException(
                    "El jefe de una obra debe tener rol JEFE_TERRENO o ADMIN, y " + candidato.getNombre()
                            + " es " + candidato.getRol());
        }
        return candidato;
    }

    @Transactional(readOnly = true)
    public List<Obra> listarPorEmpresa(Long empresaId) {
        AccesoEmpresa.exigirEmpresa(empresaId);
        return obraRepository.findByEmpresaId(empresaId);
    }

    @Transactional(readOnly = true)
    public Obra obtener(Long id) {
        // Punto de paso de casi todo el sistema: partidas, presupuestos, kardex,
        // préstamos y alertas llegan a su obra por acá, así que comprobar la
        // empresa una vez acá los cubre a todos.
        return obraRepository.findById(id)
                .filter(AccesoEmpresa::esPropio)
                .orElseThrow(() -> new NoSuchElementException("Obra no encontrada: " + id));
    }

    /**
     * Valida las precondiciones que el mockup ya anticipaba (sin
     * herramientas fuera, sin alertas sin resolver) y solo entonces
     * invoca Obra.cerrar().
     */
    public Obra cerrarObra(Long obraId) {
        // Con el mismo bloqueo que toma quien registra en la obra: un despacho o
        // un préstamo en curso termina antes de que se cuenten las herramientas
        // fuera, y uno que llega después ya ve la obra cerrada.
        Obra obra = obtenerBloqueada(obraId);

        long herramientasFuera = prestamoHerramientaRepository.findByObraIdAndFechaDevolRealIsNull(obraId).size();
        if (herramientasFuera > 0) {
            throw new IllegalStateException(
                    "No se puede cerrar la obra: quedan " + herramientasFuera + " herramientas sin devolver");
        }

        long alertasSinResolver = alertaRepository.findByObraIdAndResueltoFalse(obraId).size();
        if (alertasSinResolver > 0) {
            throw new IllegalStateException(
                    "No se puede cerrar la obra: quedan " + alertasSinResolver + " alertas sin resolver");
        }

        obra.cerrar();
        return obraRepository.save(obra);
    }

    /**
     * La obra, bloqueada hasta el fin de la transacción, y solo si sigue abierta.
     *
     * <p>Es la puerta de todo lo que escribe en el inventario de una obra. El
     * bloqueo cierra dos carreras: dos despachos del mismo material que leen el
     * mismo saldo y dejan el stock negativo, y un movimiento que se cuela
     * mientras alguien cierra la obra. Serializar por obra es barato: en una
     * bodega registran uno o dos bodegueros, no cientos.
     */
    public Obra obtenerAbiertaParaRegistrar(Long obraId) {
        Obra obra = obtenerBloqueada(obraId);
        if (obra.getEstado() == EstadoObra.CERRADA) {
            throw new ConflictoException(ConflictoException.OBRA_CERRADA,
                    "La obra " + obra.getNombre() + " está cerrada: ya no se registran movimientos en ella");
        }
        return obra;
    }

    /**
     * La obra, bloqueada hasta el fin de la transacción, sin importar su estado.
     *
     * <p>{@code refresh} y no una consulta con bloqueo: si la obra ya se había
     * cargado en esta transacción —la trae en EAGER cualquier solicitud o
     * préstamo—, la consulta bloquearía la fila pero devolvería la copia vieja
     * en memoria, y el estado que se compara sería el de antes de esperar.
     */
    public Obra obtenerBloqueada(Long obraId) {
        Obra obra = obtener(obraId);
        entityManager.refresh(obra, LockModeType.PESSIMISTIC_WRITE);
        return obra;
    }
}
