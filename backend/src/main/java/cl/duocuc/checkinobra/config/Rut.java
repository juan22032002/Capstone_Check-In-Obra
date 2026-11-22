package cl.duocuc.checkinobra.config;

import java.util.Locale;

/**
 * RUT chileno: validación del dígito verificador y un único formato guardado.
 *
 * <p>El formato canónico es {@code 12.345.678-5}: con puntos, guion y la K en
 * mayúscula. Es el mismo con que ya estaban guardados los RUT existentes, así
 * que las respuestas no cambian de forma. Lo que importa es que haya uno solo:
 * con "14109556-0" y "14.109.556-0" guardados tal cual, el UNIQUE de la
 * columna los veía distintos y la misma persona quedaba registrada dos veces.
 *
 * <p>Se valida al <b>escribir</b>, nunca al leer. Las bases de desarrollo
 * tienen RUT con el dígito equivocado desde antes de esta validación, y esas
 * filas tienen que seguir cargando.
 */
public final class Rut {

    private Rut() {
    }

    /**
     * @return el RUT en formato canónico
     * @throws IllegalArgumentException si falta, si no tiene forma de RUT o si el
     *     dígito verificador no corresponde (→ 400)
     */
    public static String normalizar(String rut) {
        if (rut == null || rut.isBlank()) {
            throw new IllegalArgumentException("El RUT es obligatorio");
        }
        String limpio = rut.replace(".", "").replace("-", "").replace(" ", "").trim().toUpperCase();
        if (!limpio.matches("[0-9]{1,8}[0-9K]")) {
            throw new IllegalArgumentException("El RUT '" + rut.trim() + "' no tiene un formato válido");
        }
        String cuerpo = limpio.substring(0, limpio.length() - 1);
        char digito = limpio.charAt(limpio.length() - 1);
        if (digitoVerificador(cuerpo) != digito) {
            throw new IllegalArgumentException("El RUT no es válido: revisa el dígito verificador");
        }
        return conPuntos(Long.parseLong(cuerpo)) + "-" + digito;
    }

    /** Módulo 11: se multiplica de derecha a izquierda por 2, 3, 4, 5, 6, 7, 2, 3... */
    static char digitoVerificador(String cuerpo) {
        int suma = 0;
        int factor = 2;
        for (int i = cuerpo.length() - 1; i >= 0; i--) {
            suma += (cuerpo.charAt(i) - '0') * factor;
            factor = factor == 7 ? 2 : factor + 1;
        }
        int resto = 11 - suma % 11;
        return switch (resto) {
            case 11 -> '0';
            case 10 -> 'K';
            default -> (char) ('0' + resto);
        };
    }

    private static String conPuntos(long cuerpo) {
        // Los ceros a la izquierda no son parte del número: "07.123.456" es 7.123.456.
        // Locale.ROOT: con el de la máquina, el separador puede salir como un
        // espacio duro según dónde corra el servidor.
        return String.format(Locale.ROOT, "%,d", cuerpo).replace(',', '.');
    }
}
