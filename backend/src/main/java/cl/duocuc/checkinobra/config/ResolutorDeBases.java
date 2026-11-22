package cl.duocuc.checkinobra.config;

import javax.sql.DataSource;
import java.util.Collection;

/** Dice qué base abrir para cada empresa (MT2, #105). */
public interface ResolutorDeBases {

    /**
     * La base de la empresa.
     *
     * @throws SinEmpresaEnContextoException si no hay empresa o no está registrada: no hay base por defecto
     */
    DataSource baseDe(Long empresaId);

    /** ¿Hay una base abierta para esta empresa? Es lo que decide si un token vale. */
    boolean conoce(Long empresaId);

    /** ¿La empresa existe en el catálogo pero está suspendida? Su token no abre nada: se responde 403. */
    default boolean suspendida(Long empresaId) {
        return false;
    }

    /** Las empresas con base abierta, para las tareas que recorren a todas. */
    Collection<Long> empresas();

    /** Vuelve a leer el catálogo: abre la base de una empresa recién registrada. */
    default void refrescar() {
    }
}
