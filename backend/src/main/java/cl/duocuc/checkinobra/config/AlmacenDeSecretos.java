package cl.duocuc.checkinobra.config;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import java.io.IOException;
import java.io.UncheckedIOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.attribute.PosixFilePermissions;
import java.util.regex.Pattern;

/**
 * Dónde viven las contraseñas de las bases que crea la plataforma (MT7, #110).
 *
 * <p>El catálogo guarda una referencia, nunca el secreto: {@code env:VARIABLE} para las bases que
 * se registran a mano y {@code file:nombre} para las que da de alta la API, cuyo secreto no existía
 * antes de que arrancara. Cada secreto es un archivo de un directorio propio, solo legible por quien
 * corre la API. En un despliegue ese directorio debe ser un volumen persistente; si se pierde, las
 * bases de esas empresas no se pueden abrir.
 */
@Component
public class AlmacenDeSecretos {

    public static final String PREFIJO = "file:";

    /** Nombres de archivo: nada de rutas, así que una referencia no puede salirse del directorio. */
    private static final Pattern NOMBRE = Pattern.compile("[a-z0-9_]{1,63}");

    private final Path directorio;

    public AlmacenDeSecretos(@Value("${checkinobra.secretos.directorio:./secretos}") String directorio) {
        this.directorio = Path.of(directorio).toAbsolutePath().normalize();
    }

    public String guardar(String nombre, String valor) {
        Path archivo = archivo(nombre);
        try {
            Files.createDirectories(directorio);
            Files.writeString(archivo, valor, StandardCharsets.UTF_8);
            try {
                Files.setPosixFilePermissions(archivo, PosixFilePermissions.fromString("rw-------"));
            } catch (UnsupportedOperationException e) {
                // Sistema de archivos sin permisos POSIX: queda con los del directorio.
            }
        } catch (IOException e) {
            throw new UncheckedIOException("No se pudo guardar el secreto " + nombre, e);
        }
        return PREFIJO + nombre;
    }

    public String leer(String nombre) {
        try {
            return Files.readString(archivo(nombre), StandardCharsets.UTF_8).strip();
        } catch (IOException e) {
            throw new IllegalStateException("No se pudo leer el secreto " + nombre);
        }
    }

    public void borrar(String nombre) {
        try {
            Files.deleteIfExists(archivo(nombre));
        } catch (IOException e) {
            throw new UncheckedIOException("No se pudo borrar el secreto " + nombre, e);
        }
    }

    public boolean existe(String nombre) {
        return Files.exists(archivo(nombre));
    }

    private Path archivo(String nombre) {
        if (nombre == null || !NOMBRE.matcher(nombre).matches()) {
            throw new IllegalArgumentException("Nombre de secreto no válido");
        }
        return directorio.resolve(nombre);
    }
}
