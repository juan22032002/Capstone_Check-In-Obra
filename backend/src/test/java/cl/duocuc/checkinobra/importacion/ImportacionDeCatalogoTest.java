package cl.duocuc.checkinobra.importacion;

import cl.duocuc.checkinobra.config.AccesoDenegadoException;
import cl.duocuc.checkinobra.config.Empresa;
import cl.duocuc.checkinobra.config.EmpresaService;
import cl.duocuc.checkinobra.config.RolUsuario;
import cl.duocuc.checkinobra.config.UsuarioAutenticado;
import cl.duocuc.checkinobra.cubicacion.CategoriaMaterial;
import cl.duocuc.checkinobra.cubicacion.FilaMaterial;
import cl.duocuc.checkinobra.cubicacion.Material;
import cl.duocuc.checkinobra.cubicacion.MaterialRepository;
import cl.duocuc.checkinobra.cubicacion.MaterialService;
import cl.duocuc.checkinobra.inventario.EstadoHerramienta;
import cl.duocuc.checkinobra.inventario.FilaHerramienta;
import cl.duocuc.checkinobra.inventario.Herramienta;
import cl.duocuc.checkinobra.inventario.HerramientaRepository;
import cl.duocuc.checkinobra.inventario.HerramientaService;
import org.apache.poi.ss.usermodel.Row;
import org.apache.poi.ss.usermodel.Sheet;
import org.apache.poi.ss.usermodel.Workbook;
import org.apache.poi.xssf.usermodel.XSSFWorkbook;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.context.SecurityContextHolder;

import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyCollection;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.lenient;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * La importación masiva es <b>todo o nada</b> (RN-31) y simula por defecto. Las
 * dos cosas son fáciles de romper al refactorizar y caras de descubrir después:
 * un catálogo importado a medias no se puede deshacer desde la app, y una
 * simulación que escribiera dejaría de ser una simulación.
 *
 * <p>Con repositorios simulados: lo que se prueba es la decisión de guardar o
 * no, que no necesita base de datos.
 */
@ExtendWith(MockitoExtension.class)
class ImportacionDeCatalogoTest {

    private static final long MI_EMPRESA = 1L;

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
        // La empresa sale del token, nunca de la petición (RN-22): sin sesión en
        // el contexto, AccesoEmpresa no tiene contra qué comparar.
        autenticarEn(MI_EMPRESA);

        materialService = new MaterialService(materialRepository, empresaService);
        herramientaService = new HerramientaService(herramientaRepository, empresaService);

