package cl.duocuc.checkinobra.config;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;
import java.util.NoSuchElementException;

@Service
@Transactional
public class UsuarioService {

    private final UsuarioRepository usuarioRepository;
    private final EmpresaService empresaService;
    private final CatalogoDeEmpresas catalogo;
    private final SesionService sesionService;
    private final EventosDeSeguridad eventos;

    public UsuarioService(
            UsuarioRepository usuarioRepository, EmpresaService empresaService, CatalogoDeEmpresas catalogo,
            SesionService sesionService, EventosDeSeguridad eventos) {
        this.usuarioRepository = usuarioRepository;
        this.empresaService = empresaService;
        this.catalogo = catalogo;
        this.sesionService = sesionService;
        this.eventos = eventos;
    }

    /** Corresponde a Empresa.registrarUsuario(u) del diagrama, orquestado desde el servicio. */
    public Usuario crear(
            Long empresaId, String nombre, String email, String rut, RolUsuario rol, String pinInicial) {
        AccesoEmpresa.exigirEmpresa(empresaId);
        if (rol == RolUsuario.PLATAFORMA) {
            throw new IllegalArgumentException("PLATAFORMA no es un rol de empresa");
        }
        // Sin distinguir mayúsculas: el índice de login guarda el correo en minúsculas, y dos usuarios
        // de una misma empresa que solo difieran en eso no se podrían distinguir al entrar.
        if (usuarioRepository.existsByEmailIgnoreCase(email)) {
            throw new IllegalStateException("Ya existe un usuario con ese correo");
        }
        // El RUT identifica a la persona en toda la cadena: quien recibe un
        // despacho, quien tiene una herramienta y quien dirige la obra se
        // muestran por nombre y RUT.
        //
        // Se normaliza antes de comparar: "14109556-0" y "14.109.556-0" son la
        // misma persona, y el UNIQUE de la columna solo lo ve si llegan escritos
        // igual.
        rut = Rut.normalizar(rut);
        if (usuarioRepository.existsByRut(rut)) {
            throw new IllegalStateException("Ya existe un usuario con ese RUT");
        }
        Empresa empresa = empresaService.obtener(empresaId);
        Usuario usuario = Usuario.builder()
                .nombre(nombre)
                .email(email)
                .rut(rut)
                .rol(rol)
                .build();
        empresa.registrarUsuario(usuario);
        if (pinInicial != null) {
            usuario.definirPin(pinInicial);
        }
        // El correo es único en todo el sistema y el login lo usa para saber qué base
        // abrir: se reserva en el índice del catálogo antes de guardar. Son dos bases sin
        // transacción compartida, así que si guardar falla se suelta la reserva.
        if (!catalogo.reservarCorreo(email, empresaId)) {
            throw new IllegalStateException("Ya existe un usuario con ese correo");
        }
        try {
            Usuario creado = usuarioRepository.saveAndFlush(usuario);
            eventos.usuarioCreado(actorId(), creado.getId(), creado.getRol());
            return creado;
        } catch (RuntimeException e) {
            catalogo.liberarCorreo(email, empresaId);
            throw e;
        }
    }

    @Transactional(readOnly = true)
    public List<Usuario> listarPorEmpresa(Long empresaId) {
        AccesoEmpresa.exigirEmpresa(empresaId);
        return usuarioRepository.findByEmpresaId(empresaId);
    }

    @Transactional(readOnly = true)
    public List<Usuario> listarPorEmpresaYRol(Long empresaId, RolUsuario rol) {
        AccesoEmpresa.exigirEmpresa(empresaId);
        return usuarioRepository.findByEmpresaIdAndRol(empresaId, rol);
    }

    @Transactional(readOnly = true)
    public Usuario obtener(Long id) {
        return usuarioRepository.findById(id)
                .filter(AccesoEmpresa::esPropio)
                .orElseThrow(() -> new NoSuchElementException("Usuario no encontrado: " + id));
    }

    public Usuario redefinirPin(Long usuarioId, String nuevoPin) {
        Usuario usuario = obtener(usuarioId);
        usuario.definirPin(nuevoPin);
        // Restablecer la clave cierra las sesiones abiertas del usuario: su token deja de valer
        // (sube la versión) y sus refresh tokens se revocan.
        usuario.invalidarSesiones();
        Usuario guardado = usuarioRepository.save(usuario);
        sesionService.revocarTodos(guardado.getId());
        eventos.claveRestablecida(actorId(), guardado.getId());
        return guardado;
    }

    /** Quién actúa, para el registro de eventos; nulo si no hay sesión (una tarea interna). */
    private static Long actorId() {
        try {
            return SesionActual.usuarioId();
        } catch (RuntimeException e) {
            return null;
        }
    }
}
