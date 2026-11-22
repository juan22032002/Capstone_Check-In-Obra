package cl.duocuc.checkinobra.cubicacion;

import cl.duocuc.checkinobra.importacion.FilaPlanilla;
import cl.duocuc.checkinobra.importacion.Numeros;

import java.util.Arrays;
import java.util.List;
import java.util.stream.Collectors;

/**
 * Una fila de la planilla de materiales, ya validada.
 *
 * <p>Está separada del servicio a propósito: acá vive todo lo que se puede
 * decidir mirando la fila sola, sin base de datos. Lo que sí necesita la base
 * —que el SKU no exista ya— lo comprueba {@code MaterialService}.
 */
public record FilaMaterial(
        String sku,
        String nombre,
        CategoriaMaterial categoria,
        double precioUnitario,
        double stockMinimo,
        String codigoBarra) {

    /** El orden manda: el lector va por posición, no por el nombre de la columna. */
    public static final List<String> ENCABEZADOS =
            List.of("SKU", "NOMBRE", "CATEGORIA", "PRECIO_UNITARIO", "STOCK_MINIMO", "CODIGO_BARRA");

    public static final List<List<String>> EJEMPLOS = List.of(
            List.of("VOL-ST-10-120240", "Volcanita ST 10 mm 1,20 x 2,40", "VOLCANITA", "5980", "40", "7801234567890"),
            List.of("MET-MON-60-3M", "Montante Metalcom 60 mm x 3 m", "METALCOM", "2450", "120", ""));

    /**
     * @throws IllegalArgumentException con un mensaje que se pueda mostrar tal
     *         cual al lado del número de fila
     */
    public static FilaMaterial desde(FilaPlanilla fila) {
        String sku = Numeros.obligatorio(fila.texto(0), "El SKU", 50).toUpperCase();
        String nombre = Numeros.obligatorio(fila.texto(1), "El nombre", 200);
        CategoriaMaterial categoria = categoriaDe(fila.texto(2));
        double precio = Numeros.noNegativo(fila.texto(3), "El precio unitario");
        double minimo = Numeros.noNegativo(fila.texto(4), "El stock mínimo");
        String codigoBarra = Numeros.opcional(fila.texto(5), "El código de barras", 50);

        return new FilaMaterial(sku, nombre, categoria, precio, minimo, codigoBarra);
    }

    private static CategoriaMaterial categoriaDe(String texto) {
        String limpio = texto.trim().toUpperCase();
        if (limpio.isEmpty()) {
            throw new IllegalArgumentException("La categoría es obligatoria" + valoresValidos());
        }
        return Arrays.stream(CategoriaMaterial.values())
                .filter(c -> c.name().equals(limpio))
                .findFirst()
                .orElseThrow(() -> new IllegalArgumentException(
                        "La categoría '" + texto.trim() + "' no existe" + valoresValidos()));
    }

    private static String valoresValidos() {
        return " (válidas: "
                + Arrays.stream(CategoriaMaterial.values()).map(Enum::name).collect(Collectors.joining(", "))
                + ")";
    }
}
