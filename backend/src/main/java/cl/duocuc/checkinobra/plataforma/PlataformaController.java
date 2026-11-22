package cl.duocuc.checkinobra.plataforma;

import cl.duocuc.checkinobra.config.CatalogoDeEmpresas;
import cl.duocuc.checkinobra.config.CatalogoDeEmpresas.EmpresaRegistrada;
import cl.duocuc.checkinobra.config.CatalogoDeEmpresas.OperadorRegistrado;
import cl.duocuc.checkinobra.config.EventosDeSeguridad;
import cl.duocuc.checkinobra.config.JwtService;
import cl.duocuc.checkinobra.config.ResolutorDeBases;
import cl.duocuc.checkinobra.config.SesionActual;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.validation.Valid;
import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;
import java.util.NoSuchElementException;

/**
 * Las rutas del operador de plataforma (MT6, #109). Solo las toca el rol {@code PLATAFORMA}
 * (ver {@code SecurityConfig}), que no pertenece a ninguna empresa: nada de lo que hay acá abre la
 * base de una.
 */
@RestController
@RequestMapping("/api/plataforma")
@Tag(name = "Plataforma")
public class PlataformaController {

    private final PlataformaAutenticacionService autenticacion;
    private final CatalogoDeEmpresas catalogo;
    private final JwtService jwtService;
    private final AltaDeEmpresaService altaDeEmpresa;
    private final EventosDeSeguridad eventos;
    private final ResolutorDeBases resolutor;

    public PlataformaController(
            PlataformaAutenticacionService autenticacion, CatalogoDeEmpresas catalogo, JwtService jwtService,
            AltaDeEmpresaService altaDeEmpresa, EventosDeSeguridad eventos, ResolutorDeBases resolutor) {
        this.resolutor = resolutor;
        this.autenticacion = autenticacion;
        this.catalogo = catalogo;
        this.jwtService = jwtService;
        this.altaDeEmpresa = altaDeEmpresa;
        this.eventos = eventos;
    }

    @PostMapping("/auth/login")
    public SesionDePlataformaResponse login(@Valid @RequestBody LoginDeOperadorRequest req, HttpServletRequest http) {
        OperadorRegistrado operador = autenticacion.login(req.email(), req.clave(), http.getRemoteAddr());
        return new SesionDePlataformaResponse(jwtService.emitirParaOperador(operador), operador.email(), operador.nombre());
    }

    @GetMapping("/yo")
    public OperadorResponse yo() {
        return catalogo.buscarOperadorActivo(SesionActual.usuario().usuarioId())
                .map(o -> new OperadorResponse(o.id(), o.email(), o.nombre()))
                .orElseThrow();
    }

    /** Las empresas registradas, sin lo que sirve para abrir su base (usuario de base y secreto). */
    @GetMapping("/empresas")
    public List<EmpresaDePlataformaResponse> empresas() {
        return catalogo.listar().stream().map(EmpresaDePlataformaResponse::de).toList();
    }

    /**
     * Da de alta una constructora: su base, su usuario de PostgreSQL, el esquema y su primer ADMIN,
     * que queda obligado a cambiar la clave en su primer ingreso. Si algún paso falla, se deshace todo.
     */
    @PostMapping("/empresas")
    @ResponseStatus(HttpStatus.CREATED)
    public AltaDeEmpresaResponse darDeAlta(@Valid @RequestBody AltaDeEmpresaRequest req) {
        var resultado = altaDeEmpresa.dar(
                req.rut(), req.nombre(), req.adminEmail(), req.adminClave(), Boolean.TRUE.equals(req.copiarCatalogoBase()));
        eventos.empresaCreada(SesionActual.usuario().usuarioId(), resultado.empresaId());
        return new AltaDeEmpresaResponse(resultado.empresaId(), resultado.rut(), resultado.nombre(),
                resultado.adminEmail(), resultado.claveTemporal());
    }

    /**
     * Suspende ({@code SUSPENDIDA}) o reactiva ({@code ACTIVA}) una empresa. Idempotente. Una empresa
     * suspendida pierde su pool y recibe 403 en cada petición; sus datos no se tocan.
     */
    @PutMapping("/empresas/{id}/estado")
    public EmpresaDePlataformaResponse cambiarEstado(@PathVariable Long id, @Valid @RequestBody CambiarEstadoRequest req) {
        if (!catalogo.cambiarEstadoDeEmpresa(id, req.estado())) {
            throw new NoSuchElementException("Empresa no encontrada: " + id);
        }
        // El pool se cierra (o se abre) ahora y el 403 vale de inmediato.
        resolutor.refrescar();
        eventos.empresaCambiaDeEstado(SesionActual.usuario().usuarioId(), id, req.estado());
        return catalogo.listar().stream().filter(e -> e.id().equals(id)).findFirst()
                .map(EmpresaDePlataformaResponse::de).orElseThrow();
    }

    public record CambiarEstadoRequest(@NotBlank @Pattern(regexp = "ACTIVA|SUSPENDIDA") String estado) {
    }

    public record AltaDeEmpresaRequest(
            @NotBlank @Size(max = 20) String rut,
            @NotBlank @Size(max = 200) String nombre,
            @NotBlank @Email @Size(max = 200) String adminEmail,
            @Size(min = 8, max = 72) String adminClave,
            Boolean copiarCatalogoBase) {
    }

    /** {@code claveTemporal} solo viene si el sistema la generó: es la única vez que se muestra. */
    public record AltaDeEmpresaResponse(Long id, String rut, String nombre, String adminEmail, String claveTemporal) {
    }

    public record LoginDeOperadorRequest(
            @NotBlank @Size(max = 255) String email, @NotBlank @Size(max = 200) String clave) {
    }

    public record SesionDePlataformaResponse(String token, String email, String nombre) {
    }

    public record OperadorResponse(Long id, String email, String nombre) {
    }

    public record EmpresaDePlataformaResponse(
            Long id, String rut, String nombre, String plan, String estado, String migracionEstado) {

        static EmpresaDePlataformaResponse de(EmpresaRegistrada e) {
            return new EmpresaDePlataformaResponse(
                    e.id(), e.rut(), e.nombre(), e.plan(), e.estado(), e.migracionEstado());
        }
    }
}
