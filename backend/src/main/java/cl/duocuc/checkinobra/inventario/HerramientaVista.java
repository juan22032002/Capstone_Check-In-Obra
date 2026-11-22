package cl.duocuc.checkinobra.inventario;

/**
 * Lo que un usuario ve de una herramienta: {@link HerramientaResponse}, con su
 * valor de reposición, o {@link HerramientaBasicaResponse}, sin él, para el
 * trabajador (S-08).
 */
public sealed interface HerramientaVista permits HerramientaResponse, HerramientaBasicaResponse {
}
