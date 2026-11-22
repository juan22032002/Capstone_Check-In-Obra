package cl.duocuc.checkinobra.plataforma;

import cl.duocuc.checkinobra.config.CatalogoDeEmpresas;
import cl.duocuc.checkinobra.config.CatalogoDeEmpresas.OperadorRegistrado;
import cl.duocuc.checkinobra.config.DemasiadosIntentosException;
import cl.duocuc.checkinobra.config.EventosDeSeguridad;
import cl.duocuc.checkinobra.config.LimitadorDeIntentos;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.security.crypto.bcrypt.BCrypt;
import org.springframework.stereotype.Service;

import java.time.Clock;
import java.time.Duration;
import java.util.Optional;

/**
 * El login del operador de plataforma (MT6, #109), con las mismas defensas que el de una empresa:
 * bloqueo creciente por cuenta y por IP, un BCrypt siempre (exista o no el operador) y la misma
 * respuesta para una clave equivocada, un correo inexistente y un operador desactivado.
 */
@Service
public class PlataformaAutenticacionService {

    public static final String CREDENCIALES_INVALIDAS = "Credenciales inválidas";

    /** Largo mínimo de la clave de un operador: administra todas las empresas. */
    public static final int CLAVE_MINIMA = 12;

    private static final int CLAVE_MAXIMA = 72;
    private static final String HASH_DE_RELLENO = BCrypt.hashpw("relleno-sin-uso", BCrypt.gensalt());

    private final CatalogoDeEmpresas catalogo;
    private final EventosDeSeguridad eventos;
    private final LimitadorDeIntentos porCuenta;
    private final LimitadorDeIntentos porIp;

    public PlataformaAutenticacionService(
            CatalogoDeEmpresas catalogo,
            EventosDeSeguridad eventos,
            @Value("${checkinobra.login.cuenta.max-fallos:5}") int cuentaMaxFallos,
            @Value("${checkinobra.login.cuenta.bloqueo-base-segundos:60}") long cuentaBloqueoBase,
            @Value("${checkinobra.login.cuenta.bloqueo-maximo-segundos:3600}") long cuentaBloqueoMaximo,
            @Value("${checkinobra.login.ip.max-fallos:30}") int ipMaxFallos,
            @Value("${checkinobra.login.ip.bloqueo-base-segundos:300}") long ipBloqueoBase,
            @Value("${checkinobra.login.ip.bloqueo-maximo-segundos:3600}") long ipBloqueoMaximo,
            @Value("${checkinobra.login.olvido-segundos:86400}") long olvido) {
        this.catalogo = catalogo;
        this.eventos = eventos;
        this.porCuenta = new LimitadorDeIntentos(cuentaMaxFallos, Duration.ofSeconds(cuentaBloqueoBase),
                Duration.ofSeconds(cuentaBloqueoMaximo), Duration.ofSeconds(olvido), Clock.systemUTC());
        this.porIp = new LimitadorDeIntentos(ipMaxFallos, Duration.ofSeconds(ipBloqueoBase),
                Duration.ofSeconds(ipBloqueoMaximo), Duration.ofSeconds(olvido), Clock.systemUTC());
    }

    public OperadorRegistrado login(String email, String clave, String ip) {
        String claveCuenta = "op:" + (email == null ? "" : email.trim().toLowerCase());
        exigirNoBloqueado(claveCuenta, ip);
        Optional<OperadorRegistrado> operador = catalogo.buscarOperadorPorCorreo(email).filter(OperadorRegistrado::activo);
        if (!comprobar(operador, clave)) {
            porCuenta.registrarFallo(claveCuenta);
            porIp.registrarFallo(ip);
            eventos.plataformaLoginFallido(operador.map(OperadorRegistrado::id).orElse(null), ip);
            throw new IllegalArgumentException(CREDENCIALES_INVALIDAS);
        }
        porCuenta.registrarExito(claveCuenta);
        eventos.plataformaLoginExitoso(operador.orElseThrow().id(), ip);
        return operador.orElseThrow();
    }

    /** El hash de una clave que cumple la política; falla con un mensaje claro si no. */
    public static String hashDeClave(String clave) {
        if (clave == null || clave.length() < CLAVE_MINIMA || clave.length() > CLAVE_MAXIMA) {
            throw new IllegalArgumentException(
                    "La clave de un operador debe tener entre " + CLAVE_MINIMA + " y " + CLAVE_MAXIMA + " caracteres");
        }
        return BCrypt.hashpw(clave, BCrypt.gensalt());
    }

    private void exigirNoBloqueado(String claveCuenta, String ip) {
        Optional<Duration> espera = porCuenta.bloqueoRestante(claveCuenta);
        Optional<Duration> esperaIp = porIp.bloqueoRestante(ip);
        if (espera.isPresent() || esperaIp.isPresent()) {
            Duration mayor = espera.orElse(Duration.ZERO).compareTo(esperaIp.orElse(Duration.ZERO)) >= 0
                    ? espera.orElse(Duration.ZERO) : esperaIp.orElse(Duration.ZERO);
            eventos.loginBloqueado(ip);
            throw new DemasiadosIntentosException(mayor);
        }
    }

    private static boolean comprobar(Optional<OperadorRegistrado> operador, String clave) {
        String candidata = clave == null ? "" : clave;
        if (operador.isPresent() && operador.get().pinHash() != null) {
            return BCrypt.checkpw(candidata, operador.get().pinHash());
        }
        BCrypt.checkpw(candidata, HASH_DE_RELLENO);
        return false;
    }
}
