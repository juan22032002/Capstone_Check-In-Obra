package cl.duocuc.checkinobra.cubicacion;

import jakarta.validation.constraints.DecimalMax;
import jakarta.validation.constraints.PositiveOrZero;
import jakarta.validation.Valid;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.NoSuchElementException;

@RestController
@RequestMapping("/api/materiales/{materialId}/merma")
@Tag(name = "ParametroMerma")
public class ParametroMermaController {

    private final ParametroMermaService parametroMermaService;

    public ParametroMermaController(ParametroMermaService parametroMermaService) {
        this.parametroMermaService = parametroMermaService;
    }

    /** Definir parámetros de merma es exclusivo de ADMIN, según la matriz de permisos. */
    @PutMapping
    @PreAuthorize("hasRole('ADMIN')")
    public ParametroMermaResponse definir(@PathVariable Long materialId, @Valid @RequestBody DefinirMermaRequest req) {
        return ParametroMermaResponse.de(parametroMermaService.definirParaMaterial(materialId, req.porcentaje()));
    }

    @GetMapping
    public ParametroMermaResponse obtener(@PathVariable Long materialId) {
        return ParametroMermaResponse.de(parametroMermaService.paraMaterial(materialId)
                .orElseThrow(() -> new NoSuchElementException("El material no tiene parámetro de merma propio")));
    }

    /** Merma entre 0 % y 50 %: más que eso no es una merma de obra, es un error de tipeo. */
    public record DefinirMermaRequest(
            @PositiveOrZero(message = "La merma no puede ser negativa") @DecimalMax(value = "50", message = "La merma no puede pasar de 50 %") double porcentaje) {
    }
}
