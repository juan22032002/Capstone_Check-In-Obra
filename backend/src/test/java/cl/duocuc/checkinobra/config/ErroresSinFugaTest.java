package cl.duocuc.checkinobra.config;

import org.junit.jupiter.api.Test;
import org.springframework.http.ResponseEntity;

import java.util.ArrayList;
import java.util.NoSuchElementException;
import java.util.Optional;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.catchThrowableOfType;

/**
 * SEG10 (#98, S-25): el cuerpo de un error lleva el mensaje solo de las excepciones que escribimos
 * nosotros. Las de librerías cuentan detalles internos ({@code Invalid UUID string: …}) y salen
 * con un texto genérico; el original queda en el log.
 */
class ErroresSinFugaTest {

    private final ApiExceptionHandler manejador = new ApiExceptionHandler();

    private static String mensaje(ResponseEntity<ApiExceptionHandler.ErrorBody> r) {
        return r.getBody().mensaje();
    }

    @Test
    void unaExcepcionPropiaConservaSuMensaje() {
        var ex = new IllegalArgumentException("El SKU es obligatorio");

        assertThat(mensaje(manejador.solicitudInvalida(ex))).isEqualTo("El SKU es obligatorio");
        assertThat(mensaje(manejador.noEncontrado(new NoSuchElementException("Obra no encontrada: 7"))))
                .isEqualTo("Obra no encontrada: 7");
        assertThat(mensaje(manejador.conflicto(new IllegalStateException("Ya existe un material con ese SKU"))))
                .isEqualTo("Ya existe un material con ese SKU");
    }

    @Test
    void unConflictoConCodigoConservaMensajeYCodigo() {
        var r = manejador.conflicto(new ConflictoException(ConflictoException.SOLICITUD_DUPLICADA, "Ya pediste X"));

        assertThat(mensaje(r)).isEqualTo("Ya pediste X");
        assertThat(r.getBody().codigo()).isEqualTo(ConflictoException.SOLICITUD_DUPLICADA);
    }

    @Test
    void unaExcepcionDeLibreriaSaleConUnTextoGenerico() {
        // UUID.fromString lanza IllegalArgumentException desde el JDK con el valor recibido.
        var deLibreria = catchThrowableOfType(IllegalArgumentException.class, () -> UUID.fromString("no-es-un-uuid"));
        assertThat(deLibreria.getMessage()).contains("no-es-un-uuid");

        assertThat(mensaje(manejador.solicitudInvalida(deLibreria)))
                .isEqualTo("La solicitud no es válida").doesNotContain("uuid").doesNotContain("UUID");
    }

    @Test
    void elNoValuePresentDelJdkNoLlegaAlCliente() {
        var deLibreria = catchThrowableOfType(NoSuchElementException.class, () -> Optional.empty().orElseThrow());
        assertThat(deLibreria.getMessage()).isEqualTo("No value present");

        assertThat(mensaje(manejador.noEncontrado(deLibreria))).isEqualTo("No se encontró lo que pedías");
    }

    @Test
    void unEstadoIlegalDeLibreriaSaleGenerico() {
        // ArrayList.iterator().remove() sin next() lanza IllegalStateException desde el JDK.
        var deLibreria = catchThrowableOfType(IllegalStateException.class, () -> new ArrayList<>().iterator().remove());

        assertThat(mensaje(manejador.conflicto(deLibreria)))
                .isEqualTo("La operación no se puede completar en el estado actual");
    }

    @Test
    void unaSesionInvalidaDa401ConSuCodigoYNoDicePorQue() {
        var r = manejador.sesionInvalida(new SesionInvalidaException());

        assertThat(r.getStatusCode().value()).isEqualTo(401);
        assertThat(r.getBody().codigo()).isEqualTo("SESION_INVALIDA");
    }
}
