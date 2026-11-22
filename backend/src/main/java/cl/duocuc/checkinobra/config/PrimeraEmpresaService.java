package cl.duocuc.checkinobra.config;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.Locale;

/**
 * Crea al administrador de la primera empresa cuando todavía no tiene ninguno (MT1/MT2).
 *
 * <p>La migración V2 sembraba una empresa y un ADMIN en cada base nueva. Eso salió de
 * {@code db/migration}: la empresa la registra {@link BaseInicialInicializador} y su
 * ADMIN se crea acá, con la clave de {@code PRIMER_ADMIN_CLAVE}, obligado a cambiarla en
 * su primer ingreso (SEG3). Corre con la empresa en el {@link TenantContext}.
 */
@Service
@Transactional
public class PrimeraEmpresaService {

    static final String NOMBRE_DEL_ADMIN = "Administrador Check-In-Obra";

    private final EmpresaRepository empresaRepository;
    private final UsuarioRepository usuarioRepository;

    public PrimeraEmpresaService(EmpresaRepository empresaRepository, UsuarioRepository usuarioRepository) {
        this.empresaRepository = empresaRepository;
        this.usuarioRepository = usuarioRepository;
    }

    /**
     * Crea el ADMIN de la empresa si no tiene ninguno.
     *
     * @return {@code true} si lo creó; {@code false} si no hizo nada (sin clave, sin empresa, o ya hay un ADMIN)
     * @throws IllegalStateException si la clave es un valor de ejemplo
     * @throws IllegalArgumentException si la clave no cumple la política de claves
     */
    public boolean crearAdminSiNoHay(String rut, String adminEmail, String clave) {
        if (clave == null || clave.isBlank()) {
            return false;
        }
        if (clave.trim().toLowerCase(Locale.ROOT).startsWith("cambiar")) {
            throw new IllegalStateException(
                    "PRIMER_ADMIN_CLAVE es un valor de ejemplo. Define una clave propia de 8 o más caracteres.");
        }
        Empresa empresa = empresaRepository.findByRut(rut).orElse(null);
        if (empresa == null || usuarioRepository.existsByEmpresaIdAndRol(empresa.getId(), RolUsuario.ADMIN)) {
            return false;
        }
        // La clave se valida antes de guardar nada.
        Usuario admin = Usuario.builder()
                .nombre(NOMBRE_DEL_ADMIN)
                .email(adminEmail.trim())
                .rol(RolUsuario.ADMIN)
                .empresa(empresa)
                .build();
        admin.definirPin(clave);
        admin.setDebeCambiarPin(true);
        usuarioRepository.save(admin);
        return true;
    }
}
