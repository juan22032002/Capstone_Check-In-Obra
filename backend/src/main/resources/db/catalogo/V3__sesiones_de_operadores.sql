-- MT6 (#109): los operadores de plataforma entran con su propio token, que se revalida contra esta
-- tabla en cada petición. token_version sube para dejar sin efecto los tokens ya emitidos de un
-- operador; activo = false lo saca del todo.
ALTER TABLE operadores ADD COLUMN token_version INTEGER NOT NULL DEFAULT 0;
