package cl.duocuc.checkinobra.importacion;

import cl.duocuc.checkinobra.cubicacion.CategoriaMaterial;
import cl.duocuc.checkinobra.cubicacion.FilaMaterial;
import cl.duocuc.checkinobra.inventario.FilaHerramienta;
import org.apache.poi.ss.usermodel.Row;
import org.apache.poi.ss.usermodel.Sheet;
import org.apache.poi.ss.usermodel.Workbook;
import org.apache.poi.xssf.usermodel.XSSFWorkbook;
import org.junit.jupiter.api.Test;

import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * La importación masiva se come archivos que llena una persona en Excel, y ahí
 * el mismo número aparece escrito de cinco formas distintas. Estas pruebas
 * clavan cómo se leen: son pura lectura y validación de filas, así que corren
 * sin base de datos ni contexto de Spring.
 */
class PlanillaDeImportacionTest {

    @Test
    void leeLasFilasSaltandoElEncabezadoYLasFilasEnBlanco() throws IOException {
        byte[] archivo = planilla(
                FilaMaterial.ENCABEZADOS,
                List.of("VOL-ST-10", "Volcanita ST 10 mm", "VOLCANITA", "5980", "40", "7801234567890"),
                List.of("", "", "", "", "", ""),
                List.of("MET-MON-60", "Montante 60 mm", "METALCOM", "2450", "120", ""));

        List<FilaPlanilla> filas = LectorPlanilla.leer(new ByteArrayInputStream(archivo), 6);

        assertThat(filas).hasSize(2);
        // El número es el que muestra Excel, para poder ir a corregir la fila.
        assertThat(filas.get(0).numero()).isEqualTo(2);
        assertThat(filas.get(1).numero()).isEqualTo(4);
    }

    @Test
    void unArchivoQueNoEsExcelSeExplicaEnCastellano() {
        InputStream csv = new ByteArrayInputStream("SKU,NOMBRE\nVOL-1,Volcanita\n".getBytes());

        assertThatThrownBy(() -> LectorPlanilla.leer(csv, 6))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("archivo Excel");
    }

    @Test
    void unPdfConNombreDeExcelTambienSeExplicaEnCastellano() {
        // POI distingue el formato por los primeros bytes, no por la extensión.
        // Sin capturar su excepción propia, lo que llegaba a la app era su
        // mensaje en inglés sobre streams OLE2.
        InputStream pdf = new ByteArrayInputStream("%PDF-1.7\n%\u00E2\u00E3\u00CF\u00D3\n".getBytes());

        assertThatThrownBy(() -> LectorPlanilla.leer(pdf, 6))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("archivo Excel");
    }

    @Test
    void lasCantidadesSeLeenComoLasEscribeUnChileno() {
        // Miles con punto, decimales con coma: 5.980 son cinco mil novecientos
        // ochenta, no cinco coma noventa y ocho.
        assertThat(Numeros.decimal("5.980", "El precio")).isEqualTo(5980);
        assertThat(Numeros.decimal("$ 12.500", "El precio")).isEqualTo(12500);
        assertThat(Numeros.decimal("1.234.567", "El precio")).isEqualTo(1234567);
        assertThat(Numeros.decimal("12,5", "La cantidad")).isEqualTo(12.5);
        assertThat(Numeros.decimal("12.500,75", "El precio")).isEqualTo(12500.75);
        // Un punto que no deja tres dígitos detrás es decimal, no separador.
        assertThat(Numeros.decimal("12.5", "La cantidad")).isEqualTo(12.5);
        assertThat(Numeros.decimal("0.75", "La cantidad")).isEqualTo(0.75);
        // Tres dígitos detrás de un cero no son miles: 0.750 kilos es una
        // cantidad, no setecientos cincuenta.
        assertThat(Numeros.decimal("0.750", "La cantidad")).isEqualTo(0.75);
        assertThat(Numeros.decimal("12.500.000", "El precio")).isEqualTo(12_500_000);
        assertThat(Numeros.decimal("-5.980", "El ajuste")).isEqualTo(-5980);
        // Un primer grupo de cuatro dígitos no tiene forma de miles.
        assertThat(Numeros.decimal("1234.567", "La cantidad")).isEqualTo(1234.567);
    }

