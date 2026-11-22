package cl.duocuc.checkinobra.config;

/**
 * Validación de los textos libres que escribe una persona en el teléfono: el
 * "para qué" de una solicitud, el nombre de algo que no está en el catálogo, una
 * nota de bodega.
 *
 * <p>Recorta antes de medir. Un campo lleno de espacios no dice nada, y sin el
 * recorte pasaría el mínimo.
 */
public final class Texto {

    private Texto() {
    }

    /**
     * El texto recortado, o 400 si queda fuera del largo.
     *
     * @param campo cómo se llama para quien lo escribió, para el mensaje
     */
    public static String obligatorio(String valor, String campo, int minimo, int maximo) {
        String limpio = valor == null ? "" : valor.trim();
        if (limpio.length() < minimo || limpio.length() > maximo) {
            throw new IllegalArgumentException(
                    campo + " debe tener entre " + minimo + " y " + maximo + " caracteres");
        }
        return limpio;
    }

    /** Como {@link #obligatorio}, pero vacío o nulo es válido y queda nulo. */
    public static String opcional(String valor, String campo, int maximo) {
        if (valor == null || valor.isBlank()) {
            return null;
        }
        return obligatorio(valor, campo, 1, maximo);
    }
}
