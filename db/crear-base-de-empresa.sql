-- Crea la base de una empresa y deja lista su conexión (MT5, #108).
--
-- Es el paso de infraestructura del alta de una empresa: una base vacía, con el migrador
-- como dueño (él aplica las migraciones) y la API con permiso de conexión y de DML sobre
-- lo que el migrador cree. Las tablas las crea MigradorDeBases al arrancar la API, una
-- vez registrada la base en el catálogo. Hoy lo usan las pruebas de aislamiento para
-- tener una segunda base; el módulo de plataforma (fase 4) hará lo mismo al dar de alta.
--
-- Idempotente. Necesita los roles de roles.sql ya creados.
-- Uso: psql -v ON_ERROR_STOP=1 -v base=checkinobra_empresa_2 -f crear-base-de-empresa.sql
\set ON_ERROR_STOP on

SELECT format('CREATE DATABASE %I OWNER checkinobra_migrador', :'base')
WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = :'base') \gexec

-- Solo estos dos roles se conectan a la base de una empresa.
SELECT format('REVOKE CONNECT ON DATABASE %I FROM PUBLIC', :'base') \gexec
SELECT format('GRANT CONNECT ON DATABASE %I TO checkinobra_app, checkinobra_migrador', :'base') \gexec

\c :"base"
ALTER SCHEMA public OWNER TO checkinobra_migrador;
GRANT USAGE ON SCHEMA public TO checkinobra_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO checkinobra_app;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO checkinobra_app;
ALTER DEFAULT PRIVILEGES FOR ROLE checkinobra_migrador IN SCHEMA public
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO checkinobra_app;
ALTER DEFAULT PRIVILEGES FOR ROLE checkinobra_migrador IN SCHEMA public
    GRANT USAGE, SELECT ON SEQUENCES TO checkinobra_app;
