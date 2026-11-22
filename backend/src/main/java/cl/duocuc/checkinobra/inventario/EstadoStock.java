package cl.duocuc.checkinobra.inventario;

/**
 * Cómo está el saldo de un material en una obra respecto de su stock mínimo.
 *
 * <p>El umbral de BAJO (25 % sobre el mínimo) es el mismo que ya usaba la app
 * para pintar la barra de stock; vive acá para que el aviso de faltantes y la
 * pantalla digan lo mismo.
 */
public enum EstadoStock {
    CRITICO,
    BAJO,
    OK;

    static final double MARGEN_BAJO = 1.25;

    /**
     * Un material sin mínimo definido (0) nunca falta: nadie dijo cuánto
     * debería haber, y marcarlo crítico al quedar en cero sería ruido.
     */
    public static EstadoStock de(double stock, double stockMinimo) {
        if (stockMinimo <= 0) {
            return OK;
        }
        if (stock < stockMinimo) {
            return CRITICO;
        }
        if (stock < stockMinimo * MARGEN_BAJO) {
            return BAJO;
        }
        return OK;
    }
}
