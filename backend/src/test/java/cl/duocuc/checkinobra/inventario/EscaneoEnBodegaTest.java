package cl.duocuc.checkinobra.inventario;

import cl.duocuc.checkinobra.config.AccesoDenegadoException;
import cl.duocuc.checkinobra.config.Empresa;
import cl.duocuc.checkinobra.config.EmpresaService;
import cl.duocuc.checkinobra.config.RolUsuario;
import cl.duocuc.checkinobra.config.UsuarioAutenticado;
import cl.duocuc.checkinobra.cubicacion.Material;
import cl.duocuc.checkinobra.cubicacion.MaterialRepository;
import cl.duocuc.checkinobra.cubicacion.MaterialService;
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
import java.util.NoSuchElementException;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * Lo que hace el escáner del bodeguero al resolver un código.
 *
 * <p>Dos invariantes que no se ven en la pantalla y que son justamente las que
 * importan: que un código ajeno responda lo mismo que uno inexistente
 * (RN-23/RN-30), y que mayúsculas y minúsculas no partan un catálogo en dos
 * (RN-32).
 */
@ExtendWith(MockitoExtension.class)
class EscaneoEnBodegaTest {

    private static final long MI_EMPRESA = 1L;
    private static final long OTRA_EMPRESA = 2L;

    @Mock
    private MaterialRepository materialRepository;

    @Mock
    private HerramientaRepository herramientaRepository;

    @Mock
    private EmpresaService empresaService;

    private MaterialService materialService;
    private HerramientaService herramientaService;

    @BeforeEach
    void prepararSesionYServicios() {
        var usuario = new UsuarioAutenticado(7L, "jorge@constructora.cl", RolUsuario.BODEGUERO, MI_EMPRESA);
        SecurityContextHolder.getContext().setAuthentication(
                new UsernamePasswordAuthenticationToken(usuario, null, List.of()));

        materialService = new MaterialService(materialRepository, empresaService);
        herramientaService = new HerramientaService(herramientaRepository, empresaService);
    }

    @AfterEach
    void limpiarSesion() {
        SecurityContextHolder.clearContext();
    }

    @Test
    void unCodigoDeBarrasResuelveElMaterialDelEnvase() {
        Material volcanita = material("VOL-ST-10", "7801234567890");
        when(materialRepository.findByEmpresaIdAndCodigoBarra(MI_EMPRESA, "7801234567890"))
                .thenReturn(Optional.of(volcanita));

        assertThat(materialService.buscarPorCodigo(MI_EMPRESA, "7801234567890")).isSameAs(volcanita);
        // Ni siquiera llega a probar el SKU: el de fábrica es lo que se escanea
        // el 99 % de las veces y por eso va primero.
        verify(materialRepository, never()).findByEmpresaIdAndSku(anyLong(), anyString());
    }

    @Test
    void siNoEsCodigoDeBarrasSeIntentaComoSkuYSeNormaliza() {
        Material montante = material("MET-MON-60", null);
        when(materialRepository.findByEmpresaIdAndCodigoBarra(MI_EMPRESA, "met-mon-60"))
                .thenReturn(Optional.empty());
        // El SKU se guarda en mayúsculas; quien lo teclea a mano no tiene por
        // qué saberlo.
        when(materialRepository.findByEmpresaIdAndSku(MI_EMPRESA, "MET-MON-60"))
                .thenReturn(Optional.of(montante));

        assertThat(materialService.buscarPorCodigo(MI_EMPRESA, "  met-mon-60  ")).isSameAs(montante);
    }

    @Test
    void unCodigoQueNoEstaEnElCatalogoNoSeInventa() {
        when(materialRepository.findByEmpresaIdAndCodigoBarra(MI_EMPRESA, "9999")).thenReturn(Optional.empty());
        when(materialRepository.findByEmpresaIdAndSku(MI_EMPRESA, "9999")).thenReturn(Optional.empty());

        assertThatThrownBy(() -> materialService.buscarPorCodigo(MI_EMPRESA, "9999"))
                .isInstanceOf(NoSuchElementException.class)
                .hasMessage("Código no reconocido");
    }

    @Test
    void elEscanerNoResuelveCodigosDeOtraConstructora() {
        // Sin esto, apuntar la cámara a la etiqueta de otra empresa devolvería
        // su material: el SKU es único en toda la base, no por empresa.
        assertThatThrownBy(() -> materialService.buscarPorCodigo(OTRA_EMPRESA, "7801234567890"))
                .isInstanceOf(AccesoDenegadoException.class);
    }

