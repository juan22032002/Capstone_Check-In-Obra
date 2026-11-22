package cl.duocuc.checkinobra.config;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Component;

import java.util.List;

/**
 * Al arrancar, migra la base de cada empresa del catálogo y abre las que quedaron al día
 * (MT3, #106). Corre después de registrar la base actual y antes de crear su administrador.
 * Una base que falla queda anotada en el catálogo y sin abrir; las demás siguen.
 */
@Component
@Order(1)
public class MigracionInicializador implements ApplicationRunner {

    private static final Logger log = LoggerFactory.getLogger(MigracionInicializador.class);

    private final MigradorDeBases migrador;
    private final ResolutorDeBases resolutor;

    public MigracionInicializador(MigradorDeBases migrador, ResolutorDeBases resolutor) {
        this.migrador = migrador;
        this.resolutor = resolutor;
    }

    @Override
    public void run(ApplicationArguments args) {
        List<MigradorDeBases.Resultado> resultados = migrador.migrarTodas();
        long fallidas = resultados.stream().filter(r -> !r.ok()).count();
        log.info("Migraciones: {} base(s) revisada(s), {} con error.", resultados.size(), fallidas);
        // Recién ahora se sabe cuáles bases quedaron al día: se abren sus pools.
        resolutor.refrescar();
    }
}
