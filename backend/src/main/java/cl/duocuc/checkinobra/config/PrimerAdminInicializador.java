package cl.duocuc.checkinobra.config;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Component;

/**
 * Al arrancar, aplica {@code PRIMER_ADMIN_CLAVE} al administrador inicial si
 * todavía no tiene credencial. Nunca imprime la clave.
 */
@Component
@Order(10)
public class PrimerAdminInicializador implements ApplicationRunner {

    private static final Logger log = LoggerFactory.getLogger(PrimerAdminInicializador.class);

    private final CatalogoDeEmpresas catalogo;
    private final PrimerAdminService primerAdminService;
    private final PrimeraEmpresaService primeraEmpresaService;
    private final String email;
    private final String clave;
    private final String rutEmpresa;
    private final String nombreEmpresa;

    public PrimerAdminInicializador(
            CatalogoDeEmpresas catalogo,
            PrimerAdminService primerAdminService,
            PrimeraEmpresaService primeraEmpresaService,
            @Value("${checkinobra.primer-admin.email:admin@arauco-ltda.cl}") String email,
            @Value("${checkinobra.primer-admin.clave:}") String clave,
            @Value("${checkinobra.primera-empresa.rut:76.412.330-9}") String rutEmpresa,
            @Value("${checkinobra.primera-empresa.nombre:Constructora Arauco Ltda.}") String nombreEmpresa) {
        this.catalogo = catalogo;
        this.primerAdminService = primerAdminService;
        this.primeraEmpresaService = primeraEmpresaService;
        this.email = email;
        this.clave = clave;
        this.rutEmpresa = rutEmpresa;
        this.nombreEmpresa = nombreEmpresa;
    }

    @Override
    public void run(ApplicationArguments args) {
        var empresa = catalogo.buscarPorRut(rutEmpresa);
        if (empresa.isEmpty()) {
            log.warn("La empresa {} no está registrada en el catálogo: no hay administrador al que darle clave.",
                    rutEmpresa);
            return;
        }
        // Fuera de una petición no hay empresa en el contexto: se fija la de esta.
        TenantContext.ejecutarEn(empresa.get().id(), this::aplicar);
    }

    private void aplicar() {
        if (clave == null || clave.isBlank()) {
            if (primerAdminService.hayAdminSinCredencial(email)) {
                log.warn("El administrador {} no tiene clave y nadie puede entrar con él. "
                        + "Define PRIMER_ADMIN_CLAVE (8 o más caracteres) y reinicia la API.", email);
            }
            return;
        }
        // Una clave que no cumple la política hace fallar el arranque: es una
        // configuración equivocada y conviene verla, no que el admin quede sin acceso.
        if (primeraEmpresaService.crearAdminSiNoHay(rutEmpresa, email, clave)) {
            log.info("Se creó el administrador {} de la empresa {}: deberá cambiar la clave en su primer ingreso.",
                    email, rutEmpresa);
            return;
        }
        // Base que ya tenía administrador sin credencial (la semilla anulada por V11).
        if (primerAdminService.fijarClaveInicial(email, clave)) {
            log.info("Se fijó la clave inicial de {}: deberá cambiarla en su primer ingreso.", email);
        }
    }
}
