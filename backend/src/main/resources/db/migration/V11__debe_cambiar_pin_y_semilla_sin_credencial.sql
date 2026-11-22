-- SEG3 (#91, S-03): el administrador inicial ya no entra con un PIN publicado.
--
-- 1. usuarios.debe_cambiar_pin: mientras sea TRUE, la cuenta solo puede llamar a
--    PUT /api/auth/pin (ver JwtAuthFilter). Se limpia al definir una clave nueva.
ALTER TABLE usuarios ADD COLUMN debe_cambiar_pin BOOLEAN NOT NULL DEFAULT FALSE;

-- 2. La credencial que sembraba V2 (PIN 0000) está publicada en el README: quien
--    la conociera podía entrar, cambiarla y quedarse con la cuenta. Se anula; el
--    primer administrador recibe su clave de PRIMER_ADMIN_CLAVE al arrancar
--    (PrimerAdminInicializador) y queda obligado a cambiarla.
UPDATE usuarios
SET pin_hash = NULL
WHERE pin_hash = '$2a$10$kFSIWta/.cMLeikoQc0JW.DMmNBA9nMPVHb/h7CDh3SwK3SxGMVui';

-- 3. Todo usuario existente que no sea TRABAJADOR debe cambiar su clave al próximo
--    ingreso. El hash no revela el largo, así que no se puede saber cuáles tienen
--    todavía un PIN de 4 dígitos (la política de 8 caracteres es posterior).
UPDATE usuarios
SET debe_cambiar_pin = TRUE
WHERE rol <> 'TRABAJADOR'
  AND pin_hash IS NOT NULL;
