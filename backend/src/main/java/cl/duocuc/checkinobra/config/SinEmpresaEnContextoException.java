package cl.duocuc.checkinobra.config;

/**
 * Se intentó abrir una base sin empresa en el contexto, o con una que no está
 * registrada. No hay base por defecto, así que la operación falla en vez de caer
 * en una cualquiera: sería justo el cruce entre empresas que esto evita.
 *
 * <p>No es un {@link IllegalStateException} a propósito: ese sale como 409 y esto es
 * un error del servidor, no un conflicto que el cliente pueda resolver.
 */
public class SinEmpresaEnContextoException extends RuntimeException {

    public SinEmpresaEnContextoException(String mensaje) {
        super(mensaje);
    }
}
