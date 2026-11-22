package cl.duocuc.checkinobra.config;

import cl.duocuc.checkinobra.config.RegistroIdempotencia.ClaveReutilizada;
import cl.duocuc.checkinobra.config.RegistroIdempotencia.EnCurso;
import cl.duocuc.checkinobra.config.RegistroIdempotencia.Repetida;
import cl.duocuc.checkinobra.config.RegistroIdempotencia.Reserva;
import cl.duocuc.checkinobra.config.RegistroIdempotencia.Reservada;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ReadListener;
import jakarta.servlet.ServletException;
import jakarta.servlet.ServletInputStream;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletRequestWrapper;
import jakarta.servlet.http.HttpServletResponse;
import jakarta.servlet.http.Part;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;
import org.springframework.web.util.ContentCachingResponseWrapper;
import tools.jackson.databind.json.JsonMapper;

import java.io.BufferedReader;
import java.io.ByteArrayInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.time.Instant;
import java.util.Comparator;
import java.util.HexFormat;
import java.util.List;
import java.util.Set;
import java.util.UUID;

/**
 * Cabecera {@code Idempotency-Key}: la misma petición repetida recibe la misma
 * respuesta, y la operación se ejecuta una sola vez.
 *
 * <p>El caso que lo motiva: el móvil corta a los 8 segundos, el servidor ya
 * había guardado el despacho, la respuesta no llega, el bodeguero toca otra vez
 * y el stock baja dos veces. Con la cabecera, el segundo toque recibe la
 * respuesta del primero.
 *
 * <p>Contrato con la app:
 * <ul>
 *   <li>La cabecera es opcional; sin ella la petición se atiende como siempre.
 *       Si viene y no es un UUID → 400.</li>
 *   <li>Misma clave, misma petición, ya terminada → el mismo status y el mismo
 *       cuerpo, con {@code Idempotency-Replayed: true}. Se repiten también los
 *       4xx de negocio, para que reintentar no cambie el resultado.</li>
 *   <li>Misma clave mientras la primera sigue en curso → 409
 *       {@code IDEMPOTENCIA_EN_CURSO}; reintentar con la misma clave.</li>
 *   <li>Misma clave con otra ruta u otro cuerpo → 422
 *       {@code IDEMPOTENCIA_CLAVE_REUTILIZADA}; es un error de la app.</li>
 *   <li>Un 5xx, un 401/403 o un conflicto de bloqueo no se guardan: el
 *       reintento vuelve a ejecutar.</li>
 * </ul>
 *
 * <p>Corre después de la cadena de Spring Security —un filtro {@code @Component}
 * sin orden queda al final—, así que el usuario del token ya está resuelto.
 *
 * <p><b>Hueco conocido:</b> la respuesta se guarda después de que la transacción
 * del negocio confirmó. Si el servidor se cae exactamente entre las dos cosas,
 * la reserva queda sin respuesta, se da por abandonada a los
 * {@value RegistroIdempotencia#ABANDONO}, y un reintento posterior vuelve a
 * ejecutar.
 */
@Component
public class IdempotenciaFilter extends OncePerRequestFilter {

    public static final String CABECERA = "Idempotency-Key";
    public static final String CABECERA_REPETIDA = "Idempotency-Replayed";

    public static final String EN_CURSO = "IDEMPOTENCIA_EN_CURSO";
    public static final String CLAVE_REUTILIZADA = "IDEMPOTENCIA_CLAVE_REUTILIZADA";

    /**
     * Atributo de la petición con el que un manejador de errores avisa que su
     * respuesta es transitoria y no se debe repetir (ver
     * {@link ApiExceptionHandler#conflictoConcurrente}).
     */
    public static final String NO_GUARDAR = IdempotenciaFilter.class.getName() + ".NO_GUARDAR";

    private static final Set<String> METODOS_QUE_ESCRIBEN = Set.of("POST", "PUT", "PATCH", "DELETE");

    /** Tope para leer el cuerpo a memoria; igual al de las planillas. */
    private static final int CUERPO_MAXIMO = 6 * 1024 * 1024;

    private final RegistroIdempotencia registro;
    private final JsonMapper jsonMapper;

