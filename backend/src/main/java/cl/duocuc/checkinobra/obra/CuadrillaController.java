package cl.duocuc.checkinobra.obra;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;
import jakarta.validation.Valid;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.http.HttpStatus;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

@RestController
@RequestMapping("/api/cuadrillas")
@Tag(name = "Cuadrilla")
public class CuadrillaController {

    private final CuadrillaService cuadrillaService;

    public CuadrillaController(CuadrillaService cuadrillaService) {
        this.cuadrillaService = cuadrillaService;
    }

    @PostMapping
    @PreAuthorize("hasAnyRole('ADMIN', 'JEFE_TERRENO')")
    @ResponseStatus(HttpStatus.CREATED)
    public CuadrillaResponse crear(@Valid @RequestBody CrearCuadrillaRequest req) {
        return CuadrillaResponse.de(cuadrillaService.crear(req.obraId(), req.nombre()));
    }

    @GetMapping
    @PreAuthorize("hasAnyRole('ADMIN', 'JEFE_TERRENO', 'BODEGUERO')")
    public List<CuadrillaResponse> listarPorObra(@RequestParam Long obraId) {
        return cuadrillaService.listarPorObra(obraId).stream().map(CuadrillaResponse::de).toList();
    }

    @GetMapping("/{id}")
    @PreAuthorize("hasAnyRole('ADMIN', 'JEFE_TERRENO', 'BODEGUERO')")
    public CuadrillaResponse obtener(@PathVariable Long id) {
        return CuadrillaResponse.de(cuadrillaService.obtener(id));
    }

    public record CrearCuadrillaRequest(
            @NotNull(message = "Falta la obra") Long obraId,
            @NotBlank(message = "El nombre es obligatorio") @Size(max = 200, message = "El nombre admite hasta 200 caracteres") String nombre) {
    }
}
