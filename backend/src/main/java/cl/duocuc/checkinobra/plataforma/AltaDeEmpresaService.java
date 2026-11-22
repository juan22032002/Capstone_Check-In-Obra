package cl.duocuc.checkinobra.plataforma;

import cl.duocuc.checkinobra.config.AlmacenDeSecretos;
import cl.duocuc.checkinobra.config.CatalogoDeEmpresas;
import cl.duocuc.checkinobra.config.CatalogoDeEmpresas.EmpresaRegistrada;
import cl.duocuc.checkinobra.config.MigradorDeBases;
import cl.duocuc.checkinobra.config.PrimeraEmpresaService;
import cl.duocuc.checkinobra.config.ResolutorDeBases;
import cl.duocuc.checkinobra.config.Rut;
import cl.duocuc.checkinobra.config.TenantContext;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.stereotype.Service;

import java.security.SecureRandom;
import java.util.ArrayDeque;
import java.util.Deque;

/**
 * El alta de una constructora de punta a punta (MT7, #110): una operación que deja funcionando su
 * base, su usuario de PostgreSQL, su esquema y su primer ADMIN, sin reiniciar la API y sin escribir
 * migraciones a mano.
 *
 * <p>Cada paso registra cómo se deshace. Si uno falla, los anteriores se revierten en orden inverso
 * y la empresa no queda a medias: ni en el catálogo, ni como base, ni como usuario de PostgreSQL, ni
 * con su correo reservado.
 *
 * <p>No es transaccional (hay un catálogo, un servidor de bases y archivos): por eso las
 * compensaciones son explícitas. Una compensación que falla se deja en el log y no tapa el error original.
 */
@Service
public class AltaDeEmpresaService {

    private static final Logger log = LoggerFactory.getLogger(AltaDeEmpresaService.class);
    private static final String ALFABETO = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789";
    private static final int LARGO_CLAVE_BASE = 32;
    private static final int LARGO_CLAVE_TEMPORAL = 16;

    /** Lo que el operador recibe. {@code claveTemporal} solo viene si la generó el sistema. */
    public record Resultado(long empresaId, String rut, String nombre, String adminEmail, String claveTemporal) {
    }

    private final CatalogoDeEmpresas catalogo;
    private final AprovisionadorDeBases aprovisionador;
    private final AlmacenDeSecretos secretos;
    private final MigradorDeBases migrador;
    private final ResolutorDeBases resolutor;
    private final PrimeraEmpresaService primeraEmpresa;
    private final SecureRandom azar = new SecureRandom();

    public AltaDeEmpresaService(
            CatalogoDeEmpresas catalogo, AprovisionadorDeBases aprovisionador, AlmacenDeSecretos secretos,
            MigradorDeBases migrador, ResolutorDeBases resolutor, PrimeraEmpresaService primeraEmpresa) {
        this.catalogo = catalogo;
        this.aprovisionador = aprovisionador;
        this.secretos = secretos;
        this.migrador = migrador;
        this.resolutor = resolutor;
        this.primeraEmpresa = primeraEmpresa;
    }

