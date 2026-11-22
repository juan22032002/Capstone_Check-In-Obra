package cl.duocuc.checkinobra.cubicacion;

import cl.duocuc.checkinobra.config.AccesoEmpresa;
import cl.duocuc.checkinobra.config.Empresa;
import cl.duocuc.checkinobra.config.EmpresaService;
import cl.duocuc.checkinobra.importacion.FilaPlanilla;
import cl.duocuc.checkinobra.importacion.LectorPlanilla;
import cl.duocuc.checkinobra.importacion.ResultadoImportacion;
import cl.duocuc.checkinobra.importacion.ResultadoImportacion.ErrorFila;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.io.InputStream;
import java.util.ArrayList;
import java.util.Collection;
import java.util.Comparator;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.NoSuchElementException;
import java.util.Set;
import java.util.function.Function;
import java.util.stream.Collectors;

@Service
@Transactional
public class MaterialService {

    private final MaterialRepository materialRepository;
    private final EmpresaService empresaService;

    public MaterialService(MaterialRepository materialRepository, EmpresaService empresaService) {
        this.materialRepository = materialRepository;
        this.empresaService = empresaService;
    }

    public Material crear(
            Long empresaId, String sku, String nombre, CategoriaMaterial categoria,
            double precioUnitario, double stockMinimo, String codigoBarra) {
        // El SKU se guarda en mayúsculas. La app ya lo hacía en su formulario,
        // pero el servicio no: un material creado desde Swagger o desde un
        // cliente futuro con el SKU en minúsculas quedaba invisible para el
        // escáner, que lo busca normalizado.
        sku = sku == null ? "" : sku.trim().toUpperCase();
        if (sku.isEmpty()) {
            throw new IllegalArgumentException("El SKU es obligatorio");
        }
        codigoBarra = codigoBarra == null || codigoBarra.isBlank() ? null : codigoBarra.trim();

        // Con ignore-case porque puede haber filas anteriores a la
        // normalización: si no, "vol-10" y "VOL-10" conviven como dos
        // materiales que nadie distingue en pantalla.
        if (materialRepository.findByEmpresaIdAndSkuIgnoreCase(empresaId, sku).isPresent()) {
            throw new IllegalStateException("Ya existe un material con ese SKU");
        }
        // El duplicado del código de barras se busca **dentro de la empresa**:
        // el mismo EAN lo tienen todas las constructoras que compran ese
        // producto (ver la restricción de V4).
        if (codigoBarra != null
                && materialRepository.findByEmpresaIdAndCodigoBarra(empresaId, codigoBarra).isPresent()) {
            throw new IllegalStateException("Ya existe un material con ese código de barras");
        }
        Empresa empresa = empresaService.obtener(empresaId);
        Material material = Material.builder()
                .sku(sku)
                .codigoBarra(codigoBarra)
                .nombre(nombre)
                .categoria(categoria)
                .precioUnitario(precioUnitario)
                .stockMinimo(stockMinimo)
                .empresa(empresa)
                .build();
        return materialRepository.save(material);
    }

    /**
     * Lo que resuelve el escáner del bodeguero: un código leído de una etiqueta,
     * sin saber de antemano si es el de fábrica o el SKU de la empresa.
     *
     * <p>Se prueba primero el código de barras porque es el que trae el envase
     * —es lo que se escanea el 99 % de las veces— y después el SKU, que cubre
     * los materiales etiquetados a mano por la propia bodega.
     */
    @Transactional(readOnly = true)
    public Material buscarPorCodigo(Long empresaId, String codigo) {
        AccesoEmpresa.exigirEmpresa(empresaId);
        String limpio = codigo.trim();
        return materialRepository.findByEmpresaIdAndCodigoBarra(empresaId, limpio)
                .or(() -> materialRepository.findByEmpresaIdAndSku(empresaId, limpio.toUpperCase()))
                .orElseThrow(() -> new NoSuchElementException("Código no reconocido"));
    }

