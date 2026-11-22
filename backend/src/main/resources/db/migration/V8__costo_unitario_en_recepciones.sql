-- Costo real de compra en cada recepción.
--
-- `materiales.precio_unitario` es el precio de catálogo que fija el
-- administrador y el que usa el presupuesto; no dice cuánto se pagó de verdad.
-- El costo real llega con la factura, recepción por recepción, y puede cambiar
-- entre una compra y la siguiente. Por eso vive en el movimiento y no en el
-- material: el último costo y el promedio ponderado se derivan de acá, igual
-- que el stock.
--
-- Nulo en DESPACHO y CONSUMO (el material ya está pagado) y en las recepciones
-- anteriores a esta migración o registradas sin factura a mano.
--
-- NUMERIC y no DOUBLE PRECISION: es dinero, y el promedio ponderado suma
-- muchos de ellos.
ALTER TABLE kardex_movimientos ADD COLUMN costo_unitario NUMERIC(14, 2);

ALTER TABLE kardex_movimientos ADD CONSTRAINT ck_kardex_costo_solo_en_recepcion
    CHECK (costo_unitario IS NULL OR (tipo_movimiento = 'RECEPCION' AND costo_unitario > 0));

-- El último costo y el promedio de cada material se consultan juntos para todo
-- el catálogo: sin este índice, cada listado de materiales recorre el kardex
-- entero de la empresa.
CREATE INDEX idx_kardex_material_costo ON kardex_movimientos (material_id, fecha DESC)
    WHERE costo_unitario IS NOT NULL;
