package cl.duocuc.checkinobra.config;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;

/**
 * El registro de eventos de seguridad (SEG10, #98, S-24): quién hizo qué, desde dónde y cuándo,
 * en una línea {@code evento=… clave=valor} por el logger {@code seguridad}, para que se pueda
 * filtrar y enviar aparte.
 *
 * <p>Lleva ids (de usuario, de empresa) y la IP; <b>nunca</b> una clave, un PIN, un token ni un
 * correo: un registro de seguridad que filtra credenciales es peor que no tenerlo.
 */
@Component
public class EventosDeSeguridad {

    /** Nombre del logger, para configurarlo aparte en {@code logback}. */
    public static final String LOGGER = "seguridad";

    private static final Logger log = LoggerFactory.getLogger(LOGGER);

    public void loginExitoso(Usuario usuario, String ip) {
        log.info("evento=LOGIN_OK usuarioId={} empresaId={} rol={} ip={}",
                usuario.getId(), usuario.getEmpresa().getId(), usuario.getRol(), ip);
    }

    /** @param usuarioId el de la cuenta, o nulo si el correo o el id no existen */
    public void loginFallido(Long usuarioId, String ip) {
        log.warn("evento=LOGIN_FALLO usuarioId={} ip={}", usuarioId == null ? "desconocido" : usuarioId, ip);
    }

    /** Login de un operador de plataforma: sin empresa, con el id del operador. */
    public void plataformaLoginExitoso(Long operadorId, String ip) {
        log.info("evento=PLATAFORMA_LOGIN_OK operadorId={} ip={}", operadorId, ip);
    }

    public void plataformaLoginFallido(Long operadorId, String ip) {
        log.warn("evento=PLATAFORMA_LOGIN_FALLO operadorId={} ip={}", operadorId == null ? "desconocido" : operadorId, ip);
    }

    public void empresaCambiaDeEstado(Long operadorId, Long empresaId, String estado) {
        log.warn("evento=EMPRESA_ESTADO operadorId={} empresaId={} estado={}", operadorId, empresaId, estado);
    }

    public void empresaCreada(Long operadorId, Long empresaId) {
        log.info("evento=EMPRESA_CREADA operadorId={} empresaId={}", operadorId, empresaId);
    }

    public void loginBloqueado(String ip) {
        log.warn("evento=LOGIN_BLOQUEADO ip={}", ip);
    }

    public void accesoDenegado(String metodo, String ruta) {
        var sesion = SesionDelContexto.descripcion();
        log.warn("evento=ACCESO_DENEGADO {} metodo={} ruta={}", sesion, metodo, ruta);
    }

    public void claveRestablecida(Long actorId, Long objetivoId) {
        log.info("evento=CLAVE_RESTABLECIDA actorId={} usuarioId={}", actorId, objetivoId);
    }

    public void claveCambiada(Long usuarioId, String ip) {
        log.info("evento=CLAVE_CAMBIADA usuarioId={} ip={}", usuarioId, ip);
    }

    public void usuarioCreado(Long actorId, Long nuevoId, RolUsuario rol) {
        log.info("evento=USUARIO_CREADO actorId={} usuarioId={} rol={}", actorId, nuevoId, rol);
    }

    public void sesionRefrescada(Long usuarioId) {
        log.info("evento=SESION_REFRESCADA usuarioId={}", usuarioId);
    }

    public void sesionCerrada(Long usuarioId) {
        log.info("evento=SESION_CERRADA usuarioId={}", usuarioId);
    }

    /** Se presentó un refresh token ya usado: se revocan todas las sesiones del usuario. */
    public void refreshReutilizado(Long usuarioId) {
        log.warn("evento=REFRESH_REUTILIZADO usuarioId={}", usuarioId);
    }

    /** Quién es el que actúa, si hay alguien autenticado en este hilo. */
    private static final class SesionDelContexto {
        static String descripcion() {
            try {
                var u = SesionActual.usuario();
                return "usuarioId=" + u.usuarioId() + " empresaId=" + u.empresaId() + " rol=" + u.rol();
            } catch (RuntimeException e) {
                return "usuarioId=anonimo";
            }
        }
    }
}
