package cl.duocuc.checkinobra.config;

import jakarta.servlet.http.HttpServletRequest;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.dao.OptimisticLockingFailureException;
import org.springframework.dao.PessimisticLockingFailureException;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import com.fasterxml.jackson.databind.exc.InvalidFormatException;
import org.springframework.http.converter.HttpMessageNotReadableException;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.method.annotation.MethodArgumentTypeMismatchException;
import org.springframework.web.bind.MissingServletRequestParameterException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;
import org.springframework.web.multipart.MaxUploadSizeExceededException;

import java.time.Instant;
import java.util.Arrays;
import java.util.List;
import java.util.NoSuchElementException;
import java.util.stream.Collectors;

@RestControllerAdvice
public class ApiExceptionHandler {

    /**
     * @param codigo qué conflicto es, para que la app decida sin leer el mensaje
     *     (ver {@link ConflictoException}). Nulo cuando el status ya lo dice todo.
     */
    public record ErrorBody(Instant instante, int status, String mensaje, String codigo) {
    }

    /** Dos escrituras chocaron sobre la misma fila; repetir la petición es seguro. */
    public static final String CONFLICTO_CONCURRENTE = "CONFLICTO_CONCURRENTE";

    /** Un UNIQUE de la base rechazó el dato; repetir la petición da lo mismo. */
    public static final String DATO_DUPLICADO = "DATO_DUPLICADO";

    /**
     * Login bloqueado por demasiados fallos. {@code Retry-After} va en segundos y
     * el {@code codigo} deja a la app mostrar la espera sin leer el mensaje.
     */
    @ExceptionHandler(DemasiadosIntentosException.class)
    public ResponseEntity<ErrorBody> demasiadosIntentos(DemasiadosIntentosException ex) {
        return ResponseEntity.status(HttpStatus.TOO_MANY_REQUESTS)
                .header(HttpHeaders.RETRY_AFTER, String.valueOf(ex.segundos()))
                .body(new ErrorBody(Instant.now(), HttpStatus.TOO_MANY_REQUESTS.value(), ex.getMessage(),
                        DemasiadosIntentosException.CODIGO));
    }

    /** El refresh token no sirve: 401 y un código para que la app pida la clave de nuevo. */
    @ExceptionHandler(SesionInvalidaException.class)
    public ResponseEntity<ErrorBody> sesionInvalida(SesionInvalidaException ex) {
        return cuerpo(HttpStatus.UNAUTHORIZED, ex.getMessage(), SesionInvalidaException.CODIGO);
    }

    @ExceptionHandler(AccesoDenegadoException.class)
    public ResponseEntity<ErrorBody> accesoDenegado(AccesoDenegadoException ex) {
        return cuerpo(HttpStatus.FORBIDDEN, ex.getMessage());
    }

    @ExceptionHandler(NoSuchElementException.class)
    public ResponseEntity<ErrorBody> noEncontrado(NoSuchElementException ex) {
        return cuerpo(HttpStatus.NOT_FOUND, mensajeSeguro(ex, "No se encontró lo que pedías"));
    }

    @ExceptionHandler(IllegalStateException.class)
    public ResponseEntity<ErrorBody> conflicto(IllegalStateException ex) {
        String codigo = ex instanceof ConflictoException c ? c.codigo() : null;
        return cuerpo(HttpStatus.CONFLICT,
                mensajeSeguro(ex, "La operación no se puede completar en el estado actual"), codigo);
    }

    /**
     * La base rechazó un dato repetido que la validación previa no vio, porque
     * otra petición lo insertó entre la comprobación y la escritura (dos
     * importaciones de la misma planilla, un doble tap sin clave de
     * idempotencia). Sin este manejador salía un 500.
     */
    @ExceptionHandler(DataIntegrityViolationException.class)
    public ResponseEntity<ErrorBody> datoDuplicado(DataIntegrityViolationException ex) {
        return cuerpo(HttpStatus.CONFLICT,
                "Otro registro con esos mismos datos se guardó recién. Actualiza y revisa antes de repetir.",
                DATO_DUPLICADO);
    }

