package cl.duocuc.checkinobra.plataforma;

import cl.duocuc.checkinobra.config.CatalogoDeEmpresas;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Component;

/**
 * Al arrancar, si el catálogo no tiene ningún operador y se definió {@code PLATAFORMA_OPERADOR_EMAIL}
 * y {@code PLATAFORMA_OPERADOR_CLAVE}, crea el primero. Nunca imprime la clave. Con operadores ya
 * creados no hace nada: no hay forma de que una variable de entorno agregue o reemplace uno.
 */
@Component
@Order(5)
public class OperadorInicialInicializador implements ApplicationRunner {

    private static final Logger log = LoggerFactory.getLogger(OperadorInicialInicializador.class);

    private final CatalogoDeEmpresas catalogo;
    private final String email;
    private final String clave;

    public OperadorInicialInicializador(
            CatalogoDeEmpresas catalogo,
            @Value("${checkinobra.plataforma.operador.email:}") String email,
            @Value("${checkinobra.plataforma.operador.clave:}") String clave) {
        this.catalogo = catalogo;
        this.email = email;
        this.clave = clave;
    }

    @Override
    public void run(ApplicationArguments args) {
        if (catalogo.contarOperadores() > 0 || email.isBlank() || clave.isBlank()) {
            return;
        }
        // Una clave que no cumple la política hace fallar el arranque: es una configuración
        // equivocada y conviene verla, no que la plataforma quede sin operador.
        String hash = PlataformaAutenticacionService.hashDeClave(clave);
        if (catalogo.crearOperador(email, "Operador de plataforma", hash).isPresent()) {
            log.info("Se creó el operador de plataforma {}.", email.trim().toLowerCase());
        }
    }
}
