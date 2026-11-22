package cl.duocuc.checkinobra.control;

import cl.duocuc.checkinobra.config.Usuario;
import cl.duocuc.checkinobra.cubicacion.CostoMaterial;
import cl.duocuc.checkinobra.cubicacion.Material;
import cl.duocuc.checkinobra.inventario.EstadoStock;
import cl.duocuc.checkinobra.inventario.Herramienta;
import cl.duocuc.checkinobra.inventario.PrestamoHerramienta;
import cl.duocuc.checkinobra.obra.Cuadrilla;
import cl.duocuc.checkinobra.obra.Obra;
import cl.duocuc.checkinobra.obra.ObraResponse;
import cl.duocuc.checkinobra.obra.Trabajador;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.List;

/**
 * La ficha completa de una obra. Cada parte es un record plano —ids, nombres y
 * números—, igual que cualquier otra respuesta: agrupar no es excusa para
 * volver a mandar entidades.
 */
public record DetalleObraResponse(
        ObraResponse obra,
        List<JefeDeObra> jefes,
        List<CuadrillaEnObra> cuadrillas,
        List<TrabajadorEnObra> trabajadores,
        List<MaterialEnObra> materiales,
        List<HerramientaEnObra> herramientas,
        Resumen resumen) {

    static DetalleObraResponse de(
            Obra obra,
            List<CuadrillaEnObra> cuadrillas,
            List<TrabajadorEnObra> trabajadores,
            List<MaterialEnObra> materiales,
            List<HerramientaEnObra> herramientas,
            long alertasPendientes) {
        // Hoy una obra tiene a lo más un jefe: el de terreno asignado. No hay
        // asociación de bodegueros a obras, así que no se inventa una.
        List<JefeDeObra> jefes = obra.getJefeTerreno() == null
                ? List.of()
                : List.of(JefeDeObra.de(obra.getJefeTerreno()));

        Resumen resumen = new Resumen(
                trabajadores.size(),
                jefes.size(),
                materiales.stream().filter(m -> m.estado().equals(EstadoStock.CRITICO.name())).count(),
                materiales.stream().filter(m -> m.estado().equals(EstadoStock.BAJO.name())).count(),
                materiales.stream().mapToDouble(MaterialEnObra::valorStock).sum(),
                herramientas.size(),
                herramientas.stream().filter(HerramientaEnObra::vencida).count(),
                herramientas.stream().mapToDouble(HerramientaEnObra::valorReposicion).sum(),
                alertasPendientes);

        return new DetalleObraResponse(
                ObraResponse.de(obra), jefes, cuadrillas, trabajadores, materiales, herramientas, resumen);
    }

    public record JefeDeObra(Long usuarioId, String nombre, String rut, String rol) {
        static JefeDeObra de(Usuario u) {
            return new JefeDeObra(u.getId(), u.getNombre(), u.getRut(), u.getRol().name());
        }
    }

    public record CuadrillaEnObra(Long id, String nombre, long cantidadTrabajadores) {
        static CuadrillaEnObra de(Cuadrilla c, long cantidadTrabajadores) {
            return new CuadrillaEnObra(c.getId(), c.getNombre(), cantidadTrabajadores);
        }
    }

    public record TrabajadorEnObra(Long id, String nombre, String rut, Long cuadrillaId, String cuadrillaNombre) {
        static TrabajadorEnObra de(Trabajador t) {
            return new TrabajadorEnObra(
                    t.getId(), t.nombre(), t.rut(), t.getCuadrilla().getId(), t.getCuadrilla().getNombre());
        }
    }

    /**
     * @param valorStock el saldo valorizado al último costo real, o al precio de
     *     catálogo si nunca se registró uno. Un saldo negativo —no debería
     *     existir, pero el kardex no lo impide en datos viejos— vale cero.
     */
    public record MaterialEnObra(
            Long materialId,
            String sku,
            String nombre,
            String categoria,
            double stock,
            double stockMinimo,
            double precioUnitario,
            BigDecimal ultimoCostoUnitario,
            BigDecimal costoPromedio,
            double valorStock,
            String estado) {

        static MaterialEnObra de(Material m, double stock, EstadoStock estado, CostoMaterial costo) {
            BigDecimal ultimo = costo == null ? null : costo.getUltimoCostoUnitario();
            double precioDeValorizacion = ultimo != null ? ultimo.doubleValue() : m.getPrecioUnitario();
            return new MaterialEnObra(
                    m.getId(),
                    m.getSku(),
                    m.getNombre(),
                    m.getCategoria().name(),
                    stock,
                    m.getStockMinimo(),
                    m.getPrecioUnitario(),
                    ultimo,
                    costo == null ? null : costo.getCostoPromedio(),
                    Math.max(stock, 0) * precioDeValorizacion,
                    estado.name());
        }
    }

    public record HerramientaEnObra(
            Long herramientaId,
            Long prestamoId,
            String codigoQr,
            String nombre,
            String categoria,
            String estado,
            double valorReposicion,
            PrestadaA prestadaA,
            LocalDateTime fechaDevolEsperada,
            boolean vencida) {

        static HerramientaEnObra de(PrestamoHerramienta p) {
            Herramienta h = p.getHerramienta();
            Trabajador t = p.getTrabajador();
            return new HerramientaEnObra(
                    h.getId(),
                    p.getId(),
                    h.getCodigoQr(),
                    h.getNombre(),
                    h.getCategoria(),
                    h.getEstado().name(),
                    h.getValorReposicion(),
                    new PrestadaA(t.getId(), t.nombre(), t.rut()),
                    p.getFechaDevolEsperada(),
                    p.estaVencido());
        }
    }

    public record PrestadaA(Long trabajadorId, String nombre, String rut) {
    }

    public record Resumen(
            long cantidadTrabajadores,
            long cantidadJefes,
            long materialesCriticos,
            long materialesBajos,
            double valorMateriales,
            long herramientasEnObra,
            long herramientasVencidas,
            double valorHerramientas,
            long alertasPendientes) {
    }
}
