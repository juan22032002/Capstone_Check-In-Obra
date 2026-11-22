package cl.duocuc.checkinobra.importacion;

import java.util.List;

/**
 * Lo que devuelve una importación masiva, tanto la simulación como la real.
 *
 * <p>La importación es <b>todo o nada</b>: si una sola fila está mal, no se
 * guarda ninguna. La alternativa —importar lo válido y reportar lo demás—
 * deja el catálogo a medias y obliga a adivinar qué entró y qué no antes de
 * volver a subir el archivo corregido. Acá la planilla es la unidad: se
 * arregla y se sube de nuevo.
 *
 * @param confirmado {@code false} en la simulación, que es lo que la app
 *                   muestra antes de que el administrador apriete el botón
 * @param filasLeidas  filas con contenido, sin contar el encabezado
 * @param filasValidas cuántas pasaron todas las validaciones
 * @param importadas   cuántas quedaron guardadas. Siempre 0 si no se confirmó
 *                     o si hubo errores
 * @param errores      qué está mal y en qué fila, en el orden del archivo
 */
public record ResultadoImportacion(
        boolean confirmado,
        int filasLeidas,
        int filasValidas,
        int importadas,
        List<ErrorFila> errores) {

    /** Un problema concreto, ubicado en la fila que hay que ir a corregir. */
    public record ErrorFila(int fila, String detalle) {
    }

    public static ResultadoImportacion conErrores(int leidas, List<ErrorFila> errores) {
        return new ResultadoImportacion(false, leidas, leidas - errores.size(), 0, errores);
    }

    public static ResultadoImportacion simulada(int leidas) {
        return new ResultadoImportacion(false, leidas, leidas, 0, List.of());
    }

    public static ResultadoImportacion importada(int leidas) {
        return new ResultadoImportacion(true, leidas, leidas, leidas, List.of());
    }
}
