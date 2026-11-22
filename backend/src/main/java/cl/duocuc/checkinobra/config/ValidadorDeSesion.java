package cl.duocuc.checkinobra.config;

import org.springframework.stereotype.Component;

/**
 * Revalida un token contra el usuario en cada petición (SEG10, #98, S-11): el usuario tiene que
 * existir y seguir con la versión de sesión con que se emitió el token. Corre con la empresa del
 * token ya fijada en el {@link TenantContext}.
 *
 * <p>Es una lectura por llave primaria de una sola columna; cambiar la clave de un usuario sube
 * su versión y deja sin efecto, de inmediato, todos sus tokens anteriores.
 */
@Component
public class ValidadorDeSesion {

    private final UsuarioRepository usuarioRepository;

    public ValidadorDeSesion(UsuarioRepository usuarioRepository) {
        this.usuarioRepository = usuarioRepository;
    }

    /** @param versionDelToken el claim {@code tv}; nulo si el token no lo trae (no vale) */
    public boolean vigente(long usuarioId, Number versionDelToken) {
        if (versionDelToken == null) {
            return false;
        }
        return usuarioRepository.findTokenVersionById(usuarioId)
                .map(actual -> actual == versionDelToken.intValue())
                .orElse(false);
    }
}
