package cl.duocuc.checkinobra.config;

import jakarta.persistence.Entity;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.config.BeanDefinition;
import org.springframework.context.annotation.ClassPathScanningCandidateComponentProvider;
import org.springframework.core.type.filter.AnnotationTypeFilter;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.context.SecurityContextHolder;

import java.util.List;
import java.util.NoSuchElementException;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.assertj.core.api.Assertions.fail;

/**
 * El aislamiento entre constructoras depende de que <b>toda</b> entidad sepa
 * decir de qué empresa es. Una sola que no implemente {@link PerteneceAEmpresa}
 * es un agujero que el compilador no ve, porque el guardián simplemente no se
 * puede aplicar sobre ella.
 */
class AislamientoEntreEmpresasTest {

    @AfterEach
    void limpiarContexto() {
        SecurityContextHolder.clearContext();
    }

    private void autenticarEnEmpresa(long empresaId) {
        var usuario = new UsuarioAutenticado(1L, "alguien@empresa.cl", RolUsuario.BODEGUERO, empresaId);
        SecurityContextHolder.getContext()
                .setAuthentication(new UsernamePasswordAuthenticationToken(usuario, null, List.of()));
    }

    @Test
    void toda_entidad_jpa_sabe_a_que_empresa_pertenece() {
        var scanner = new ClassPathScanningCandidateComponentProvider(false);
        scanner.addIncludeFilter(new AnnotationTypeFilter(Entity.class));

        var entidades = scanner.findCandidateComponents("cl.duocuc.checkinobra").stream()
                .map(BeanDefinition::getBeanClassName)
                .toList();

        assertThat(entidades).hasSizeGreaterThan(10);

        for (String nombre : entidades) {
            try {
                Class<?> entidad = Class.forName(nombre);
                if (!PerteneceAEmpresa.class.isAssignableFrom(entidad)) {
                    fail("%s no implementa PerteneceAEmpresa: el guardián de empresa no puede protegerla.",
                            entidad.getSimpleName());
                }
            } catch (ClassNotFoundException e) {
                throw new IllegalStateException(e);
            }
        }
    }

    @Test
    void un_recurso_ajeno_es_indistinguible_de_uno_que_no_existe() {
        autenticarEnEmpresa(1L);
        PerteneceAEmpresa ajeno = () -> 2L;

        // Esta es la propiedad que hace real el aislamiento. Si el recurso ajeno
        // produjera un error propio, la respuesta diría "existe, pero no es
        // tuyo" — y con eso se recorren los ids del sistema para saber cuántas
        // obras tiene la competencia. Filtrado, produce el mismo Optional vacío
        // y por lo tanto el mismo 404 que un id inventado.
        Optional<PerteneceAEmpresa> existePeroEsAjeno =
                Optional.of(ajeno).filter(AccesoEmpresa::esPropio);
        Optional<PerteneceAEmpresa> noExiste = Optional.empty();

        assertThat(existePeroEsAjeno).isEqualTo(noExiste);

        assertThatThrownBy(() -> existePeroEsAjeno.orElseThrow(
                        () -> new NoSuchElementException("Obra no encontrada: 7")))
                .isInstanceOf(NoSuchElementException.class)
                .hasMessage("Obra no encontrada: 7");
    }

    @Test
    void un_recurso_propio_pasa_el_filtro() {
        autenticarEnEmpresa(7L);
        PerteneceAEmpresa propio = () -> 7L;

        assertThat(AccesoEmpresa.esPropio(propio)).isTrue();
        assertThat(Optional.of(propio).filter(AccesoEmpresa::esPropio)).contains(propio);
    }

    @Test
    void sin_empresa_en_el_recurso_tampoco_pasa() {
        autenticarEnEmpresa(1L);

        // Un null no es "coincide con cualquiera": es un dato sin dueño, y ante
        // la duda no se entrega.
        assertThat(AccesoEmpresa.esPropio(() -> null)).isFalse();
    }

    @Test
    void sin_nadie_autenticado_no_se_entrega_nada() {
        SecurityContextHolder.clearContext();

        assertThatThrownBy(() -> AccesoEmpresa.esPropio(() -> 1L))
                .isInstanceOf(AccesoDenegadoException.class);
    }

    @Test
    void afirmar_pertenecer_a_otra_empresa_si_es_403() {
        autenticarEnEmpresa(1L);

        // Distinto del caso anterior: acá no se pide un recurso que pueda existir
        // o no, se afirma una pertenencia falsa. No hay nada que enumerar.
        assertThatThrownBy(() -> AccesoEmpresa.exigirEmpresa(2L))
                .isInstanceOf(AccesoDenegadoException.class)
                .hasMessageContaining("no pertenece a tu empresa");
    }

    @Test
    void soloPropios_filtra_en_vez_de_fallar() {
        autenticarEnEmpresa(1L);
        PerteneceAEmpresa mio = () -> 1L;
        PerteneceAEmpresa ajeno = () -> 2L;

        assertThat(AccesoEmpresa.soloPropios(List.of(mio, ajeno))).containsExactly(mio);
    }

    @Test
    void ningun_controlador_recibe_un_empresaId_del_cliente() throws Exception {
        var scanner = new ClassPathScanningCandidateComponentProvider(false);
        scanner.addIncludeFilter(new org.springframework.core.type.filter.RegexPatternTypeFilter(
                java.util.regex.Pattern.compile(".*Controller$")));

        for (var definicion : scanner.findCandidateComponents("cl.duocuc.checkinobra")) {
            Class<?> controlador = Class.forName(definicion.getBeanClassName());

            for (var metodo : controlador.getDeclaredMethods()) {
                for (var parametro : metodo.getParameters()) {
                    if (parametro.isAnnotationPresent(
                            org.springframework.web.bind.annotation.RequestParam.class)) {
                        assertThat(parametro.getName())
                                .as("%s.%s recibe la empresa por parámetro; debe salir del token",
                                        controlador.getSimpleName(), metodo.getName())
                                .isNotEqualTo("empresaId");
                    }
                }
            }

            // Y tampoco por el cuerpo de la petición.
            for (Class<?> anidada : controlador.getDeclaredClasses()) {
                if (!anidada.isRecord() || !anidada.getSimpleName().endsWith("Request")) {
                    continue;
                }
                // La única excepción es el login por PIN: antes de autenticarse no hay token de
                // donde sacar la empresa, y los ids de usuario se repiten entre bases. Se
                // valida contra el catálogo y no abre otra base que la que ese usuario tiene.
                if (anidada.getSimpleName().equals("LoginPorPinRequest")) {
                    continue;
                }
                assertThat(anidada.getRecordComponents())
                        .as("%s", anidada.getSimpleName())
                        .extracting(java.lang.reflect.RecordComponent::getName)
                        .doesNotContain("empresaId");
            }
        }
    }
}
