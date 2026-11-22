package cl.duocuc.checkinobra.config;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.security.crypto.bcrypt.BCrypt;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Clock;
import java.time.Duration;
import java.util.Optional;

/**
 * Verifica credenciales con tres defensas contra la fuerza bruta (S-02, S-23):
 *
 * <ol>
 *   <li>Bloqueo creciente por cuenta y por IP. Un bloqueado recibe 429 sin que
 *       se mire su PIN, así que ni el correcto entra mientras dure.</li>
 *   <li>La clave de la cuenta es la misma por las dos rutas de login, de modo
 *       que alternar entre ellas no multiplica los intentos. Para una cuenta
 *       que no existe se usa el identificador recibido, y se bloquea igual:
 *       si solo las reales se bloquearan, el 429 delataría cuáles existen.</li>
 *   <li>Siempre se ejecuta un BCrypt, exista o no la cuenta, para que el
 *       tiempo de respuesta no distinga una de otra.</li>
 * </ol>
 *
 * <p>El PIN equivocado, la cuenta inexistente y el rol no permitido dan la
 * misma respuesta: {@link #CREDENCIALES_INVALIDAS}.
 */
@Service
public class AutenticacionService {

    static final String CREDENCIALES_INVALIDAS = "Credenciales inválidas";

    /**
     * Hash de relleno con el mismo costo que los reales (gensalt() por defecto),
     * calculado una vez al cargar la clase.
     */
    private static final String HASH_DE_RELLENO = BCrypt.hashpw("relleno-sin-uso", BCrypt.gensalt());

    private final UsuarioRepository usuarioRepository;
    private final CatalogoDeEmpresas catalogo;
    private final ResolutorDeBases resolutor;
    private final EventosDeSeguridad eventos;
    private final SesionService sesionService;
    private final LimitadorDeIntentos porCuenta;
    private final LimitadorDeIntentos porIp;

    @Autowired
    public AutenticacionService(
            UsuarioRepository usuarioRepository,
            CatalogoDeEmpresas catalogo,
            ResolutorDeBases resolutor,
            EventosDeSeguridad eventos,
            SesionService sesionService,
            @Value("${checkinobra.login.cuenta.max-fallos:5}") int cuentaMaxFallos,
            @Value("${checkinobra.login.cuenta.bloqueo-base-segundos:60}") long cuentaBloqueoBase,
            @Value("${checkinobra.login.cuenta.bloqueo-maximo-segundos:3600}") long cuentaBloqueoMaximo,
            @Value("${checkinobra.login.ip.max-fallos:30}") int ipMaxFallos,
            @Value("${checkinobra.login.ip.bloqueo-base-segundos:300}") long ipBloqueoBase,
            @Value("${checkinobra.login.ip.bloqueo-maximo-segundos:3600}") long ipBloqueoMaximo,
            @Value("${checkinobra.login.olvido-segundos:86400}") long olvido) {
        this(usuarioRepository, catalogo, resolutor, eventos, sesionService,
                new LimitadorDeIntentos(cuentaMaxFallos, Duration.ofSeconds(cuentaBloqueoBase),
                        Duration.ofSeconds(cuentaBloqueoMaximo), Duration.ofSeconds(olvido), Clock.systemUTC()),
                new LimitadorDeIntentos(ipMaxFallos, Duration.ofSeconds(ipBloqueoBase),
                        Duration.ofSeconds(ipBloqueoMaximo), Duration.ofSeconds(olvido), Clock.systemUTC()));
    }

    AutenticacionService(
            UsuarioRepository usuarioRepository, CatalogoDeEmpresas catalogo, ResolutorDeBases resolutor,
            EventosDeSeguridad eventos, SesionService sesionService,
            LimitadorDeIntentos porCuenta, LimitadorDeIntentos porIp) {
        this.usuarioRepository = usuarioRepository;
        this.catalogo = catalogo;
        this.resolutor = resolutor;
        this.eventos = eventos;
        this.sesionService = sesionService;
        this.porCuenta = porCuenta;
        this.porIp = porIp;
    }

    /**
     * Login por correo + clave: los cuatro roles.
     *
     * <p>No es transaccional: hay que saber de qué empresa es el correo, y eso se lee del
     * índice del catálogo, antes de poder abrir la base de esa empresa. Un correo que no
     * está en el índice se trata como una cuenta que no existe.
     */
    public Usuario loginPorCorreo(String email, String clave, String ip) {
        Optional<Long> empresaId = catalogo.empresaDeCorreo(email).filter(resolutor::conoce);
        Optional<Usuario> usuario = empresaId.flatMap(id -> TenantContext.ejecutarEn(id,
                () -> usuarioRepository.findByEmail(email)
                        .filter(u -> u.autenticarPorEmail(email))
                        .filter(u -> esDeLaEmpresa(u, id))));
        String claveCuenta = usuario.map(u -> claveDeCuenta(u.getEmpresa().getId(), u.getId()))
                .orElse("e:" + (email == null ? "" : email.trim().toLowerCase()));
        return verificar(usuario, clave, claveCuenta, ip);
    }

