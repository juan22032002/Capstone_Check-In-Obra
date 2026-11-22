package cl.duocuc.checkinobra.config;

import io.jsonwebtoken.Claims;
import io.jsonwebtoken.JwtException;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.jspecify.annotations.NonNull;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;
import java.util.List;

/** Lee el Bearer token de cada request y, si es válido, autentica al usuario. */
public class JwtAuthFilter extends OncePerRequestFilter {

    private final JwtService jwtService;
    private final ResolutorDeBases resolutor;
    private final ValidadorDeSesion validador;
    private final ValidadorDeOperador validadorDeOperador;

    public JwtAuthFilter(
            JwtService jwtService, ResolutorDeBases resolutor, ValidadorDeSesion validador,
            ValidadorDeOperador validadorDeOperador) {
        this.jwtService = jwtService;
        this.resolutor = resolutor;
        this.validador = validador;
        this.validadorDeOperador = validadorDeOperador;
    }

    /**
     * El token de un operador de plataforma (MT6, #109): sin empresa, revalidado contra el catálogo y
     * sin tocar ninguna base de empresa. Un token con ese rol que además trae empresa es inválido: no
     * hay un operador "de" una empresa.
     */
    private void autenticarOperador(Claims claims) {
        if (claims.get("empresaId") != null) {
            throw new IllegalArgumentException("Un token de plataforma no lleva empresa");
        }
        long operadorId = Long.parseLong(claims.getSubject());
        if (!validadorDeOperador.vigente(operadorId, claims.get("tv", Number.class))) {
            throw new IllegalArgumentException("El token ya no corresponde a un operador vigente");
        }
        var operador = new UsuarioAutenticado(
                operadorId, claims.get("email", String.class), RolUsuario.PLATAFORMA, null);
        SecurityContextHolder.getContext().setAuthentication(new UsernamePasswordAuthenticationToken(
                operador, null, List.of(new SimpleGrantedAuthority("ROLE_" + RolUsuario.PLATAFORMA.name()))));
    }

    /** La única llamada que una cuenta con clave provisoria puede hacer. */
    static final String RUTA_CAMBIO_DE_CLAVE = "/api/auth/pin";

    private static boolean esCambioDeClave(HttpServletRequest request) {
        return "PUT".equals(request.getMethod()) && RUTA_CAMBIO_DE_CLAVE.equals(request.getRequestURI());
    }

    /** Mismo cuerpo que {@code ApiExceptionHandler.ErrorBody}: la app lo lee igual. */
    private static void responderDebeCambiarPin(HttpServletResponse response) throws IOException {
        response.setStatus(HttpServletResponse.SC_FORBIDDEN);
        response.setContentType("application/json");
        response.setCharacterEncoding("UTF-8");
        response.getWriter().write("{\"instante\":\"" + java.time.Instant.now() + "\",\"status\":403,"
                + "\"mensaje\":\"Debes cambiar tu clave antes de seguir usando la aplicación\","
                + "\"codigo\":\"" + DEBE_CAMBIAR_PIN + "\"}");
    }

    /** Valor de {@code codigo} cuando la empresa del token está suspendida. */
    public static final String EMPRESA_SUSPENDIDA = "EMPRESA_SUSPENDIDA";

    private static void responderEmpresaSuspendida(HttpServletResponse response) throws IOException {
        response.setStatus(HttpServletResponse.SC_FORBIDDEN);
        response.setContentType("application/json");
        response.setCharacterEncoding("UTF-8");
        response.getWriter().write("{\"instante\":\"" + java.time.Instant.now() + "\",\"status\":403,"
                + "\"mensaje\":\"Tu empresa está suspendida: comunícate con la plataforma\","
                + "\"codigo\":\"" + EMPRESA_SUSPENDIDA + "\"}");
    }

    /** Valor de {@code codigo} cuando la cuenta debe cambiar su clave primero. */
    public static final String DEBE_CAMBIAR_PIN = "DEBE_CAMBIAR_PIN";

    @Override
    protected void doFilterInternal(
            @NonNull HttpServletRequest request,
            @NonNull HttpServletResponse response,
            @NonNull FilterChain filterChain) throws ServletException, IOException {

        String header = request.getHeader("Authorization");
        if (header != null && header.startsWith("Bearer ")) {
            try {
                Claims claims = jwtService.validarYExtraer(header.substring(7));
                String rol = claims.get("rol", String.class);
                if (RolUsuario.PLATAFORMA.name().equals(rol)) {
                    autenticarOperador(claims);
                    filterChain.doFilter(request, response);
                    return;
                }
                // Un token sin empresa no vale: antes daba un NullPointerException aquí
                // (un 500); ahora es un token inválido, y la petición sale como 401.
                Number empresaClaim = claims.get("empresaId", Number.class);
                if (empresaClaim == null) {
                    throw new IllegalArgumentException("El token no trae empresa");
                }
                long empresaId = empresaClaim.longValue();
                // Una empresa suspendida no abre nada: 403 con su código, sin tocar su base (MT8).
                if (resolutor.suspendida(empresaId)) {
                    SecurityContextHolder.clearContext();
                    TenantContext.limpiar();
                    responderEmpresaSuspendida(response);
                    return;
                }
                // La empresa tiene que tener una base abierta: un token de una empresa
                // que no está en el catálogo (o está suspendida) no abre nada.
                if (!resolutor.conoce(empresaId)) {
                    throw new IllegalArgumentException("La empresa del token no tiene base registrada");
                }
                long usuarioId = Long.parseLong(claims.getSubject());
                // El token no se confía por completo hasta vencer: se revalida contra el usuario, que
                // tiene que existir y seguir con la versión de sesión con que se emitió (S-11). Es una
                // lectura de la base de la empresa, así que se hace con su contexto fijado.
                TenantContext.fijar(empresaId);
                if (!validador.vigente(usuarioId, claims.get("tv", Number.class))) {
                    throw new IllegalArgumentException("El token ya no corresponde a la sesión del usuario");
                }
                // Cuenta con clave provisoria: solo puede cambiarla. Se corta acá y
                // no por @PreAuthorize: hay endpoints sin rol (solo autenticados) y
                // quedarían abiertos.
                if (Boolean.TRUE.equals(claims.get("cambiarPin", Boolean.class)) && !esCambioDeClave(request)) {
                    SecurityContextHolder.clearContext();
                    TenantContext.limpiar();
                    responderDebeCambiarPin(response);
                    return;
                }
                // El principal es el usuario completo, no solo su id: el
                // empresaId viaja firmado en el token y es lo que después
                // decide a qué datos puede llegar esta petición.
                var usuario = new UsuarioAutenticado(
                        usuarioId,
                        claims.get("email", String.class),
                        RolUsuario.valueOf(rol),
                        empresaId);
                var authToken = new UsernamePasswordAuthenticationToken(
                        usuario,
                        null,
                        List.of(new SimpleGrantedAuthority("ROLE_" + rol)));
                SecurityContextHolder.getContext().setAuthentication(authToken);
                // Desde acá, y hasta que termine la petición, la base es la de esta empresa
                // (ya está fijada: la validación de arriba la necesitó).
            } catch (JwtException | IllegalArgumentException | ClassCastException ex) {
                SecurityContextHolder.clearContext();
                TenantContext.limpiar();
            }
        }
        try {
            filterChain.doFilter(request, response);
        } finally {
            // En un finally y después de toda la cadena: IdempotenciaFilter corre más
            // adentro y también usa la base, así que limpiar antes se la quitaría.
            TenantContext.limpiar();
        }
    }
}
