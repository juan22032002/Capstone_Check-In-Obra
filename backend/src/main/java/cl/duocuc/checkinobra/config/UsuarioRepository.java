package cl.duocuc.checkinobra.config;

import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.Optional;

public interface UsuarioRepository extends JpaRepository<Usuario, Long> {
    Optional<Usuario> findByEmail(String email);
    boolean existsByEmail(String email);
    boolean existsByEmailIgnoreCase(String email);
    boolean existsByRut(String rut);
    boolean existsByEmpresaIdAndRol(Long empresaId, RolUsuario rol);

    /** Solo la versión de sesión, para revalidar un token en cada petición sin cargar al usuario. */
    @org.springframework.data.jpa.repository.Query("select u.tokenVersion from Usuario u where u.id = :id")
    Optional<Integer> findTokenVersionById(Long id);
    List<Usuario> findByEmpresaId(Long empresaId);
    List<Usuario> findByEmpresaIdAndRol(Long empresaId, RolUsuario rol);
}
