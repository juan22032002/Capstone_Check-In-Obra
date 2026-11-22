package cl.duocuc.checkinobra.config;

import jakarta.servlet.DispatcherType;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.security.config.annotation.method.configuration.EnableMethodSecurity;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configurers.AbstractHttpConfigurer;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.http.HttpMethod;
import org.springframework.http.HttpStatus;
import org.springframework.security.authentication.AnonymousAuthenticationToken;
import org.springframework.security.authorization.AuthorizationDecision;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.security.web.authentication.HttpStatusEntryPoint;
import org.springframework.security.web.authentication.UsernamePasswordAuthenticationFilter;

@Configuration
@EnableMethodSecurity
public class SecurityConfig {

    private final JwtService jwtService;
    private final ResolutorDeBases resolutor;
    private final ValidadorDeSesion validador;
    private final EventosDeSeguridad eventos;
    private final ValidadorDeOperador validadorDeOperador;
    private final boolean documentacionPublica;

    public SecurityConfig(
            JwtService jwtService, ResolutorDeBases resolutor, ValidadorDeSesion validador, ValidadorDeOperador validadorDeOperador, EventosDeSeguridad eventos,
            @org.springframework.beans.factory.annotation.Value("${springdoc.api-docs.enabled:true}")
            boolean documentacionPublica) {
        this.documentacionPublica = documentacionPublica;
        this.validadorDeOperador = validadorDeOperador;
        this.jwtService = jwtService;
        this.resolutor = resolutor;
        this.validador = validador;
        this.eventos = eventos;
    }

    /** Autenticado y no operador de plataforma: lo que exige toda ruta de empresa que no declara un rol. */
    private static org.springframework.security.authorization.AuthorizationManager<
            org.springframework.security.web.access.intercept.RequestAuthorizationContext> autenticadoDeEmpresa() {
        return (autenticacion, contexto) -> new AuthorizationDecision(
                autenticacion.get().isAuthenticated()
                        && !(autenticacion.get() instanceof AnonymousAuthenticationToken)
                        && autenticacion.get().getAuthorities().stream()
                                .noneMatch(a -> a.getAuthority().equals("ROLE_PLATAFORMA")));
    }

    @Bean
    public SecurityFilterChain filterChain(HttpSecurity http) throws Exception {
        http
                .csrf(AbstractHttpConfigurer::disable)
                .sessionManagement(sm -> sm.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
                // Sin token, o con uno vencido o mal firmado → 401. El valor por
                // defecto de Spring Security para una API sin login por
                // formulario era 403, igual que un rol insuficiente, y la app no
                // podía distinguir "vuelve a entrar con tu PIN" de "tu rol no
                // permite esto". El 403 queda solo para lo segundo.
                .exceptionHandling(e -> e
                        .authenticationEntryPoint(new HttpStatusEntryPoint(HttpStatus.UNAUTHORIZED))
                        // Un rol que no alcanza (@PreAuthorize) sigue siendo 403, y ahora queda registrado.
                        .accessDeniedHandler((request, response, denegado) -> {
                            eventos.accesoDenegado(request.getMethod(), request.getRequestURI());
                            response.sendError(HttpStatus.FORBIDDEN.value());
                        }))
                .authorizeHttpRequests(auth -> auth
                        // Cuando algo falla, Spring reenvía internamente a
                        // /error. Ese reenvío pasa otra vez por esta cadena y,
                        // al no estar permitido, terminaba en un 403 con cuerpo
                        // vacío: un 404 o un 405 se veían como "no tienes
                        // permiso". Se permite el *dispatch* de error, no una
                        // petición directa a /error.
                        .dispatcherTypeMatchers(DispatcherType.ERROR).permitAll()
                        // Cambiar la propia clave exige estar autenticado: va antes
                        // del permitAll de /api/auth/**.
                        .requestMatchers(HttpMethod.PUT, "/api/auth/pin").access(autenticadoDeEmpresa())
                        .requestMatchers("/api/auth/**", "/actuator/health/**").permitAll()
                        // La documentación de la API es pública solo donde está encendida: en el
                        // perfil prod (springdoc.api-docs.enabled=false) estas rutas pasan a exigir
                        // autenticación y, además, springdoc ya no las sirve (S-12).
                        .requestMatchers("/v3/api-docs/**", "/swagger-ui/**", "/swagger-ui.html")
                        .access((autenticacion, contexto) -> new AuthorizationDecision(documentacionPublica))
                        // Plataforma (MT6, #109): el login es público; todo lo demás, solo del rol PLATAFORMA.
                        .requestMatchers(HttpMethod.POST, "/api/plataforma/auth/login").permitAll()
                        .requestMatchers("/api/plataforma/**").hasRole("PLATAFORMA")
                        // Y a la inversa: un token de plataforma no llega a ninguna ruta de empresa,
                        // tampoco a las que solo piden "estar autenticado" y no declaran un rol.
                        .anyRequest().access(autenticadoDeEmpresa()))
                .addFilterBefore(new JwtAuthFilter(jwtService, resolutor, validador, validadorDeOperador),
                        UsernamePasswordAuthenticationFilter.class);
        return http.build();
    }
}
