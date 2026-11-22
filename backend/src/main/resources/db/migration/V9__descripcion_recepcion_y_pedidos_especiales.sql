-- Tres cosas del flujo del trabajador.
--
-- 1. "Para qué" en cada solicitud. Sin eso el bodeguero despacha a ciegas: 36
--    planchas pueden ser para un tabique o un error de dedo, y no hay cómo
--    preguntarlo después. Nulo solo en las solicitudes anteriores a esta
--    migración; la API lo exige al crear.
ALTER TABLE solicitudes_material    ADD COLUMN descripcion VARCHAR(300);
ALTER TABLE solicitudes_herramienta ADD COLUMN descripcion VARCHAR(300);

-- 2. Cuándo el trabajador confirmó que recibió lo aprobado. APROBADA dice que
--    bodega lo entregó; ENTREGADA con esta fecha dice que él lo reconoce.
ALTER TABLE solicitudes_material    ADD COLUMN fecha_recepcion TIMESTAMP;
ALTER TABLE solicitudes_herramienta ADD COLUMN fecha_recepcion TIMESTAMP;

-- 3. Pedidos especiales: lo que no está en el catálogo, o está pero no hay en
--    bodega, y hay que conseguir. No toca el kardex: lo que se compra entra por
--    una recepción normal y sale por un despacho normal; el pedido solo sigue
--    el estado de la gestión.
CREATE TABLE pedidos_especiales (
    id                   BIGSERIAL PRIMARY KEY,
    tipo                 VARCHAR(20)  NOT NULL,
    nombre               VARCHAR(120) NOT NULL,
    cantidad             DOUBLE PRECISION NOT NULL CHECK (cantidad > 0),
    unidad               VARCHAR(20),
    descripcion          VARCHAR(300) NOT NULL,
    estado               VARCHAR(20)  NOT NULL,
    fecha_solicitud      TIMESTAMP    NOT NULL,
    fecha_actualizacion  TIMESTAMP    NOT NULL,
    nota_bodega          VARCHAR(300),
    motivo_rechazo       VARCHAR(300),
    fecha_entrega        TIMESTAMP,
    fecha_recepcion      TIMESTAMP,
    obra_id              BIGINT NOT NULL REFERENCES obras (id),
    trabajador_id        BIGINT NOT NULL REFERENCES trabajadores (id),
    material_id          BIGINT REFERENCES materiales (id),
    herramienta_id       BIGINT REFERENCES herramientas (id),
    gestionado_por_id    BIGINT REFERENCES usuarios (id),
    -- El ítem de catálogo, si lo hay, es uno solo y del tipo que se pidió.
    CONSTRAINT ck_pedido_item_segun_tipo CHECK (
        (tipo = 'MATERIAL'    AND herramienta_id IS NULL) OR
        (tipo = 'HERRAMIENTA' AND material_id    IS NULL))
);

CREATE INDEX idx_pedido_especial_obra_estado ON pedidos_especiales (obra_id, estado);
CREATE INDEX idx_pedido_especial_trabajador ON pedidos_especiales (trabajador_id);
