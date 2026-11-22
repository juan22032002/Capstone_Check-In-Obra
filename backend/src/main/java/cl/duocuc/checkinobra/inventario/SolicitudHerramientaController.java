package cl.duocuc.checkinobra.inventario;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;
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
@RequestMapping("/api/solicitudes-herramienta")
@Tag(name = "SolicitudHerramienta")
public class SolicitudHerramientaController {

    private final SolicitudHerramientaService solicitudHerramientaService;

    public SolicitudHerramientaController(SolicitudHerramientaService solicitudHerramientaService) {
        this.solicitudHerramientaService = solicitudHerramientaService;
    }

    /** Solicitar herramienta es exclusivo de TRABAJADOR, según la matriz de permisos. */
    @PostMapping
    @PreAuthorize("hasRole('TRABAJADOR')")
    @ResponseStatus(HttpStatus.CREATED)
    public SolicitudHerramientaResponse crear(@Valid @RequestBody CrearSolicitudRequest req) {
        return SolicitudHerramientaResponse.de(
                solicitudHerramientaService.crear(
                        // Se pide a nombre propio, igual que una solicitud de material.
                        SesionActual.usuarioId(), req.herramientaId(), req.cantidad(), req.descripcion()));
    }

    /** Aprobar/rechazar es de BODEGUERO o ADMIN, según la matriz de permisos. */
    @PutMapping("/{id}/aprobar")
    @PreAuthorize("hasAnyRole('ADMIN', 'BODEGUERO')")
    public PrestamoHerramientaResponse aprobar(@PathVariable Long id, @Valid @RequestBody AprobarRequest req) {
        // Aprobar una solicitud produce el préstamo, no la solicitud.
        return PrestamoHerramientaResponse.de(
                solicitudHerramientaService.aprobar(id, SesionActual.usuarioId(), req.fechaDevolEsperada()));
    }

    @PutMapping("/{id}/rechazar")
    @PreAuthorize("hasAnyRole('ADMIN', 'BODEGUERO')")
    public SolicitudHerramientaResponse rechazar(@PathVariable Long id, @Valid @RequestBody RechazarRequest req) {
        return SolicitudHerramientaResponse.de(
                solicitudHerramientaService.rechazar(id, SesionActual.usuarioId(), req.motivo()));
    }

    /** El trabajador retira su propia solicitud mientras sigue pendiente. */
    @PutMapping("/{id}/cancelar")
    @PreAuthorize("hasRole('TRABAJADOR')")
    public SolicitudHerramientaResponse cancelar(@PathVariable Long id) {
        return SolicitudHerramientaResponse.de(solicitudHerramientaService.cancelar(id));
    }

    /** El trabajador confirma que recibió la herramienta: APROBADA → ENTREGADA. */
    @PutMapping("/{id}/confirmar-recepcion")
    @PreAuthorize("hasRole('TRABAJADOR')")
    public SolicitudHerramientaResponse confirmarRecepcion(@PathVariable Long id) {
        return SolicitudHerramientaResponse.de(solicitudHerramientaService.confirmarRecepcion(id));
    }

    /** Las propias, la más nueva primero. Sale del token: no recibe id. */
    @GetMapping("/mias")
    @PreAuthorize("hasRole('TRABAJADOR')")
    public List<SolicitudHerramientaResponse> mias() {
        return solicitudHerramientaService.listarMias().stream().map(SolicitudHerramientaResponse::de).toList();
    }

    /** Un trabajador solo obtiene las suyas; lo exige el servicio. */
    @GetMapping("/{id}")
    public SolicitudHerramientaResponse obtener(@PathVariable Long id) {
        return SolicitudHerramientaResponse.de(solicitudHerramientaService.obtener(id));
    }

    /**
     * Un trabajador solo puede listar por su propio {@code trabajadorId}; por
     * obra vería las de sus compañeros. Lo exige el servicio.
     */
    @GetMapping
    public List<SolicitudHerramientaResponse> listar(
            @RequestParam(required = false) Long trabajadorId,
            @RequestParam(required = false) Long obraId,
            @RequestParam(required = false, defaultValue = "false") boolean soloPendientes) {
        List<SolicitudHerramienta> solicitudes;
        if (trabajadorId != null) {
            solicitudes = solicitudHerramientaService.listarPorTrabajador(trabajadorId);
        } else if (obraId != null) {
            solicitudes = soloPendientes
                    ? solicitudHerramientaService.listarPendientesPorObra(obraId)
                    : solicitudHerramientaService.listarPorObra(obraId);
        } else {
            throw new IllegalArgumentException("Se requiere trabajadorId u obraId");
        }
        return solicitudes.stream().map(SolicitudHerramientaResponse::de).toList();
    }

    /** {@code cantidad} es opcional y, si viene, tiene que ser 1: cada herramienta tiene su QR. */
    public record CrearSolicitudRequest(
            @NotNull(message = "Falta la herramienta") Long herramientaId,
            Integer cantidad,
            @NotBlank(message = "Cuenta para qué la necesitas") @Size(max = 300, message = "La descripción admite hasta 300 caracteres") String descripcion) {
    }

    public record AprobarRequest(LocalDateTime fechaDevolEsperada) {
    }

    public record RechazarRequest(
            @NotBlank(message = "El motivo es obligatorio") @Size(max = 500, message = "El motivo admite hasta 500 caracteres") String motivo) {
    }
}
