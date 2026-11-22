-- Un solo formato de RUT: 12.345.678-5 (puntos, guion, K mayúscula).
--
-- Desde ahora la API normaliza el RUT antes de guardarlo (Rut.normalizar). Los
-- ya guardados se llevan al mismo formato, porque de otro modo el UNIQUE sigue
-- dejando pasar la misma persona escrita de otra forma: "14109556-0" en la base
-- no choca con un "14.109.556-0" nuevo.
--
-- Solo se cambia el FORMATO; el dígito verificador no se corrige ni se valida.
-- Un RUT con el dígito equivocado queda como estaba, porque cuál es el correcto
-- lo sabe la persona, no la migración. La API valida solo al escribir, así que
-- esas filas siguen cargando.
--
-- Igual que en V5: si dos filas quedarían con el mismo RUT normalizado, no se
-- toca ninguna, para no violar el UNIQUE. Hay que resolverlas a mano.

WITH limpio AS (
    SELECT id, upper(regexp_replace(rut, '[.[:space:]-]', '', 'g')) AS rut
    FROM usuarios
    WHERE rut IS NOT NULL
), canonico AS (
    SELECT id,
           replace(to_char(left(rut, -1)::bigint, 'FM999,999,999'), ',', '.') || '-' || right(rut, 1) AS rut
    FROM limpio
    WHERE rut ~ '^[0-9]{1,8}[0-9K]$'
)
UPDATE usuarios u
SET rut = c.rut
FROM canonico c
WHERE u.id = c.id
  AND u.rut <> c.rut
  AND NOT EXISTS (SELECT 1 FROM usuarios otro WHERE otro.rut = c.rut)
  AND (SELECT count(*) FROM canonico c2 WHERE c2.rut = c.rut) = 1;

WITH limpio AS (
    SELECT id, upper(regexp_replace(rut, '[.[:space:]-]', '', 'g')) AS rut
    FROM empresas
), canonico AS (
    SELECT id,
           replace(to_char(left(rut, -1)::bigint, 'FM999,999,999'), ',', '.') || '-' || right(rut, 1) AS rut
    FROM limpio
    WHERE rut ~ '^[0-9]{1,8}[0-9K]$'
)
UPDATE empresas e
SET rut = c.rut
FROM canonico c
WHERE e.id = c.id
  AND e.rut <> c.rut
  AND NOT EXISTS (SELECT 1 FROM empresas otra WHERE otra.rut = c.rut)
  AND (SELECT count(*) FROM canonico c2 WHERE c2.rut = c.rut) = 1;