    @Test
    void unPrecioQueNoEsNumeroDiceCualCampoEs() {
        assertThatThrownBy(() -> Numeros.decimal("cinco mil", "El precio unitario"))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("El precio unitario")
                .hasMessageContaining("cinco mil");

        assertThatThrownBy(() -> Numeros.noNegativo("-3", "El stock mínimo"))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("no puede ser negativo");
    }

    @Test
    void unaFilaDeMaterialValidaQuedaNormalizada() {
        FilaMaterial material = FilaMaterial.desde(new FilaPlanilla(
                2, List.of("vol-st-10", "  Volcanita ST 10 mm  ", "volcanita", "5.980", "40", "7801234567890")));

        assertThat(material.sku()).isEqualTo("VOL-ST-10");
        assertThat(material.nombre()).isEqualTo("Volcanita ST 10 mm");
        assertThat(material.categoria()).isEqualTo(CategoriaMaterial.VOLCANITA);
        assertThat(material.precioUnitario()).isEqualTo(5980);
        assertThat(material.stockMinimo()).isEqualTo(40);
        assertThat(material.codigoBarra()).isEqualTo("7801234567890");
    }

    @Test
    void elCodigoDeBarrasEsOpcional() {
        FilaMaterial material = FilaMaterial.desde(
                new FilaPlanilla(2, List.of("MET-MON-60", "Montante 60 mm", "METALCOM", "2450", "120", "")));

        assertThat(material.codigoBarra()).isNull();
    }

    @Test
    void unaCategoriaInventadaListaLasValidas() {
        assertThatThrownBy(() -> FilaMaterial.desde(
                new FilaPlanilla(2, List.of("X-1", "Plancha rara", "PLANCHA", "100", "1", ""))))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("PLANCHA")
                .hasMessageContaining("VOLCANITA");
    }

    @Test
    void unSkuVacioNoPasa() {
        assertThatThrownBy(() -> FilaMaterial.desde(
                new FilaPlanilla(7, List.of("", "Volcanita", "VOLCANITA", "100", "1", ""))))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("El SKU es obligatorio");
    }

    @Test
    void unaFilaDeHerramientaValidaQuedaNormalizada() {
        FilaHerramienta herramienta = FilaHerramienta.desde(
                new FilaPlanilla(2, List.of("her-tal-014", "Taladro percutor", "Eléctrica", "89.990")));

        assertThat(herramienta.codigoQr()).isEqualTo("HER-TAL-014");
        assertThat(herramienta.nombre()).isEqualTo("Taladro percutor");
        assertThat(herramienta.categoria()).isEqualTo("Eléctrica");
        assertThat(herramienta.valorReposicion()).isEqualTo(89990);
    }

    @Test
    void laPlantillaQueSeDescargaLaVuelveALeerElMismoLector() {
        byte[] plantilla = PlantillaExcel.generar("Materiales", FilaMaterial.ENCABEZADOS, FilaMaterial.EJEMPLOS);

        List<FilaPlanilla> filas = LectorPlanilla.leer(new ByteArrayInputStream(plantilla), 6);

        // Las filas de ejemplo de la plantilla tienen que ser importables tal
        // cual: si no lo fueran, el primer intento de todo el mundo fallaría.
        assertThat(filas).hasSize(FilaMaterial.EJEMPLOS.size());
        assertThat(filas).allSatisfy(fila -> assertThat(FilaMaterial.desde(fila)).isNotNull());
    }

    @SafeVarargs
    private static byte[] planilla(List<String> encabezados, List<String>... filas) throws IOException {
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
            return salida.toByteArray();
        }
    }
}
