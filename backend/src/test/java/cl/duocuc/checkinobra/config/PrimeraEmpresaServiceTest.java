package cl.duocuc.checkinobra.config;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * MT1/MT2: la migración V2 ya no siembra el administrador. La empresa la registra el
 * arranque, y este servicio crea a su ADMIN con la clave que viene del entorno.
 */
@ExtendWith(MockitoExtension.class)
class PrimeraEmpresaServiceTest {

    private static final String RUT = "76.412.330-9";

    @Mock private EmpresaRepository empresaRepository;
    @Mock private UsuarioRepository usuarioRepository;
    @InjectMocks private PrimeraEmpresaService servicio;

    private Empresa empresa() {
        return Empresa.builder().id(1L).nombre("Constructora Arauco Ltda.").rut(RUT).build();
    }

    @Test
    void siLaEmpresaNoTieneAdminLoCreaObligadoACambiarLaClave() {
        when(empresaRepository.findByRut(RUT)).thenReturn(Optional.of(empresa()));
        when(usuarioRepository.existsByEmpresaIdAndRol(1L, RolUsuario.ADMIN)).thenReturn(false);

        boolean creado = servicio.crearAdminSiNoHay(RUT, "admin@arauco-ltda.cl", "clave-inicial-segura");

        assertThat(creado).isTrue();
        ArgumentCaptor<Usuario> admin = ArgumentCaptor.forClass(Usuario.class);
        verify(usuarioRepository).save(admin.capture());
        assertThat(admin.getValue().getRol()).isEqualTo(RolUsuario.ADMIN);
        assertThat(admin.getValue().getEmail()).isEqualTo("admin@arauco-ltda.cl");
        assertThat(admin.getValue().getEmpresa().getRut()).isEqualTo(RUT);
        assertThat(admin.getValue().autenticar("clave-inicial-segura")).isTrue();
        assertThat(admin.getValue().isDebeCambiarPin()).isTrue();
    }

    @Test
    void siLaEmpresaYaTieneAdminNoHaceNada() {
        when(empresaRepository.findByRut(RUT)).thenReturn(Optional.of(empresa()));
        when(usuarioRepository.existsByEmpresaIdAndRol(1L, RolUsuario.ADMIN)).thenReturn(true);

        assertThat(servicio.crearAdminSiNoHay(RUT, "admin@x.cl", "clave-inicial-segura")).isFalse();

        verify(usuarioRepository, never()).save(any());
    }

    @Test
    void sinLaEmpresaNoCreaNada() {
        when(empresaRepository.findByRut(RUT)).thenReturn(Optional.empty());

        assertThat(servicio.crearAdminSiNoHay(RUT, "admin@x.cl", "clave-inicial-segura")).isFalse();

        verify(usuarioRepository, never()).save(any());
    }

    @Test
    void sinClaveNoCreaNada() {
        assertThat(servicio.crearAdminSiNoHay(RUT, "admin@x.cl", "")).isFalse();
        assertThat(servicio.crearAdminSiNoHay(RUT, "admin@x.cl", null)).isFalse();

        verify(usuarioRepository, never()).save(any());
    }

    @Test
    void unMarcadorDeEjemploNuncaEsLaClaveInicial() {
        assertThatThrownBy(() -> servicio.crearAdminSiNoHay(RUT, "admin@x.cl", "CAMBIAR_generar_una_clave"))
                .isInstanceOf(IllegalStateException.class);

        verify(usuarioRepository, never()).save(any());
    }

    @Test
    void unaClaveQueNoCumpleLaPoliticaNoGuardaNada() {
        when(empresaRepository.findByRut(RUT)).thenReturn(Optional.of(empresa()));
        when(usuarioRepository.existsByEmpresaIdAndRol(1L, RolUsuario.ADMIN)).thenReturn(false);

        assertThatThrownBy(() -> servicio.crearAdminSiNoHay(RUT, "admin@x.cl", "1234"))
                .isInstanceOf(IllegalArgumentException.class);

        verify(usuarioRepository, never()).save(any());
    }
}
