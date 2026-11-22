package cl.duocuc.checkinobra.control;

import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/obras")
@Tag(name = "Obra")
public class DetalleObraController {

    private final DetalleObraService detalleObraService;

    public DetalleObraController(DetalleObraService detalleObraService) {
        this.detalleObraService = detalleObraService;
    }

    /**
     * La ficha de la obra lleva RUTs, costos y a quién se le prestó cada
     * herramienta: es de quien la dirige o la abastece, no del trabajador.
     */
    @GetMapping("/{id}/detalle")
    @PreAuthorize("hasAnyRole('ADMIN', 'JEFE_TERRENO', 'BODEGUERO')")
    public DetalleObraResponse detalle(@PathVariable Long id) {
        return detalleObraService.detalle(id);
    }
}
