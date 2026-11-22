-- El código de barras del material, para el escáner del bodeguero.
--
-- El SKU es interno: lo define la constructora y es lo que aparece en la guía
-- de despacho. El código de barras viene impreso de fábrica en el envase y es
-- lo que el bodeguero tiene físicamente delante cuando llega el camión. Son
-- dos identificadores distintos del mismo material y hacen falta los dos: sin
-- el de fábrica, escanear una plancha obliga igual a buscarla a mano en la
-- lista.
--
-- Nullable porque no todo material lo trae —los perfiles Metalcom se venden
-- por tira, sin etiqueta— y esos se siguen resolviendo por SKU.
ALTER TABLE materiales ADD COLUMN codigo_barra VARCHAR(50);

-- Único **por empresa**, no en toda la base.
--
-- Acá está la diferencia con el SKU: el SKU lo inventa cada constructora, pero
-- un EAN-13 es del producto, no de quien lo compra. La misma plancha de
-- Volcanita trae el mismo código en la bodega de todas las constructoras del
-- país. Con un UNIQUE global, la segunda empresa que intentara registrarla
-- fallaría —y como la importación es todo o nada, se le caería la planilla
-- entera— con un mensaje que además le confirma que esa fila existe en otro
-- tenant.
--
-- UNIQUE en PostgreSQL admite varios NULL, así que los materiales sin etiqueta
-- no chocan entre sí ni dentro de la misma empresa.
ALTER TABLE materiales ADD CONSTRAINT uq_materiales_empresa_codigo_barra UNIQUE (empresa_id, codigo_barra);
