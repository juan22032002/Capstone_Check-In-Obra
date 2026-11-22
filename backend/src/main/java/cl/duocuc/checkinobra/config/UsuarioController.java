package cl.duocuc.checkinobra.config;

import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;
import jakarta.validation.Valid;
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

import java.util.List;

@RestController
@RequestMapping("/api/usuarios")
@Tag(name = "Usuario")
public class UsuarioController {

    private final UsuarioService usuarioService;

    public UsuarioController(UsuarioService usuarioService) {
        this.usuarioService = usuarioService;
    }

    /** Crear usuarios y asignar rol es exclusivo de ADMIN, según la matriz de permisos. */
    @PostMapping
    @PreAuthorize("hasRole('ADMIN')")
    @ResponseStatus(HttpStatus.CREATED)
    public UsuarioResponse crear(@Valid @RequestBody CrearUsuarioRequest req) {
        // La empresa sale del token, no de la petición. Mientras el cliente
        // pudiera nombrarla, pedir los datos de otra constructora era cuestión
        // de cambiar un número en la URL.
        return UsuarioResponse.de(usuarioService.crear(
                SesionActual.empresaId(), req.nombre(), req.email(), req.rut(), req.rol(), req.pinInicial()));
    }

    /** Leer el padrón es tan sensible como escribirlo: mismo rol que crear. */
    @GetMapping
    @PreAuthorize("hasRole('ADMIN')")
    public List<UsuarioResponse> listarPorEmpresa() {
        return usuarioService.listarPorEmpresa(SesionActual.empresaId()).stream()
                .map(UsuarioResponse::de)
                .toList();
    }

    @GetMapping("/{id}")
    @PreAuthorize("hasRole('ADMIN')")
    public UsuarioResponse obtener(@PathVariable Long id) {
        return UsuarioResponse.de(usuarioService.obtener(id));
    }

    @PutMapping("/{id}/pin")
    @PreAuthorize("hasRole('ADMIN')")
    public UsuarioResponse redefinirPin(@PathVariable Long id, @Valid @RequestBody RedefinirPinRequest req) {
        return UsuarioResponse.de(usuarioService.redefinirPin(id, req.nuevoPin()));
    }

    public record CrearUsuarioRequest(
            @NotBlank(message = "El nombre es obligatorio") @Size(max = 200, message = "El nombre admite hasta 200 caracteres") String nombre,
            @NotBlank(message = "El correo es obligatorio") @Email(message = "El correo no tiene un formato válido") @Size(max = 200, message = "El correo admite hasta 200 caracteres") String email,
            @NotBlank(message = "El RUT es obligatorio") @Size(max = 20, message = "El RUT admite hasta 20 caracteres") String rut,
            @NotNull(message = "Falta el rol") RolUsuario rol,
            @Size(max = 72, message = "La clave admite hasta 72 caracteres") String pinInicial) {
    }

    public record RedefinirPinRequest(
            @NotBlank(message = "La clave nueva es obligatoria") @Size(max = 72, message = "La clave admite hasta 72 caracteres") String nuevoPin) {
    }
}
