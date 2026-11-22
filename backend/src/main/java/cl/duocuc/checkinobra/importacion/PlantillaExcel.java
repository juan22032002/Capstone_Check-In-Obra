package cl.duocuc.checkinobra.importacion;

import org.apache.poi.ss.usermodel.Cell;
import org.apache.poi.ss.usermodel.CellStyle;
import org.apache.poi.ss.usermodel.FillPatternType;
import org.apache.poi.ss.usermodel.Font;
import org.apache.poi.ss.usermodel.IndexedColors;
import org.apache.poi.ss.usermodel.Row;
import org.apache.poi.ss.usermodel.Sheet;
import org.apache.poi.ss.usermodel.Workbook;
import org.apache.poi.xssf.usermodel.XSSFWorkbook;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.UncheckedIOException;
import java.util.List;

/**
 * Genera la planilla vacía que se descarga antes de importar.
 *
 * <p>Existe porque el orden de las columnas no es negociable: el lector va por
 * posición, no por el nombre del encabezado. Pedirle a alguien que arme el
 * archivo desde cero termina en columnas cambiadas de lugar y en una
 * importación que falla entera por un detalle que nadie documentó.
 */
public final class PlantillaExcel {

    private PlantillaExcel() {
    }

    /**
     * @param encabezados nombres de las columnas, en orden
     * @param ejemplos    una o dos filas de muestra con datos plausibles
     */
    public static byte[] generar(String hoja, List<String> encabezados, List<List<String>> ejemplos) {
        try (Workbook libro = new XSSFWorkbook(); ByteArrayOutputStream salida = new ByteArrayOutputStream()) {
            Sheet pagina = libro.createSheet(hoja);

            Font negrita = libro.createFont();
            negrita.setBold(true);
            CellStyle estiloEncabezado = libro.createCellStyle();
            estiloEncabezado.setFont(negrita);
            estiloEncabezado.setFillForegroundColor(IndexedColors.GREY_25_PERCENT.getIndex());
            estiloEncabezado.setFillPattern(FillPatternType.SOLID_FOREGROUND);

            Row fila = pagina.createRow(0);
            for (int i = 0; i < encabezados.size(); i++) {
                Cell celda = fila.createCell(i);
                celda.setCellValue(encabezados.get(i));
                celda.setCellStyle(estiloEncabezado);
            }

            // Las filas de ejemplo se escriben como texto para que Excel no
            // reformatee un SKU con guiones ni recorte los ceros de un código
            // de barras.
            for (int f = 0; f < ejemplos.size(); f++) {
                Row ejemplo = pagina.createRow(f + 1);
                List<String> valores = ejemplos.get(f);
                for (int c = 0; c < valores.size(); c++) {
                    ejemplo.createCell(c).setCellValue(valores.get(c));
                }
            }

            for (int i = 0; i < encabezados.size(); i++) {
                pagina.autoSizeColumn(i);
            }

            libro.write(salida);
            return salida.toByteArray();
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }
}
