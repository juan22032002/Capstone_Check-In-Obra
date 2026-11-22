package cl.duocuc.checkinobra.inventario;

/** El saldo de un material en una obra, sumado en la base. */
public record SaldoObraMaterial(Long obraId, Long materialId, double stock) {
}
