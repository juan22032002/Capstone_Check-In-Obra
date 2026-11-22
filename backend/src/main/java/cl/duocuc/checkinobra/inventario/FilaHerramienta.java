package cl.duocuc.checkinobra.inventario;

import cl.duocuc.checkinobra.importacion.FilaPlanilla;
import cl.duocuc.checkinobra.importacion.Numeros;

import java.util.List;

/**
 * Una fila de la planilla de herramientas, ya validada.
 *
 * <p>El código es el que va impreso en la etiqueta que se pega a la herramienta
 * y el que después se escanea. Se pide en la planilla en vez de generarlo el
 * sistema porque las etiquetas se imprimen antes: cuando llegan veinte
 * taladros con su código pegado, el catálogo tiene que adoptarlos, no
 * renombrarlos.
 */
public record FilaHerramienta(String codigoQr, String nombre, String categoria, double valorReposicion) {

    public static final List<String> ENCABEZADOS =
            List.of("CODIGO", "NOMBRE", "CATEGORIA", "VALOR_REPOSICION");

    public static final List<List<String>> EJEMPLOS = List.of(
            List.of("HER-TAL-014", "Taladro percutor 800 W", "Eléctrica", "89990"),
            List.of("HER-NIV-003", "Nivel láser autonivelante", "Medición", "149990"));

    public static FilaHerramienta desde(FilaPlanilla fila) {
        String codigo = Numeros.obligatorio(fila.texto(0), "El código", 100).toUpperCase();
        String nombre = Numeros.obligatorio(fila.texto(1), "El nombre", 200);
        String categoria = Numeros.obligatorio(fila.texto(2), "La categoría", 100);
        double valor = Numeros.noNegativo(fila.texto(3), "El valor de reposición");

        return new FilaHerramienta(codigo, nombre, categoria, valor);
    }
}
