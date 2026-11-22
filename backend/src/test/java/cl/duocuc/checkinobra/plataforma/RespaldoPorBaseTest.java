package cl.duocuc.checkinobra.plataforma;

import cl.duocuc.checkinobra.config.AlmacenDeSecretos;
import cl.duocuc.checkinobra.config.CatalogoDeEmpresas;
import cl.duocuc.checkinobra.config.ResolutorDeBases;
import cl.duocuc.checkinobra.config.UrlsDeBases;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.test.context.SpringBootTest;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.attribute.PosixFilePermission;
import java.sql.DriverManager;
import java.sql.SQLException;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ThreadLocalRandom;
import java.util.concurrent.TimeUnit;
import java.util.stream.Stream;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.junit.jupiter.api.Assumptions.assumeTrue;

/**
 * MT8 (#111): el respaldo por base con {@code pg_dump} y su restauración, probados con los scripts
 * de verdad: se respalda la base de una empresa dada de alta, se restaura en otra base y se
 * comprueba que tiene lo mismo y los mismos permisos.
 *
 * <p>Necesita las herramientas de PostgreSQL: en el PATH, o dentro de un contenedor con
 * {@code CHECKINOBRA_PG_PREFIX} (por ejemplo {@code "docker exec -i mi-postgres"}). Si no están, la
 * prueba se omite, salvo con {@code CHECKINOBRA_EXIGIR_RESPALDO=true} (la CI), donde falla.
 */
@SpringBootTest(
        webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT,
        properties = {
                "checkinobra.pruebas.conexion-compartida=false",
                "spring.jpa.hibernate.ddl-auto=none",
                "spring.jpa.properties.hibernate.boot.allow_jdbc_metadata_access=false"})
class RespaldoPorBaseTest {

    private static final Path SCRIPTS = Path.of("..", "scripts").toAbsolutePath().normalize();

    @Autowired private AltaDeEmpresaService alta;
    @Autowired private AprovisionadorDeBases aprovisionador;
    @Autowired private AlmacenDeSecretos secretos;
    @Autowired private CatalogoDeEmpresas catalogo;
    @Autowired private ResolutorDeBases resolutor;

    @Value("${spring.datasource.url}") private String urlServidor;
    @Value("${spring.flyway.password}") private String claveMigrador;
    @Value("${checkinobra.plataforma.aprovisionador.password}") private String claveAprovisionador;

    private final List<String> basesParaBorrar = new ArrayList<>();
    private Path respaldos;
    private String rut;
    private String base;
    private String usuario;

    @BeforeEach
    void empresaConDatos() throws IOException {
        assumeTrue(herramientasDisponibles(), "No hay pg_dump/psql (ver CHECKINOBRA_PG_PREFIX)");
        respaldos = Files.createTempDirectory("respaldos-");
        String cuerpo = String.valueOf(10_000_000 + ThreadLocalRandom.current().nextInt(80_000_000));
        rut = cuerpo.substring(0, 2) + "." + cuerpo.substring(2, 5) + "." + cuerpo.substring(5) + "-" + dv(cuerpo);
        var r = alta.dar(rut, "Constructora respaldada", "admin-" + cuerpo + "@constructora.cl", null, true);
        assertThat(r.empresaId()).isPositive();
        String digitos = rut.replaceAll("[^0-9K]", "").toLowerCase();
        base = "checkinobra_e" + digitos;
        usuario = "app_e" + digitos;
    }

    @AfterEach
    void limpiar() throws IOException {
        if (respaldos == null) {
            return;
        }
        basesParaBorrar.forEach(aprovisionador::eliminarBase);
        catalogo.buscarPorRut(rut).ifPresent(e -> catalogo.eliminarEmpresa(e.id()));
        resolutor.refrescar();
        aprovisionador.eliminar(base, usuario);
        secretos.borrar(usuario);
        try (Stream<Path> s = Files.walk(respaldos)) {
            s.sorted(java.util.Comparator.reverseOrder()).forEach(p -> p.toFile().delete());
        }
    }

