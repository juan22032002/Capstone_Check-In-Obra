package cl.duocuc.checkinobra.cubicacion;

/**
 * Lo que un usuario ve de un material: {@link MaterialResponse} con precio y costos
 * para quien los maneja, y {@link MaterialBasicoResponse}, sin ellos, para el
 * trabajador (S-08). Son tipos distintos, y no el mismo con campos en nulo, para
 * que el campo no exista en la respuesta en vez de viajar vacío: nadie puede
 * "olvidar" anularlo en un endpoint nuevo si el registro que arma no lo tiene.
 */
public sealed interface MaterialVista permits MaterialResponse, MaterialBasicoResponse {
}
