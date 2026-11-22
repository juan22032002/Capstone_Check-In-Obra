package cl.duocuc.checkinobra.cubicacion;

import cl.duocuc.checkinobra.config.PerteneceAEmpresa;
import cl.duocuc.checkinobra.config.Empresa;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.FetchType;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.Table;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

@Entity
@Table(name = "materiales")
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class Material implements PerteneceAEmpresa {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    // Único por empresa: UNIQUE (empresa_id, sku), migración V13.
    @Column(nullable = false)
    private String sku;

    /**
     * El código impreso de fábrica en el envase — lo que lee el escáner de
     * código de barras del bodeguero. No está en el diagrama de clases: el
     * modelo solo tenía el SKU, que es interno y no viene en ninguna etiqueta.
     *
     * <p>Nullable porque no todo material lo trae; esos se siguen encontrando
     * por SKU. La unicidad es por empresa y vive en la restricción
     * {@code uq_materiales_empresa_codigo_barra} (V4): el código es del
     * producto, no de la constructora, así que dos empresas pueden tener el
     * mismo.
     */
    @Column(name = "codigo_barra", length = 50)
    private String codigoBarra;

    @Column(nullable = false)
    private String nombre;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 20)
    private CategoriaMaterial categoria;

    @Column(name = "precio_unitario", nullable = false)
    private double precioUnitario;

    /**
     * Stock mínimo antes de que KardexMovimientoService dispare una
     * Alerta STOCK_CRITICO — no está en el diagrama (Material no lo
     * incluye), se agrega porque sin un umbral ese tipo de alerta no se
     * puede calcular.
     */
    @Column(name = "stock_minimo", nullable = false)
    private double stockMinimo;

    @ManyToOne(fetch = FetchType.EAGER, optional = false)
    @JoinColumn(name = "empresa_id", nullable = false)
    private Empresa empresa;

    @Override
    public Long empresaId() {
        return empresa.getId();
    }
}
