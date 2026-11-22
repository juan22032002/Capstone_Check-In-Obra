package cl.duocuc.checkinobra.config;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * Da su clave inicial al primer administrador (S-03).
 *
 * <p>La migración V2 sembraba un administrador con un PIN publicado en el README;
 * V11 anuló esa credencial. La clave que lo reemplaza no está en el repositorio:
 * viene de {@code PRIMER_ADMIN_CLAVE} y, como la conoce quien despliega, la
 * cuenta queda obligada a cambiarla al primer ingreso.
 */
@Service
@Transactional
public class PrimerAdminService {

    private final UsuarioRepository usuarioRepository;

    public PrimerAdminService(UsuarioRepository usuarioRepository) {
        this.usuarioRepository = usuarioRepository;
    }

    /**
     * Fija la clave inicial de un ADMIN que todavía no tiene credencial.
     *
     * <p>No hace nada, y devuelve {@code false}, si la cuenta no existe, no es
     * ADMIN o ya tiene credencial: así reiniciar la API con la variable puesta no
     * pisa la clave que el administrador eligió después. Una clave que no cumple
     * la política de claves lanza {@link IllegalArgumentException}.
     */
    public boolean fijarClaveInicial(String email, String clave) {
        if (email == null || clave == null || clave.isBlank()) {
            return false;
        }
        // Un marcador copiado de un .env.example no es una clave: es público.
        if (clave.trim().toLowerCase(java.util.Locale.ROOT).startsWith("cambiar")) {
            throw new IllegalStateException(
                    "PRIMER_ADMIN_CLAVE es un valor de ejemplo. Define una clave propia de 8 o más caracteres.");
        }
        return usuarioRepository.findByEmail(email.trim())
                .filter(u -> u.getRol() == RolUsuario.ADMIN)
                .filter(u -> u.getPinHash() == null)
                .map(u -> {
                    u.definirPin(clave);
                    u.setDebeCambiarPin(true);
                    usuarioRepository.save(u);
                    return true;
                })
                .orElse(false);
    }

    /** ¿Hay un ADMIN con ese correo sin credencial? Para avisar en el log cuando falta la clave. */
    @Transactional(readOnly = true)
    public boolean hayAdminSinCredencial(String email) {
        return email != null && usuarioRepository.findByEmail(email.trim())
                .filter(u -> u.getRol() == RolUsuario.ADMIN)
                .filter(u -> u.getPinHash() == null)
                .isPresent();
    }
}
