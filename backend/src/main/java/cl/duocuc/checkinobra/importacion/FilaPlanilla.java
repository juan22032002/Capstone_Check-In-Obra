package cl.duocuc.checkinobra.importacion;

import java.util.List;

/**
 * Una fila de la planilla, ya leída como texto plano.
 *
 * <p>Todo llega como {@code String} a propósito. Excel guarda "12.000" como el
 * número 12000, "0080" como 80 y una fecha como un serial, así que confiar en
 * el tipo de la celda hace que el mismo archivo se lea distinto según cómo lo
 * haya formateado quien lo llenó. Se lee el texto tal como se ve en pantalla y
 * la conversión la hace quien conoce el campo.
 *
 * @param numero número de fila <b>como lo muestra Excel</b> (1 es el
 *               encabezado), para que un error se pueda ir a corregir sin
 *               contar filas a mano
 */
public record FilaPlanilla(int numero, List<String> celdas) {

    /** La celda de esa columna, o cadena vacía si no existe o está en blanco. */
    public String texto(int columna) {
        return columna < celdas.size() ? celdas.get(columna) : "";
    }

    /**
     * Una fila con todas sus celdas en blanco. Se ignora en vez de reportarla:
     * las planillas reales vienen con filas sueltas al final, y marcarlas como
     * error obligaría a limpiar el archivo por algo que no dice nada.
     */
    public boolean vacia() {
        return celdas.stream().allMatch(String::isBlank);
    }
}
