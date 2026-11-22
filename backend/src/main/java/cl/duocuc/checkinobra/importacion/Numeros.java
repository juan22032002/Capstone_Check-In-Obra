package cl.duocuc.checkinobra.importacion;

import java.util.regex.Pattern;

/** Lee números escritos como los escribe la gente en una planilla. */
public final class Numeros {

    /** "5.980", "-12.500.000"; no "0.750" ni "1234.567". */
    private static final Pattern FORMA_DE_MILES = Pattern.compile("-?[1-9]\\d{0,2}(\\.\\d{3})+");

    private Numeros() {
    }

    /**
     * Convierte el texto de una celda a número.
     *
     * <p>El caso difícil es el punto: en Chile "5.980" son cinco mil novecientos
     * ochenta, y en el formato de Estados Unidos son cinco coma noventa y ocho.
     * La regla que se aplica es la que resuelve bien lo que de verdad llega a
     * un catálogo de materiales:
     *
     * <ul>
     *   <li>con coma y punto ("12.500,75"), el punto separa miles y la coma decimales;</li>
     *   <li>con coma sola ("12,5"), la coma es el decimal;</li>
     *   <li>con punto solo, es separador de miles <b>si</b> el número tiene
     *       forma de miles: un primer grupo de uno a tres dígitos que no empieza
     *       en cero, y después solo grupos de exactamente tres ("5.980" → 5980,
     *       "12.500.000" → 12500000). En cualquier otro caso es decimal
     *       ("12.5" → 12,5, "0.750" → 0,75, "1234.567" → 1234,567).</li>
     * </ul>
     *
     * <p>La condición del cero importa: "0.750" kilos es una cantidad normal en
     * una planilla de materiales, y con solo mirar los tres dígitos se leía
     * como setecientos cincuenta. La app aplica la misma regla al escribir
     * cantidades; si una cambia, la otra también.
     *
     * <p>Queda un caso que se lee mal: "2.500" escrito con intención de dos coma
     * cinco. Es la ambigüedad del formato, no del lector, y se resuelve del lado
     * de es-CL porque esta es la planilla de una constructora chilena.
     */
    public static double decimal(String texto, String campo) {
        String limpio = texto.replace("$", "").replace(" ", "").replace(" ", "").trim();
        if (limpio.isEmpty()) {
            throw new IllegalArgumentException(campo + " está vacío");
        }

        if (limpio.contains(",")) {
            limpio = limpio.replace(".", "").replace(",", ".");
        } else {
            if (FORMA_DE_MILES.matcher(limpio).matches()) {
                limpio = limpio.replace(".", "");
            }
        }

        try {
            double valor = Double.parseDouble(limpio);
            if (Double.isNaN(valor) || Double.isInfinite(valor)) {
                throw new NumberFormatException(limpio);
            }
            return valor;
        } catch (NumberFormatException e) {
            throw new IllegalArgumentException(campo + " no es un número válido: '" + texto + "'");
        }
    }

    /** Igual que {@link #decimal}, pero rechaza los negativos. */
    public static double noNegativo(String texto, String campo) {
        double valor = decimal(texto, campo);
        if (valor < 0) {
            throw new IllegalArgumentException(campo + " no puede ser negativo");
        }
        return valor;
    }

    /** Texto obligatorio, recortado y con el largo que aguanta la columna. */
    public static String obligatorio(String texto, String campo, int largoMaximo) {
        String limpio = texto.trim();
        if (limpio.isEmpty()) {
            throw new IllegalArgumentException(campo + " es obligatorio");
        }
        if (limpio.length() > largoMaximo) {
            throw new IllegalArgumentException(campo + " supera los " + largoMaximo + " caracteres");
        }
        return limpio;
    }

    /** Texto opcional: devuelve {@code null} si la celda viene en blanco. */
    public static String opcional(String texto, String campo, int largoMaximo) {
        String limpio = texto.trim();
        if (limpio.isEmpty()) {
            return null;
        }
        if (limpio.length() > largoMaximo) {
            throw new IllegalArgumentException(campo + " supera los " + largoMaximo + " caracteres");
        }
        return limpio;
    }
}
