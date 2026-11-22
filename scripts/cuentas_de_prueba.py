#!/usr/bin/env python3
"""Deja listas las cuentas de prueba de los cuatro roles, con PIN conocido.

La base solo trae al administrador. Las demás cuentas se crean a mano
desde la app, y su PIN no se puede leer después (solo se guarda la huella), así
que cada integrante del equipo terminaba con cuentas distintas y PINs que nadie
recordaba.

Este script usa la API como el administrador y se puede correr las veces que
haga falta:

- Si la cuenta ya existe (se busca por correo), no la duplica: le fija el PIN
  de la tabla.
- Si no existe, la crea con su RUT y su PIN.
- A los trabajadores les asegura una ficha en una cuadrilla de la obra de
  prueba. Sin cuadrilla, un trabajador no aparece en ninguna obra y el
  bodeguero no puede despacharle nada.

Solo usa la biblioteca estándar: corre igual en Ubuntu y en Windows.

La clave del administrador no está en el repositorio. Se toma, en este orden, de
--admin-clave, de la variable ADMIN_CLAVE o PRIMER_ADMIN_CLAVE, o del .env de la
raíz (scripts/levantar.sh lo genera). El administrador nace obligado a cambiarla:
la primera vez, el script la cambia por --nueva-clave-admin y desde entonces la
clave es esa (pásala con --admin-clave o ADMIN_CLAVE).

Uso:
    python3 scripts/cuentas_de_prueba.py --nueva-clave-admin <clave de 8 o más>
    python3 scripts/cuentas_de_prueba.py                     # las veces siguientes
    python3 scripts/cuentas_de_prueba.py --api http://localhost:8081
    python3 scripts/cuentas_de_prueba.py --renovar-credenciales

Es para la base local. No lo corras contra un servidor real: reemplaza PINs.
"""

import argparse
import json
import os
import sys
import urllib.error
import urllib.request

ADMIN_EMAIL = "admin@arauco-ltda.cl"

OBRA = {
    "nombre": "Los Almendros · Torre B",
    "cliente": "Inmobiliaria Aconcagua",
    "ubicacion": "Av. Los Almendros 1240, Ñuñoa",
}
CUADRILLA = "Cuadrilla 1"

# Los RUT tienen dígito verificador válido. Correo y PIN son los que quedan
# documentados en el README: si cambias uno acá, cámbialo allá. Jefe de terreno
# y bodeguero llevan clave de 8 o más caracteres (la API la exige para todo rol
# que no sea TRABAJADOR); el trabajador, PIN de 4 dígitos.
CUENTAS = [
    {
        "rol": "JEFE_TERRENO",
        "nombre": "Rodrigo Cárcamo",
        "email": "rodrigo.carcamo@arauco-ltda.cl",
        "rut": "14.109.556-0",
        "pin": "jefe-1111-obra",
    },
    {
        "rol": "BODEGUERO",
        "nombre": "Jorge Reyes",
        "email": "jorge.reyes@arauco-ltda.cl",
        "rut": "16.482.903-0",
        "pin": "bodega-2222-obra",
    },
    {
        "rol": "TRABAJADOR",
        "nombre": "Marcelo Sepúlveda",
        "email": "marcelo.sepulveda@arauco-ltda.cl",
        "rut": "17.930.556-9",
        "pin": "3333",
    },
    {
        "rol": "TRABAJADOR",
        "nombre": "Javier Ortiz",
        "email": "javier.ortiz@arauco-ltda.cl",
        "rut": "19.775.310-2",
        "pin": "4444",
    },
]


def digito_verificador(cuerpo: str) -> str:
    """Módulo 11 del RUT chileno."""
    suma, factor = 0, 2
    for d in reversed(cuerpo):
        suma += int(d) * factor
        factor = 2 if factor == 7 else factor + 1
    resto = 11 - suma % 11
    return {11: "0", 10: "K"}.get(resto, str(resto))


def rut_valido(rut: str) -> bool:
    limpio = rut.replace(".", "").upper()
    cuerpo, _, dv = limpio.partition("-")
    return cuerpo.isdigit() and digito_verificador(cuerpo) == dv


def clave_de_admin(argumento):
    """--admin-clave, ADMIN_CLAVE, PRIMER_ADMIN_CLAVE o el .env de la raíz."""
    if argumento:
        return argumento
    for variable in ("ADMIN_CLAVE", "PRIMER_ADMIN_CLAVE"):
        if os.environ.get(variable):
            return os.environ[variable]
    env = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".env")
    try:
        with open(env, encoding="utf-8") as f:
            for linea in f:
                nombre, _, valor = linea.strip().partition("=")
                if nombre == "PRIMER_ADMIN_CLAVE" and valor:
                    return valor
    except OSError:
        pass
    return None


