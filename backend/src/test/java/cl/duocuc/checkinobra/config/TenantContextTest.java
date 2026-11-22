package cl.duocuc.checkinobra.config;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;

import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

class TenantContextTest {

    @AfterEach
    void limpiar() {
        TenantContext.limpiar();
    }

    @Test
    void sinEmpresaNoHayContexto() {
        assertThat(TenantContext.actual()).isEmpty();
    }

    @Test
    void ejecutarEnFijaLaEmpresaSoloDuranteLaTarea() {
        Long dentro = TenantContext.ejecutarEn(7L, () -> TenantContext.actual().orElseThrow());

        assertThat(dentro).isEqualTo(7L);
        assertThat(TenantContext.actual()).isEmpty();
    }

    @Test
    void ejecutarEnRestauraLaEmpresaAnterior() {
        TenantContext.fijar(1L);

        TenantContext.ejecutarEn(2L, () -> assertThat(TenantContext.actual()).contains(2L));

        assertThat(TenantContext.actual()).contains(1L);
    }

    @Test
    void siLaTareaFallaIgualSeLimpia() {
        assertThatThrownBy(() -> TenantContext.ejecutarEn(5L, () -> {
            throw new IllegalStateException("falla");
        })).isInstanceOf(IllegalStateException.class);

        assertThat(TenantContext.actual()).isEmpty();
    }

    @Test
    void cadaHiloTieneSuPropiaEmpresa() throws Exception {
        TenantContext.fijar(1L);
        ExecutorService otroHilo = Executors.newSingleThreadExecutor();
        try {
            // Una petición que llegue por otro hilo no hereda la empresa de esta.
            assertThat(otroHilo.submit(() -> TenantContext.actual().isPresent()).get()).isFalse();
        } finally {
            otroHilo.shutdown();
        }
        assertThat(TenantContext.actual()).contains(1L);
    }
}
