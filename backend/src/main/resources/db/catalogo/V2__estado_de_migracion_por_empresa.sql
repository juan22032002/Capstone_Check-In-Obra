-- MT3 (#106): el resultado de migrar la base de cada empresa queda en el catálogo.
--
-- Una base cuya migración falla no se abre (su empresa no tiene pool y sus tokens
-- no valen) y su error queda aquí, a la vista, sin impedir que arranquen las demás.
ALTER TABLE empresas
    ADD COLUMN migracion_estado VARCHAR(20) NOT NULL DEFAULT 'PENDIENTE'
        CHECK (migracion_estado IN ('PENDIENTE', 'OK', 'ERROR')),
    ADD COLUMN migracion_error  TEXT,
    ADD COLUMN migrada_en       TIMESTAMPTZ;
