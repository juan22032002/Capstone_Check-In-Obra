package cl.duocuc.checkinobra.config;

import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Component;

/**
 * Registra en el catálogo a las empresas y usuarios que una prueba crea directo en la
 * base, para que el login por correo los encuentre en el índice.
 *
 * <p>Las empresas de prueba comparten una sola base, así que se registran con un nombre
 * de base ficticio y distinto cada una (el catálogo exige uno único por empresa); el
 * resolutor de pruebas no lo usa.
 */
@Component
@ConditionalOnProperty(name = "checkinobra.pruebas.conexion-compartida", havingValue = "true")
class CatalogoDePrueba {

    private final CatalogoDeEmpresas catalogo;
    private final org.springframework.jdbc.core.JdbcTemplate enElCatalogo;
    private final java.util.List<Long> registradas = new java.util.concurrent.CopyOnWriteArrayList<>();
    private final java.util.List<Long> operadores = new java.util.concurrent.CopyOnWriteArrayList<>();

    CatalogoDePrueba(
            CatalogoDeEmpresas catalogo,
            @org.springframework.beans.factory.annotation.Value("${checkinobra.catalogo.url}") String url,
            @org.springframework.beans.factory.annotation.Value("${checkinobra.catalogo.username}") String usuario,
            @org.springframework.beans.factory.annotation.Value("${checkinobra.catalogo.password}") String clave) {
        this.catalogo = catalogo;
        this.enElCatalogo = new org.springframework.jdbc.core.JdbcTemplate(
                new org.springframework.jdbc.datasource.DriverManagerDataSource(url, usuario, clave));
    }

    /**
     * Al cerrarse el contexto de pruebas, el catálogo compartido queda como estaba: las empresas
     * ficticias no deben acumularse entre corridas, porque el arranque intenta migrar cada una.
     */
    @jakarta.annotation.PreDestroy
    void limpiar() {
        for (Long id : operadores) {
            enElCatalogo.update("DELETE FROM operadores WHERE id = ?", id);
        }
        for (Long id : registradas) {
            enElCatalogo.update("DELETE FROM indice_login WHERE empresa_id = ?", id);
            enElCatalogo.update("DELETE FROM empresas WHERE id = ?", id);
        }
    }

    /** La empresa queda en el catálogo; hace falta antes de indexar sus correos. */
    void registrar(Empresa empresa) {
        registradas.add(empresa.getId());
        catalogo.registrar(empresa.getId(), empresa.getRut(), empresa.getNombre(),
                "prueba_" + empresa.getId() + "_" + System.nanoTime(), "usuario_de_prueba", "env:NO_SE_USA");
    }

    /** El correo del usuario queda en el índice de login. */
    void indexar(Usuario usuario) {
        catalogo.reservarCorreo(usuario.getEmail(), usuario.getEmpresa().getId());
    }

    /** Un operador de plataforma con esa clave; se borra al cerrarse el contexto. */
    long operador(String email, String clave) {
        long id = catalogo.crearOperador(email, "Operadora de pruebas",
                org.springframework.security.crypto.bcrypt.BCrypt.hashpw(
                        clave, org.springframework.security.crypto.bcrypt.BCrypt.gensalt())).orElseThrow();
        operadores.add(id);
        return id;
    }
}
