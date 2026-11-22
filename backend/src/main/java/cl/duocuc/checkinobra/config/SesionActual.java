package cl.duocuc.checkinobra.config;

import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;

/** Acceso al {@link UsuarioAutenticado} de la petición en curso. */
public final class SesionActual {

    private SesionActual() {
    }

    /**
     * @throws AccesoDenegadoException si no hay nadie autenticado. Que llegue acá
     *     una petición anónima significa que alguien agregó una ruta pública que
     *     igual consulta datos de empresa: mejor que falle a que devuelva algo.
     */
    public static UsuarioAutenticado usuario() {
        Authentication auth = SecurityContextHolder.getContext().getAuthentication();
        if (auth == null || !(auth.getPrincipal() instanceof UsuarioAutenticado usuario)) {
            throw new AccesoDenegadoException("No hay un usuario autenticado en esta petición");
        }
        return usuario;
    }

    public static Long empresaId() {
        Long empresa = usuario().empresaId();
        if (empresa == null) {
            // Un operador de plataforma no pertenece a ninguna empresa: si llegó a código de empresa,
            // algo dejó pasar una ruta que no debía.
            throw new AccesoDenegadoException("Esta petición no pertenece a ninguna empresa");
        }
        return empresa;
    }

    public static Long usuarioId() {
        return usuario().usuarioId();
    }

    /**
     * ¿Quien llama es un trabajador? Es el único rol cuyo acceso depende además
     * de <em>de quién</em> es el dato: un bodeguero ve las solicitudes de la
     * obra entera, un trabajador solo las suyas.
     */
    public static boolean esTrabajador() {
        return usuario().rol() == RolUsuario.TRABAJADOR;
    }
}