    /**
     * @param adminClave la clave inicial del ADMIN, o nula para que el sistema genere una
     * @throws IllegalArgumentException RUT o correo inválidos, o clave que no cumple la política (→ 400)
     * @throws IllegalStateException el RUT o el correo ya están en uso (→ 409)
     */
    public Resultado dar(String rut, String nombre, String adminEmail, String adminClave, boolean copiarCatalogoBase) {
        if (!aprovisionador.disponible()) {
            throw new IllegalStateException(
                    "El alta de empresas no está habilitada: falta la credencial del aprovisionador de bases");
        }
        String rutNormalizado = Rut.normalizar(rut);
        String correo = adminEmail == null ? "" : adminEmail.trim();
        if (correo.isEmpty()) {
            throw new IllegalArgumentException("El correo del administrador es obligatorio");
        }
        if (catalogo.buscarPorRut(rutNormalizado).isPresent()) {
            throw new IllegalStateException("Ya existe una empresa con ese RUT");
        }
        boolean generada = adminClave == null || adminClave.isBlank();
        String claveAdmin = generada ? aleatoria(LARGO_CLAVE_TEMPORAL) : adminClave;

        String digitos = rutNormalizado.replaceAll("[^0-9K]", "").toLowerCase();
        String base = "checkinobra_e" + digitos;
        String usuarioBase = "app_e" + digitos;
        Deque<Runnable> deshacer = new ArrayDeque<>();
        Long idRegistrado = null;
        try {
            long id = registrar(rutNormalizado, nombre, base, usuarioBase);
            idRegistrado = id;

            if (!catalogo.reservarCorreo(correo, id)) {
                throw new IllegalStateException("Ya existe un usuario con ese correo");
            }

            secretos.guardar(usuarioBase, aleatoria(LARGO_CLAVE_BASE));
            deshacer.push(() -> secretos.borrar(usuarioBase));
            // El secreto se guarda antes de crear el usuario y se lee de vuelta: es lo que va a usar el
            // pool, así que se prueba la misma ruta.
            deshacer.push(() -> aprovisionador.eliminar(base, usuarioBase));
            aprovisionador.crear(base, usuarioBase, secretos.leer(usuarioBase));

            EmpresaRegistrada registrada = catalogo.buscarPorRut(rutNormalizado).orElseThrow();
            var migracion = migrador.migrar(registrada);
            if (!migracion.ok()) {
                throw new AltaDeEmpresaException("No se pudo migrar la base de la empresa: " + migracion.error());
            }
            aprovisionador.sembrar(base, id, nombre, rutNormalizado, copiarCatalogoBase);

            // El pool se agrega en caliente: no hay que reiniciar la API.
            resolutor.refrescar();
            if (!resolutor.conoce(id)) {
                throw new AltaDeEmpresaException("No se pudo abrir la base de la empresa");
            }
            boolean creado = TenantContext.ejecutarEn(id,
                    () -> primeraEmpresa.crearAdminSiNoHay(rutNormalizado, correo, claveAdmin));
            if (!creado) {
                throw new AltaDeEmpresaException("No se pudo crear el administrador de la empresa");
            }
            log.info("Empresa {} dada de alta (base {}).", id, base);
            return new Resultado(id, rutNormalizado, nombre, correo, generada ? claveAdmin : null);
        } catch (RuntimeException e) {
            deshacer(deshacer, base, idRegistrado);
            throw e;
        }
    }

    private long registrar(String rut, String nombre, String base, String usuarioBase) {
        try {
            return catalogo.registrar(null, rut, nombre, base, usuarioBase, AlmacenDeSecretos.PREFIJO + usuarioBase);
        } catch (DuplicateKeyException e) {
            // Dos altas del mismo RUT a la vez: la segunda pierde.
            throw new IllegalStateException("Ya existe una empresa con ese RUT");
        }
    }

    /** En orden inverso al de creación; cada compensación falla sola sin impedir las demás. */
    private void deshacer(Deque<Runnable> pasos, String base, Long idRegistrado) {
        log.warn("El alta de la base {} falló: se deshace lo creado.", base);
        // Primero se saca la empresa del catálogo y se cierra su pool: con conexiones abiertas la base
        // no se puede borrar. Después, en orden inverso, el resto.
        try {
            if (idRegistrado != null) {
                catalogo.eliminarEmpresa(idRegistrado);
            }
            resolutor.refrescar();
        } catch (RuntimeException e) {
            log.error("No se pudo sacar la empresa del catálogo al deshacer el alta de {}: {}", base, e.getMessage());
        }
        while (!pasos.isEmpty()) {
            try {
                pasos.pop().run();
            } catch (RuntimeException e) {
                log.error("No se pudo deshacer un paso del alta de {}: {}", base, e.getMessage());
            }
        }
    }

    private String aleatoria(int largo) {
        StringBuilder sb = new StringBuilder(largo);
        for (int i = 0; i < largo; i++) {
            sb.append(ALFABETO.charAt(azar.nextInt(ALFABETO.length())));
        }
        return sb.toString();
    }
}