    /** Se esperó demasiado por una fila bloqueada, o una versión cambió debajo. */
    @ExceptionHandler({PessimisticLockingFailureException.class, OptimisticLockingFailureException.class})
    public ResponseEntity<ErrorBody> conflictoConcurrente(RuntimeException ex, HttpServletRequest request) {
        // Es transitorio: si la petición traía clave de idempotencia, el
        // reintento con esa misma clave tiene que volver a ejecutarse, no
        // recibir este mismo 409.
        request.setAttribute(IdempotenciaFilter.NO_GUARDAR, true);
        return cuerpo(HttpStatus.CONFLICT,
                "Otra operación sobre lo mismo estaba en curso. Vuelve a intentarlo.",
                CONFLICTO_CONCURRENTE);
    }

    @ExceptionHandler(IllegalArgumentException.class)
    public ResponseEntity<ErrorBody> solicitudInvalida(IllegalArgumentException ex) {
        return cuerpo(HttpStatus.BAD_REQUEST, mensajeSeguro(ex, "La solicitud no es válida"));
    }

    /**
     * El mensaje de una excepción es para quien llama solo si la escribimos nosotros: las de
     * librerías ({@code Invalid UUID string: …}, {@code No value present}) cuentan detalles
     * internos, y publicarlas es dar pistas gratis (S-25). Una excepción es propia si se lanzó
     * desde una clase de este proyecto; el resto responde un texto genérico y deja el original
     * en el log, donde sí sirve.
     */
    static String mensajeSeguro(RuntimeException ex, String generico) {
        if (esPropia(ex)) {
            return ex.getMessage();
        }
        LoggerFactory.getLogger(ApiExceptionHandler.class)
                .warn("Excepción de librería con mensaje no publicado ({}): {}", ex.getClass().getName(), ex.getMessage());
        return generico;
    }

    private static boolean esPropia(RuntimeException ex) {
        if (ex instanceof ConflictoException) {
            return true;
        }
        StackTraceElement[] pila = ex.getStackTrace();
        return pila.length > 0 && pila[0].getClassName().startsWith("cl.duocuc.checkinobra.");
    }

    /**
     * Cuerpo ilegible: JSON roto, o un valor que no calza con el tipo esperado —
     * el caso típico es un enum inventado, como {@code "categoria": "PLANCHA"}.
     *
     * <p>Sin este manejador la excepción salía del controlador sin atender, Spring
     * la reenviaba a {@code /error}, y esa ruta no está permitida en
     * {@link SecurityConfig}: el resultado era un <b>403 con cuerpo vacío</b> ante
     * un simple error de tipeo en la petición. Depurar eso desde la app es
     * imposible: dice "no tienes permiso" cuando el permiso estaba bien.
     */
    @ExceptionHandler(HttpMessageNotReadableException.class)
    public ResponseEntity<ErrorBody> cuerpoIlegible(HttpMessageNotReadableException ex) {
        return cuerpo(HttpStatus.BAD_REQUEST, causaLegible(ex));
    }

    /** Un query param con el tipo equivocado: {@code ?obraId=abc}. */
    @ExceptionHandler(MethodArgumentTypeMismatchException.class)
    public ResponseEntity<ErrorBody> tipoInvalido(MethodArgumentTypeMismatchException ex) {
        return cuerpo(HttpStatus.BAD_REQUEST, "El parámetro '" + ex.getName() + "' no tiene un valor válido");
    }

    /** Falta un query param obligatorio. */
    @ExceptionHandler(MissingServletRequestParameterException.class)
    public ResponseEntity<ErrorBody> faltaParametro(MissingServletRequestParameterException ex) {
        return cuerpo(HttpStatus.BAD_REQUEST, "Falta el parámetro obligatorio '" + ex.getParameterName() + "'");
    }

