package cl.duocuc.checkinobra.config;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.security.SecureRandom;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.util.Base64;
import java.util.HexFormat;

/**
 * Los refresh tokens (SEG10, #98): permiten un token de acceso corto sin pedir la clave cada rato.
 *
 * <p>El valor es {@code <empresaId>.<aleatorio>}: la empresa va a la vista porque el refresh se
 * presenta sin token de acceso y hay que saber qué base abrir; el aleatorio son 256 bits y de él
 * solo se guarda el hash (SHA-256). Cada uso lo reemplaza por otro (rotación). Si se presenta uno
 * ya usado se asume que fue copiado: se revocan todos los del usuario y deja de valer su sesión.
 *
 * <p>Todos los métodos corren con la empresa del usuario en el {@link TenantContext}.
 */
@Service
@Transactional
public class SesionService {

    private static final SecureRandom AZAR = new SecureRandom();

    private final RefreshTokenRepository refreshTokenRepository;
    private final UsuarioRepository usuarioRepository;
    private final EventosDeSeguridad eventos;
    private final Duration vida;
    private final Clock reloj;

    @org.springframework.beans.factory.annotation.Autowired
    public SesionService(
            RefreshTokenRepository refreshTokenRepository,
            UsuarioRepository usuarioRepository,
            EventosDeSeguridad eventos,
            @Value("${checkinobra.jwt.refresh-dias:7}") long dias) {
        this(refreshTokenRepository, usuarioRepository, eventos, Duration.ofDays(dias), Clock.systemUTC());
    }

    SesionService(
            RefreshTokenRepository refreshTokenRepository,
            UsuarioRepository usuarioRepository,
            EventosDeSeguridad eventos,
            Duration vida,
            Clock reloj) {
        this.refreshTokenRepository = refreshTokenRepository;
        this.usuarioRepository = usuarioRepository;
        this.eventos = eventos;
        this.vida = vida;
        this.reloj = reloj;
    }

    /** Emite un refresh token para el usuario y devuelve su valor (la única vez que se ve). */
    public String emitir(Usuario usuario) {
        return crear(usuario).valor();
    }

    /**
     * Canjea un refresh token por un usuario con sesión vigente y deja revocado el presentado.
     * El llamador emite el nuevo par de tokens.
     *
     * @throws SesionInvalidaException si no existe, venció, está revocado, o ya no corresponde a la sesión del usuario
     */
    // noRollbackFor: al reutilizar un token ya usado se revocan todos y recién entonces se lanza
    // la excepción; sin esto la transacción deshace esa revocación.
    @Transactional(noRollbackFor = SesionInvalidaException.class)
    public Rotado rotar(String valor) {
        RefreshToken actual = refreshTokenRepository.findByHash(hash(secretoDe(valor)))
                .orElseThrow(SesionInvalidaException::new);
        Usuario usuario = actual.getUsuario();
        Instant ahora = reloj.instant();
        if (actual.getRevocadoEn() != null) {
            // Ya se usó (o se cerró la sesión): quien lo presenta o el dueño tiene una copia.
            refreshTokenRepository.revocarTodosDe(usuario.getId(), ahora);
            eventos.refreshReutilizado(usuario.getId());
            throw new SesionInvalidaException();
        }
        if (!actual.getExpiraEn().isAfter(ahora) || actual.getTokenVersion() != usuario.getTokenVersion()) {
            throw new SesionInvalidaException();
        }
        Emitido nuevo = crear(usuario);
        actual.setRevocadoEn(ahora);
        actual.setReemplazadoPor(nuevo.id());
        refreshTokenRepository.save(actual);
        eventos.sesionRefrescada(usuario.getId());
        return new Rotado(usuario, nuevo.valor());
    }

    /** Cierra una sesión: revoca ese refresh token. Si no existe, no hace nada ni lo dice. */
    public void revocar(String valor) {
        refreshTokenRepository.findByHash(hash(secretoDe(valor))).ifPresent(r -> {
            if (r.getRevocadoEn() == null) {
                r.setRevocadoEn(reloj.instant());
                refreshTokenRepository.save(r);
                eventos.sesionCerrada(r.getUsuario().getId());
            }
        });
    }

    /** Revoca todos los refresh tokens del usuario, por ejemplo al restablecer su clave. */
    public void revocarTodos(Long usuarioId) {
        refreshTokenRepository.revocarTodosDe(usuarioId, reloj.instant());
    }

    /** La empresa que dice el valor, para abrir su base antes de buscarlo; vacío si el formato no es el esperado. */
    public static java.util.Optional<Long> empresaDe(String valor) {
        if (valor == null) {
            return java.util.Optional.empty();
        }
        int punto = valor.indexOf('.');
        if (punto <= 0 || punto == valor.length() - 1) {
            return java.util.Optional.empty();
        }
        try {
            return java.util.Optional.of(Long.parseLong(valor.substring(0, punto)));
        } catch (NumberFormatException e) {
            return java.util.Optional.empty();
        }
    }

    /** El usuario y el refresh token que reemplaza al presentado. */
    public record Rotado(Usuario usuario, String refreshToken) {
    }

    private record Emitido(Long id, String valor) {
    }

    private Emitido crear(Usuario usuario) {
        byte[] bytes = new byte[32];
        AZAR.nextBytes(bytes);
        String secreto = Base64.getUrlEncoder().withoutPadding().encodeToString(bytes);
        Instant ahora = reloj.instant();
        RefreshToken guardado = refreshTokenRepository.save(RefreshToken.builder()
                .usuario(usuario)
                .hash(hash(secreto))
                .tokenVersion(usuario.getTokenVersion())
                .creadoEn(ahora)
                .expiraEn(ahora.plus(vida))
                .build());
        return new Emitido(guardado.getId(), usuario.getEmpresa().getId() + "." + secreto);
    }

    private static String secretoDe(String valor) {
        int punto = valor == null ? -1 : valor.indexOf('.');
        if (punto <= 0 || punto == valor.length() - 1) {
            throw new SesionInvalidaException();
        }
        return valor.substring(punto + 1);
    }

    private static String hash(String secreto) {
        try {
            return HexFormat.of().formatHex(
                    MessageDigest.getInstance("SHA-256").digest(secreto.getBytes(StandardCharsets.UTF_8)));
        } catch (NoSuchAlgorithmException e) {
            throw new IllegalStateException(e);
        }
    }
}
