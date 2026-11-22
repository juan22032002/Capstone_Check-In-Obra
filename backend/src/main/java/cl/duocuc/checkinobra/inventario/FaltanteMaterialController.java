package cl.duocuc.checkinobra.inventario;

import cl.duocuc.checkinobra.config.SesionActual;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

/**
 * El aviso de faltantes de la pestaña Materiales. Cuelga de
 * {@code /api/materiales} porque es donde la app lo muestra, pero vive en
 * inventario porque es un cálculo sobre el kardex: el catálogo no sabe de
 * saldos.
 */
@RestController
@RequestMapping("/api/materiales")
@Tag(name = "Material")
public class FaltanteMaterialController {

    private final StockObraService stockObraService;

    public FaltanteMaterialController(StockObraService stockObraService) {
        this.stockObraService = stockObraService;
    }

    /** Quien compra o repone; un trabajador no decide sobre el stock. */
    @GetMapping("/faltantes")
    @PreAuthorize("hasAnyRole('ADMIN', 'JEFE_TERRENO', 'BODEGUERO')")
    public List<FaltanteMaterialResponse> faltantes() {
        return stockObraService.faltantes(SesionActual.empresaId()).stream()
                .map(FaltanteMaterialResponse::de)
                .toList();
    }
}
