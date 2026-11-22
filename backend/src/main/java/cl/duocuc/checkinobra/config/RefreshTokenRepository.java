package cl.duocuc.checkinobra.config;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;

import java.time.Instant;
import java.util.List;
import java.util.Optional;

public interface RefreshTokenRepository extends JpaRepository<RefreshToken, Long> {

    Optional<RefreshToken> findByHash(String hash);

    List<RefreshToken> findByUsuarioIdAndRevocadoEnIsNull(Long usuarioId);

    @Modifying
    @Query("update RefreshToken r set r.revocadoEn = :ahora where r.usuario.id = :usuarioId and r.revocadoEn is null")
    int revocarTodosDe(Long usuarioId, Instant ahora);
}
