package cl.duocuc.checkinobra.config;

public enum RolUsuario {
    BODEGUERO,
    JEFE_TERRENO,
    ADMIN,
    TRABAJADOR,
    /**
     * El operador de plataforma: administra empresas y no pertenece a ninguna. No es un rol de empresa:
     * vive en la tabla {@code operadores} del catálogo, su token no lleva {@code empresaId} y
     * {@code UsuarioService} no permite crear un usuario con este rol.
     */
    PLATAFORMA
}
