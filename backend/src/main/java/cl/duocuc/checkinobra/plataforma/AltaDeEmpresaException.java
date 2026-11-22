package cl.duocuc.checkinobra.plataforma;

/**
 * Un paso del alta de una empresa falló por una causa de infraestructura. No es un error del
 * operador: sale como 500 genérico, con el detalle en el log, y el alta ya quedó deshecha.
 */
public class AltaDeEmpresaException extends RuntimeException {

    public AltaDeEmpresaException(String mensaje) {
        super(mensaje);
    }
}
