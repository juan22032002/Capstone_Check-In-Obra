package cl.duocuc.checkinobra.config;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

/**
 * Deja al día el índice de login del catálogo con los usuarios de una empresa (MT1/MT2).
 *
 * <p>Lee la base de la empresa, así que corre con su {@link TenantContext}. Un correo
 * que ya es de otra empresa no se pisa: el correo es único en todo el sistema, y
 * reasignarlo en silencio le daría a una constructora el acceso de otra.
 */
@Service
public class SincronizadorDeCatalogo {

    private static final Logger log = LoggerFactory.getLogger(SincronizadorDeCatalogo.class);

    private final CatalogoDeEmpresas catalogo;
    private final UsuarioRepository usuarioRepository;

    public SincronizadorDeCatalogo(CatalogoDeEmpresas catalogo, UsuarioRepository usuarioRepository) {
        this.catalogo = catalogo;
        this.usuarioRepository = usuarioRepository;
    }

    /** Agrega al índice los correos de la empresa que todavía no están. Idempotente. */
    public void sincronizarIndiceDeLogin(Long empresaId) {
        int enConflicto = 0;
        for (Usuario u : TenantContext.ejecutarEn(empresaId, () -> usuarioRepository.findByEmpresaId(empresaId))) {
            if (!catalogo.reservarCorreo(u.getEmail(), empresaId)) {
                enConflicto++;
            }
        }
        if (enConflicto > 0) {
            log.warn("{} correo(s) de la empresa {} ya pertenecen a otra empresa en el catálogo y no se tocaron.",
                    enConflicto, empresaId);
        }
    }
}
