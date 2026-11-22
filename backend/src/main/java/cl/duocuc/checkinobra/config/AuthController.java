package cl.duocuc.checkinobra.config;

import jakarta.validation.Valid;
import com.fasterxml.jackson.annotation.JsonAlias;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * El diagrama modela Usuario.autenticar(pin) y Usuario.autenticarPorEmail(email)
 * como dos verificaciones separadas — Usuario solo guarda pinHash, no una
 * contraseña aparte. Por eso el login para los 4 roles queda unificado como
 * "correo + PIN": el correo ubica al usuario (autenticarPorEmail) y el PIN
 * lo autentica (autenticar). La app móvil, que ya conoce al usuario en el
 * teléfono, usa el segundo endpoint solo con el id + PIN.
 */
@RestController
@RequestMapping("/api/auth")
@Tag(name = "Autenticación")
public class AuthController {

    private final AutenticacionService autenticacionService;
    private final JwtService jwtService;
    private final SesionService sesionService;
    private final ResolutorDeBases resolutor;

    public AuthController(
            AutenticacionService autenticacionService, JwtService jwtService,
            SesionService sesionService, ResolutorDeBases resolutor) {
        this.autenticacionService = autenticacionService;
        this.jwtService = jwtService;
        this.sesionService = sesionService;
        this.resolutor = resolutor;
    }

    @PostMapping("/login")
    @Operation(summary = "Login por correo + clave — los cuatro roles. "
            + "ADMIN, JEFE_TERRENO y BODEGUERO usan una clave de 8 o más caracteres; TRABAJADOR, su PIN de 4 dígitos. "
            + "Responde 429 con Retry-After tras demasiados intentos fallidos.")
    public ResponseEntity<LoginResponse> login(@Valid @RequestBody LoginPorCorreoRequest req, HttpServletRequest http) {
        Usuario usuario = autenticacionService.loginPorCorreo(req.email(), req.pin(), http.getRemoteAddr());
        return ResponseEntity.ok(respuestaPara(usuario));
    }

    @PostMapping("/login-pin")
    @Operation(summary = "Login por PIN — usuario ya identificado en el teléfono. Solo rol TRABAJADOR. "
            + "Responde 429 con Retry-After tras demasiados intentos fallidos.")
    public ResponseEntity<LoginResponse> loginPin(@Valid @RequestBody LoginPorPinRequest req, HttpServletRequest http) {
        Usuario usuario = autenticacionService.loginPorPin(req.usuarioId(), req.empresaId(), req.pin(), http.getRemoteAddr());
        return ResponseEntity.ok(respuestaPara(usuario));
    }

    @PutMapping("/pin")
    @Operation(summary = "Cambia la clave propia. Es lo único que puede llamar una cuenta con clave provisoria "
            + "(debeCambiarClave). Devuelve una sesión nueva, ya sin la obligación.")
    public ResponseEntity<LoginResponse> cambiarPin(@Valid @RequestBody CambiarPinRequest req, HttpServletRequest http) {
        Usuario usuario = autenticacionService.cambiarPin(
                SesionActual.usuarioId(), req.pinActual(), req.pinNuevo(), http.getRemoteAddr());
        return ResponseEntity.ok(respuestaPara(usuario));
    }

    @PostMapping("/refresh")
    @Operation(summary = "Canjea un refresh token por un token de acceso nuevo y un refresh token nuevo. "
            + "El presentado queda revocado; uno ya usado revoca todas las sesiones del usuario. "
            + "Responde 401 con codigo SESION_INVALIDA si no sirve.")
    public ResponseEntity<LoginResponse> refrescar(@Valid @RequestBody RefrescarRequest req) {
        Long empresaId = SesionService.empresaDe(req.refreshToken()).filter(resolutor::conoce)
                .orElseThrow(SesionInvalidaException::new);
        SesionService.Rotado rotado = TenantContext.ejecutarEn(empresaId, () -> sesionService.rotar(req.refreshToken()));
        return ResponseEntity.ok(respuestaPara(rotado.usuario(), rotado.refreshToken()));
    }

    @PostMapping("/logout")
    @Operation(summary = "Cierra la sesión: revoca el refresh token. Siempre responde 204, exista o no.")
    public ResponseEntity<Void> cerrarSesion(@Valid @RequestBody RefrescarRequest req) {
        SesionService.empresaDe(req.refreshToken()).filter(resolutor::conoce)
                .ifPresent(id -> TenantContext.ejecutarEn(id, () -> sesionService.revocar(req.refreshToken())));
        return ResponseEntity.noContent().build();
    }

    private LoginResponse respuestaPara(Usuario usuario) {
        String refresh = TenantContext.ejecutarEn(usuario.getEmpresa().getId(), () -> sesionService.emitir(usuario));
        return respuestaPara(usuario, refresh);
    }

    private LoginResponse respuestaPara(Usuario usuario, String refreshToken) {
        return new LoginResponse(
                jwtService.emitir(usuario),
                usuario.getId(),
                usuario.getNombre(),
                usuario.getRol(),
                usuario.getEmpresa().getId(),
                usuario.isDebeCambiarPin(),
                refreshToken);
    }

    public record RefrescarRequest(@NotBlank @Size(max = 4000) String refreshToken) {
    }

    public record CambiarPinRequest(
            @NotBlank @Size(max = 72) String pinActual, @NotBlank @Size(max = 72) String pinNuevo) {
    }

    /**
     * {@code pin} lleva el PIN de 4 dígitos del TRABAJADOR o la clave de 8 o más
     * caracteres de los demás roles; {@code clave} es un alias del mismo campo.
     */
    public record LoginPorCorreoRequest(
            @NotBlank String email,
            @NotBlank @Size(min = 4, max = 72) @JsonAlias("clave") String pin) {
    }

    /**
     * @param empresaId la empresa del usuario recordado en el teléfono; opcional mientras haya una sola
     */
    public record LoginPorPinRequest(
            @NotNull Long usuarioId, Long empresaId, @NotBlank @Pattern(regexp = "\\d{4}") String pin) {
    }

    /**
     * @param refreshToken para pedir otro token de acceso en {@code POST /api/auth/refresh} sin la clave;
     *     el de acceso dura poco
     * @param debeCambiarClave la clave es provisoria: el token solo sirve para
     *     {@code PUT /api/auth/pin} hasta que la cambie
     */
    public record LoginResponse(
            String token, Long usuarioId, String nombre, RolUsuario rol, Long empresaId, boolean debeCambiarClave,
            String refreshToken) {
    }
}
