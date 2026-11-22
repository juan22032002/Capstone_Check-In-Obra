-- Pedido de varias herramientas de una vez. El trabajador marca las que
-- necesita y la app le muestra un QR; el bodeguero lo escanea en el mesón,
-- confirma que es la persona y entrega todo junto.
--
-- Cada herramienta sigue siendo una solicitud_herramienta con su propio
-- préstamo: el pedido solo las agrupa y lleva el código. Las solicitudes
-- anteriores a esta migración quedan sin pedido y siguen valiendo.
CREATE TABLE pedidos_herramientas (
    id                BIGSERIAL PRIMARY KEY,
    -- UUID aleatorio. Es lo que viaja en el QR, así que no puede adivinarse
    -- a partir del id ni de otro pedido.
    codigo_qr         VARCHAR(36)  NOT NULL UNIQUE,
    estado            VARCHAR(20)  NOT NULL,
    descripcion       VARCHAR(300) NOT NULL,
    fecha_solicitud   TIMESTAMP    NOT NULL,
    fecha_entrega     TIMESTAMP,
    trabajador_id     BIGINT NOT NULL REFERENCES trabajadores (id),
    entregado_por_id  BIGINT REFERENCES usuarios (id)
);

CREATE INDEX idx_pedido_herramientas_trabajador ON pedidos_herramientas (trabajador_id, estado);

ALTER TABLE solicitudes_herramienta ADD COLUMN pedido_id BIGINT REFERENCES pedidos_herramientas (id);

CREATE INDEX idx_solicitud_herramienta_pedido ON solicitudes_herramienta (pedido_id);
