package cl.duocuc.checkinobra.inventario;

import jakarta.validation.constraints.DecimalMax;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Positive;
import jakarta.validation.Valid;
import cl.duocuc.checkinobra.config.SesionActual;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.http.HttpStatus;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

import java.math.BigDecimal;
import java.util.List;

@RestController
@RequestMapping("/api/kardex")
@Tag(name = "Kardex")
public class KardexMovimientoController {

    private final KardexMovimientoService kardexMovimientoService;

    public KardexMovimientoController(KardexMovimientoService kardexMovimientoService) {
        this.kardexMovimientoService = kardexMovimientoService;
    }

    /** Recepción, despacho y consumo son de BODEGUERO o ADMIN, según la matriz de permisos. */
    @PostMapping
    @PreAuthorize("hasAnyRole('ADMIN', 'BODEGUERO')")
    @ResponseStatus(HttpStatus.CREATED)
    public KardexMovimientoResponse registrar(@Valid @RequestBody RegistrarMovimientoRequest req) {
        return KardexMovimientoResponse.de(kardexMovimientoService.registrarMovimiento(
                req.obraId(),
                req.materialId(),
                // Quien registra es quien está autenticado. Venía en el cuerpo, y
                // así cualquier bodeguero podía atribuirle un movimiento a otro.
                SesionActual.usuarioId(),
                req.trabajadorId(),
                req.tipo(),
                req.cantidad(),
                req.costoUnitario()));
    }

    /** El movimiento de bodega lo consulta quien lo administra o lo controla, no el trabajador. */
    @GetMapping
    @PreAuthorize("hasAnyRole('ADMIN', 'JEFE_TERRENO', 'BODEGUERO')")
    public List<KardexMovimientoResponse> listarPorObra(@RequestParam Long obraId) {
        return kardexMovimientoService.listarPorObra(obraId).stream().map(KardexMovimientoResponse::de).toList();
    }

    @GetMapping("/stock")
    @PreAuthorize("hasAnyRole('ADMIN', 'JEFE_TERRENO', 'BODEGUERO')")
    public double stockActual(@RequestParam Long obraId, @RequestParam Long materialId) {
        return kardexMovimientoService.stockActual(obraId, materialId);
    }

    public record RegistrarMovimientoRequest(
            @NotNull(message = "Falta la obra") Long obraId,
            @NotNull(message = "Falta el material") Long materialId,
            /** A quién se le entrega. Obligatorio en un DESPACHO. */
            Long trabajadorId,
            @NotNull(message = "Falta el tipo de movimiento") TipoMovimiento tipo,
            @Positive(message = "La cantidad debe ser mayor que 0") @DecimalMax(value = "1000000", message = "La cantidad es demasiado grande") double cantidad,
            /** Costo real por unidad según la factura. Opcional, y solo en una RECEPCION. */
            @Positive(message = "El costo unitario debe ser mayor que 0") @DecimalMax(value = "1000000000", message = "El costo unitario es demasiado grande") BigDecimal costoUnitario) {
    }
}
