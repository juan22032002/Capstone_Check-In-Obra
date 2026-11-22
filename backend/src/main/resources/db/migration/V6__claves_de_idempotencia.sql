-- Claves de idempotencia de las peticiones que cambian estado.
--
-- La app manda `Idempotency-Key: <uuid>` en cada POST/PUT, la misma en los
-- reintentos de un mismo intento del usuario. Si la respuesta de un despacho no
-- alcanza a llegar (timeout del móvil) y el bodeguero toca de nuevo, sin esto el
-- kardex registraba dos despachos y el stock bajaba dos veces.
--
-- La clave es por usuario: dos personas no comparten claves, y un uuid ajeno no
-- sirve para leer la respuesta de otro.
--
-- `status` nulo = la primera petición todavía está en curso.
CREATE TABLE claves_idempotencia (
    id           BIGSERIAL    PRIMARY KEY,
    usuario_id   BIGINT       NOT NULL REFERENCES usuarios (id),
    clave        UUID         NOT NULL,
    -- SHA-256 de método, ruta, query y cuerpo: la misma clave con otra petición
    -- es un error del cliente, no una repetición.
    huella       VARCHAR(64)  NOT NULL,
    metodo       VARCHAR(10)  NOT NULL,
    ruta         VARCHAR(500) NOT NULL,
    status       INTEGER,
    content_type VARCHAR(200),
    cuerpo       BYTEA,
    creada_en    TIMESTAMP    NOT NULL DEFAULT now(),
    CONSTRAINT uq_claves_idempotencia_usuario_clave UNIQUE (usuario_id, clave)
);

-- La purga periódica borra por antigüedad.
CREATE INDEX idx_claves_idempotencia_creada_en ON claves_idempotencia (creada_en);
