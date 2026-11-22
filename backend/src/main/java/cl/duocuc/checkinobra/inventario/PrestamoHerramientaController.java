package cl.duocuc.checkinobra.inventario;

import jakarta.validation.constraints.NotNull;
import jakarta.validation.Valid;
import cl.duocuc.checkinobra.config.SesionActual;
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

import java.time.LocalDateTime;
import java.util.List;

@RestController
@RequestMapping("/api/prestamos-herramienta")
@Tag(name = "PrestamoHerramienta")
public class PrestamoHerramientaController {

    private final PrestamoHerramientaService prestamoHerramientaService;

    public PrestamoHerramientaController(PrestamoHerramientaService prestamoHerramientaService) {
        this.prestamoHerramientaService = prestamoHerramientaService;
    }

    /** Autorizar un préstamo directo (sin solicitud previa) es de BODEGUERO o ADMIN. */
    @PostMapping
    @PreAuthorize("hasAnyRole('ADMIN', 'BODEGUERO')")
    @ResponseStatus(HttpStatus.CREATED)
    public PrestamoHerramientaResponse prestarDirecto(@Valid @RequestBody PrestarDirectoRequest req) {
        return PrestamoHerramientaResponse.de(prestamoHerramientaService.prestarDirecto(
                req.herramientaId(), req.trabajadorId(), req.obraId(), SesionActual.usuarioId(), req.fechaDevolEsperada()));
    }

    @PutMapping("/{id}/devolucion")
    @PreAuthorize("hasAnyRole('ADMIN', 'BODEGUERO')")
    public PrestamoHerramientaResponse registrarDevolucion(
            @PathVariable Long id, @Valid @RequestBody RegistrarDevolucionRequest req) {
        return PrestamoHerramientaResponse.de(
                prestamoHerramientaService.registrarDevolucion(id, req.nuevoEstadoHerramienta()));
    }

    /** Los propios, abiertos y cerrados, el más nuevo primero. Sale del token. */
    @GetMapping("/mios")
    @PreAuthorize("hasRole('TRABAJADOR')")
    public List<PrestamoHerramientaResponse> mios() {
        return prestamoHerramientaService.listarMios().stream().map(PrestamoHerramientaResponse::de).toList();
    }

    /** Un trabajador solo obtiene los suyos; lo exige el servicio. */
    @GetMapping("/{id}")
    public PrestamoHerramientaResponse obtener(@PathVariable Long id) {
        return PrestamoHerramientaResponse.de(prestamoHerramientaService.obtener(id));
    }

    /**
     * Un trabajador solo puede listar por su propio {@code trabajadorId}; por
     * obra o los vencidos vería los de sus compañeros. Lo exige el servicio.
     */
    @GetMapping
    public List<PrestamoHerramientaResponse> listar(
            @RequestParam(required = false) Long obraId,
            @RequestParam(required = false) Long trabajadorId,
            @RequestParam(required = false, defaultValue = "false") boolean soloVencidos) {
        List<PrestamoHerramienta> prestamos;
        if (soloVencidos) {
            prestamos = prestamoHerramientaService.listarVencidos();
        } else if (obraId != null) {
            prestamos = prestamoHerramientaService.listarPorObra(obraId);
        } else if (trabajadorId != null) {
            prestamos = prestamoHerramientaService.listarPorTrabajador(trabajadorId);
        } else {
            throw new IllegalArgumentException("Se requiere obraId, trabajadorId o soloVencidos=true");
        }
        return prestamos.stream().map(PrestamoHerramientaResponse::de).toList();
    }

    public record PrestarDirectoRequest(
            @NotNull(message = "Falta la herramienta") Long herramientaId,
            @NotNull(message = "Falta el trabajador") Long trabajadorId,
            @NotNull(message = "Falta la obra") Long obraId,
            LocalDateTime fechaDevolEsperada) {
    }

    public record RegistrarDevolucionRequest(
            @NotNull(message = "Falta el estado en que vuelve la herramienta") EstadoHerramienta nuevoEstadoHerramienta) {
    }
}
