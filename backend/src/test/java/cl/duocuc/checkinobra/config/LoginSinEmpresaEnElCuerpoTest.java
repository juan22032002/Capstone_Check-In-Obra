package cl.duocuc.checkinobra.config;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.server.LocalServerPort;
import tools.jackson.databind.json.JsonMapper;

import javax.sql.DataSource;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Clock;
import java.time.Duration;
import java.util.Collection;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.when;

/**
 * MT4 (#107): sin {@code empresaId} en el cuerpo, {@code login-pin} se resuelve a la única
 * empresa si hay una sola (una app anterior sigue entrando) y no se resuelve si hay varias.
 */
@ExtendWith(MockitoExtension.class)
class LoginSinEmpresaEnElCuerpoTest {

    @Mock private UsuarioRepository usuarioRepository;
    @Mock private CatalogoDeEmpresas catalogo;

    private static ResolutorDeBases con(Long... empresas) {
        return new ResolutorDeBases() {
            @Override public DataSource baseDe(Long id) {
                throw new UnsupportedOperationException();
            }

            @Override public boolean conoce(Long id) {
                return List.of(empresas).contains(id);
            }

            @Override public Collection<Long> empresas() {
                return List.of(empresas);
            }
        };
    }

    private AutenticacionService servicio(ResolutorDeBases resolutor) {
        var limite = new LimitadorDeIntentos(
                5, Duration.ofMinutes(1), Duration.ofHours(1), Duration.ofDays(1), Clock.systemUTC());
        return new AutenticacionService(usuarioRepository, catalogo, resolutor, new EventosDeSeguridad(),
                    org.mockito.Mockito.mock(SesionService.class), limite, limite);
    }

    private Usuario obrero(long empresaId) {
        Usuario u = Usuario.builder().id(9L).nombre("Obrero").email("o@x.cl").rol(RolUsuario.TRABAJADOR)
                .empresa(Empresa.builder().id(empresaId).nombre("E").rut("1-9").build()).build();
        u.definirPin("4821");
        return u;
    }

    @Test
    void conUnaSolaEmpresaElPinSinEmpresaSeBuscaEnEsa() {
        AtomicEmpresa vista = new AtomicEmpresa();
        when(usuarioRepository.findById(9L)).thenAnswer(i -> {
            vista.valor = TenantContext.actual();
            return Optional.of(obrero(5L));
        });

        Usuario entra = servicio(con(5L)).loginPorPin(9L, null, "4821", "1.1.1.1");

        assertThat(entra.getId()).isEqualTo(9L);
        // La base se abrió con la empresa 5 en el contexto.
        assertThat(vista.valor).contains(5L);
    }

    @Test
    void conVariasEmpresasElPinSinEmpresaNoSePuedeResolver() {
        assertThatThrownBy(() -> servicio(con(5L, 6L)).loginPorPin(9L, null, "4821", "1.1.1.1"))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessage("Credenciales inválidas");
    }

    @Test
    void unaEmpresaSinBaseNoSePuedeUsar() {
        assertThatThrownBy(() -> servicio(con(5L)).loginPorPin(9L, 77L, "4821", "1.1.1.1"))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessage("Credenciales inválidas");
    }

    private static final class AtomicEmpresa {
        Optional<Long> valor = Optional.empty();
    }
}
