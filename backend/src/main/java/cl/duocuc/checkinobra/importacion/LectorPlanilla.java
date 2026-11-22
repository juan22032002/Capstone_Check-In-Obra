package cl.duocuc.checkinobra.importacion;

import org.apache.poi.EncryptedDocumentException;
import org.apache.poi.UnsupportedFileFormatException;
import org.apache.poi.openxml4j.util.ZipSecureFile;
import org.apache.poi.ss.usermodel.Cell;
import org.apache.poi.ss.usermodel.DataFormatter;
import org.apache.poi.ss.usermodel.Row;
import org.apache.poi.ss.usermodel.Sheet;
import org.apache.poi.ss.usermodel.Workbook;
import org.apache.poi.ss.usermodel.WorkbookFactory;

import java.io.BufferedInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.util.ArrayList;
import java.util.List;

/** Convierte una planilla Excel en filas de texto. */
public final class LectorPlanilla {

    /**
     * Tope de filas por archivo. No es una limitación técnica de POI: es que
     * una importación de catálogo son decenas o cientos de materiales, y un
     * archivo de cien mil filas es casi siempre el archivo equivocado. Fallar
     * temprano dice eso; procesarlo diez minutos y luego fallar, no.
     */
    public static final int MAXIMO_FILAS = 2000;

    /**
     * Tope de bytes que puede ocupar una parte del .xlsx una vez descomprimida. Una planilla de
     * 2.000 filas ocupa unos cientos de kilobytes: veinte megabytes sobran, y es lo que un archivo
     * hostil puede hacer ocupar en memoria por parte.
     */
    public static final int MAXIMO_BYTES_POR_ENTRADA = 20 * 1024 * 1024;

    /**
     * Proporción mínima entre lo comprimido y lo descomprimido (0,02 = hasta 50 veces). Una hoja de
     * cálculo real comprime unas 10 o 20 veces; una "bomba" de ceros, miles.
     */
    public static final double PROPORCION_MINIMA_DE_COMPRESION = 0.02;

    /** Tope de caracteres de texto XML por parte, para la misma amenaza por otro camino. */
    private static final int MAXIMO_TEXTO_XML = 10_000_000;

    /** Un .xlsx es un ZIP: empieza por "PK\u0003\u0004". */
    private static final byte[] FIRMA_ZIP = {'P', 'K', 3, 4};

    private static final String SOLO_XLSX =
            "No se pudo leer la planilla. Debe ser un archivo Excel (.xlsx) sin contraseña.";

    static {
        // Configuración global de POI: no hay otro lector de planillas en la aplicación.
        ZipSecureFile.setMinInflateRatio(PROPORCION_MINIMA_DE_COMPRESION);
        ZipSecureFile.setMaxEntrySize(MAXIMO_BYTES_POR_ENTRADA);
        ZipSecureFile.setMaxTextSize(MAXIMO_TEXTO_XML);
    }

    private LectorPlanilla() {
    }

    /** El archivo subido se llama {@code algo.xlsx}: el nombre no es seguridad, pero evita el error obvio. */
    public static void exigirNombreXlsx(String nombre) {
        if (nombre == null || !nombre.toLowerCase(java.util.Locale.ROOT).endsWith(".xlsx")) {
            throw new IllegalArgumentException(
                    "La planilla debe ser un archivo .xlsx (Excel moderno). Un .xls antiguo no se admite: "
                            + "guárdalo como .xlsx desde Excel.");
        }
    }

    /** Consume los primeros bytes para confirmar que es un ZIP (lo que es un .xlsx), sin perderlos. */
    private static InputStream exigirFirmaZip(InputStream entrada) throws IOException {
        BufferedInputStream con = new BufferedInputStream(entrada);
        con.mark(FIRMA_ZIP.length);
        byte[] cabecera = con.readNBytes(FIRMA_ZIP.length);
        con.reset();
        if (!java.util.Arrays.equals(cabecera, FIRMA_ZIP)) {
            // Un .xls antiguo (OLE2), un .csv, un PDF o un archivo vacío: ninguno es un .xlsx.
            throw new IllegalArgumentException(SOLO_XLSX);
        }
        return con;
    }

    /**
     * Lee la primera hoja, salta el encabezado y devuelve las filas con
     * contenido.
     *
     * @param columnas cuántas columnas leer de cada fila
     */
    public static List<FilaPlanilla> leer(InputStream entrada, int columnas) {
        try (Workbook libro = WorkbookFactory.create(exigirFirmaZip(entrada))) {
            if (libro.getNumberOfSheets() == 0) {
                throw new IllegalArgumentException("La planilla no tiene ninguna hoja");
            }
            Sheet hoja = libro.getSheetAt(0);
            DataFormatter formateador = new DataFormatter();

            List<FilaPlanilla> filas = new ArrayList<>();
            // Se parte en 1: la fila 0 es el encabezado de la plantilla.
            for (int i = 1; i <= hoja.getLastRowNum(); i++) {
                Row fila = hoja.getRow(i);
                List<String> celdas = new ArrayList<>(columnas);
                for (int c = 0; c < columnas; c++) {
                    Cell celda = fila == null ? null : fila.getCell(c);
                    celdas.add(celda == null ? "" : formateador.formatCellValue(celda).trim());
                }
                FilaPlanilla leida = new FilaPlanilla(i + 1, celdas);
                if (!leida.vacia()) {
                    filas.add(leida);
                }
                if (filas.size() > MAXIMO_FILAS) {
                    throw new IllegalArgumentException(
                            "La planilla supera las " + MAXIMO_FILAS + " filas. Divídela en varios archivos.");
                }
            }
            return filas;
        } catch (IOException | EncryptedDocumentException | UnsupportedFileFormatException
                | org.apache.poi.ooxml.POIXMLException | org.apache.poi.util.RecordFormatException e) {
            // El caso frecuente es un .csv o un .xls renombrado a .xlsx, o un
            // archivo con contraseña. Decirlo así ahorra la ronda de "no
            // funciona" — el stack trace de POI no le sirve a un administrador.
            //
            // `UnsupportedFileFormatException` va explícita aunque herede de
            // IllegalArgumentException: sin capturarla, el que llega a la app
            // es el mensaje de POI en inglés ("Your InputStream was neither an
            // OLE2 stream, nor an OOXML stream"), que no le dice nada a quien
            // subió el archivo equivocado.
            // También cubre la bomba de compresión y la parte demasiado grande: POI las corta con una
            // IOException o una POIXMLException antes de llenar la memoria, y no se detalla por qué.
            throw new IllegalArgumentException(SOLO_XLSX);
        }
    }
}
