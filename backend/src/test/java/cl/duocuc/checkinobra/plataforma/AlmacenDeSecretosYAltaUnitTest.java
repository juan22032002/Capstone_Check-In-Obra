package cl.duocuc.checkinobra.plataforma;

import cl.duocuc.checkinobra.config.AlmacenDeSecretos;
import cl.duocuc.checkinobra.config.CatalogoDeEmpresas;
import cl.duocuc.checkinobra.config.MigradorDeBases;
import cl.duocuc.checkinobra.config.PrimeraEmpresaService;
import cl.duocuc.checkinobra.config.ResolutorDeBases;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.attribute.PosixFilePermission;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

/** MT7 (#110): el almacén de secretos y lo que el alta rechaza antes de tocar nada. */
class AlmacenDeSecretosYAltaUnitTest {

    @TempDir Path directorio;

    @Test
    void guardaYLeeUnSecretoConUnaReferenciaFile() {
        var almacen = new AlmacenDeSecretos(directorio.toString());

        String ref = almacen.guardar("app_e123", "la-clave");

        assertThat(ref).isEqualTo("file:app_e123");
        assertThat(almacen.leer("app_e123")).isEqualTo("la-clave");
        assertThat(almacen.existe("app_e123")).isTrue();
        almacen.borrar("app_e123");
        assertThat(almacen.existe("app_e123")).isFalse();
    }

    @Test
    void elArchivoSoloLoLeeQuienCorreLaApi() throws Exception {
        var almacen = new AlmacenDeSecretos(directorio.toString());
        almacen.guardar("app_e123", "la-clave");

        assertThat(Files.getPosixFilePermissions(directorio.resolve("app_e123")))
                .containsExactlyInAnyOrder(PosixFilePermission.OWNER_READ, PosixFilePermission.OWNER_WRITE);
    }

    @Test
    void unaReferenciaNoPuedeSalirseDelDirectorio() {
        var almacen = new AlmacenDeSecretos(directorio.toString());

        for (String nombre : new String[] {"../x", "a/b", "..", "/etc/passwd", "", "A", null}) {
            assertThatThrownBy(() -> almacen.leer(nombre)).as(String.valueOf(nombre))
                    .isInstanceOf(IllegalArgumentException.class);
            assertThatThrownBy(() -> almacen.guardar(nombre, "x")).as(String.valueOf(nombre))
                    .isInstanceOf(IllegalArgumentException.class);
        }
    }

    @Test
    void leerUnSecretoQueNoExisteNoDiceLaRuta() {
        var almacen = new AlmacenDeSecretos(directorio.toString());

        assertThatThrownBy(() -> almacen.leer("no_existe"))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageNotContaining(directorio.toString());
    }

    @Test
    void losNombresDeBaseSeValidanAntesDeLlegarAlSql() {
        for (String malo : new String[] {"x; DROP DATABASE y", "Base", "a", "1abc", "ab-c", "", null, "a".repeat(60)}) {
            assertThat(AprovisionadorDeBases.nombreValido(malo)).as(String.valueOf(malo)).isFalse();
        }
        assertThat(AprovisionadorDeBases.nombreValido("checkinobra_e764123309")).isTrue();
    }

    @Test
    void sinLaCredencialDelAprovisionadorElAltaNoHaceNada() {
        var aprovisionador = mock(AprovisionadorDeBases.class);
        when(aprovisionador.disponible()).thenReturn(false);
        var catalogo = mock(CatalogoDeEmpresas.class);
        var servicio = new AltaDeEmpresaService(catalogo, aprovisionador, new AlmacenDeSecretos(directorio.toString()),
                mock(MigradorDeBases.class), mock(ResolutorDeBases.class), mock(PrimeraEmpresaService.class));

        assertThatThrownBy(() -> servicio.dar("76.412.330-9", "X", "a@b.cl", null, false))
                .isInstanceOf(IllegalStateException.class).hasMessageContaining("no está habilitada");
        verifyNoInteractions(catalogo);
    }

    @Test
    void elCatalogoBaseTraeMaterialesConCategoriaYPrecioValidos() {
        var filas = AprovisionadorDeBases.leerCatalogoBase();

        assertThat(filas).isNotEmpty();
        for (String[] f : filas) {
            assertThat(f).hasSize(5);
            assertThat(cl.duocuc.checkinobra.cubicacion.CategoriaMaterial.valueOf(f[2])).isNotNull();
            assertThat(Double.parseDouble(f[3])).isPositive();
        }
        assertThat(filas.stream().map(f -> f[0]).distinct()).hasSameSizeAs(filas);
    }
}
