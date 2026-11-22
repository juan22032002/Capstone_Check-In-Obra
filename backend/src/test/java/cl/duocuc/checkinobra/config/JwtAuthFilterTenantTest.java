package cl.duocuc.checkinobra.config;

import io.jsonwebtoken.Jwts;
import io.jsonwebtoken.security.Keys;
import jakarta.servlet.FilterChain;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;
import org.springframework.security.core.context.SecurityContextHolder;

import javax.crypto.SecretKey;
import javax.sql.DataSource;
import java.nio.charset.StandardCharsets;
import java.util.Collection;
import java.util.Date;
import java.util.List;
import java.util.Optional;
import java.util.Set;
import java.util.concurrent.atomic.AtomicReference;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * MT2 (#105): el filtro llena el contexto de empresa con la del token, lo limpia en un
 * {@code finally} después de toda la cadena (IdempotenciaFilter corre más adentro y
 * también usa la base), y un token sin empresa o de una empresa sin base no abre nada.
 */
class JwtAuthFilterTenantTest {

    private static final String SECRETO = "secreto-de-pruebas-de-al-menos-32-bytes-ok";
    private final JwtService jwt = new JwtService(SECRETO, 480);

    /** Una empresa conocida: la 5. */
    private final ResolutorDeBases resolutor = new ResolutorDeBases() {
        @Override
        public DataSource baseDe(Long empresaId) {
            throw new UnsupportedOperationException();
        }

        @Override
        public boolean conoce(Long empresaId) {
            return Set.of(5L).contains(empresaId);
        }

        @Override
        public Collection<Long> empresas() {
            return List.of(5L);
        }
    };

    /** Un usuario con sesión vigente: la revalidación contra la base no es lo que se prueba acá. */
    private final ValidadorDeSesion validador = org.mockito.Mockito.mock(ValidadorDeSesion.class);

    private final JwtAuthFilter filtro = new JwtAuthFilter(jwt, resolutor, validador, org.mockito.Mockito.mock(ValidadorDeOperador.class));

    @org.junit.jupiter.api.BeforeEach
    void sesionVigente() {
        org.mockito.Mockito.when(validador.vigente(org.mockito.ArgumentMatchers.anyLong(), org.mockito.ArgumentMatchers.any()))
                .thenReturn(true);
    }

    @AfterEach
    void limpiar() {
        TenantContext.limpiar();
        SecurityContextHolder.clearContext();
    }

    private String token(Object empresaId) {
        SecretKey clave = Keys.hmacShaKeyFor(SECRETO.getBytes(StandardCharsets.UTF_8));
        var b = Jwts.builder().subject("7").claim("email", "a@b.cl").claim("rol", "ADMIN").claim("tv", 0)
                .issuer("checkinobra").audience().add("checkinobra-api").and()
                .issuedAt(new Date()).expiration(new Date(System.currentTimeMillis() + 60_000));
        if (empresaId != null) {
            b.claim("empresaId", empresaId);
        }
        return b.signWith(clave).compact();
    }

    private record Observado(Optional<Long> empresaDuranteLaCadena, boolean autenticadoDurante, int status) {
    }

    private Observado pasar(String bearer) throws Exception {
        MockHttpServletRequest req = new MockHttpServletRequest("GET", "/api/obras");
        if (bearer != null) {
            req.addHeader("Authorization", "Bearer " + bearer);
        }
        MockHttpServletResponse res = new MockHttpServletResponse();
        AtomicReference<Optional<Long>> empresa = new AtomicReference<>();
        AtomicReference<Boolean> autenticado = new AtomicReference<>();
        FilterChain cadena = (rq, rs) -> {
            empresa.set(TenantContext.actual());
            autenticado.set(SecurityContextHolder.getContext().getAuthentication() != null);
        };

        filtro.doFilter(req, res, cadena);

        return new Observado(empresa.get(), autenticado.get(), res.getStatus());
    }

    @Test
    void conUnTokenValidoLaCadenaCorreConLaEmpresaDelToken() throws Exception {
        Observado o = pasar(token(5));

        assertThat(o.empresaDuranteLaCadena()).contains(5L);
        assertThat(o.autenticadoDurante()).isTrue();
    }

    @Test
    void despuesDeLaCadenaElContextoQuedaLimpio() throws Exception {
        pasar(token(5));

        assertThat(TenantContext.actual()).isEmpty();
    }

    @Test
    void siLaCadenaFallaIgualSeLimpia() {
        MockHttpServletRequest req = new MockHttpServletRequest("GET", "/api/obras");
        req.addHeader("Authorization", "Bearer " + token(5));
        FilterChain cadena = (rq, rs) -> {
            throw new IllegalStateException("falla río abajo");
        };

        assertThatThrownBy(() -> filtro.doFilter(req, new MockHttpServletResponse(), cadena))
                .isInstanceOf(IllegalStateException.class);

        assertThat(TenantContext.actual()).isEmpty();
    }

    @Test
    void unTokenSinEmpresaNoProduceUnErrorNiAbreNada() throws Exception {
        // Antes: NullPointerException en el filtro, un 500.
        Observado o = pasar(token(null));

        assertThat(o.empresaDuranteLaCadena()).isEmpty();
        assertThat(o.autenticadoDurante()).isFalse();
    }

    @Test
    void unTokenDeUnaEmpresaSinBaseNoAbreNada() throws Exception {
        Observado o = pasar(token(999));

        assertThat(o.empresaDuranteLaCadena()).isEmpty();
        assertThat(o.autenticadoDurante()).isFalse();
    }

    @Test
    void sinTokenOConUnoMalFirmadoLaCadenaCorreSinEmpresa() throws Exception {
        assertThat(pasar(null).empresaDuranteLaCadena()).isEmpty();
        assertThat(pasar("esto.no.es.un.jwt").empresaDuranteLaCadena()).isEmpty();
    }

    @Test
    void unTokenConClavePendienteNoLlenaLaEmpresa() throws Exception {
        SecretKey clave = Keys.hmacShaKeyFor(SECRETO.getBytes(StandardCharsets.UTF_8));
        String provisorio = Jwts.builder().subject("7").claim("email", "a@b.cl").claim("rol", "ADMIN")
                .claim("empresaId", 5).claim("cambiarPin", true).claim("tv", 0)
                .issuer("checkinobra").audience().add("checkinobra-api").and()
                .expiration(new Date(System.currentTimeMillis() + 60_000)).signWith(clave).compact();
        MockHttpServletResponse res = new MockHttpServletResponse();
        AtomicReference<Boolean> llegoALaCadena = new AtomicReference<>(false);

        filtro.doFilter(new MockHttpServletRequest("GET", "/api/obras") {{
            addHeader("Authorization", "Bearer " + provisorio);
        }}, res, (rq, rs) -> llegoALaCadena.set(true));

        assertThat(res.getStatus()).isEqualTo(403);
        assertThat(llegoALaCadena.get()).isFalse();
        assertThat(TenantContext.actual()).isEmpty();
    }
}
