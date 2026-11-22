package cl.duocuc.checkinobra.inventario;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotEmpty;
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
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

import java.time.LocalDateTime;
import java.util.List;

/**
 * Pedido de varias herramientas con QR de retiro. La app muestra el QR como
 * {@code PEDIDO:<codigoQr>}; las rutas reciben solo el código.
 */
@RestController
@RequestMapping("/api/pedidos-herramienta")
@Tag(name = "PedidoHerramientas")
public class PedidoHerramientasController {

    private final PedidoHerramientasService pedidoHerramientasService;

    public PedidoHerramientasController(PedidoHerramientasService pedidoHerramientasService) {
        this.pedidoHerramientasService = pedidoHerramientasService;
    }

    /** Se pide a nombre propio, igual que una solicitud suelta. */
    @PostMapping
    @PreAuthorize("hasRole('TRABAJADOR')")
    @ResponseStatus(HttpStatus.CREATED)
    public PedidoHerramientasResponse crear(@Valid @RequestBody CrearPedidoHerramientasRequest req) {
        return PedidoHerramientasResponse.de(pedidoHerramientasService.crear(
                SesionActual.usuarioId(), req.herramientaIds(), req.descripcion()));
    }

    /** Los propios, primero los pendientes, para volver a mostrar el QR. */
    @GetMapping("/mios")
    @PreAuthorize("hasRole('TRABAJADOR')")
    public List<PedidoHerramientasResponse> mios() {
        return pedidoHerramientasService.listarMios().stream().map(PedidoHerramientasResponse::de).toList();
    }

    @PutMapping("/{id}/cancelar")
    @PreAuthorize("hasRole('TRABAJADOR')")
    public PedidoHerramientasResponse cancelar(@PathVariable Long id) {
        return PedidoHerramientasResponse.de(pedidoHerramientasService.cancelar(id));
    }

    /** Lo que ve el bodeguero al escanear, antes de entregar. */
    @GetMapping("/qr/{codigoQr}")
    @PreAuthorize("hasAnyRole('ADMIN', 'BODEGUERO')")
    public PedidoHerramientasResponse porQr(@PathVariable String codigoQr) {
        return PedidoHerramientasResponse.de(pedidoHerramientasService.obtenerPorQr(codigoQr));
    }

    @PutMapping("/qr/{codigoQr}/entregar")
    @PreAuthorize("hasAnyRole('ADMIN', 'BODEGUERO')")
    public EntregaPedidoResponse entregar(@PathVariable String codigoQr, @Valid @RequestBody EntregarPedidoRequest req) {
        return EntregaPedidoResponse.de(pedidoHerramientasService.entregar(codigoQr, req.fechaDevolEsperada()));
    }

    public record CrearPedidoHerramientasRequest(
            @NotEmpty(message = "Elige al menos una herramienta") List<@NotNull(message = "Hay una herramienta sin id") Long> herramientaIds,
            @NotBlank(message = "Cuenta para qué las necesitas") @Size(max = 300, message = "La descripción admite hasta 300 caracteres") String descripcion) {
    }

    public record EntregarPedidoRequest(LocalDateTime fechaDevolEsperada) {
    }
}
