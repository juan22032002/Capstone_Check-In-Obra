package cl.duocuc.checkinobra.presupuesto;

import jakarta.validation.constraints.DecimalMax;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Positive;
import jakarta.validation.Valid;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.http.HttpStatus;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

@RestController
@RequestMapping("/api/presupuestos")
@Tag(name = "Presupuesto")
public class PresupuestoController {

    private final PresupuestoService presupuestoService;
    private final ComparadorPresupuestoService comparadorPresupuestoService;

    public PresupuestoController(
            PresupuestoService presupuestoService, ComparadorPresupuestoService comparadorPresupuestoService) {
        this.presupuestoService = presupuestoService;
        this.comparadorPresupuestoService = comparadorPresupuestoService;
    }

    @PostMapping
    @PreAuthorize("hasAnyRole('ADMIN', 'JEFE_TERRENO')")
    @ResponseStatus(HttpStatus.CREATED)
    public PresupuestoResponse crear(@Valid @RequestBody CrearPresupuestoRequest req) {
        return PresupuestoResponse.de(presupuestoService.crear(req.obraId()));
    }

    @GetMapping("/{id}")
    @PreAuthorize("hasAnyRole('ADMIN', 'JEFE_TERRENO', 'BODEGUERO')")
    public PresupuestoResponse obtener(@PathVariable Long id) {
        return PresupuestoResponse.de(presupuestoService.obtener(id));
    }

    @GetMapping
    @PreAuthorize("hasAnyRole('ADMIN', 'JEFE_TERRENO', 'BODEGUERO')")
    public PresupuestoResponse obtenerPorObra(@RequestParam Long obraId) {
        return PresupuestoResponse.de(presupuestoService.obtenerPorObra(obraId));
    }

    @PostMapping("/{id}/items")
    @PreAuthorize("hasAnyRole('ADMIN', 'JEFE_TERRENO')")
    @ResponseStatus(HttpStatus.CREATED)
    public PresupuestoItemResponse agregarItem(@PathVariable Long id, @Valid @RequestBody AgregarItemRequest req) {
        return PresupuestoItemResponse.de(presupuestoService.agregarItem(id, req.materialId(), req.cantidad()));
    }

    /**
     * Agrega de una vez los ítems cubicados de una partida (D5). Atómico: o
     * entran todos o ninguno.
     */
    @PostMapping("/{id}/items/desde-partida")
    @PreAuthorize("hasAnyRole('ADMIN', 'JEFE_TERRENO')")
    @ResponseStatus(HttpStatus.CREATED)
    public List<PresupuestoItemResponse> agregarItemsDePartida(
            @PathVariable Long id, @Valid @RequestBody AgregarItemsDePartidaRequest req) {
        return presupuestoService.agregarItemsDePartida(id, req.partidaId()).stream()
                .map(PresupuestoItemResponse::de)
                .toList();
    }

    @GetMapping("/{id}/items")
    @PreAuthorize("hasAnyRole('ADMIN', 'JEFE_TERRENO', 'BODEGUERO')")
    public List<PresupuestoItemResponse> listarItems(@PathVariable Long id) {
        return presupuestoService.listarItems(id).stream().map(PresupuestoItemResponse::de).toList();
    }

    @PutMapping("/{id}/aprobar")
    @PreAuthorize("hasAnyRole('ADMIN', 'JEFE_TERRENO')")
    public PresupuestoResponse aprobar(@PathVariable Long id) {
        return PresupuestoResponse.de(presupuestoService.aprobar(id));
    }

    /** Congelar el presupuesto es de JEFE_TERRENO o ADMIN, según la matriz de permisos. */
    @PutMapping("/{id}/congelar")
    @PreAuthorize("hasAnyRole('ADMIN', 'JEFE_TERRENO')")
    public PresupuestoResponse congelar(@PathVariable Long id) {
        return PresupuestoResponse.de(presupuestoService.congelar(id));
    }

    @GetMapping("/{id}/desviacion")
    @PreAuthorize("hasAnyRole('ADMIN', 'JEFE_TERRENO', 'BODEGUERO')")
    public ReporteDesviacion desviacion(@PathVariable Long id) {
        return comparadorPresupuestoService.compararVsEjecutado(presupuestoService.obtener(id));
    }

    public record CrearPresupuestoRequest(@NotNull(message = "Falta la obra") Long obraId) {
    }

    public record AgregarItemsDePartidaRequest(@NotNull(message = "Falta la partida") Long partidaId) {
    }

    public record AgregarItemRequest(
            @NotNull(message = "Falta el material") Long materialId,
            @Positive(message = "La cantidad debe ser mayor que 0") @DecimalMax(value = "1000000", message = "La cantidad es demasiado grande") double cantidad) {
    }
}
