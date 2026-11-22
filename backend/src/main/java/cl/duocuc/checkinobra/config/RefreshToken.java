package cl.duocuc.checkinobra.config;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.Table;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

import java.time.Instant;

/** Un refresh token emitido. Guarda el hash del valor, nunca el valor. */
@Entity
@Table(name = "refresh_tokens")
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class RefreshToken implements PerteneceAEmpresa {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @ManyToOne(fetch = FetchType.EAGER, optional = false)
    @JoinColumn(name = "usuario_id", nullable = false)
    private Usuario usuario;

    @Column(nullable = false, length = 64, unique = true)
    private String hash;

    @Column(name = "token_version", nullable = false)
    private int tokenVersion;

    @Column(name = "creado_en", nullable = false)
    private Instant creadoEn;

    @Column(name = "expira_en", nullable = false)
    private Instant expiraEn;

    @Column(name = "revocado_en")
    private Instant revocadoEn;

    @Column(name = "reemplazado_por")
    private Long reemplazadoPor;

    @Override
    public Long empresaId() {
        return usuario.empresaId();
    }
}
