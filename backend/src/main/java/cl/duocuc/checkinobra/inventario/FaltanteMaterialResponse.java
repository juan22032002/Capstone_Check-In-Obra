package cl.duocuc.checkinobra.inventario;

/** Un material que se está acabando en una obra activa. */
public record FaltanteMaterialResponse(
        Long obraId,
        String obraNombre,
        Long materialId,
        String sku,
        String nombre,
        String categoria,
        double stock,
        double stockMinimo,
        String estado) {

    public static FaltanteMaterialResponse de(StockObraService.Faltante f) {
        return new FaltanteMaterialResponse(
                f.obra().getId(),
                f.obra().getNombre(),
                f.material().getId(),
                f.material().getSku(),
                f.material().getNombre(),
                f.material().getCategoria().name(),
                f.stock(),
                f.material().getStockMinimo(),
                f.estado().name());
    }
}
