-- Base de catálogo de Check-In-Obra (MT1, #104).
--
-- Guarda qué empresas existen y cómo conectarse a la base de cada una. No tiene
-- datos de negocio: esos viven en la base de cada empresa. La escribe la API con
-- el rol checkinobra_plataforma (solo DML); estas migraciones las aplica el
-- migrador, igual que las de cada empresa (db/migration).

CREATE TABLE planes (
    id           BIGSERIAL    PRIMARY KEY,
    codigo       VARCHAR(30)  NOT NULL UNIQUE,
    nombre       VARCHAR(100) NOT NULL,
    -- Topes del plan; nulo = sin tope. Todavía no se aplican: existen para que el
    -- alta de empresa pueda asignar un plan desde el primer día.
    max_usuarios INTEGER      CHECK (max_usuarios IS NULL OR max_usuarios > 0),
    max_obras    INTEGER      CHECK (max_obras IS NULL OR max_obras > 0)
);

INSERT INTO planes (codigo, nombre) VALUES ('ESTANDAR', 'Estándar');

-- El id de una empresa es el mismo que tiene su copia en su propia base
-- (empresas.id): es el que viaja en el JWT y el que ya referencian las FKs de cada
-- base. Por eso no hay una columna aparte de "id en la base".
CREATE TABLE empresas (
    id           BIGSERIAL    PRIMARY KEY,
    rut          VARCHAR(20)  NOT NULL UNIQUE,
    nombre       VARCHAR(200) NOT NULL,
    plan_id      BIGINT       NOT NULL REFERENCES planes (id),
    estado       VARCHAR(20)  NOT NULL DEFAULT 'ACTIVA' CHECK (estado IN ('ACTIVA', 'SUSPENDIDA')),
    -- Una empresa, una base.
    nombre_base  VARCHAR(63)  NOT NULL UNIQUE,
    usuario_base VARCHAR(63)  NOT NULL,
    -- Referencia al secreto, nunca el secreto: "env:NOMBRE_DE_VARIABLE" por ahora.
    secreto_ref  VARCHAR(200) NOT NULL,
    creada_en    TIMESTAMPTZ  NOT NULL DEFAULT now()
);

-- Personal de la plataforma que da de alta y suspende empresas. Distinto de los
-- usuarios de una empresa, que viven en la base de esa empresa.
CREATE TABLE operadores (
    id        BIGSERIAL    PRIMARY KEY,
    email     VARCHAR(255) NOT NULL UNIQUE,
    nombre    VARCHAR(200) NOT NULL,
    pin_hash  VARCHAR(100),
    activo    BOOLEAN      NOT NULL DEFAULT TRUE
);

-- A qué empresa pertenece un correo. Para abrir la base correcta hay que saber la
-- empresa de quien inicia sesión, y eso pasa antes del JWT. El correo es único en
-- todo el sistema; el PIN se sigue validando en la base de la empresa.
CREATE TABLE indice_login (
    email      VARCHAR(255) PRIMARY KEY,  -- en minúsculas
    empresa_id BIGINT       NOT NULL REFERENCES empresas (id)
);

CREATE INDEX idx_indice_login_empresa ON indice_login (empresa_id);
