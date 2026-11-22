package cl.duocuc.checkinobra.inventario;

import jakarta.validation.constraints.DecimalMax;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Positive;
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

import java.util.List;

@RestController
@RequestMapping("/api/solicitudes-material")
@Tag(name = "SolicitudMaterial")
public class SolicitudMaterialController {

    private final SolicitudMaterialService solicitudMaterialService;

    public SolicitudMaterialController(SolicitudMaterialService solicitudMaterialService) {
        this.solicitudMaterialService = solicitudMaterialService;
    }

    /** Solicitar material es exclusivo de TRABAJADOR, según la matriz de permisos. */
    @PostMapping
    @PreAuthorize("hasRole('TRABAJADOR')")
    @ResponseStatus(HttpStatus.CREATED)
    public SolicitudMaterialResponse crear(@Valid @RequestBody CrearSolicitudRequest req) {
        return SolicitudMaterialResponse.de(
                solicitudMaterialService.crear(
                        // Se pide a nombre propio: con el trabajadorId en el
                        // cuerpo, un trabajador podía pedir a nombre de otro.
                        SesionActual.usuarioId(), req.materialId(), req.obraId(), req.cantidad(),
                        req.descripcion()));
    }

    /** Aprobar/rechazar es de BODEGUERO o ADMIN, según la matriz de permisos. */
    @PutMapping("/{id}/aprobar")
    @PreAuthorize("hasAnyRole('ADMIN', 'BODEGUERO')")
    public KardexMovimientoResponse aprobar(@PathVariable Long id, @Valid @RequestBody AprobarRequest req) {
        // Aprobar despacha: lo que sale es el movimiento de kardex.
        return KardexMovimientoResponse.de(
                solicitudMaterialService.aprobar(id, SesionActual.usuarioId(), req.cantidadAEntregar()));
    }

    @PutMapping("/{id}/rechazar")
    @PreAuthorize("hasAnyRole('ADMIN', 'BODEGUERO')")
    public SolicitudMaterialResponse rechazar(@PathVariable Long id, @Valid @RequestBody RechazarRequest req) {
        return SolicitudMaterialResponse.de(
                solicitudMaterialService.rechazar(id, SesionActual.usuarioId(), req.motivo()));
    }

    /** El trabajador retira su propia solicitud mientras sigue pendiente. */
    @PutMapping("/{id}/cancelar")
    @PreAuthorize("hasRole('TRABAJADOR')")
    public SolicitudMaterialResponse cancelar(@PathVariable Long id) {
        return SolicitudMaterialResponse.de(solicitudMaterialService.cancelar(id));
    }

    /** El trabajador confirma que recibió lo que bodega aprobó: APROBADA → ENTREGADA. */
    @PutMapping("/{id}/confirmar-recepcion")
    @PreAuthorize("hasRole('TRABAJADOR')")
    public SolicitudMaterialResponse confirmarRecepcion(@PathVariable Long id) {
        return SolicitudMaterialResponse.de(solicitudMaterialService.confirmarRecepcion(id));
    }

    /** Las propias, la más nueva primero. Sale del token: no recibe id. */
    @GetMapping("/mias")
    @PreAuthorize("hasRole('TRABAJADOR')")
    public List<SolicitudMaterialResponse> mias() {
        return solicitudMaterialService.listarMias().stream().map(SolicitudMaterialResponse::de).toList();
    }

    /** Un trabajador solo obtiene las suyas; lo exige el servicio. */
    @GetMapping("/{id}")
    public SolicitudMaterialResponse obtener(@PathVariable Long id) {
        return SolicitudMaterialResponse.de(solicitudMaterialService.obtener(id));
    }

    /**
     * Un trabajador solo puede listar por su propio {@code trabajadorId}; por
     * obra vería las de sus compañeros. Lo exige el servicio.
     */
    @GetMapping
    public List<SolicitudMaterialResponse> listar(
            @RequestParam(required = false) Long trabajadorId,
            @RequestParam(required = false) Long obraId,
            @RequestParam(required = false, defaultValue = "false") boolean soloPendientes) {
        List<SolicitudMaterial> solicitudes;
        if (trabajadorId != null) {
            solicitudes = solicitudMaterialService.listarPorTrabajador(trabajadorId);
        } else if (obraId != null) {
            solicitudes = soloPendientes
                    ? solicitudMaterialService.listarPendientesPorObra(obraId)
                    : solicitudMaterialService.listarPorObra(obraId);
        } else {
            throw new IllegalArgumentException("Se requiere trabajadorId u obraId");
        }
        return solicitudes.stream().map(SolicitudMaterialResponse::de).toList();
    }

    /** {@code obraId} es opcional: por defecto, la obra de la cuadrilla de quien pide. */
    public record CrearSolicitudRequest(
            @NotNull(message = "Falta el material") Long materialId,
            Long obraId,
            @Positive(message = "La cantidad pedida debe ser mayor que 0") @DecimalMax(value = "1000000", message = "La cantidad es demasiado grande") double cantidad,
            @NotBlank(message = "Cuenta para qué lo necesitas") @Size(max = 300, message = "La descripción admite hasta 300 caracteres") String descripcion) {
    }

    public record AprobarRequest(
            @Positive(message = "La cantidad a entregar debe ser mayor que 0") @DecimalMax(value = "1000000", message = "La cantidad es demasiado grande") double cantidadAEntregar) {
    }

    public record RechazarRequest(
            @NotBlank(message = "El motivo es obligatorio") @Size(max = 500, message = "El motivo admite hasta 500 caracteres") String motivo) {
    }
}