        Empresa empresa = Empresa.builder().id(MI_EMPRESA).nombre("Constructora").rut("76.543.210-K").build();
        lenient().when(empresaService.obtener(MI_EMPRESA)).thenReturn(empresa);
    }

    @AfterEach
    void limpiarSesion() {
        SecurityContextHolder.clearContext();
    }

    @Test
    void simular_noEscribeNadaYCuentaLoQueEntraria() {
        catalogoVacio();

        ResultadoImportacion informe = materialService.importar(MI_EMPRESA, dosMateriales(), false);

        assertThat(informe.confirmado()).isFalse();
        assertThat(informe.filasLeidas()).isEqualTo(2);
        assertThat(informe.filasValidas()).isEqualTo(2);
        assertThat(informe.importadas()).isZero();
        assertThat(informe.errores()).isEmpty();
        verify(materialRepository, never()).saveAll(any());
    }

    @Test
    void confirmar_guardaTodasLasFilasConLaEmpresaDelToken() {
        catalogoVacio();

        ResultadoImportacion informe = materialService.importar(MI_EMPRESA, dosMateriales(), true);

        assertThat(informe.confirmado()).isTrue();
        assertThat(informe.importadas()).isEqualTo(2);

        @SuppressWarnings("unchecked")
        ArgumentCaptor<List<Material>> guardados = ArgumentCaptor.forClass(List.class);
        verify(materialRepository).saveAll(guardados.capture());

        assertThat(guardados.getValue()).hasSize(2);
        assertThat(guardados.getValue()).allSatisfy(
                m -> assertThat(m.getEmpresa().getId()).isEqualTo(MI_EMPRESA));
        assertThat(guardados.getValue().getFirst().getSku()).isEqualTo("VOL-ST-10");
        assertThat(guardados.getValue().getFirst().getCategoria()).isEqualTo(CategoriaMaterial.VOLCANITA);
        assertThat(guardados.getValue().getFirst().getPrecioUnitario()).isEqualTo(5980);
        // La segunda fila viene sin código de barras: es opcional y no se
        // guarda como cadena vacía, porque la columna es UNIQUE y dos vacíos
        // chocarían entre sí.
        assertThat(guardados.getValue().getLast().getCodigoBarra()).isNull();
    }

    @Test
    void unaFilaMalaImpideGuardarTodoElArchivo() {
        // Todo o nada: la fila 3 tiene una categoría inventada, así que las dos
        // buenas tampoco entran. Importar "lo que se pueda" dejaría el catálogo
        // a medias y sin forma de saber qué quedó adentro.
        catalogoVacio();

        ResultadoImportacion informe = materialService.importar(
                MI_EMPRESA,
                planilla(
                        FilaMaterial.ENCABEZADOS,
                        List.of("VOL-ST-10", "Volcanita ST 10 mm", "VOLCANITA", "5980", "40", ""),
                        List.of("X-1", "Plancha rara", "PLANCHA", "100", "1", ""),
                        List.of("MET-MON-60", "Montante 60 mm", "METALCOM", "2450", "120", "")),
                true);

        assertThat(informe.importadas()).isZero();
        assertThat(informe.filasValidas()).isEqualTo(2);
        assertThat(informe.errores()).singleElement().satisfies(error -> {
            // El número es el que muestra Excel: la fila 1 es el encabezado.
            assertThat(error.fila()).isEqualTo(3);
            assertThat(error.detalle()).contains("PLANCHA");
        });
        verify(materialRepository, never()).saveAll(any());
    }

    @Test
    void unSkuRepetidoDentroDelMismoArchivoSeDetectaAunqueLaBaseEsteVacia() {
        // La base no puede verlo: todavía no se guardó nada. Es el error más
        // frecuente al pegar filas desde otra planilla.
        catalogoVacio();

        ResultadoImportacion informe = materialService.importar(
                MI_EMPRESA,
                planilla(
                        FilaMaterial.ENCABEZADOS,
                        List.of("VOL-ST-10", "Volcanita ST 10 mm", "VOLCANITA", "5980", "40", ""),
                        List.of("vol-st-10", "Volcanita repetida", "VOLCANITA", "6100", "40", "")),
                true);

        assertThat(informe.errores()).singleElement().satisfies(error -> {
            assertThat(error.fila()).isEqualTo(3);
            assertThat(error.detalle()).contains("se repite en la planilla");
        });
        verify(materialRepository, never()).saveAll(any());
    }

    @Test
    void unSkuQueYaExisteEnElCatalogoSeReporta() {
        when(materialRepository.findByEmpresaIdAndSkuIn(anyLong(), anyCollection()))
                .thenReturn(List.of(Material.builder().id(9L).sku("VOL-ST-10").build()));
        when(materialRepository.findByEmpresaIdAndCodigoBarraIn(anyLong(), anyCollection()))
                .thenReturn(List.of());

        ResultadoImportacion informe = materialService.importar(MI_EMPRESA, dosMateriales(), true);

        assertThat(informe.errores()).singleElement().satisfies(
                error -> assertThat(error.detalle()).contains("Ya existe un material con el SKU"));
        verify(materialRepository, never()).saveAll(any());
    }

    @Test
    void elArchivoSeContrastaConLaBaseEnDosConsultas_noEnDosPorFila() {
        // El tope es de 2.000 filas: preguntando fila por fila serían cuatro
        // mil idas a la base para responder algo que cabe en dos.
        catalogoVacio();

        materialService.importar(
                MI_EMPRESA,
                planilla(
                        FilaMaterial.ENCABEZADOS,
                        List.of("VOL-ST-10", "Volcanita ST 10 mm", "VOLCANITA", "5980", "40", "780000000001"),
                        List.of("MET-MON-60", "Montante 60 mm", "METALCOM", "2450", "120", "780000000002"),
                        List.of("OSB-11-120240", "OSB 11,1 mm", "OSB", "12990", "20", "780000000003")),
                false);

        verify(materialRepository, times(1)).findByEmpresaIdAndSkuIn(anyLong(), anyCollection());
        verify(materialRepository, times(1)).findByEmpresaIdAndCodigoBarraIn(anyLong(), anyCollection());
        verify(materialRepository, never()).findByEmpresaIdAndSkuIgnoreCase(anyLong(), anyString());
        verify(materialRepository, never()).findByEmpresaIdAndCodigoBarra(anyLong(), anyString());
    }

    @Test
    void unaPlanillaSinFilasConDatosNoEsUnaImportacionVacia() {
        // Es casi siempre el archivo equivocado, y decirlo evita el "importó 0
        // y no sé por qué".
        assertThatThrownBy(() -> materialService.importar(MI_EMPRESA, planilla(FilaMaterial.ENCABEZADOS), false))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("ninguna fila con datos");
    }

    @Test
    void nadieImportaAlCatalogoDeOtraConstructora() {
        assertThatThrownBy(() -> materialService.importar(2L, dosMateriales(), true))
                .isInstanceOf(AccesoDenegadoException.class);
        verify(materialRepository, never()).saveAll(any());
    }

    @Test
    void lasHerramientasImportadasNacenDisponiblesYConElCodigoNormalizado() {
        when(herramientaRepository.findByEmpresaIdAndCodigoQrIn(anyLong(), anyCollection())).thenReturn(List.of());

        ResultadoImportacion informe = herramientaService.importar(
                MI_EMPRESA,
                planilla(
                        FilaHerramienta.ENCABEZADOS,
                        List.of("her-tal-014", "Taladro percutor 800 W", "Eléctrica", "89.990")),
                true);

        assertThat(informe.importadas()).isEqualTo(1);

        @SuppressWarnings("unchecked")
        ArgumentCaptor<List<Herramienta>> guardadas = ArgumentCaptor.forClass(List.class);
        verify(herramientaRepository).saveAll(guardadas.capture());

        Herramienta herramienta = guardadas.getValue().getFirst();
        assertThat(herramienta.getCodigoQr()).isEqualTo("HER-TAL-014");
        assertThat(herramienta.getValorReposicion()).isEqualTo(89990);
        // Una herramienta recién dada de alta está en bodega: no puede nacer
        // prestada ni en mantención.
        assertThat(herramienta.getEstado()).isEqualTo(EstadoHerramienta.DISPONIBLE);
    }

    /**
     * Nada de lo que trae la planilla existe todavía. Son dos consultas por
     * archivo —no dos por fila—, así que se simulan una sola vez.
     */
    private void catalogoVacio() {
        lenient().when(materialRepository.findByEmpresaIdAndSkuIn(anyLong(), anyCollection())).thenReturn(List.of());
        lenient()
                .when(materialRepository.findByEmpresaIdAndCodigoBarraIn(anyLong(), anyCollection()))
                .thenReturn(List.of());
    }

    private static void autenticarEn(long empresaId) {
        var usuario = new UsuarioAutenticado(7L, "jorge@constructora.cl", RolUsuario.ADMIN, empresaId);
        SecurityContextHolder.getContext().setAuthentication(
                new UsernamePasswordAuthenticationToken(usuario, null, List.of()));
    }

    private static InputStream dosMateriales() {
        return planilla(
                FilaMaterial.ENCABEZADOS,
                List.of("VOL-ST-10", "Volcanita ST 10 mm", "VOLCANITA", "5980", "40", "7801234567890"),
                List.of("MET-MON-60", "Montante 60 mm", "METALCOM", "2450", "120", ""));
    }

    @SafeVarargs
    private static InputStream planilla(List<String> encabezados, List<String>... filas) {
        try (Workbook libro = new XSSFWorkbook(); ByteArrayOutputStream salida = new ByteArrayOutputStream()) {
            Sheet hoja = libro.createSheet("Hoja 1");
            Row encabezado = hoja.createRow(0);
            for (int i = 0; i < encabezados.size(); i++) {
                encabezado.createCell(i).setCellValue(encabezados.get(i));
            }
            for (int f = 0; f < filas.length; f++) {
                Row fila = hoja.createRow(f + 1);
                for (int c = 0; c < filas[f].size(); c++) {
                    fila.createCell(c).setCellValue(filas[f].get(c));
                }
            }
            libro.write(salida);
            return new ByteArrayInputStream(salida.toByteArray());
        } catch (IOException e) {
            throw new IllegalStateException("No se pudo armar la planilla de prueba", e);
        }
    }
}
