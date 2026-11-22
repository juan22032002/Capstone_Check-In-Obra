package cl.duocuc.checkinobra.config;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.context.SecurityContextHolder;

import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * MT2 (#105): el correo es único en todo el sistema y el login lo usa para saber qué
 * base abrir. Se reserva en el catálogo antes de guardar; son dos bases sin transacción
 * compartida, así que si guardar falla se suelta la reserva.
 */
@ExtendWith(MockitoExtension.class)
class UsuarioServiceCatalogoTest {

    @Mock private UsuarioRepository usuarioRepository;
    @Mock private EmpresaService empresaService;
    @Mock private CatalogoDeEmpresas catalogo;

    private UsuarioService servicio;

    @BeforeEach
    void preparar() {
        var admin = new UsuarioAutenticado(1L, "admin@x.cl", RolUsuario.ADMIN, 1L);
        SecurityContextHolder.getContext().setAuthentication(
                new UsernamePasswordAuthenticationToken(admin, null, List.of()));
        servicio = new UsuarioService(usuarioRepository, empresaService, catalogo,
                org.mockito.Mockito.mock(SesionService.class), new EventosDeSeguridad());
        org.mockito.Mockito.lenient().when(empresaService.obtener(1L))
                .thenReturn(Empresa.builder().id(1L).nombre("E").rut("1-9").build());
    }

    @AfterEach
    void limpiar() {
        SecurityContextHolder.clearContext();
    }

    @Test
    void siElCorreoYaEsDeOtraEmpresaNoSeGuardaNada() {
        when(catalogo.reservarCorreo("pedro@x.cl", 1L)).thenReturn(false);

        assertThatThrownBy(() -> servicio.crear(1L, "Pedro", "pedro@x.cl", "14109556-0", RolUsuario.BODEGUERO, null))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("correo");

        verify(usuarioRepository, never()).saveAndFlush(any());
    }

    @Test
    void unCorreoQueSoloDifiereEnLasMayusculasEsDuplicado() {
        when(usuarioRepository.existsByEmailIgnoreCase("PEDRO@x.cl")).thenReturn(true);

        assertThatThrownBy(() -> servicio.crear(1L, "Pedro", "PEDRO@x.cl", "14109556-0", RolUsuario.BODEGUERO, null))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("correo");

        verify(catalogo, never()).reservarCorreo(any(), any());
    }

    @Test
    void siGuardarFallaSeSueltaLaReservaDelCorreo() {
        when(catalogo.reservarCorreo("pedro@x.cl", 1L)).thenReturn(true);
        when(usuarioRepository.saveAndFlush(any())).thenThrow(new IllegalArgumentException("falla la base"));

        assertThatThrownBy(() -> servicio.crear(1L, "Pedro", "pedro@x.cl", "14109556-0", RolUsuario.BODEGUERO, null))
                .isInstanceOf(IllegalArgumentException.class);

        verify(catalogo).liberarCorreo("pedro@x.cl", 1L);
    }

    @Test
    void siTodoSaleBienElCorreoQuedaReservado() {
        when(catalogo.reservarCorreo("pedro@x.cl", 1L)).thenReturn(true);
        when(usuarioRepository.saveAndFlush(any())).thenAnswer(i -> i.getArgument(0));

        Usuario creado = servicio.crear(1L, "Pedro", "pedro@x.cl", "14109556-0", RolUsuario.BODEGUERO, null);

        assertThat(creado.getEmail()).isEqualTo("pedro@x.cl");
        verify(catalogo, never()).liberarCorreo(any(), any());
    }
}