    /**
     * Login por id + PIN: solo TRABAJADOR, que ya está identificado en su teléfono.
     *
     * @param empresaId la empresa que la app recuerda junto al usuario. Los ids de usuario
     *     se repiten entre bases, así que sin la empresa no se sabe en cuál buscar. Si no
     *     viene y hay una sola empresa se usa esa (una app anterior a esto), y con varias
     *     no se puede resolver y se trata como una cuenta que no existe.
     */
    public Usuario loginPorPin(Long usuarioId, Long empresaId, String pin, String ip) {
        Optional<Long> empresa = elegirEmpresa(empresaId);
        Optional<Usuario> usuario = empresa.flatMap(id -> TenantContext.ejecutarEn(id,
                () -> usuarioRepository.findById(usuarioId).filter(u -> esDeLaEmpresa(u, id))));
        String claveCuenta = usuario.map(u -> claveDeCuenta(u.getEmpresa().getId(), u.getId()))
                .orElse("i:" + empresaId + ":" + usuarioId);
        // Un ADMIN, JEFE_TERRENO o BODEGUERO no entra por acá aunque acierte: su
        // clave es larga y el id es secuencial, justo lo que facilita adivinar.
        Optional<Usuario> permitido = usuario.filter(u -> u.getRol() == RolUsuario.TRABAJADOR);
        return verificar(permitido, pin, claveCuenta, ip);
    }

    private Optional<Long> elegirEmpresa(Long empresaId) {
        if (empresaId != null) {
            return Optional.of(empresaId).filter(resolutor::conoce);
        }
        var todas = resolutor.empresas();
        return todas.size() == 1 ? todas.stream().findFirst() : Optional.empty();
    }

    /**
     * Segunda comprobación, además de abrir la base de esa empresa: el usuario encontrado tiene
     * que ser de ella. Con una base por empresa siempre lo es; si la base fuera compartida (como
     * la de la suite de pruebas, o una mal registrada) esto evita entrar con la empresa equivocada.
     */
    private static boolean esDeLaEmpresa(Usuario usuario, Long empresaId) {
        return usuario.getEmpresa() != null && empresaId.equals(usuario.getEmpresa().getId());
    }

    /** Los ids de usuario se repiten entre bases: la clave del bloqueo incluye la empresa. */
    private static String claveDeCuenta(Long empresaId, Long usuarioId) {
        return "u:" + empresaId + ":" + usuarioId;
    }

    /**
     * El usuario cambia su propia clave. Exige la actual (y cuenta los fallos como
     * cualquier login: quien robó un token no puede adivinarla sin límite), una
     * nueva distinta que cumpla la política de su rol, y limpia la obligación de
     * cambiarla.
     */
    @Transactional
    public Usuario cambiarPin(Long usuarioId, String pinActual, String pinNuevo, String ip) {
        Usuario usuario = usuarioRepository.findById(usuarioId)
                .orElseThrow(() -> new IllegalArgumentException(CREDENCIALES_INVALIDAS));
        verificar(Optional.of(usuario), pinActual, claveDeCuenta(usuario.getEmpresa().getId(), usuario.getId()), ip);
        if (pinNuevo != null && pinNuevo.equals(pinActual)) {
            throw new IllegalArgumentException("La clave nueva debe ser distinta de la actual");
        }
        usuario.definirPin(pinNuevo);
        // Una clave nueva deja sin efecto las demás sesiones del usuario: el token que ya tenía y
        // sus refresh tokens. La respuesta trae una sesión nueva.
        usuario.invalidarSesiones();
        Usuario guardado = usuarioRepository.save(usuario);
        sesionService.revocarTodos(guardado.getId());
        eventos.claveCambiada(guardado.getId(), ip);
        return guardado;
    }

    private Usuario verificar(Optional<Usuario> usuario, String clave, String claveCuenta, String ip) {
        try {
            exigirNoBloqueado(claveCuenta, ip);
        } catch (DemasiadosIntentosException e) {
            eventos.loginBloqueado(ip);
            throw e;
        }
        boolean correcta = comprobar(usuario, clave);
        if (!correcta) {
            porCuenta.registrarFallo(claveCuenta);
            porIp.registrarFallo(ip);
            eventos.loginFallido(usuario.map(Usuario::getId).orElse(null), ip);
            throw new IllegalArgumentException(CREDENCIALES_INVALIDAS);
        }
        // El acierto limpia la cuenta pero no la IP: quien tiene una cuenta
        // propia no debería poder reiniciar así el contador con que prueba las ajenas.
        porCuenta.registrarExito(claveCuenta);
        Usuario autenticado = usuario.orElseThrow();
        eventos.loginExitoso(autenticado, ip);
        return autenticado;
    }

    private void exigirNoBloqueado(String claveCuenta, String ip) {
        Optional<Duration> espera = porCuenta.bloqueoRestante(claveCuenta);
        Optional<Duration> esperaIp = porIp.bloqueoRestante(ip);
        if (espera.isPresent() || esperaIp.isPresent()) {
            Duration mayor = espera.orElse(Duration.ZERO).compareTo(esperaIp.orElse(Duration.ZERO)) >= 0
                    ? espera.orElse(Duration.ZERO) : esperaIp.orElse(Duration.ZERO);
            throw new DemasiadosIntentosException(mayor);
        }
    }

    /** Un BCrypt siempre, haya o no cuenta con credencial: ver la nota de la clase. */
    private static boolean comprobar(Optional<Usuario> usuario, String clave) {
        String candidata = clave == null ? "" : clave;
        if (usuario.isPresent() && usuario.get().getPinHash() != null) {
            return BCrypt.checkpw(candidata, usuario.get().getPinHash());
        }
        BCrypt.checkpw(candidata, HASH_DE_RELLENO);
        return false;
    }
}
