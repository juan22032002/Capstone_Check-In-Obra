package cl.duocuc.checkinobra.cubicacion;

import jakarta.validation.constraints.DecimalMax;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.PositiveOrZero;
import jakarta.validation.constraints.Size;
import jakarta.validation.Valid;
import cl.duocuc.checkinobra.config.SesionActual;
import cl.duocuc.checkinobra.importacion.PlantillaExcel;
import cl.duocuc.checkinobra.importacion.LectorPlanilla;
import cl.duocuc.checkinobra.importacion.ResultadoImportacion;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
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
import org.springframework.web.multipart.MultipartFile;

import java.io.IOException;
import java.io.UncheckedIOException;
import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api/materiales")
@Tag(name = "Material")
public class MaterialController {

    private final MaterialService materialService;

    public MaterialController(MaterialService materialService) {
        this.materialService = materialService;
    }

    /** Definir catálogo y precios es exclusivo de ADMIN, según la matriz de permisos. */
    @PostMapping
    @PreAuthorize("hasRole('ADMIN')")
    @ResponseStatus(HttpStatus.CREATED)
    public MaterialResponse crear(@Valid @RequestBody CrearMaterialRequest req) {
        // La empresa sale del token, no de la petición. Mientras el cliente
        // pudiera nombrarla, pedir los datos de otra constructora era cuestión
        // de cambiar un número en la URL.
        return MaterialResponse.de(materialService.crear(
                SesionActual.empresaId(),
                req.sku(),
                req.nombre(),
                req.categoria(),
                req.precioUnitario(),
                req.stockMinimo(),
                req.codigoBarra()));
    }

    /**
     * Alta masiva desde una planilla Excel.
     *
     * <p>Sin {@code confirmar} solo simula: valida el archivo completo y
     * devuelve el mismo informe que devolvería la importación real, pero sin
     * escribir nada. Es lo que la app muestra antes de dejar apretar el botón,
     * porque cargar un catálogo a ciegas y descubrir después que veinte precios
     * quedaron mal es un problema que ya no se arregla desde la app.
     */
    @PostMapping(value = "/importar", consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
    @PreAuthorize("hasRole('ADMIN')")
    public ResultadoImportacion importar(
            @RequestParam("archivo") MultipartFile archivo,
            @RequestParam(required = false, defaultValue = "false") boolean confirmar) {
        if (archivo.isEmpty()) {
            throw new IllegalArgumentException("La planilla llegó vacía");
        }
        LectorPlanilla.exigirNombreXlsx(archivo.getOriginalFilename());
        try (var entrada = archivo.getInputStream()) {
            return materialService.importar(SesionActual.empresaId(), entrada, confirmar);
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }

    /** La planilla vacía con las columnas en el orden que espera el lector. */
    @GetMapping("/plantilla-importacion")
    @PreAuthorize("hasRole('ADMIN')")
    public ResponseEntity<byte[]> plantillaDeImportacion() {
        byte[] planilla = PlantillaExcel.generar("Materiales", FilaMaterial.ENCABEZADOS, FilaMaterial.EJEMPLOS);
        return ResponseEntity.ok()
                .contentType(MediaType.parseMediaType(
                        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"))
                .header(HttpHeaders.CONTENT_DISPOSITION, "attachment; filename=\"materiales-plantilla.xlsx\"")
                .body(planilla);
    }

    /**
     * El catálogo lo lee cualquier rol, pero el trabajador lo recibe sin precios ni
     * costos (S-08): son del administrador, según la matriz de permisos.
     */
    @GetMapping
    public List<MaterialVista> listar(@RequestParam(required = false) CategoriaMaterial categoria) {
        Long empresaId = SesionActual.empresaId();
        List<Material> materiales = categoria == null
                ? materialService.listarPorEmpresa(empresaId)
                : materialService.listarPorEmpresaYCategoria(empresaId, categoria);
        if (SesionActual.esTrabajador()) {
            return materiales.stream().<MaterialVista>map(MaterialBasicoResponse::de).toList();
        }
        Map<Long, CostoMaterial> costos = materialService.costosPorMaterial(empresaId);
        return materiales.stream().<MaterialVista>map(m -> MaterialResponse.de(m, costos.get(m.getId()))).toList();
    }

    @GetMapping("/{id}")
    public MaterialVista obtener(@PathVariable Long id) {
        return vista(materialService.obtener(id));
    }

    /**
     * Lo que resuelve el escáner de código de barras del bodeguero. Acepta el
     * código impreso de fábrica o el SKU de la empresa: quien apunta la cámara
     * a una etiqueta no sabe cuál de los dos está leyendo.
     */
    @GetMapping("/por-codigo/{codigo}")
    public MaterialVista buscarPorCodigo(@PathVariable String codigo) {
        return vista(materialService.buscarPorCodigo(SesionActual.empresaId(), codigo));
    }

    @PutMapping("/{id}/precio")
    @PreAuthorize("hasRole('ADMIN')")
    public MaterialResponse actualizarPrecio(@PathVariable Long id, @Valid @RequestBody ActualizarPrecioRequest req) {
        return conCosto(materialService.actualizarPrecio(id, req.nuevoPrecio()));
    }

    private MaterialResponse conCosto(Material material) {
        return MaterialResponse.de(material, materialService.costoDe(material));
    }

    /** Con costos para quien los maneja; sin ellos, para el trabajador. */
    private MaterialVista vista(Material material) {
        return SesionActual.esTrabajador() ? MaterialBasicoResponse.de(material) : conCosto(material);
    }

    public record CrearMaterialRequest(
            @NotBlank(message = "El SKU es obligatorio") @Size(max = 50, message = "El SKU admite hasta 50 caracteres") String sku,
            @NotBlank(message = "El nombre es obligatorio") @Size(max = 200, message = "El nombre admite hasta 200 caracteres") String nombre,
            @NotNull(message = "Falta la categoría") CategoriaMaterial categoria,
            @PositiveOrZero(message = "El precio no puede ser negativo") @DecimalMax(value = "1000000000", message = "El precio es demasiado grande") double precioUnitario,
            @PositiveOrZero(message = "El stock mínimo no puede ser negativo") @DecimalMax(value = "1000000", message = "El stock mínimo es demasiado grande") double stockMinimo,
            @Size(max = 50, message = "El código de barras admite hasta 50 caracteres") String codigoBarra) {
    }

    public record ActualizarPrecioRequest(
            @PositiveOrZero(message = "El precio no puede ser negativo") @DecimalMax(value = "1000000000", message = "El precio es demasiado grande") double nuevoPrecio) {
    }
}
