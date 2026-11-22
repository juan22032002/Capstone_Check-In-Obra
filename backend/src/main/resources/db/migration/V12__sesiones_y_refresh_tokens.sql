-- SEG10 (#98, S-11): sesiones que se pueden invalidar.
--
-- token_version: sube cuando cambia lo que un token da por hecho (se restablece la clave, se
-- cambia el rol). El token lleva la versión con que se emitió y JwtAuthFilter la compara con
-- esta: si no coincide, el token ya no vale, aunque no haya vencido.
ALTER TABLE usuarios ADD COLUMN token_version INTEGER NOT NULL DEFAULT 0;

-- Refresh tokens: permiten un token de acceso corto sin pedir la clave a cada rato. Se guarda
-- solo el hash (SHA-256) de un valor aleatorio, nunca el valor. Cada uso lo reemplaza por otro
-- (rotación); si se presenta uno ya usado, se asume robo y se revocan todos los del usuario.
CREATE TABLE refresh_tokens (
    id              BIGSERIAL    PRIMARY KEY,
    usuario_id      BIGINT       NOT NULL REFERENCES usuarios (id) ON DELETE CASCADE,
    hash            VARCHAR(64)  NOT NULL UNIQUE,
    token_version   INTEGER      NOT NULL,
    creado_en       TIMESTAMPTZ  NOT NULL DEFAULT now(),
    expira_en       TIMESTAMPTZ  NOT NULL,
    revocado_en     TIMESTAMPTZ,
    reemplazado_por BIGINT       REFERENCES refresh_tokens (id)
);

CREATE INDEX idx_refresh_tokens_usuario ON refresh_tokens (usuario_id);