class Api:
    def __init__(self, base: str):
        self.base = base.rstrip("/")
        self.token = None

    def llamar(self, metodo: str, ruta: str, cuerpo=None):
        datos = None if cuerpo is None else json.dumps(cuerpo).encode()
        pedido = urllib.request.Request(
            self.base + ruta, data=datos, method=metodo
        )
        pedido.add_header("Content-Type", "application/json")
        if self.token:
            pedido.add_header("Authorization", f"Bearer {self.token}")
        try:
            with urllib.request.urlopen(pedido, timeout=15) as r:
                texto = r.read().decode()
                return r.status, (json.loads(texto) if texto else None)
        except urllib.error.HTTPError as e:
            texto = e.read().decode()
            try:
                return e.code, json.loads(texto) if texto else None
            except json.JSONDecodeError:
                return e.code, {"mensaje": texto}

    def exigir(self, metodo: str, ruta: str, cuerpo=None):
        status, datos = self.llamar(metodo, ruta, cuerpo)
        if status >= 300:
            mensaje = (datos or {}).get("mensaje", "") if isinstance(datos, dict) else ""
            raise RuntimeError(f"{metodo} {ruta} → {status} {mensaje}".strip())
        return datos


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--api", default="http://localhost:8081")
    parser.add_argument(
        "--renovar-credenciales",
        action="store_true",
        help="emite una credencial nueva a cada trabajador e imprime el código "
        "(la anterior deja de valer). Sirve para probar el escaneo escribiendo "
        "el código a mano.",
    )
    parser.add_argument("--admin-clave", help="clave actual del administrador")
    parser.add_argument(
        "--nueva-clave-admin",
        help="si el administrador debe cambiar su clave (primer ingreso), la cambia por esta",
    )
    args = parser.parse_args()

    for c in CUENTAS:
        assert rut_valido(c["rut"]), f"RUT inválido en la tabla: {c['rut']}"

    clave = clave_de_admin(args.admin_clave)
    if not clave:
        print("Falta la clave del administrador: usa --admin-clave, ADMIN_CLAVE o el .env de la raíz.")
        return 1

    api = Api(args.api)
    try:
        sesion = api.exigir("POST", "/api/auth/login", {"email": ADMIN_EMAIL, "pin": clave})
    except (RuntimeError, urllib.error.URLError) as e:
        print(f"No se pudo entrar como administrador en {args.api}: {e}")
        print("¿Está arriba el backend? (docker compose up -d)")
        return 1
    api.token = sesion["token"]

    if sesion.get("debeCambiarClave"):
        if not args.nueva_clave_admin:
            print("El administrador debe cambiar su clave antes de operar.")
            print("Vuelve a correr con --nueva-clave-admin <clave de 8 o más caracteres>,")
            print("o cámbiala desde la app.")
            return 1
        sesion = api.exigir(
            "PUT", "/api/auth/pin",
            {"pinActual": clave, "pinNuevo": args.nueva_clave_admin},
        )
        api.token = sesion["token"]
        print("Clave del administrador cambiada. Desde ahora usa esa (--admin-clave o ADMIN_CLAVE).")

    # Obra y cuadrilla de prueba.
    obras = api.exigir("GET", "/api/obras")
    obra = next(
        (o for o in obras if o["nombre"] == OBRA["nombre"] and o["estado"] == "ACTIVA"),
        None,
    )
    if obra is None:
        obra = api.exigir("POST", "/api/obras", OBRA)
        print(f"Obra creada: {obra['nombre']}")
    cuadrillas = api.exigir("GET", f"/api/cuadrillas?obraId={obra['id']}")
    cuadrilla = cuadrillas[0] if cuadrillas else api.exigir(
        "POST", "/api/cuadrillas", {"obraId": obra["id"], "nombre": CUADRILLA}
    )

    usuarios = {u["email"]: u for u in api.exigir("GET", "/api/usuarios")}
    en_obra = {
        t["usuarioId"]: t
        for t in api.exigir("GET", f"/api/trabajadores?obraId={obra['id']}")
        if "usuarioId" in t
    }

    filas = [("ADMIN", ADMIN_EMAIL, "(la que definiste)", "")]
    for c in CUENTAS:
        u = usuarios.get(c["email"])
        if u is None:
            u = api.exigir(
                "POST",
                "/api/usuarios",
                {
                    "nombre": c["nombre"],
                    "email": c["email"],
                    "rut": c["rut"],
                    "rol": c["rol"],
                    "pinInicial": c["pin"],
                },
            )
            estado = "creada"
        else:
            api.exigir("PUT", f"/api/usuarios/{u['id']}/pin", {"nuevoPin": c["pin"]})
            estado = "PIN restablecido"

        nota = estado
        if c["rol"] == "TRABAJADOR":
            ficha = en_obra.get(u["id"])
            if ficha is None:
                status, ficha = api.llamar(
                    "POST",
                    "/api/trabajadores",
                    {"usuarioId": u["id"], "cuadrillaId": cuadrilla["id"]},
                )
                if status >= 300:
                    ficha = None
                    nota += "; tiene ficha, pero no en esta obra"
                else:
                    nota += f"; credencial {ficha.get('credencialQr', '?')}"
            if ficha and args.renovar_credenciales and "id" in ficha:
                nueva = api.exigir("PUT", f"/api/trabajadores/{ficha['id']}/credencial")
                nota += f"; credencial {nueva.get('credencialQr', '?')}"
        filas.append((c["rol"], c["email"], c["pin"], nota))

    print(f"\nObra de prueba: {obra['nombre']} · {cuadrilla['nombre']}\n")
    ancho = max(len(f[1]) for f in filas)
    print(f"{'ROL':<13} {'CORREO':<{ancho}}  PIN / CLAVE")
    for rol, email, pin, nota in filas:
        print(f"{rol:<13} {email:<{ancho}}  {pin}  {nota}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
