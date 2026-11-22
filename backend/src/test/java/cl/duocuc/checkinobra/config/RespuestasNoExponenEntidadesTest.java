package cl.duocuc.checkinobra.config;

import jakarta.persistence.Entity;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.config.BeanDefinition;
import org.springframework.context.annotation.ClassPathScanningCandidateComponentProvider;
import org.springframework.core.type.filter.AssignableTypeFilter;
import org.springframework.core.type.filter.RegexPatternTypeFilter;

import java.lang.reflect.ParameterizedType;
import java.lang.reflect.RecordComponent;
import java.lang.reflect.Type;
import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.List;
import java.util.Set;
import java.util.regex.Pattern;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.fail;

/**
 * La regla es "los controladores devuelven records, nunca entidades". Se cumplió
 * una vez, a mano, en 16 controladores. Sin algo que la sostenga, el próximo
 * endpoint la rompe sin que nadie lo note — que es justo como el hash del PIN
 * terminó publicado.
 *
 * <p>Estas pruebas la revisan sobre el código, no sobre una lista escrita a mano:
 * recorren todos los {@code *Response} del proyecto y todas las entidades JPA, y
 * fallan si alguna se asoma a la superficie de la API.
 */
class RespuestasNoExponenEntidadesTest {

    private static final String BASE = "cl.duocuc.checkinobra";

    /**
     * Lo único que puede viajar en una respuesta: escalares, texto, fechas.
     * Cualquier otra cosa es un objeto del dominio y arrastra su grafo.
     */
    private static final Set<Class<?>> TIPOS_PERMITIDOS = Set.of(
            long.class, int.class, double.class, boolean.class,
            Long.class, Integer.class, Double.class, Boolean.class,
            String.class, BigDecimal.class, LocalDate.class, LocalDateTime.class);

    private List<Class<?>> buscar(org.springframework.core.type.filter.TypeFilter filtro) {
        var scanner = new ClassPathScanningCandidateComponentProvider(false);
        scanner.addIncludeFilter(filtro);
        return scanner.findCandidateComponents(BASE).stream()
                .map(BeanDefinition::getBeanClassName)
                .<Class<?>>map(nombre -> {
                    try {
                        return Class.forName(nombre);
                    } catch (ClassNotFoundException e) {
                        throw new IllegalStateException(e);
                    }
                })
                .toList();
    }

    @Test
    void ningun_record_de_respuesta_lleva_un_objeto_del_dominio() {
        List<Class<?>> respuestas =
                buscar(new RegexPatternTypeFilter(Pattern.compile(".*Response$")));

        // Si el escaneo no encuentra nada, el test pasaría en vacío y no
        // protegería nada.
        assertThat(respuestas).hasSizeGreaterThan(10);

        for (Class<?> respuesta : respuestas) {
            assertThat(respuesta.isRecord())
                    .as("%s debería ser un record", respuesta.getSimpleName())
                    .isTrue();

            revisarComponentes(respuesta);
        }
    }

    /**
     * Una respuesta agregada —la ficha de una obra— puede agrupar sus partes en
     * records anidados y en listas de ellos. Se permite solo si cada parte, a su
     * vez, cumple la misma regla: agrupar no puede ser la puerta para volver a
     * mandar una entidad.
     */
    private void revisarComponentes(Class<?> record) {
        for (RecordComponent componente : record.getRecordComponents()) {
            Type tipo = componente.getGenericType();
            if (tipo instanceof ParameterizedType lista && lista.getRawType() == List.class
                    && lista.getActualTypeArguments()[0] instanceof Class<?> elemento) {
                revisarTipo(record, componente, elemento);
            } else if (tipo instanceof Class<?> clase) {
                revisarTipo(record, componente, clase);
            } else {
                fail("%s.%s es de tipo %s, que no se puede revisar.",
                        record.getSimpleName(), componente.getName(), tipo.getTypeName());
            }
        }
    }

    private void revisarTipo(Class<?> record, RecordComponent componente, Class<?> tipo) {
        if (tipo.isEnum() || TIPOS_PERMITIDOS.contains(tipo)) {
            return;
        }
        if (tipo.isRecord() && !tipo.isAnnotationPresent(Entity.class)) {
            revisarComponentes(tipo);
            return;
        }
        fail("%s.%s es de tipo %s. Una respuesta solo lleva escalares, texto y fechas: "
                        + "aplana la relación a su id y, si hace falta para leerla, su nombre.",
                record.getSimpleName(), componente.getName(), tipo.getSimpleName());
    }

    @Test
    void ninguna_entidad_jpa_es_tipo_de_retorno_de_un_controlador() throws Exception {
        Set<String> entidades = buscar(new org.springframework.core.type.filter.AnnotationTypeFilter(Entity.class))
                .stream()
                .map(Class::getName)
                .collect(java.util.stream.Collectors.toUnmodifiableSet());

        assertThat(entidades).hasSizeGreaterThan(10);

        for (Class<?> controlador : buscar(new RegexPatternTypeFilter(Pattern.compile(".*Controller$")))) {
            for (var metodo : controlador.getDeclaredMethods()) {
                if (!java.lang.reflect.Modifier.isPublic(metodo.getModifiers())) {
                    continue;
                }
                var retorno = metodo.getGenericReturnType().getTypeName();
                for (String entidad : entidades) {
                    // Cubre `Obra`, `List<Obra>` y `ResponseEntity<Obra>` por igual.
                    if (retorno.equals(entidad) || retorno.contains("<" + entidad + ">")) {
                        fail("%s.%s devuelve la entidad %s. Devuelve su record de respuesta.",
                                controlador.getSimpleName(),
                                metodo.getName(),
                                entidad.substring(entidad.lastIndexOf('.') + 1));
                    }
                }
            }
        }
    }

    @Test
    void la_credencial_del_trabajador_solo_viaja_al_emitirla() {
        // El QR es un portador: quien lo tiene se presenta en bodega como ese
        // trabajador. Solo el record de emisión puede llevarlo.
        var componentes = cl.duocuc.checkinobra.obra.TrabajadorResponse.class.getRecordComponents();
        assertThat(componentes).extracting(RecordComponent::getName).doesNotContain("credencialQr");

        var conCredencial = cl.duocuc.checkinobra.obra.TrabajadorCredencialResponse.class.getRecordComponents();
        assertThat(conCredencial).extracting(RecordComponent::getName).contains("credencialQr");
    }

    @Test
    void ningun_record_de_respuesta_expone_el_pin() {
        for (Class<?> respuesta : buscar(new RegexPatternTypeFilter(Pattern.compile(".*Response$")))) {
            assertThat(respuesta.getRecordComponents())
                    .as("%s", respuesta.getSimpleName())
                    .extracting(RecordComponent::getName)
                    .noneMatch(nombre -> nombre.toLowerCase().contains("pin"));
        }
    }
}
