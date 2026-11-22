package cl.duocuc.checkinobra.importacion;

import org.apache.poi.xssf.usermodel.XSSFWorkbook;
import org.junit.jupiter.api.Test;

import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.util.List;
import java.util.Random;
import java.util.zip.ZipEntry;
import java.util.zip.ZipInputStream;
import java.util.zip.ZipOutputStream;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * SEG12 (#100, S-21): la planilla es un archivo que sube un usuario. Solo {@code .xlsx}, con la
 * firma de un ZIP, y sin dejar que un archivo pequeño se expanda hasta agotar la memoria.
 */
class ExcelSeguroTest {

    private static byte[] xlsxValido() throws IOException {
        try (XSSFWorkbook libro = new XSSFWorkbook(); ByteArrayOutputStream salida = new ByteArrayOutputStream()) {
            var hoja = libro.createSheet("Hoja 1");
            hoja.createRow(0).createCell(0).setCellValue("SKU");
            hoja.createRow(1).createCell(0).setCellValue("VOL-1");
            libro.write(salida);
            return salida.toByteArray();
        }
    }

    private static final String HOJA_ABRE = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>"
            + "<worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\"><sheetData/><!--";
    private static final String HOJA_CIERRA = "--></worksheet>";

    /**
     * El mismo libro con la hoja reemplazada por una hoja <b>válida</b> con {@code relleno} dentro de
     * un comentario XML. Válida a propósito: sin los límites POI la leería sin problema, así que si
     * el archivo se rechaza es por el límite y no porque el contenido sea basura.
     */
    private static byte[] conHojaRellena(byte[] xlsx, byte[] relleno) throws IOException {
        byte[] hoja = new byte[HOJA_ABRE.length() + relleno.length + HOJA_CIERRA.length()];
        System.arraycopy(HOJA_ABRE.getBytes(), 0, hoja, 0, HOJA_ABRE.length());
        System.arraycopy(relleno, 0, hoja, HOJA_ABRE.length(), relleno.length);
        System.arraycopy(HOJA_CIERRA.getBytes(), 0, hoja, HOJA_ABRE.length() + relleno.length, HOJA_CIERRA.length());
        ByteArrayOutputStream salida = new ByteArrayOutputStream();
        try (ZipInputStream zin = new ZipInputStream(new ByteArrayInputStream(xlsx));
                ZipOutputStream zout = new ZipOutputStream(salida)) {
            for (ZipEntry e = zin.getNextEntry(); e != null; e = zin.getNextEntry()) {
                zout.putNextEntry(new ZipEntry(e.getName()));
                zout.write(e.getName().equals("xl/worksheets/sheet1.xml") ? hoja : zin.readAllBytes());
                zout.closeEntry();
            }
        }
        return salida.toByteArray();
    }

    @Test
    void unXlsxNormalSeLee() throws IOException {
        List<FilaPlanilla> filas = LectorPlanilla.leer(new ByteArrayInputStream(xlsxValido()), 1);

        assertThat(filas).hasSize(1);
    }

    @Test
    void unXlsAntiguoSeRechazaAunqueSeaUnExcelValido() {
        // Cabecera de un archivo OLE2 (Excel 97-2003, .xls).
        byte[] ole2 = {(byte) 0xD0, (byte) 0xCF, 0x11, (byte) 0xE0, (byte) 0xA1, (byte) 0xB1, 0x1A, (byte) 0xE1, 0, 0, 0, 0};

        assertThatThrownBy(() -> LectorPlanilla.leer(new ByteArrayInputStream(ole2), 1))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining(".xlsx");
    }

    @Test
    void unArchivoSinLaFirmaDeUnZipSeRechazaSinLlegarAPoi() {
        byte[] texto = "SKU,NOMBRE\nVOL-1,Volcanita\n".getBytes();
        byte[] pdf = "%PDF-1.7 aaaaaaaaaaaa".getBytes();
        byte[] vacio = new byte[0];

        for (byte[] archivo : List.of(texto, pdf, vacio)) {
            assertThatThrownBy(() -> LectorPlanilla.leer(new ByteArrayInputStream(archivo), 1))
                    .isInstanceOf(IllegalArgumentException.class)
                    .hasMessageContaining(".xlsx");
        }
    }

    @Test
    void unZipQueNoEsUnLibroDeExcelSeRechazaConUnMensajeEnCastellano() throws IOException {
        ByteArrayOutputStream salida = new ByteArrayOutputStream();
        try (ZipOutputStream zip = new ZipOutputStream(salida)) {
            zip.putNextEntry(new ZipEntry("hola.txt"));
            zip.write("hola".getBytes());
            zip.closeEntry();
        }

        assertThatThrownBy(() -> LectorPlanilla.leer(new ByteArrayInputStream(salida.toByteArray()), 1))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("planilla");
    }

    /** Se comprime a unos 60 KB y se expande a 60 MB: mil veces, algo que ninguna planilla real hace. */
    @Test
    void unaBombaDeCompresionSeRechazaPorSuProporcion() throws IOException {
        byte[] espacios = new byte[60 * 1024 * 1024];
        java.util.Arrays.fill(espacios, (byte) ' ');
        byte[] bomba = conHojaRellena(xlsxValido(), espacios);

        assertThat(bomba.length).isLessThan(2 * 1024 * 1024);
        assertThatThrownBy(() -> LectorPlanilla.leer(new ByteArrayInputStream(bomba), 1))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("planilla");
    }

    /** Una hoja enorme pero poco comprimible: no la frena la proporción, la frena el tope por entrada. */
    @Test
    void unaHojaMasGrandeQueElTopeSeRechazaAunqueSuProporcionSeaNormal() throws IOException {
        byte[] relleno = new byte[LectorPlanilla.MAXIMO_BYTES_POR_ENTRADA + 1024 * 1024];
        Random azar = new Random(7);
        for (int i = 0; i < relleno.length; i++) {
            relleno[i] = (byte) ('a' + azar.nextInt(16)); // 4 bits por byte: comprime ~2:1, muy sobre 0,02
        }
        byte[] grande = conHojaRellena(xlsxValido(), relleno);

        assertThat((double) grande.length / relleno.length).isGreaterThan(LectorPlanilla.PROPORCION_MINIMA_DE_COMPRESION * 5);
        assertThatThrownBy(() -> LectorPlanilla.leer(new ByteArrayInputStream(grande), 1))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("planilla");
    }

    /** La misma hoja pero bajo el tope se lee: el rechazo anterior es por el tamaño y no por la forma. */
    @Test
    void unaHojaGrandeBajoElTopeSiSeLee() throws IOException {
        byte[] relleno = new byte[2 * 1024 * 1024];
        Random azar = new Random(9);
        for (int i = 0; i < relleno.length; i++) {
            relleno[i] = (byte) ('a' + azar.nextInt(16));
        }

        List<FilaPlanilla> filas = LectorPlanilla.leer(
                new ByteArrayInputStream(conHojaRellena(xlsxValido(), relleno)), 1);

        assertThat(filas).isEmpty();
    }

    @Test
    void soloSeAceptaElNombreXlsx() {
        LectorPlanilla.exigirNombreXlsx("materiales.xlsx");
        LectorPlanilla.exigirNombreXlsx("MATERIALES.XLSX");

        for (String nombre : new String[] {"materiales.xls", "materiales.csv", "materiales.xlsx.exe", "xlsx", "", null}) {
            assertThatThrownBy(() -> LectorPlanilla.exigirNombreXlsx(nombre))
                    .as(String.valueOf(nombre)).isInstanceOf(IllegalArgumentException.class).hasMessageContaining(".xlsx");
        }
    }

    @Test
    void laProporcionYElTopeQuedanConfigurados() throws IOException {
        // Se ejecuta una lectura para asegurar que la configuración global de POI ya se aplicó.
        LectorPlanilla.leer(new ByteArrayInputStream(xlsxValido()), 1);

        assertThat(org.apache.poi.openxml4j.util.ZipSecureFile.getMinInflateRatio())
                .isGreaterThanOrEqualTo(LectorPlanilla.PROPORCION_MINIMA_DE_COMPRESION);
        assertThat(org.apache.poi.openxml4j.util.ZipSecureFile.getMaxEntrySize())
                .isLessThanOrEqualTo((long) LectorPlanilla.MAXIMO_BYTES_POR_ENTRADA);
    }
}
