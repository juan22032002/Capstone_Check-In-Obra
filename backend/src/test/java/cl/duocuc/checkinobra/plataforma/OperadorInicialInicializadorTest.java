package cl.duocuc.checkinobra.plataforma;

import cl.duocuc.checkinobra.config.CatalogoDeEmpresas;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;

import java.util.OptionalLong;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/** MT6 (#109): el primer operador se crea solo si el catálogo no tiene ninguno y la clave cumple la política. */
class OperadorInicialInicializadorTest {

    private final CatalogoDeEmpresas catalogo = mock(CatalogoDeEmpresas.class);

    private OperadorInicialInicializador con(String email, String clave) {
        return new OperadorInicialInicializador(catalogo, email, clave);
    }

    @Test
    void creaElPrimerOperadorConLaClaveHasheada() {
        when(catalogo.contarOperadores()).thenReturn(0);
        when(catalogo.crearOperador(anyString(), anyString(), anyString())).thenReturn(OptionalLong.of(1));

        con("Operador@Plataforma.cl", "una-clave-bien-larga-1").run(null);

        ArgumentCaptor<String> hash = ArgumentCaptor.forClass(String.class);
        verify(catalogo).crearOperador(anyString(), anyString(), hash.capture());
        assertThat(hash.getValue()).startsWith("$2").doesNotContain("una-clave-bien-larga-1");
    }

    @Test
    void conOperadoresYaCreadosNoHaceNada() {
        when(catalogo.contarOperadores()).thenReturn(1);

        con("otro@plataforma.cl", "una-clave-bien-larga-1").run(null);

        verify(catalogo, never()).crearOperador(any(), any(), any());
    }

    @Test
    void sinVariablesNoHaceNada() {
        when(catalogo.contarOperadores()).thenReturn(0);

        con("", "").run(null);
        con("operador@plataforma.cl", "").run(null);
        con("", "una-clave-bien-larga-1").run(null);

        verify(catalogo, never()).crearOperador(any(), any(), any());
    }

    @Test
    void unaClaveCortaHaceFallarElArranque() {
        when(catalogo.contarOperadores()).thenReturn(0);

        assertThatThrownBy(() -> con("operador@plataforma.cl", "corta-123").run(null))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("12");
        verify(catalogo, never()).crearOperador(any(), any(), any());
    }
}
