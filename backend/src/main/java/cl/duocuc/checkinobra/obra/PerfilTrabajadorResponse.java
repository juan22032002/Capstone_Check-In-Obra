package cl.duocuc.checkinobra.obra;

/**
 * Lo que un trabajador ve de sí mismo: sus datos, dónde trabaja y su credencial.
 *
 * <p>Lleva {@code credencialQr} porque es la propia: el teléfono la necesita
 * para dibujar el QR que escanea el bodeguero. Solo lo devuelven las rutas
 * {@code /api/trabajadores/yo}, que salen del token y no reciben un id, así que
 * nadie obtiene por acá la credencial de otro.
 *
 * <p>Cuadrilla y obra son nulas si todavía no lo asignan a ninguna.
 */
public record PerfilTrabajadorResponse(
        Long id,
        Long usuarioId,
        String nombre,
        String rut,
        Long cuadrillaId,
        String cuadrillaNombre,
        Long obraId,
        String obraNombre,
        String obraEstado,
        String credencialQr) {

    public static PerfilTrabajadorResponse de(Trabajador t) {
        Cuadrilla c = t.getCuadrilla();
        Obra o = c == null ? null : c.getObra();
        return new PerfilTrabajadorResponse(
                t.getId(),
                t.getUsuario().getId(),
                t.nombre(),
                t.rut(),
                c == null ? null : c.getId(),
                c == null ? null : c.getNombre(),
                o == null ? null : o.getId(),
                o == null ? null : o.getNombre(),
                o == null ? null : o.getEstado().name(),
                t.getCredencialQr());
    }
}
