package cl.duocuc.checkinobra.config;

import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;

import javax.sql.DataSource;
import java.util.ArrayList;
import java.util.Collection;
import java.util.List;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

/**
 * MT2 (#105): {@code purgarVencidas} es la única tarea que corre fuera de una petición,
 * sin empresa en el contexto. Recorre las empresas fijando la de cada una, y si una falla
 * sigue con las demás.
 */
class PurgaDeIdempotenciaPorEmpresaTest {

    private final ResolutorDeBases resolutor = new ResolutorDeBases() {
        @Override
        public DataSource baseDe(Long empresaId) {
            throw new UnsupportedOperationException();
        }

        @Override
        public boolean conoce(Long empresaId) {
            return true;
        }

        @Override
        public Collection<Long> empresas() {
            return List.of(3L, 4L, 5L);
        }
    };

    @Test
    void recorreCadaEmpresaConSuPropiaBaseEnElContexto() {
        JdbcTemplate jdbc = mock(JdbcTemplate.class);
        List<Optional<Long>> vistas = new ArrayList<>();
        when(jdbc.update(anyString(), any(Object[].class))).thenAnswer(i -> {
            vistas.add(TenantContext.actual());
            return 0;
        });

        new RegistroIdempotencia(jdbc, resolutor).purgarVencidas();

        assertThat(vistas).containsExactly(Optional.of(3L), Optional.of(4L), Optional.of(5L));
        assertThat(TenantContext.actual()).isEmpty();
    }

    @Test
    void siUnaBaseFallaSigueConLasDemas() {
        JdbcTemplate jdbc = mock(JdbcTemplate.class);
        List<Long> purgadas = new ArrayList<>();
        when(jdbc.update(anyString(), any(Object[].class))).thenAnswer(i -> {
            Long empresa = TenantContext.actual().orElseThrow();
            if (empresa == 4L) {
                throw new IllegalStateException("la base de la empresa 4 no responde");
            }
            purgadas.add(empresa);
            return 0;
        });

        new RegistroIdempotencia(jdbc, resolutor).purgarVencidas();

        assertThat(purgadas).containsExactly(3L, 5L);
    }
}
