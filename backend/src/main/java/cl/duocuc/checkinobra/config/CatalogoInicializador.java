package cl.duocuc.checkinobra.config;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Component;

/**
 * Al arrancar, deja al día el índice de login de cada empresa con base abierta y cuenta
 * cuántas conoce. Corre después de crear la primera empresa y su administrador.
 */
@Component
@Order(20)
public class CatalogoInicializador implements ApplicationRunner {

    private static final Logger log = LoggerFactory.getLogger(CatalogoInicializador.class);

    private final CatalogoDeEmpresas catalogo;
    private final ResolutorDeBases resolutor;
    private final SincronizadorDeCatalogo sincronizador;

    public CatalogoInicializador(
            CatalogoDeEmpresas catalogo, ResolutorDeBases resolutor, SincronizadorDeCatalogo sincronizador) {
        this.catalogo = catalogo;
        this.resolutor = resolutor;
        this.sincronizador = sincronizador;
    }

    @Override
    public void run(ApplicationArguments args) {
        for (Long empresaId : resolutor.empresas()) {
            try {
                sincronizador.sincronizarIndiceDeLogin(empresaId);
            } catch (RuntimeException e) {
                // Una base que falla no impide arrancar a las demás.
                log.error("No se pudo sincronizar el índice de login de la empresa {}: {}", empresaId, e.getMessage());
            }
        }
        log.info("Catálogo: {} empresa(s) registrada(s), {} con base abierta.",
                catalogo.listar().size(), resolutor.empresas().size());
    }
}
