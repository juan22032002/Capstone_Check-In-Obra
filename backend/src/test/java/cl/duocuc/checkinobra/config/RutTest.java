package cl.duocuc.checkinobra.config;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.context.SecurityContextHolder;

import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * El RUT identifica a la persona en todo el sistema: quien recibe un despacho,
 * quien tiene una herramienta, quien dirige la obra. Un dígito equivocado o un
 * formato distinto partían a una persona en dos.
 */
@ExtendWith(MockitoExtension.class)
class RutTest {

    @Mock
    private UsuarioRepository usuarioRepository;

    @Mock
    private EmpresaService empresaService;

    @Mock
    private CatalogoDeEmpresas catalogo;

    private UsuarioService usuarioService;

    @BeforeEach
    void prepararSesion() {
        var admin = new UsuarioAutenticado(1L, "admin@constructora.cl", RolUsuario.ADMIN, 1L);
        SecurityContextHolder.getContext().setAuthentication(
                new UsernamePasswordAuthenticationToken(admin, null, List.of()));
        usuarioService = new UsuarioService(usuarioRepository, empresaService, catalogo,
                org.mockito.Mockito.mock(SesionService.class), new EventosDeSeguridad());
        org.mockito.Mockito.lenient().when(catalogo.reservarCorreo(any(), any())).thenReturn(true);
    }

    @AfterEach
    void limpiarSesion() {
        SecurityContextHolder.clearContext();
    }

    @Test
    void cualquierFormatoQuedaEnElCanonico() {
        assertThat(Rut.normalizar("14109556-0")).isEqualTo("14.109.556-0");
        assertThat(Rut.normalizar("14.109.556-0")).isEqualTo("14.109.556-0");
        assertThat(Rut.normalizar(" 141095560 ")).isEqualTo("14.109.556-0");
        assertThat(Rut.normalizar("17.930.556-9")).isEqualTo("17.930.556-9");
        assertThat(Rut.normalizar("5.126.663-3")).isEqualTo("5.126.663-3");
    }

    @Test
    void laKSeGuardaEnMayuscula() {
        // 10.000.013 tiene dígito K.
        assertThat(Rut.digitoVerificador("10000013")).isEqualTo('K');
        assertThat(Rut.normalizar("10000013-k")).isEqualTo("10.000.013-K");
    }

    @Test
    void unDigitoVerificadorEquivocadoSeRechaza() {
        // Los que había en las bases locales: el correcto de 14.109.556 es 0.
        assertThatThrownBy(() -> Rut.normalizar("14.109.556-2"))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessage("El RUT no es válido: revisa el dígito verificador");
        assertThatThrownBy(() -> Rut.normalizar("76.412.330-9"))
                .isInstanceOf(IllegalArgumentException.class);
    }

    @Test
    void loQueNoTieneFormaDeRutSeRechaza() {
        assertThatThrownBy(() -> Rut.normalizar("14.109.55A-0")).isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(() -> Rut.normalizar("123456789-0")).isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(() -> Rut.normalizar("")).hasMessage("El RUT es obligatorio");
        assertThatThrownBy(() -> Rut.normalizar(null)).hasMessage("El RUT es obligatorio");
    }

    @Test
    void elUsuarioSeGuardaConElRutNormalizado() {
        when(empresaService.obtener(1L)).thenReturn(Empresa.builder().id(1L).nombre("Constructora").build());
        when(usuarioRepository.saveAndFlush(any())).thenAnswer(i -> i.getArgument(0));

        usuarioService.crear(1L, "Pedro", "pedro@constructora.cl", "14109556-0", RolUsuario.BODEGUERO, null);

        ArgumentCaptor<Usuario> guardado = ArgumentCaptor.forClass(Usuario.class);
        verify(usuarioRepository).saveAndFlush(guardado.capture());
        assertThat(guardado.getValue().getRut()).isEqualTo("14.109.556-0");
    }

    /** El UNIQUE solo ve el duplicado si los dos llegan escritos igual. */
    @Test
    void laMismaPersonaEscritaDeOtraFormaEsUnDuplicado() {
        when(usuarioRepository.existsByRut("14.109.556-0")).thenReturn(true);

        assertThatThrownBy(() -> usuarioService.crear(
                1L, "Pedro", "pedro2@constructora.cl", "14109556-0", RolUsuario.BODEGUERO, null))
                .isInstanceOf(IllegalStateException.class)
                .hasMessage("Ya existe un usuario con ese RUT");
        verify(usuarioRepository, never()).saveAndFlush(any());
    }

    @Test
    void unRutInvalidoNoLlegaALaBase() {
        assertThatThrownBy(() -> usuarioService.crear(
                1L, "Pedro", "pedro@constructora.cl", "14.109.556-2", RolUsuario.BODEGUERO, null))
                .isInstanceOf(IllegalArgumentException.class);
        verify(usuarioRepository, never()).existsByRut(anyString());
        verify(usuarioRepository, never()).saveAndFlush(any());
    }
}
