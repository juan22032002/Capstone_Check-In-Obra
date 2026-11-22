package cl.duocuc.checkinobra.config;

import io.jsonwebtoken.Claims;
import io.jsonwebtoken.Jwts;
import io.jsonwebtoken.security.Keys;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import javax.crypto.SecretKey;
import java.nio.charset.StandardCharsets;
import java.util.Date;

/**
 * Emite y valida los JWT que resultan de Usuario.autenticar()/
 * autenticarPorEmail(). El token lleva el id de usuario, su rol y su
 * empresa — lo mínimo que necesita el resto de la API para autorizar.
 */
@Component
public class JwtService {

    /** HS256 exige al menos 256 bits; menos que eso se adivina por fuerza bruta. */
    static final int MIN_BYTES_SECRETO = 32;

    /**
     * Todo valor de ejemplo que se haya publicado empieza así: el que estuvo en
     * application.properties y el marcador de .env.example. Rechazar el prefijo
     * y no solo el valor exacto cubre también una copia con otro formato.
     */
    private static final String PREFIJO_DE_EJEMPLO = "cambiar";

    public static final String EMISOR = "checkinobra";
    public static final String AUDIENCIA = "checkinobra-api";

    private final SecretKey key;
    private final long expiracionMinutos;

    public JwtService(
            @Value("${checkinobra.jwt.secret}") String secret,
            @Value("${checkinobra.jwt.expiracion-minutos:30}") long expiracionMinutos) {
        this.key = Keys.hmacShaKeyFor(exigirSecretoSeguro(secret).getBytes(StandardCharsets.UTF_8));
        this.expiracionMinutos = expiracionMinutos;
    }

    /**
     * La API no arranca sin un secreto propio. Con un valor por defecto
     * publicado en el repo, cualquiera firmaba un token con {@code rol=ADMIN} y
     * la empresa que quisiera (S-01). El mensaje nunca incluye el valor
     * recibido: un secreto mal pegado no debe terminar en los logs.
     */
    static String exigirSecretoSeguro(String secreto) {
        if (secreto == null || secreto.isBlank()) {
            throw new IllegalStateException(
                    "Falta JWT_SECRET. Defínelo en el .env (ver .env.example); "
                            + "genera uno con: openssl rand -base64 48");
        }
        String limpio = secreto.trim();
        if (limpio.toLowerCase(java.util.Locale.ROOT).startsWith(PREFIJO_DE_EJEMPLO)) {
            throw new IllegalStateException(
                    "JWT_SECRET es el valor de ejemplo del repositorio y no es seguro. "
                            + "Genera uno propio con: openssl rand -base64 48");
        }
        if (limpio.getBytes(StandardCharsets.UTF_8).length < MIN_BYTES_SECRETO) {
            throw new IllegalStateException(
                    "JWT_SECRET debe tener al menos " + MIN_BYTES_SECRETO
                            + " bytes. Genera uno con: openssl rand -base64 48");
        }
        return limpio;
    }

    public String emitir(Usuario usuario) {
        Date ahora = new Date();
        Date expira = new Date(ahora.getTime() + expiracionMinutos * 60_000);
        return Jwts.builder()
                .subject(usuario.getId().toString())
                .claim("email", usuario.getEmail())
                .claim("rol", usuario.getRol().name())
                .claim("empresaId", usuario.getEmpresa().getId())
                // La versión de sesión con que se emite: si el usuario la sube (clave restablecida),
                // este token deja de valer aunque no haya vencido.
                .claim("tv", usuario.getTokenVersion())
                // Quién lo emitió y para quién: un token firmado con la misma clave pero para otro
                // servicio no se acepta acá.
                .issuer(EMISOR)
                .audience().add(AUDIENCIA).and()
                // Solo viaja cuando es verdadero: la cuenta está limitada a cambiar su clave.
                .claim("cambiarPin", usuario.isDebeCambiarPin() ? Boolean.TRUE : null)
                .issuedAt(ahora)
                .expiration(expira)
                .signWith(key)
                .compact();
    }

    /**
     * El token de un operador de plataforma: sin {@code empresaId} (no pertenece a ninguna) y con
     * {@code rol=PLATAFORMA}. El filtro lo distingue por ese rol y lo revalida contra el catálogo.
     */
    public String emitirParaOperador(CatalogoDeEmpresas.OperadorRegistrado operador) {
        Date ahora = new Date();
        return Jwts.builder()
                .subject(operador.id().toString())
                .claim("email", operador.email())
                .claim("rol", RolUsuario.PLATAFORMA.name())
                .claim("tv", operador.tokenVersion())
                .issuer(EMISOR)
                .audience().add(AUDIENCIA).and()
                .issuedAt(ahora)
                .expiration(new Date(ahora.getTime() + expiracionMinutos * 60_000))
                .signWith(key)
                .compact();
    }

    public Claims validarYExtraer(String token) {
        return Jwts.parser()
                .verifyWith(key)
                .requireIssuer(EMISOR)
                .requireAudience(AUDIENCIA)
                .build()
                .parseSignedClaims(token)
                .getPayload();
    }
}