    @Test
    void elRespaldoSeRestauraEnOtraBaseConLoMismoYLosMismosPermisos() throws Exception {
        String dump = ejecutar("respaldar-empresa.sh", base, respaldos.toString()).salida.strip();
        Path archivo = Path.of(dump);
        assertThat(Files.size(archivo)).isPositive();
        assertThat(Files.getPosixFilePermissions(archivo))
                .containsExactlyInAnyOrder(PosixFilePermission.OWNER_READ, PosixFilePermission.OWNER_WRITE);

        String destino = base + "_r";
        basesParaBorrar.add(destino);
        Resultado restauracion = ejecutar("restaurar-empresa.sh", archivo.toString(), destino, usuario);
        assertThat(restauracion.codigo).as(restauracion.salida).isZero();

        String clave = secretos.leer(usuario);
        String url = new UrlsDeBases(urlServidor).de(destino);
        try (var c = DriverManager.getConnection(url, usuario, clave)) {
            // Lo mismo que la original: la empresa, el catálogo base copiado y el historial de migraciones.
            assertThat(unNumero(c, "SELECT count(*) FROM empresas")).isEqualTo(1);
            assertThat(unNumero(c, "SELECT count(*) FROM materiales"))
                    .isEqualTo(AprovisionadorDeBases.leerCatalogoBase().size());
            assertThat(unNumero(c, "SELECT count(*) FROM flyway_schema_history"))
                    .isEqualTo(contarEnOriginal("SELECT count(*) FROM flyway_schema_history"));
            // Los permisos son los de una empresa dada de alta: DML sí, esquema no.
            c.createStatement().execute("UPDATE materiales SET stock_minimo = stock_minimo");
            assertThatThrownBy(() -> c.createStatement().execute("CREATE TABLE intruso (id int)"))
                    .isInstanceOf(SQLException.class);
        }
        // Y sigue siendo de su dueña: no se conecta nadie más que ella y el migrador.
        assertThatThrownBy(() -> DriverManager.getConnection(url, "checkinobra_app", "app-pass").close())
                .isInstanceOf(SQLException.class);
    }

    @Test
    void noSobrescribeUnaBaseQueYaExiste() throws Exception {
        String dump = ejecutar("respaldar-empresa.sh", base, respaldos.toString()).salida.strip();

        Resultado r = ejecutar("restaurar-empresa.sh", dump, base, usuario);

        assertThat(r.codigo).isEqualTo(3);
        assertThat(r.salida).contains("no se sobrescribe");
        // La original sigue intacta.
        assertThat(contarEnOriginal("SELECT count(*) FROM materiales"))
                .isEqualTo(AprovisionadorDeBases.leerCatalogoBase().size());
    }

    @Test
    void unRespaldoCorruptoNoDejaUnaBaseAMedias() throws Exception {
        Path basura = respaldos.resolve("basura.dump");
        Files.write(basura, "esto no es un respaldo de pg_dump".getBytes(StandardCharsets.UTF_8));
        String destino = base + "_x";
        basesParaBorrar.add(destino);

        Resultado r = ejecutar("restaurar-empresa.sh", basura.toString(), destino, usuario);

        assertThat(r.codigo).isNotZero();
        assertThat(aprovisionador.existeBase(destino)).isFalse();
    }

    @Test
    void respaldarUnaBaseQueNoExisteFallaSinDejarArchivos() throws Exception {
        Resultado r = ejecutar("respaldar-empresa.sh", "checkinobra_no_existe", respaldos.toString());

        assertThat(r.codigo).isNotZero();
        try (Stream<Path> s = Files.list(respaldos)) {
            assertThat(s.toList()).isEmpty();
        }
    }

    /**
     * pg_dump 17 sobre un servidor 16 escribe un volcado con parámetros que el 16 no conoce y la
     * restauración falla a mitad (lo que pasó en la CI). Los scripts lo detectan antes de tocar nada.
     */
    @Test
    void siElClienteNoEsDeLaVersionDelServidorLosScriptsSeNieganYNoTocanNada() throws Exception {
        Path falso = respaldos.resolve("prefijo-falso.sh");
        Files.writeString(falso, """
                #!/usr/bin/env bash
                # Se hace pasar por un cliente de la versión 99; todo lo demás va al prefijo real.
                case " $* " in
                  *" pg_dump --version"*|*" pg_restore --version"*) echo "pg_dump (PostgreSQL) 99.0"; exit 0;;
                esac
                exec ${REAL_PREFIX:-} "$@"
                """);
        falso.toFile().setExecutable(true);
        String real = System.getenv("CHECKINOBRA_PG_PREFIX");
        Map<String, String> distinto = Map.of("PG_PREFIX", falso.toString(), "REAL_PREFIX", real == null ? "" : real);

        Resultado respaldo = ejecutarCon(distinto, "respaldar-empresa.sh", base, respaldos.toString());
        Path dump = Path.of(ejecutar("respaldar-empresa.sh", base, respaldos.toString()).salida.strip());
        Resultado restauracion = ejecutarCon(distinto, "restaurar-empresa.sh", dump.toString(), base + "_v", usuario);

        assertThat(respaldo.codigo).as(respaldo.salida).isEqualTo(4);
        assertThat(respaldo.salida).contains("Versiones distintas").contains("99");
        assertThat(restauracion.codigo).as(restauracion.salida).isEqualTo(4);
        assertThat(aprovisionador.existeBase(base + "_v")).isFalse();
        try (Stream<Path> s = Files.list(respaldos)) {
            // Solo el prefijo falso y el respaldo bueno: el intento con versión distinta no dejó nada.
            assertThat(s.map(p -> p.getFileName().toString()).filter(n -> n.endsWith(".dump") || n.endsWith(".parcial")))
                    .hasSize(1);
        }
    }

