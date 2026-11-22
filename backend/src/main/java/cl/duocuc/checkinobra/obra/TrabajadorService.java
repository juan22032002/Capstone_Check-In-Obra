package cl.duocuc.checkinobra.obra;

import cl.duocuc.checkinobra.config.AccesoDenegadoException;
import cl.duocuc.checkinobra.config.AccesoEmpresa;
import cl.duocuc.checkinobra.config.ConflictoException;
import cl.duocuc.checkinobra.config.RolUsuario;
import cl.duocuc.checkinobra.config.SesionActual;
import cl.duocuc.checkinobra.config.Usuario;
import cl.duocuc.checkinobra.config.UsuarioService;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;
import java.util.NoSuchElementException;
import java.util.UUID;

@Service
@Transactional
public class TrabajadorService {

    private final TrabajadorRepository trabajadorRepository;
    private final UsuarioService usuarioService;
    private final CuadrillaService cuadrillaService;
    private final ObraService obraService;

    public TrabajadorService(
            TrabajadorRepository trabajadorRepository,
            UsuarioService usuarioService,
            CuadrillaService cuadrillaService,
            ObraService obraService) {
        this.trabajadorRepository = trabajadorRepository;
        this.usuarioService = usuarioService;
        this.cuadrillaService = cuadrillaService;
        this.obraService = obraService;
    }

    public Trabajador crear(Long usuarioId, Long cuadrillaId) {
        // Por el servicio y no por el repositorio: así un usuario de otra empresa
        // da el mismo 404 que uno inexistente. Con findById, un ADMIN ajeno creaba
        // la ficha de un usuario que no era suyo y recibía su credencial QR (S-06).
        Usuario usuario = usuarioService.obtener(usuarioId);
        if (usuario.getRol() != RolUsuario.TRABAJADOR) {
            throw new IllegalStateException("Solo un Usuario con rol TRABAJADOR puede extenderse a Trabajador");
        }
        Cuadrilla cuadrilla = cuadrillaId != null ? cuadrillaService.obtener(cuadrillaId) : null;
        Trabajador trabajador = Trabajador.builder()
                .usuario(usuario)
                .cuadrilla(cuadrilla)
                .credencialQr(UUID.randomUUID().toString())
                .build();
        return trabajadorRepository.save(trabajador);
    }

    @Transactional(readOnly = true)
    public Trabajador obtener(Long id) {
        return trabajadorRepository.findById(id)
                .filter(AccesoEmpresa::esPropio)
                .orElseThrow(() -> new NoSuchElementException("Trabajador no encontrado: " + id));
    }

    /** La ficha de trabajador de un usuario: la de quien está pidiendo algo. */
    @Transactional(readOnly = true)
    public Trabajador obtenerPorUsuario(Long usuarioId) {
        return trabajadorRepository.findByUsuarioId(usuarioId)
                .filter(AccesoEmpresa::esPropio)
                .orElseThrow(() -> new NoSuchElementException("El usuario " + usuarioId + " no tiene ficha de trabajador"));
    }

    @Transactional(readOnly = true)
    public Trabajador buscarPorCredencialQr(String credencialQr) {
        // Un QR de otra empresa no se resuelve, aunque el código sea válido.
        return trabajadorRepository.findByCredencialQr(credencialQr)
                .filter(AccesoEmpresa::esPropio)
                .orElseThrow(() -> new NoSuchElementException("Credencial no reconocida"));
    }

    @Transactional(readOnly = true)
    public List<Trabajador> listarPorCuadrilla(Long cuadrillaId) {
        // Se valida la cuadrilla antes de consultar: una ajena responde como una
        // que no existe en vez de devolver nombre y RUT de otra empresa (S-05).
        cuadrillaService.obtener(cuadrillaId);
        return trabajadorRepository.findByCuadrillaId(cuadrillaId);
    }

    @Transactional(readOnly = true)
    public List<Trabajador> listarPorObra(Long obraId) {
        obraService.obtener(obraId);
        return trabajadorRepository.findByCuadrilla_ObraId(obraId);
    }

    /** Renueva el QR de la credencial (pantalla TrabCredencial · "Renovar código"). */
    public Trabajador renovarCredencial(Long trabajadorId) {
        Trabajador trabajador = obtener(trabajadorId);
        trabajador.setCredencialQr(UUID.randomUUID().toString());
        return trabajadorRepository.save(trabajador);
    }

    /**
     * La ficha de quien llama, con su credencial lista para mostrarse.
     *
     * <p>Un trabajador creado antes de que la credencial se emitiera al darlo de
     * alta puede no tener una. En vez de dejarlo sin QR hasta que un
     * administrador lo note, se le emite al abrir su pantalla.
     */
    public Trabajador miFicha() {
        Trabajador yo = obtenerPorUsuario(SesionActual.usuarioId());
        if (yo.getCredencialQr() == null) {
            yo.setCredencialQr(UUID.randomUUID().toString());
            yo = trabajadorRepository.save(yo);
        }
        return yo;
    }

    /** El trabajador renueva su propia credencial, por ejemplo si le fotografiaron el QR. */
    public Trabajador renovarMiCredencial() {
        return renovarCredencial(obtenerPorUsuario(SesionActual.usuarioId()).getId());
    }

    /**
     * Si quien llama es un trabajador, el dato tiene que ser suyo.
     *
     * <p>Para los demás roles no hace nada: el bodeguero y el jefe ven lo de
     * toda la obra. Es 403 y no 404 porque el trabajador del que se pregunta es
     * de la misma empresa —ya pasó el filtro de empresa—, así que no hay nada
     * que enumerar: lo que falta es permiso, no existencia.
     */
    @Transactional(readOnly = true)
    public void exigirQueSeaPropio(Long trabajadorId) {
        if (!SesionActual.esTrabajador()) {
            return;
        }
        if (!obtenerPorUsuario(SesionActual.usuarioId()).getId().equals(trabajadorId)) {
            throw new AccesoDenegadoException("Un trabajador solo puede ver lo suyo");
        }
    }

    /**
     * Para los listados por obra: un trabajador no los usa, porque verían lo de
     * sus compañeros. Lo suyo lo pide por su id o por las rutas "mías".
     */
    public static void exigirQueNoSeaTrabajador() {
        if (SesionActual.esTrabajador()) {
            throw new AccesoDenegadoException("Un trabajador solo puede ver lo suyo");
        }
    }

    /**
     * El trabajador está asignado a esa obra (por su cuadrilla). Sin esto, un despacho o un préstamo
     * podía quedar a nombre de alguien de otra obra, o sin cuadrilla, y el kardex perdía el dato que
     * lo justifica: a quién se le entregó y dónde trabaja.
     */
    public void exigirQueSeaDeLaObra(Trabajador trabajador, Long obraId) {
        Obra asignada = obraAsignada(trabajador);
        if (!asignada.getId().equals(obraId)) {
            throw new ConflictoException(ConflictoException.OBRA_NO_ASIGNADA,
                    "El trabajador no pertenece a esta obra: está asignado a " + asignada.getNombre());
        }
    }

    /**
     * La obra desde la que un trabajador puede pedir: la de su cuadrilla. Sin
     * cuadrilla no tiene ninguna, y una solicitud suya no tendría a qué bodega
     * llegar.
     */
    public Obra obraAsignada(Trabajador trabajador) {
        if (trabajador.getCuadrilla() == null) {
            throw new ConflictoException(ConflictoException.SIN_CUADRILLA,
                    "No estás asignado a ninguna cuadrilla: pídele a tu jefe de obra que te asigne una");
        }
        return trabajador.getCuadrilla().getObra();
    }
}
