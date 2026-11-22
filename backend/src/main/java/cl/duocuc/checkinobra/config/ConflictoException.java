package cl.duocuc.checkinobra.config;

/**
 * Un {@link IllegalStateException} que además dice <b>cuál</b> conflicto es.
 *
 * <p>Sale como 409 igual que cualquier otro, pero lleva un {@code codigo} en el
 * cuerpo del error. La app lo necesita para decidir qué hacer sin leer el
 * mensaje: un 409 por stock insuficiente se le muestra al bodeguero y no se
 * reintenta, uno por una solicitud que ya se aprobó significa "ya estaba
 * hecho", y uno por dos escrituras que chocaron se puede reintentar.
 */
public class ConflictoException extends IllegalStateException {

    public static final String STOCK_INSUFICIENTE = "STOCK_INSUFICIENTE";
    public static final String YA_RESUELTA = "YA_RESUELTA";
    public static final String YA_DEVUELTO = "YA_DEVUELTO";
    public static final String OBRA_CERRADA = "OBRA_CERRADA";
    /** El trabajador no está en ninguna cuadrilla, así que no tiene obra desde la cual pedir. */
    public static final String SIN_CUADRILLA = "SIN_CUADRILLA";
    /** El trabajador pidió para una obra que no es la de su cuadrilla. */
    public static final String OBRA_NO_ASIGNADA = "OBRA_NO_ASIGNADA";
    public static final String HERRAMIENTA_NO_DISPONIBLE = "HERRAMIENTA_NO_DISPONIBLE";
    /** Ya hay una solicitud pendiente del mismo trabajador por la misma herramienta. */
    public static final String SOLICITUD_DUPLICADA = "SOLICITUD_DUPLICADA";
    /** Se quiso confirmar la recepción de algo que bodega todavía no entrega. */
    public static final String NO_ENTREGADA = "NO_ENTREGADA";
    /** El pedido especial no puede pasar a ese estado desde el que tiene. */
    public static final String TRANSICION_INVALIDA = "TRANSICION_INVALIDA";
    /** El presupuesto está CONGELADO (RN-12): ya no admite cambios. */
    public static final String PRESUPUESTO_CONGELADO = "PRESUPUESTO_CONGELADO";
    /** La partida es de otra obra que el presupuesto al que se quiere agregar. */
    public static final String PARTIDA_DE_OTRA_OBRA = "PARTIDA_DE_OTRA_OBRA";
    /** La partida todavía no se cubicó: no hay ítems que agregar. */
    public static final String PARTIDA_SIN_CUBICAR = "PARTIDA_SIN_CUBICAR";
    /** La solicitud es parte de un pedido con QR: se entrega o se cancela el pedido entero. */
    public static final String EN_PEDIDO = "EN_PEDIDO";

    private final String codigo;

    public ConflictoException(String codigo, String mensaje) {
        super(mensaje);
        this.codigo = codigo;
    }

    public String codigo() {
        return codigo;
    }
}
