-- SEG12 (#100, S-22): el SKU de un material y el código QR de una herramienta eran únicos en toda la
-- base. Con una base por empresa eso ya equivale a "por empresa", pero una base que reúna a más de
-- una (la de las pruebas, o una instalación que así se configure) dejaba que la primera constructora
-- en usar "VOL-10" se lo impidiera a las demás, y que el error de la segunda revelara que el código
-- existe en otra. Pasa a ser único dentro de la empresa, como ya lo es el código de barras (V4).
ALTER TABLE materiales DROP CONSTRAINT IF EXISTS materiales_sku_key;
ALTER TABLE materiales ADD CONSTRAINT uq_materiales_empresa_sku UNIQUE (empresa_id, sku);

ALTER TABLE herramientas DROP CONSTRAINT IF EXISTS herramientas_codigo_qr_key;
ALTER TABLE herramientas ADD CONSTRAINT uq_herramientas_empresa_codigo_qr UNIQUE (empresa_id, codigo_qr);
