package cl.duocuc.checkinobra.config;

import cl.duocuc.checkinobra.inventario.KardexMovimiento;
import cl.duocuc.checkinobra.inventario.TipoMovimiento;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import tools.jackson.databind.ObjectMapper;
import tools.jackson.databind.json.JsonMapper;

import java.time.LocalDateTime;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Los controladores devuelven entidades, no DTOs. Mientras siga siendo así, lo
 * único que impide que el hash del PIN viaje al cliente es el {@code @JsonIgnore}
 * de {@link Usuario#getPinHash()} — y eso es un detalle que se borra sin querer
 * al refactorizar. Estas pruebas lo dejan clavado.
 */
class PinHashNoSeSerializaTest {

    private ObjectMapper mapper;
    private Usuario usuario;

    @BeforeEach
    void prepararUsuarioConPin() {
        // Jackson 3 (`tools.jackson`), que es el que Spring Boot 4 usa para
        // serializar las respuestas HTTP. En el classpath también está Jackson 2
        // —lo arrastran JJWT y el starter— y usar ese haría que el test
        // aprobara un mapper distinto del que de verdad manda los datos por la
        // red. Ya pasó una vez con el manejador de errores.
        mapper = JsonMapper.builder().build();
        usuario = Usuario.builder()
                .id(7L)
                .nombre("Jorge Reyes")
                .email("jorge@constructora.cl")
                .rol(RolUsuario.BODEGUERO)
                .empresa(Empresa.builder().id(1L).nombre("Constructora").rut("76.543.210-K").build())
                .build();
        usuario.definirPin("clave-larga-4821");
    }

    @Test
    void el_usuario_serializado_no_lleva_el_hash() {
        String json = mapper.writeValueAsString(usuario);

        assertThat(json).doesNotContain("pinHash");
        assertThat(json).doesNotContain(usuario.getPinHash());
        // El prefijo de todo hash BCrypt, por si alguien lo renombra.
        assertThat(json).doesNotContain("$2a$");
        // Y lo que sí tiene que llegar, llega.
        assertThat(json).contains("Jorge Reyes").contains("BODEGUERO");
    }

    @Test
    void tampoco_lo_lleva_a_traves_del_kardex() {
        // GET /api/kardex devuelve la entidad, y su @ManyToOne EAGER hacia
        // Usuario arrastraba el hash de quien registró cada movimiento.
        KardexMovimiento movimiento = KardexMovimiento.builder()
                .id(1L)
                .tipoMovimiento(TipoMovimiento.DESPACHO)
                .cantidad(12)
                .fecha(LocalDateTime.now())
                .usuario(usuario)
                .build();

        String json = mapper.writeValueAsString(movimiento);

        assertThat(json).doesNotContain("pinHash");
        assertThat(json).doesNotContain(usuario.getPinHash());
        assertThat(json).doesNotContain("$2a$");
    }

    @Test
    void el_hash_sigue_existiendo_y_autenticando_puertas_adentro() {
        // Ocultarlo en el JSON no puede haberlo desconectado del login.
        assertThat(usuario.getPinHash()).isNotBlank();
        assertThat(usuario.autenticar("clave-larga-4821")).isTrue();
        assertThat(usuario.autenticar("0000")).isFalse();
    }
}