    @Test
    void dosConstructorasPuedenTenerElMismoCodigoDeBarras() {
        // Un EAN-13 identifica al producto, no a quien lo compra: la misma
        // plancha de Volcanita trae el mismo código en todas las bodegas del
        // país. Si el duplicado se buscara en toda la base, la segunda empresa
        // que la registrara se quedaría sin poder hacerlo —y, al importar, con
        // la planilla entera rechazada— por una fila que ni siquiera es suya.
        when(materialRepository.findByEmpresaIdAndSkuIgnoreCase(MI_EMPRESA, "VOL-ST-10")).thenReturn(Optional.empty());
        when(materialRepository.findByEmpresaIdAndCodigoBarra(MI_EMPRESA, "7801234567890"))
                .thenReturn(Optional.empty());
        when(empresaService.obtener(MI_EMPRESA)).thenReturn(empresa(MI_EMPRESA));

        materialService.crear(
                MI_EMPRESA, "VOL-ST-10", "Volcanita ST 10 mm",
                cl.duocuc.checkinobra.cubicacion.CategoriaMaterial.VOLCANITA, 5980, 40, "7801234567890");

        verify(materialRepository).save(any(Material.class));
    }

    @Test
    void elSkuSeGuardaEnMayusculasParaQueElEscanerLoEncuentre() {
        // La app ya lo hacía en su formulario; el servicio no. Un material
        // creado desde Swagger con el SKU en minúsculas quedaba invisible para
        // el escáner, que lo busca normalizado.
        when(materialRepository.findByEmpresaIdAndSkuIgnoreCase(MI_EMPRESA, "VOL-ST-10")).thenReturn(Optional.empty());
        when(empresaService.obtener(MI_EMPRESA)).thenReturn(empresa(MI_EMPRESA));

        materialService.crear(
                MI_EMPRESA, "  vol-st-10  ", "Volcanita ST 10 mm",
                cl.duocuc.checkinobra.cubicacion.CategoriaMaterial.VOLCANITA, 5980, 40, null);

        ArgumentCaptor<Material> guardado = ArgumentCaptor.forClass(Material.class);
        verify(materialRepository).save(guardado.capture());
        assertThat(guardado.getValue().getSku()).isEqualTo("VOL-ST-10");
    }

    @Test
    void laEtiquetaDeUnaHerramientaSeResuelveEnMayusculas() {
        Herramienta taladro = herramienta("HER-TAL-014", MI_EMPRESA);
        when(herramientaRepository.findByEmpresaIdAndCodigoQr(MI_EMPRESA, "HER-TAL-014")).thenReturn(Optional.of(taladro));

        assertThat(herramientaService.buscarPorCodigoQr(" her-tal-014 ")).isSameAs(taladro);
    }

    @Test
    void unaHerramientaAjenaRespondeLoMismoQueUnaInexistente() {
        // Mismo tipo de excepción y mismo mensaje: distinguirlas permitiría
        // contar las herramientas de la competencia probando códigos (RN-23).
        when(herramientaRepository.findByEmpresaIdAndCodigoQr(MI_EMPRESA, "HER-TAL-014"))
                .thenReturn(Optional.of(herramienta("HER-TAL-014", OTRA_EMPRESA)));

        assertThatThrownBy(() -> herramientaService.buscarPorCodigoQr("HER-TAL-014"))
                .isInstanceOf(NoSuchElementException.class)
                .hasMessage("Código no reconocido");
    }

    @Test
    void darDeAltaDosHerramientasConElMismoCodigoEsUnConflicto() {
        // Antes esto reventaba con una violación de UNIQUE, que llega a la app
        // como un 500 sin explicación.
        when(herramientaRepository.findByEmpresaIdAndCodigoQr(MI_EMPRESA, "HER-TAL-014"))
                .thenReturn(Optional.of(herramienta("HER-TAL-014", MI_EMPRESA)));

        assertThatThrownBy(() -> herramientaService.crear(
                MI_EMPRESA, "her-tal-014", "Otro taladro", "Eléctrica", 50000))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("Ya existe una herramienta con ese código");
        verify(herramientaRepository, never()).save(any());
    }

    @Test
    void unaHerramientaSinCodigoNoSePuedeDarDeAlta() {
        assertThatThrownBy(() -> herramientaService.crear(MI_EMPRESA, "   ", "Taladro", "Eléctrica", 50000))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("obligatorio");
    }

    private static Material material(String sku, String codigoBarra) {
        return Material.builder()
                .id(3L)
                .sku(sku)
                .codigoBarra(codigoBarra)
                .nombre("Material")
                .empresa(empresa(MI_EMPRESA))
                .build();
    }

    private static Herramienta herramienta(String codigo, long empresaId) {
        return Herramienta.builder()
                .id(8L)
                .codigoQr(codigo)
                .nombre("Taladro percutor 800 W")
                .categoria("Eléctrica")
                .estado(EstadoHerramienta.DISPONIBLE)
                .valorReposicion(89990)
                .empresa(empresa(empresaId))
                .build();
    }

    private static Empresa empresa(long id) {
        return Empresa.builder().id(id).nombre("Constructora").rut("76.543.210-K").build();
    }
}
