package cl.duocuc.checkinobra.config;

import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * Solo lectura, y solo de la propia empresa.
 *
 * <p>No hay endpoint para crear constructoras. Lo hubo, y era incoherente: el
 * ADMIN que la creaba no podía verla después, porque el aislamiento por empresa
 * lo dejaba fuera de la que acababa de crear. Dar de alta un tenant no es una
 * operación de un tenant — necesitaría un rol por encima de los cuatro, y este
 * sistema tiene cuatro por diseño (una sola clase {@code Usuario}, el permiso lo
 * decide {@code rol}).
 *
 * <p>Mientras eso siga así, una constructora nueva se da de alta por migración
 * junto con su primer ADMIN, como hacía {@code V2__seed_admin.sql}. El README lo
 * documenta en "Dar de alta una constructora".
 */
@RestController
@RequestMapping("/api/empresas")
@Tag(name = "Empresa")
public class EmpresaController {

    private final EmpresaService empresaService;

    public EmpresaController(EmpresaService empresaService) {
        this.empresaService = empresaService;
    }

    /** La constructora de quien llama. Sale del token, no se puede pedir otra. */
    @GetMapping("/mia")
    public EmpresaResponse mia() {
        return EmpresaResponse.de(empresaService.obtener(SesionActual.empresaId()));
    }

    @GetMapping("/{id}")
    public EmpresaResponse obtener(@PathVariable Long id) {
        return EmpresaResponse.de(empresaService.obtener(id));
    }
}