    /**
     * La planilla de una importación masiva pasó el tope de tamaño.
     *
     * <p>Sin este manejador, Spring responde un 500 genérico y quien está
     * subiendo el archivo no tiene forma de saber que el problema es el peso.
     */
    @ExceptionHandler(MaxUploadSizeExceededException.class)
    public ResponseEntity<ErrorBody> archivoDemasiadoGrande(MaxUploadSizeExceededException ex) {
        return cuerpo(HttpStatus.PAYLOAD_TOO_LARGE,
                "El archivo supera el tamaño máximo permitido. Una planilla de catálogo no debería pesar tanto: "
                        + "revisa que no traiga imágenes ni hojas de más.");
    }

    @ExceptionHandler(MethodArgumentNotValidException.class)
    public ResponseEntity<ErrorBody> validacion(MethodArgumentNotValidException ex) {
        String mensaje = ex.getBindingResult().getFieldErrors().stream()
                .map(e -> e.getField() + ": " + e.getDefaultMessage())
                .collect(Collectors.joining("; "));
        return cuerpo(HttpStatus.BAD_REQUEST, mensaje);
    }

    /**
     * Jackson explica bien el problema, pero en varias líneas y citando la clase
     * Java. Se rescata la primera línea, que es la que le sirve a quien llama, sin
     * filtrar los nombres internos del backend.
     */
    private String causaLegible(HttpMessageNotReadableException ex) {
        // Se recorre la cadena entera porque, al deserializar un `record`, la
        // causa más específica no siempre es la que explica el problema.
        //
        // Y se pregunta por las dos clases a propósito: en el classpath conviven
        // Jackson 2 (`com.fasterxml.jackson`, que usan JJWT y los tests) y
        // Jackson 3 (`tools.jackson`, que es el que Spring Boot 4 usa para
        // convertir las peticiones HTTP). Son `InvalidFormatException`
        // distintos y sin parentesco: mirar solo el de Jackson 2 hacía que este
        // método nunca reconociera un enum inválido llegado por HTTP.
        for (Throwable causa = ex; causa != null; causa = causa.getCause()) {
            if (causa instanceof InvalidFormatException j2) {
                return explicar(j2.getValue(), campoDe(j2.getPath()), j2.getTargetType());
            }
            if (causa instanceof tools.jackson.databind.exc.InvalidFormatException j3) {
                return explicar(j3.getValue(), campoDe(j3.getPath()), j3.getTargetType());
            }
        }
        return "El cuerpo de la petición no se pudo leer: revisa que sea JSON válido";
    }

    private String campoDe(List<? extends Object> ruta) {
        if (ruta.isEmpty()) {
            return "un campo";
        }
        Object ultima = ruta.getLast();
        if (ultima instanceof com.fasterxml.jackson.databind.JsonMappingException.Reference r) {
            return r.getFieldName() == null ? "un campo" : r.getFieldName();
        }
        // Jackson 3 renombró `getFieldName()` a `getPropertyName()`.
        if (ultima instanceof tools.jackson.core.JacksonException.Reference r) {
            return r.getPropertyName() == null ? "un campo" : r.getPropertyName();
        }
        return "un campo";
    }

    /** Para un enum, listar los valores válidos ahorra ir a leer el código. */
    private String explicar(Object valor, String campo, Class<?> tipoEsperado) {
        String valores = tipoEsperado != null && tipoEsperado.isEnum()
                ? " (valores válidos: "
                        + Arrays.stream(tipoEsperado.getEnumConstants())
                                .map(Object::toString)
                                .collect(Collectors.joining(", "))
                        + ")"
                : "";
        return "El valor '" + valor + "' no es válido para " + campo + valores;
    }

    private ResponseEntity<ErrorBody> cuerpo(HttpStatus status, String mensaje) {
        return cuerpo(status, mensaje, null);
    }

    private ResponseEntity<ErrorBody> cuerpo(HttpStatus status, String mensaje, String codigo) {
        return ResponseEntity.status(status).body(new ErrorBody(Instant.now(), status.value(), mensaje, codigo));
    }
}
