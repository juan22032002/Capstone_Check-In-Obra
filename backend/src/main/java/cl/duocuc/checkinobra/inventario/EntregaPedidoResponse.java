package cl.duocuc.checkinobra.inventario;

import java.util.List;

/** El pedido ya entregado, con un préstamo por cada herramienta que salió. */
public record EntregaPedidoResponse(
        PedidoHerramientasResponse pedido,
        List<PrestamoHerramientaResponse> prestamos) {

    public static EntregaPedidoResponse de(PedidoHerramientasService.Entrega e) {
        return new EntregaPedidoResponse(
                PedidoHerramientasResponse.de(e.pedido()),
                e.prestamos().stream().map(PrestamoHerramientaResponse::de).toList());
    }
}
