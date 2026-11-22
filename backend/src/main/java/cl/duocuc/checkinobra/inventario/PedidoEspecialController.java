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
@RequestMapping("/api/pedidos-especiales")
@Tag(name = "PedidoEspecial")
public class PedidoEspecialController {

    private final PedidoEspecialService pedidoEspecialService;

    public PedidoEspecialController(PedidoEspecialService pedidoEspecialService) {
        this.pedidoEspecialService = pedidoEspecialService;
    }

    /** Lo pide el trabajador, a nombre propio y para la obra de su cuadrilla. */
    @PostMapping
    @PreAuthorize("hasRole('TRABAJADOR')")
    @ResponseStatus(HttpStatus.CREATED)
    public PedidoEspecialResponse crear(@Valid @RequestBody CrearPedidoRequest req) {
        return PedidoEspecialResponse.de(pedidoEspecialService.crear(
                SesionActual.usuarioId(), req.tipo(), req.nombre(), req.cantidad(), req.unidad(),
                req.descripcion(), req.materialId(), req.herramientaId()));
    }

    @GetMapping("/mios")
    @PreAuthorize("hasRole('TRABAJADOR')")
    public List<PedidoEspecialResponse> mios() {
        return pedidoEspecialService.listarMios().stream().map(PedidoEspecialResponse::de).toList();
    }

    /** La bandeja de bodega y la pestaña del administrador. Sin obra, toda la empresa. */
    @GetMapping
    @PreAuthorize("hasAnyRole('ADMIN', 'BODEGUERO', 'JEFE_TERRENO')")
    public List<PedidoEspecialResponse> listar(
            @RequestParam(required = false) Long obraId,
            @RequestParam(required = false, defaultValue = "false") boolean soloAbiertos) {
        return pedidoEspecialService.listar(obraId, soloAbiertos).stream().map(PedidoEspecialResponse::de).toList();
    }

    /** Un trabajador solo obtiene los suyos; lo exige el servicio. */
    @GetMapping("/{id}")
    public PedidoEspecialResponse obtener(@PathVariable Long id) {
        return PedidoEspecialResponse.de(pedidoEspecialService.obtener(id));
    }

    @PutMapping("/{id}/gestionar")
    @PreAuthorize("hasAnyRole('ADMIN', 'BODEGUERO')")
    public PedidoEspecialResponse gestionar(@PathVariable Long id, @Valid @RequestBody(required = false) NotaRequest req) {
        return PedidoEspecialResponse.de(pedidoEspecialService.gestionar(id, req == null ? null : req.nota()));
    }

    @PutMapping("/{id}/listo")
    @PreAuthorize("hasAnyRole('ADMIN', 'BODEGUERO')")
    public PedidoEspecialResponse listo(@PathVariable Long id, @Valid @RequestBody(required = false) NotaRequest req) {
        return PedidoEspecialResponse.de(pedidoEspecialService.marcarListo(id, req == null ? null : req.nota()));
    }

    @PutMapping("/{id}/entregar")
    @PreAuthorize("hasAnyRole('ADMIN', 'BODEGUERO')")
    public PedidoEspecialResponse entregar(@PathVariable Long id) {
        return PedidoEspecialResponse.de(pedidoEspecialService.entregar(id));
    }

    @PutMapping("/{id}/rechazar")
    @PreAuthorize("hasAnyRole('ADMIN', 'BODEGUERO')")
    public PedidoEspecialResponse rechazar(@PathVariable Long id, @Valid @RequestBody RechazarRequest req) {
        return PedidoEspecialResponse.de(pedidoEspecialService.rechazar(id, req.motivo()));
    }

    @PutMapping("/{id}/cancelar")
    @PreAuthorize("hasRole('TRABAJADOR')")
    public PedidoEspecialResponse cancelar(@PathVariable Long id) {
        return PedidoEspecialResponse.de(pedidoEspecialService.cancelar(id));
    }

    @PutMapping("/{id}/confirmar-recepcion")
    @PreAuthorize("hasRole('TRABAJADOR')")
    public PedidoEspecialResponse confirmarRecepcion(@PathVariable Long id) {
        return PedidoEspecialResponse.de(pedidoEspecialService.confirmarRecepcion(id));
    }

    public record CrearPedidoRequest(
            @NotNull(message = "Falta el tipo de pedido") TipoPedidoEspecial tipo,
            @NotBlank(message = "El nombre es obligatorio") @Size(max = 120, message = "El nombre admite hasta 120 caracteres") String nombre,
            @Positive(message = "La cantidad debe ser mayor que 0") @DecimalMax(value = "1000000", message = "La cantidad es demasiado grande") double cantidad,
            @Size(max = 20, message = "La unidad admite hasta 20 caracteres") String unidad,
            /** Para qué lo necesita. */
            @NotBlank(message = "Cuenta para qué lo necesitas") @Size(max = 300, message = "La descripción admite hasta 300 caracteres") String descripcion,
            Long materialId,
            Long herramientaId) {
    }

    public record NotaRequest(@Size(max = 300, message = "La nota admite hasta 300 caracteres") String nota) {
    }

    public record RechazarRequest(
            @NotBlank(message = "El motivo es obligatorio") @Size(max = 300, message = "El motivo admite hasta 300 caracteres") String motivo) {
    }
}
