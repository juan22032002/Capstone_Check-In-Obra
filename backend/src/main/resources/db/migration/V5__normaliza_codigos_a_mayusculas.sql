-- Los códigos que se escanean pasan a estar siempre en mayúsculas.
--
-- El escáner busca el código normalizado (`MaterialService.buscarPorCodigo`,
-- `HerramientaService.buscarPorCodigoQr`), y desde ahora el alta también lo
-- guarda así. Sin esta migración, todo lo creado antes con minúsculas queda
-- inalcanzable justo por la vía que se acaba de construir: se apunta la cámara
-- a la etiqueta impresa, el código llega en mayúsculas, no calza con lo
-- guardado y la app responde "no está en el catálogo de tu empresa".
--
-- El `NOT EXISTS` evita que la migración caiga por una colisión: si ya
-- existieran dos filas que solo se diferencian en mayúsculas —"vol-10" y
-- "VOL-10"—, normalizar una violaría el UNIQUE. Esas se dejan como están, a la
-- vista, en vez de tumbar el arranque de toda la aplicación por un caso que
-- necesita decisión humana.

UPDATE materiales m
SET sku = upper(m.sku)
WHERE m.sku <> upper(m.sku)
  AND NOT EXISTS (
      SELECT 1 FROM materiales otro
      WHERE otro.id <> m.id AND otro.sku = upper(m.sku)
  );

UPDATE herramientas h
SET codigo_qr = upper(h.codigo_qr)
WHERE h.codigo_qr <> upper(h.codigo_qr)
  AND NOT EXISTS (
      SELECT 1 FROM herramientas otra
      WHERE otra.id <> h.id AND otra.codigo_qr = upper(h.codigo_qr)
  );