    public IdempotenciaFilter(RegistroIdempotencia registro, JsonMapper jsonMapper) {
        this.registro = registro;
        this.jsonMapper = jsonMapper;
    }

    @Override
    protected boolean shouldNotFilter(HttpServletRequest request) {
        String ruta = request.getRequestURI();
        return request.getHeader(CABECERA) == null
                || !METODOS_QUE_ESCRIBEN.contains(request.getMethod())
                || !ruta.startsWith("/api/")
                // El login no tiene usuario todavía, y repetirlo no hace daño.
                || ruta.startsWith("/api/auth/")
                // Plataforma no tiene empresa: no hay base donde guardar la clave.
                || ruta.startsWith("/api/plataforma/");
    }

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain chain)
            throws ServletException, IOException {
        UUID clave;
        try {
            clave = UUID.fromString(request.getHeader(CABECERA).trim());
        } catch (IllegalArgumentException e) {
            error(response, HttpStatus.BAD_REQUEST, "La cabecera " + CABECERA + " debe ser un UUID", null);
            return;
        }

        Long usuarioId = usuarioAutenticado();
        if (usuarioId == null) {
            // Sin usuario no hay dónde anotar la clave. Spring Security ya
            // rechaza lo anónimo antes de llegar acá; esto es por si alguien
            // abre una ruta.
            chain.doFilter(request, response);
            return;
        }

        HttpServletRequest peticion;
        String huellaCuerpo;
        if (esMultipart(request)) {
            peticion = request;
            huellaCuerpo = huellaDePartes(request);
            if (huellaCuerpo == null) {
                // El multipart no se pudo leer (por ejemplo, pasó el tope de
                // tamaño). Que el controlador responda el error de siempre.
                chain.doFilter(request, response);
                return;
            }
        } else {
            byte[] cuerpo = request.getInputStream().readNBytes(CUERPO_MAXIMO);
            peticion = new PeticionReleible(request, cuerpo);
            huellaCuerpo = sha256(cuerpo);
        }

        String metodo = request.getMethod();
        String ruta = request.getRequestURI();
        String query = request.getQueryString() == null ? "" : request.getQueryString();
        String huella = sha256((metodo + " " + ruta + "?" + query + "\n" + huellaCuerpo)
                .getBytes(StandardCharsets.UTF_8));

        Reserva reserva = registro.reservar(usuarioId, clave, huella, metodo, ruta);
        switch (reserva) {
            case Repetida r -> repetir(response, r);
            case EnCurso e -> error(response, HttpStatus.CONFLICT,
                    "Esta operación ya se está procesando. Espera un momento y vuelve a intentarlo.", EN_CURSO);
            case ClaveReutilizada c -> error(response, HttpStatus.UNPROCESSABLE_CONTENT,
                    "La clave de idempotencia ya se usó con otra petición.", CLAVE_REUTILIZADA);
            case Reservada r -> ejecutar(peticion, response, chain, usuarioId, clave);
        }
    }

    private void ejecutar(
            HttpServletRequest peticion,
            HttpServletResponse response,
            FilterChain chain,
            Long usuarioId,
            UUID clave) throws ServletException, IOException {
        ContentCachingResponseWrapper respuesta = new ContentCachingResponseWrapper(response);
        try {
            chain.doFilter(peticion, respuesta);
        } catch (ServletException | IOException | RuntimeException e) {
            // Lo que sale como excepción (un @PreAuthorize denegado, un error
            // sin manejar) lo termina de responder otro filtro: no hay respuesta
            // que guardar, y el reintento tiene que poder ejecutarse.
            registro.liberar(usuarioId, clave);
            throw e;
        }

        if (seGuarda(peticion, respuesta.getStatus())) {
            registro.guardar(usuarioId, clave, respuesta.getStatus(), respuesta.getContentType(),
                    respuesta.getContentAsByteArray());
        } else {
            registro.liberar(usuarioId, clave);
        }
        respuesta.copyBodyToResponse();
    }

    private boolean seGuarda(HttpServletRequest peticion, int status) {
        if (peticion.getAttribute(NO_GUARDAR) != null) {
            return false;
        }
        // 401/403: la próxima vez puede venir con otro token o con otro rol.
        return status < 500 && status != 401 && status != 403;
    }

    private void repetir(HttpServletResponse response, Repetida r) throws IOException {
        response.setStatus(r.status());
        response.setHeader(CABECERA_REPETIDA, "true");
        if (r.contentType() != null) {
            response.setContentType(r.contentType());
        }
        if (r.cuerpo() != null) {
            response.setContentLength(r.cuerpo().length);
            response.getOutputStream().write(r.cuerpo());
        }
    }

    private void error(HttpServletResponse response, HttpStatus status, String mensaje, String codigo)
            throws IOException {
        response.setStatus(status.value());
        response.setContentType(MediaType.APPLICATION_JSON_VALUE);
        response.setCharacterEncoding(StandardCharsets.UTF_8.name());
        jsonMapper.writeValue(response.getOutputStream(),
                new ApiExceptionHandler.ErrorBody(Instant.now(), status.value(), mensaje, codigo));
    }

    private Long usuarioAutenticado() {
        Authentication auth = SecurityContextHolder.getContext().getAuthentication();
        return auth != null && auth.getPrincipal() instanceof UsuarioAutenticado u ? u.usuarioId() : null;
    }

    private boolean esMultipart(HttpServletRequest request) {
        String tipo = request.getContentType();
        return tipo != null && tipo.toLowerCase().startsWith("multipart/");
    }

    /**
     * La huella de un multipart no puede ser la de sus bytes: el separador entre
     * partes lo inventa el cliente en cada envío, y un reintento de la misma
     * planilla llega con otro. Se usa el contenido de cada parte.
     */
    private String huellaDePartes(HttpServletRequest request) {
        try {
            MessageDigest digest = MessageDigest.getInstance("SHA-256");
            List<Part> partes = request.getParts().stream()
                    .sorted(Comparator.comparing(Part::getName))
                    .toList();
            for (Part parte : partes) {
                digest.update((parte.getName() + "\0" + parte.getSubmittedFileName() + "\0")
                        .getBytes(StandardCharsets.UTF_8));
                try (InputStream contenido = parte.getInputStream()) {
                    digest.update(contenido.readAllBytes());
                }
                digest.update((byte) 0);
            }
            return HexFormat.of().formatHex(digest.digest());
        } catch (IOException | ServletException | IllegalStateException e) {
            return null;
        } catch (NoSuchAlgorithmException e) {
            throw new IllegalStateException(e);
        }
    }

    private static String sha256(byte[] datos) {
        try {
            return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(datos));
        } catch (NoSuchAlgorithmException e) {
            throw new IllegalStateException(e);
        }
    }

    /** El cuerpo ya se leyó para calcular la huella; el controlador lo lee de acá. */
    private static final class PeticionReleible extends HttpServletRequestWrapper {

        private final byte[] cuerpo;

        PeticionReleible(HttpServletRequest request, byte[] cuerpo) {
            super(request);
            this.cuerpo = cuerpo;
        }

        @Override
        public ServletInputStream getInputStream() {
            ByteArrayInputStream entrada = new ByteArrayInputStream(cuerpo);
            return new ServletInputStream() {
                @Override
                public int read() {
                    return entrada.read();
                }

                @Override
                public int read(byte[] b, int off, int len) {
                    return entrada.read(b, off, len);
                }

                @Override
                public boolean isFinished() {
                    return entrada.available() == 0;
                }

                @Override
                public boolean isReady() {
                    return true;
                }

                @Override
                public void setReadListener(ReadListener listener) {
                    throw new UnsupportedOperationException();
                }
            };
        }

        @Override
        public BufferedReader getReader() {
            String charset = getCharacterEncoding() == null ? StandardCharsets.UTF_8.name() : getCharacterEncoding();
            return new BufferedReader(new InputStreamReader(getInputStream(), java.nio.charset.Charset.forName(charset)));
        }

        @Override
        public int getContentLength() {
            return cuerpo.length;
        }

        @Override
        public long getContentLengthLong() {
            return cuerpo.length;
        }
    }
}
