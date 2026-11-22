package cl.duocuc.checkinobra.control;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;
import jakarta.validation.Valid;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

@RestController
@RequestMapping("/api/alertas")
@Tag(name = "Alerta")
public class AlertaController {

    private final AlertaService alertaService;

    public AlertaController(AlertaService alertaService) {
        this.alertaService = alertaService;
    }

    @GetMapping
    @PreAuthorize("hasAnyRole('ADMIN', 'JEFE_TERRENO', 'BODEGUERO')")
    public List<AlertaResponse> listar(
            @RequestParam Long obraId, @RequestParam(required = false, defaultValue = "false") boolean soloSinResolver) {
        List<Alerta> alertas =
                soloSinResolver ? alertaService.listarSinResolver(obraId) : alertaService.listarPorObra(obraId);
        return alertas.stream().map(AlertaResponse::de).toList();
    }

    /** Resolver una alerta es de BODEGUERO, JEFE_TERRENO o ADMIN, según la matriz de permisos. */
    @PutMapping("/{id}/resolver")
    @PreAuthorize("hasAnyRole('ADMIN', 'JEFE_TERRENO', 'BODEGUERO')")
    public AlertaResponse resolver(@PathVariable Long id) {
        return AlertaResponse.de(alertaService.resolver(id));
    }

    @PostMapping("/detectar-no-devueltas")
    @PreAuthorize("hasAnyRole('ADMIN', 'JEFE_TERRENO', 'BODEGUERO')")
    public List<AlertaResponse> detectarNoDevueltas(@RequestParam Long obraId) {
        return alertaService.detectarNoDevueltas(obraId).stream().map(AlertaResponse::de).toList();
    }

    @PostMapping("/detectar-stock-critico")
    @PreAuthorize("hasAnyRole('ADMIN', 'JEFE_TERRENO', 'BODEGUERO')")
    public List<AlertaResponse> detectarStockCritico(@RequestParam Long obraId) {
        return alertaService.detectarStockCritico(obraId).stream().map(AlertaResponse::de).toList();
    }

    /** Cerrar turno de bodega es exclusivo de BODEGUERO, según la matriz de permisos. */
    @PostMapping("/cierre-turno")
    @PreAuthorize("hasAnyRole('ADMIN', 'BODEGUERO')")
    public AlertaResponse generarCierreTurno(@Valid @RequestBody CierreTurnoRequest req) {
        return AlertaResponse.de(alertaService.generarCierreTurno(req.obraId(), req.mensaje()));
    }

    public record CierreTurnoRequest(
            @NotNull(message = "Falta la obra") Long obraId,
            @NotBlank(message = "El mensaje es obligatorio") @Size(max = 500, message = "El mensaje admite hasta 500 caracteres") String mensaje) {
    }
}
