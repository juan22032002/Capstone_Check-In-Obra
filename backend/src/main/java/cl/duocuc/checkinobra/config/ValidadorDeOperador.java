package cl.duocuc.checkinobra.config;

import org.springframework.stereotype.Component;

/**
 * Revalida el token de un operador de plataforma contra el catálogo en cada petición (MT6, #109):
 * el operador tiene que existir, estar activo y seguir con la versión de sesión del token.
 */
@Component
public class ValidadorDeOperador {

    private final CatalogoDeEmpresas catalogo;

    public ValidadorDeOperador(CatalogoDeEmpresas catalogo) {
        this.catalogo = catalogo;
    }

    /** @param versionDelToken el claim {@code tv}; nulo si el token no lo trae (no vale) */
    public boolean vigente(long operadorId, Number versionDelToken) {
        if (versionDelToken == null) {
            return false;
        }
        return catalogo.buscarOperadorActivo(operadorId)
                .map(o -> o.tokenVersion() == versionDelToken.intValue())
                .orElse(false);
    }
}
