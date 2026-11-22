package cl.duocuc.checkinobra.config;

/**
 * El refresh token no sirve: no existe, venció, fue revocado o ya se usó. La app debe volver a
 * pedir la clave. Sale como 401 con {@code codigo=SESION_INVALIDA}, sin decir cuál de esos fue.
 */
public class SesionInvalidaException extends RuntimeException {

    public static final String CODIGO = "SESION_INVALIDA";

    public SesionInvalidaException() {
        super("La sesión no es válida o venció: vuelve a iniciar sesión");
    }
}
