package cl.duocuc.checkinobra.inventario;

import jakarta.validation.constraints.DecimalMax;
import jakarta.validation.constraints.NotBlank;
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
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.multipart.MultipartFile;

import java.io.IOException;
import java.io.UncheckedIOException;
import java.util.List;

@RestController
@RequestMapping("/api/herramientas")
@Tag(name = "Herramienta")
public class HerramientaController {

    private final HerramientaService herramientaService;

    public HerramientaController(HerramientaService herramientaService) {
        this.herramientaService = herramientaService;
    }

    @PostMapping
    @PreAuthorize("hasAnyRole('ADMIN', 'BODEGUERO')")
    @ResponseStatus(HttpStatus.CREATED)
    public HerramientaResponse crear(@Valid @RequestBody CrearHerramientaRequest req) {
        // La empresa sale del token, no de la petición. Mientras el cliente
        // pudiera nombrarla, pedir los datos de otra constructora era cuestión
        // de cambiar un número en la URL.
        return HerramientaResponse.de(herramientaService.crear(
                SesionActual.empresaId(), req.codigoQr(), req.nombre(), req.categoria(), req.valorReposicion()));
    }

    /**
     * Cualquier rol lee el catálogo de herramientas, pero el trabajador lo recibe
     * sin el valor de reposición (S-08).
     */
    @GetMapping
    public List<HerramientaVista> listarPorEmpresa() {
        return herramientaService.listarPorEmpresa(SesionActual.empresaId()).stream()
                .<HerramientaVista>map(HerramientaController::vista)
                .toList();
    }

    @GetMapping("/{id}")
    public HerramientaVista obtener(@PathVariable Long id) {
        return vista(herramientaService.obtener(id));
    }

    /** Con valor de reposición para quien lo maneja; sin él, para el trabajador. */
    private static HerramientaVista vista(Herramienta herramienta) {
        return SesionActual.esTrabajador()
                ? HerramientaBasicaResponse.de(herramienta)
                : HerramientaResponse.de(herramienta);
    }

    /**
     * Alta masiva desde una planilla Excel. Igual que en materiales, sin
     * {@code confirmar} solo valida y devuelve el informe sin escribir nada.
     *
     * <p>La autoriza también el BODEGUERO —y no solo el ADMIN, como en
     * materiales— porque las herramientas las etiqueta y las da de alta la
     * propia bodega cuando llegan: es la misma persona que ya puede crearlas
     * de a una.
     */
    @PostMapping(value = "/importar", consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
    @PreAuthorize("hasAnyRole('ADMIN', 'BODEGUERO')")
    public ResultadoImportacion importar(
            @RequestParam("archivo") MultipartFile archivo,
            @RequestParam(required = false, defaultValue = "false") boolean confirmar) {
        if (archivo.isEmpty()) {
            throw new IllegalArgumentException("La planilla llegó vacía");
        }
        LectorPlanilla.exigirNombreXlsx(archivo.getOriginalFilename());
        try (var entrada = archivo.getInputStream()) {
            return herramientaService.importar(SesionActual.empresaId(), entrada, confirmar);
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }

    /** La planilla vacía con las columnas en el orden que espera el lector. */
    @GetMapping("/plantilla-importacion")
    @PreAuthorize("hasAnyRole('ADMIN', 'BODEGUERO')")
    public ResponseEntity<byte[]> plantillaDeImportacion() {
        byte[] planilla = PlantillaExcel.generar(
                "Herramientas", FilaHerramienta.ENCABEZADOS, FilaHerramienta.EJEMPLOS);
        return ResponseEntity.ok()
                .contentType(MediaType.parseMediaType(
                        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"))
                .header(HttpHeaders.CONTENT_DISPOSITION, "attachment; filename=\"herramientas-plantilla.xlsx\"")
                .body(planilla);
    }

    @GetMapping("/por-codigo/{codigoQr}")
    public HerramientaVista buscarPorCodigo(@PathVariable String codigoQr) {
        return vista(herramientaService.buscarPorCodigoQr(codigoQr));
    }

    public record CrearHerramientaRequest(
            @NotBlank(message = "El código es obligatorio") @Size(max = 100, message = "El código admite hasta 100 caracteres") String codigoQr,
            @NotBlank(message = "El nombre es obligatorio") @Size(max = 200, message = "El nombre admite hasta 200 caracteres") String nombre,
            @NotBlank(message = "La categoría es obligatoria") @Size(max = 100, message = "La categoría admite hasta 100 caracteres") String categoria,
            @PositiveOrZero(message = "El valor de reposición no puede ser negativo") @DecimalMax(value = "1000000000", message = "El valor de reposición es demasiado grande") double valorReposicion) {
    }
}