    /**
     * Alta masiva desde una planilla Excel.
     *
     * <p>Dos pasadas y en este orden: primero se valida el archivo entero, y
     * solo si no quedó ningún error —y solo si quien llama confirmó— se guarda.
     * Así la simulación que ve el administrador antes de apretar el botón es
     * exactamente la misma comprobación que después decide si se escribe, y no
     * una aproximación que puede diferir.
     *
     * @param confirmar {@code false} simula: no toca la base
     */
    public ResultadoImportacion importar(Long empresaId, InputStream planilla, boolean confirmar) {
        AccesoEmpresa.exigirEmpresa(empresaId);

        List<FilaPlanilla> filas = LectorPlanilla.leer(planilla, FilaMaterial.ENCABEZADOS.size());
        if (filas.isEmpty()) {
            throw new IllegalArgumentException("La planilla no tiene ninguna fila con datos");
        }

        List<ErrorFila> errores = new ArrayList<>();
        List<FilaMaterial> validas = new ArrayList<>();
        // Los duplicados dentro del mismo archivo no los ve la base —todavía no
        // se guardó nada— y son el error más frecuente al pegar desde otra
        // planilla. Se detectan acá.
        Set<String> skusDelArchivo = new HashSet<>();
        Set<String> codigosDelArchivo = new HashSet<>();
        // El número de fila se guarda junto al dato: los errores de la segunda
        // pasada tienen que poder ubicarse en el archivo igual que los de la
        // primera.
        Map<String, Integer> filaDelSku = new HashMap<>();

        for (FilaPlanilla fila : filas) {
            try {
                FilaMaterial material = FilaMaterial.desde(fila);

                if (!skusDelArchivo.add(material.sku())) {
                    throw new IllegalArgumentException("El SKU '" + material.sku() + "' se repite en la planilla");
                }
                if (material.codigoBarra() != null && !codigosDelArchivo.add(material.codigoBarra())) {
                    throw new IllegalArgumentException(
                            "El código de barras '" + material.codigoBarra() + "' se repite en la planilla");
                }

                filaDelSku.put(material.sku(), fila.numero());
                validas.add(material);
            } catch (IllegalArgumentException e) {
                errores.add(new ErrorFila(fila.numero(), e.getMessage()));
            }
        }

        // Contra la base, dos consultas para todo el archivo en vez de dos por
        // fila. Con el tope de 2.000 filas la diferencia es entre dos consultas
        // y cuatro mil.
        Set<String> skusExistentes = existentes(
                skusDelArchivo, skus -> materialRepository.findByEmpresaIdAndSkuIn(empresaId, skus), Material::getSku);
        Set<String> codigosExistentes = existentes(
                codigosDelArchivo,
                codigos -> materialRepository.findByEmpresaIdAndCodigoBarraIn(empresaId, codigos),
                Material::getCodigoBarra);

        validas.removeIf(material -> {
            if (skusExistentes.contains(material.sku())) {
                errores.add(new ErrorFila(
                        filaDelSku.get(material.sku()),
                        "Ya existe un material con el SKU '" + material.sku() + "'"));
                return true;
            }
            if (material.codigoBarra() != null && codigosExistentes.contains(material.codigoBarra())) {
                errores.add(new ErrorFila(
                        filaDelSku.get(material.sku()),
                        "Ya existe un material con el código de barras '" + material.codigoBarra() + "'"));
                return true;
            }
            return false;
        });

        // Los errores se reportan en el orden del archivo, que es el orden en
        // que quien lo corrige va a recorrerlo.
        errores.sort(Comparator.comparingInt(ErrorFila::fila));

        if (!errores.isEmpty()) {
            return ResultadoImportacion.conErrores(filas.size(), errores);
        }
        if (!confirmar) {
            return ResultadoImportacion.simulada(filas.size());
        }

        Empresa empresa = empresaService.obtener(empresaId);
        materialRepository.saveAll(validas.stream()
                .map(f -> Material.builder()
                        .sku(f.sku())
                        .codigoBarra(f.codigoBarra())
                        .nombre(f.nombre())
                        .categoria(f.categoria())
                        .precioUnitario(f.precioUnitario())
                        .stockMinimo(f.stockMinimo())
                        .empresa(empresa)
                        .build())
                .toList());
        return ResultadoImportacion.importada(validas.size());
    }

    @Transactional(readOnly = true)
    public List<Material> listarPorEmpresa(Long empresaId) {
        AccesoEmpresa.exigirEmpresa(empresaId);
        return materialRepository.findByEmpresaId(empresaId);
    }

    @Transactional(readOnly = true)
    public List<Material> listarPorEmpresaYCategoria(Long empresaId, CategoriaMaterial categoria) {
        AccesoEmpresa.exigirEmpresa(empresaId);
        return materialRepository.findByEmpresaIdAndCategoria(empresaId, categoria);
    }

    @Transactional(readOnly = true)
    public Material obtener(Long id) {
        return materialRepository.findById(id)
                .filter(AccesoEmpresa::esPropio)
                .orElseThrow(() -> new NoSuchElementException("Material no encontrado: " + id));
    }

    /**
     * Último costo y promedio de cada material de la empresa, por id. Los que no
     * tienen ninguna recepción con costo no están en el mapa.
     */
    @Transactional(readOnly = true)
    public Map<Long, CostoMaterial> costosPorMaterial(Long empresaId) {
        AccesoEmpresa.exigirEmpresa(empresaId);
        return materialRepository.costosPorEmpresa(empresaId).stream()
                .collect(Collectors.toMap(CostoMaterial::getMaterialId, Function.identity()));
    }

    /** El costo de un material, o nulo si no tiene recepciones con costo. */
    @Transactional(readOnly = true)
    public CostoMaterial costoDe(Material material) {
        // Recibe el material ya obtenido, y por lo tanto ya filtrado por empresa.
        return materialRepository.costoDe(material.getId()).orElse(null);
    }

    public Material actualizarPrecio(Long materialId, double nuevoPrecio) {
        Material material = obtener(materialId);
        material.setPrecioUnitario(nuevoPrecio);
        return materialRepository.save(material);
    }

    /**
     * Cuáles de estos códigos ya existen, en una sola consulta. Con el conjunto
     * vacío ni siquiera se pregunta.
     */
    private static <T> Set<String> existentes(
            Set<String> codigos, Function<Collection<String>, List<T>> buscar, Function<T, String> codigoDe) {
        if (codigos.isEmpty()) {
            return Set.of();
        }
        return buscar.apply(codigos).stream().map(codigoDe).collect(Collectors.toSet());
    }
}