    @Test
    void losScriptsRechazanNombresQueNoSonDeBase() throws Exception {
        assertThat(ejecutar("respaldar-empresa.sh", "x; DROP DATABASE y", respaldos.toString()).codigo).isEqualTo(2);
        assertThat(ejecutar("restaurar-empresa.sh", "no-importa", "Base-Mala", usuario).codigo).isEqualTo(2);
    }

    // ---- soporte ------------------------------------------------------------------------------

    private record Resultado(int codigo, String salida) {
    }

    private Resultado ejecutar(String script, String... argumentos) throws Exception {
        return ejecutarCon(Map.of(), script, argumentos);
    }

    private Resultado ejecutarCon(Map<String, String> extra, String script, String... argumentos) throws Exception {
        List<String> comando = new ArrayList<>(List.of("bash", SCRIPTS.resolve(script).toString()));
        comando.addAll(Arrays.asList(argumentos));
        ProcessBuilder pb = new ProcessBuilder(comando).redirectErrorStream(true);
        Map<String, String> env = pb.environment();
        env.put("CHECKINOBRA_MIGRADOR_PASSWORD", claveMigrador);
        env.put("CHECKINOBRA_APROVISIONADOR_PASSWORD", claveAprovisionador);
        String prefijo = System.getenv("CHECKINOBRA_PG_PREFIX");
        if (prefijo != null && !prefijo.isBlank()) {
            // Las herramientas corren dentro del contenedor: el servidor está en su localhost:5432.
            env.put("PG_PREFIX", prefijo);
            env.put("PGHOST", "localhost");
            env.put("PGPORT", "5432");
        } else {
            env.put("PGHOST", hostDe(urlServidor));
            env.put("PGPORT", puertoDe(urlServidor));
        }
        env.putAll(extra);
        Process p = pb.start();
        String salida = new String(p.getInputStream().readAllBytes(), StandardCharsets.UTF_8);
        assertThat(p.waitFor(120, TimeUnit.SECONDS)).as("el script terminó a tiempo").isTrue();
        return new Resultado(p.exitValue(), salida);
    }

    private boolean herramientasDisponibles() {
        String prefijo = System.getenv("CHECKINOBRA_PG_PREFIX");
        List<String> comando = new ArrayList<>();
        if (prefijo != null && !prefijo.isBlank()) {
            comando.addAll(Arrays.asList(prefijo.trim().split("\\s+")));
        }
        comando.addAll(List.of("pg_dump", "--version"));
        boolean hay;
        try {
            Process p = new ProcessBuilder(comando).redirectErrorStream(true).start();
            hay = p.waitFor(30, TimeUnit.SECONDS) && p.exitValue() == 0;
        } catch (IOException | InterruptedException e) {
            hay = false;
        }
        if (!hay && "true".equals(System.getenv("CHECKINOBRA_EXIGIR_RESPALDO"))) {
            throw new AssertionError("Faltan las herramientas de PostgreSQL y CHECKINOBRA_EXIGIR_RESPALDO=true");
        }
        return hay;
    }

    private long contarEnOriginal(String sql) throws SQLException {
        String url = new UrlsDeBases(urlServidor).de(base);
        try (var c = DriverManager.getConnection(url, usuario, secretos.leer(usuario))) {
            return unNumero(c, sql);
        }
    }

    private static long unNumero(java.sql.Connection c, String sql) throws SQLException {
        try (var rs = c.createStatement().executeQuery(sql)) {
            rs.next();
            return rs.getLong(1);
        }
    }

    private static String hostDe(String url) {
        return url.replaceAll("^jdbc:postgresql://([^:/]+).*$", "$1");
    }

    private static String puertoDe(String url) {
        return url.replaceAll("^jdbc:postgresql://[^:/]+:(\\d+).*$", "$1");
    }

    private static char dv(String cuerpo) {
        int suma = 0;
        int factor = 2;
        for (int i = cuerpo.length() - 1; i >= 0; i--) {
            suma += (cuerpo.charAt(i) - '0') * factor;
            factor = factor == 7 ? 2 : factor + 1;
        }
        int resto = 11 - suma % 11;
        return resto == 11 ? '0' : resto == 10 ? 'K' : (char) ('0' + resto);
    }
}
