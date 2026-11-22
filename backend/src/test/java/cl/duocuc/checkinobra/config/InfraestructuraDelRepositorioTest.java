package cl.duocuc.checkinobra.config;

import org.junit.jupiter.api.Test;

import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * SEG11 (#99): lo que la auditoría pidió en la configuración del repositorio, fijado para que
 * nadie lo deshaga sin darse cuenta: imágenes por digest y sin root, acciones por SHA, permisos
 * mínimos, Dependabot y análisis en la CI, y nada de correo que no se usa.
 */
class InfraestructuraDelRepositorioTest {

    private static final Path RAIZ = Path.of("..");

    private static String leer(String ruta) throws Exception {
        return Files.readString(RAIZ.resolve(ruta));
    }

    @Test
    void elDockerfileNoCorreComoRootYTieneHealthcheck() throws Exception {
        String dockerfile = leer("backend/Dockerfile");

        assertThat(dockerfile).contains("USER app").contains("HEALTHCHECK").contains("/actuator/health");
        // USER va después de crear el usuario y antes de arrancar.
        assertThat(dockerfile.indexOf("adduser")).isLessThan(dockerfile.indexOf("USER app"));
        assertThat(dockerfile.indexOf("USER app")).isLessThan(dockerfile.indexOf("ENTRYPOINT"));
    }

    @Test
    void todaImagenDelDockerfileYDelComposeVaFijadaPorDigest() throws Exception {
        for (String archivo : List.of("backend/Dockerfile", "docker-compose.yml")) {
            Matcher m = Pattern.compile("(?m)^\\s*(?:FROM|image:)\\s+(\\S+)").matcher(leer(archivo));
            int vistas = 0;
            while (m.find()) {
                vistas++;
                assertThat(m.group(1)).as("%s: %s", archivo, m.group(1)).matches(".+@sha256:[0-9a-f]{64}(\\s+AS\\s+\\w+)?");
            }
            assertThat(vistas).as(archivo).isPositive();
        }
    }

    @Test
    void todaAccionDeLosWorkflowsVaFijadaPorShaYConPermisosMinimos() throws Exception {
        try (var archivos = Files.list(RAIZ.resolve(".github/workflows"))) {
            List<Path> workflows = archivos.filter(p -> p.toString().endsWith(".yml")).toList();
            assertThat(workflows).hasSizeGreaterThanOrEqualTo(3);
            for (Path w : workflows) {
                String texto = Files.readString(w);
                Matcher usos = Pattern.compile("uses:\\s+(\\S+)").matcher(texto);
                while (usos.find()) {
                    assertThat(usos.group(1)).as("%s: %s", w.getFileName(), usos.group(1)).matches(".+@[0-9a-f]{40}");
                }
                // Permisos del GITHUB_TOKEN declarados, y de solo lectura por defecto.
                assertThat(texto).as(w.getFileName().toString()).containsPattern("(?m)^permissions:\\n  contents: read");
            }
        }
    }

    @Test
    void laCiTieneAnalisisDeCodigoYRevisionDeDependenciasYDependabotCubreCadaEcosistema() throws Exception {
        assertThat(leer(".github/workflows/codeql.yml")).contains("codeql-action/analyze");
        assertThat(leer(".github/workflows/dependencias.yml")).contains("dependency-review-action");
    }

    /** Sin GHAS (repo privado) estos dos jobs fallan en cada PR: corren solo con la variable GHAS=true. */
    @Test
    void codeqlYLaRevisionDeDependenciasSoloCorrenConLaVariableGhas() throws Exception {
        for (String workflow : List.of("codeql.yml", "dependencias.yml")) {
            assertThat(leer(".github/workflows/" + workflow)).as(workflow).contains("if: vars.GHAS == 'true'");
        }
    }

    @Test
    void dependabotCubreCadaEcosistema() throws Exception {

        String dependabot = leer(".github/dependabot.yml");
        for (String ecosistema : List.of("maven", "pub", "github-actions", "docker")) {
            assertThat(dependabot).contains("package-ecosystem: " + ecosistema);
        }
    }

    @Test
    void noQuedaNadaDeCorreoQueNoSeUsa() throws Exception {
        assertThat(leer("backend/pom.xml")).doesNotContain("starter-mail");
        assertThat(leer("backend/src/main/resources/application.properties"))
                .doesNotContain("spring.mail").doesNotContain("BREVO");
        assertThat(leer(".env.example")).doesNotContain("BREVO");
        assertThat(leer("backend/.env.example")).doesNotContain("BREVO");
    }

    @Test
    void elPerfilProdApagaSwagger() throws Exception {
        assertThat(leer("backend/src/main/resources/application-prod.properties"))
                .contains("springdoc.api-docs.enabled=false")
                .contains("springdoc.swagger-ui.enabled=false");
    }
}
