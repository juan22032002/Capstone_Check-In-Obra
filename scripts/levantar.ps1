<#
Deja Check-In-Obra andando para desarrollar en Windows: enciende Docker
Desktop si esta apagado, construye y levanta las imagenes, y arranca un
emulador de Android. El emulador parte primero y bootea mientras Docker
construye, que es lo que mas tarda.

  powershell -ExecutionPolicy Bypass -File scripts\levantar.ps1
  powershell -ExecutionPolicy Bypass -File scripts\levantar.ps1 -App          # ademas corre la app (flutter run)
  powershell -ExecutionPolicy Bypass -File scripts\levantar.ps1 -SinCache     # reconstruye las imagenes desde cero
  powershell -ExecutionPolicy Bypass -File scripts\levantar.ps1 -SinEmulador  # solo Docker
  powershell -ExecutionPolicy Bypass -File scripts\levantar.ps1 -Avd NOMBRE   # otro emulador
  powershell -ExecutionPolicy Bypass -File scripts\levantar.ps1 -Telefono     # corre la app en el telefono por USB
                                                                               # (API por adb reverse), sin emulador

Con varios telefonos conectados: -Telefono -Serie <serie> (la serie sale de 'adb devices').

En Linux y macOS usar scripts/levantar.sh. Compatible con Windows PowerShell 5.1.
#>
[CmdletBinding()]
param(
    [switch]$App,
    [switch]$SinCache,
    [switch]$SinEmulador,
    [string]$Avd = $env:AVD,
    [switch]$Telefono,
    [string]$Serie = $env:TELEFONO
)

# 'Continue' y no 'Stop': en Windows PowerShell 5.1, con 'Stop' cualquier linea
# que adb, emulator o docker escriban en stderr corta el script aunque el
# comando haya funcionado. Los codigos de salida se revisan a mano.
$ErrorActionPreference = 'Continue'

$Raiz = Split-Path -Parent $PSScriptRoot
Set-Location $Raiz

$Api = 'http://localhost:8081'
# El backend no tiene actuator; que publique su OpenAPI significa que arranco
# y que Flyway ya corrio.
$Sonda = "$Api/v3/api-docs"
$EsperaDocker = 180
$EsperaApi = 240        # la primera vez compila la imagen entera
$EsperaEmulador = 240
$PuertoEmulador = 5554
$Dispositivo = "emulator-$PuertoEmulador"

function Paso($texto) { Write-Host ''; Write-Host $texto -ForegroundColor Cyan }
function Info($texto) { Write-Host "  $texto" }
function Bien($texto) { Write-Host "  $texto" -ForegroundColor Green }
function Mal($texto)  { Write-Host "  $texto" -ForegroundColor Red }
function Salir($texto) { Mal $texto; exit 1 }

if ($Telefono) {
    if ($PSBoundParameters.ContainsKey('Avd')) {
        Salir '-Telefono no usa emulador: no se puede combinar con -Avd.'
    }
    # El telefono reemplaza al emulador, y la app siempre se corre en el.
    $SinEmulador = $true
    $App = $false
} elseif ($App -and $SinEmulador) {
    Salir '-App necesita el emulador: no se puede combinar con -SinEmulador.'
}

# --- herramientas ---------------------------------------------------------
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Salir "Falta 'docker' en el PATH. Instala Docker Desktop."
}

# emulator.exe y adb.exe suelen no estar en el PATH aunque el SDK este
# instalado: Android Studio no los agrega. Se buscan en las rutas de siempre.
$Emulator = $null
$Adb = $null
if (-not $SinEmulador -or $Telefono) {
    $candidatos = @(@($env:ANDROID_HOME, $env:ANDROID_SDK_ROOT, (Join-Path $env:LOCALAPPDATA 'Android\Sdk')) |
        Where-Object { $_ -and (Test-Path (Join-Path $_ 'emulator\emulator.exe')) })
    $comando = Get-Command emulator -ErrorAction SilentlyContinue
    if ($comando) {
        $Emulator = $comando.Source
    } elseif ($candidatos) {
        $Emulator = Join-Path $candidatos[0] 'emulator\emulator.exe'
    }
    $comando = Get-Command adb -ErrorAction SilentlyContinue
    if ($comando) {
        $Adb = $comando.Source
    } elseif ($candidatos) {
        $Adb = Join-Path $candidatos[0] 'platform-tools\adb.exe'
    }
    $faltaAdb = -not $Adb -or -not (Test-Path $Adb)
    $faltaEmulator = (-not $SinEmulador) -and (-not $Emulator -or -not (Test-Path $Emulator))
    if ($faltaAdb -or $faltaEmulator) {
        Mal 'No se encontro el SDK de Android (emulator.exe y adb.exe).'
        Info 'Instalalo desde Android Studio o define ANDROID_HOME.'
        Info 'Para seguir solo con Docker: scripts\levantar.ps1 -SinEmulador'
        exit 1
    }
}
if (($App -or $Telefono) -and -not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    Salir "Falta 'flutter' en el PATH."
}

# --- 0. telefono -----------------------------------------------------------
# Se busca antes de tocar Docker: si el telefono no esta autorizado, mejor
# saberlo ahora y no despues de construir la imagen.
if ($Telefono) {
    Paso 'Telefono'
    & $Adb start-server 2>$null | Out-Null
    $lineas = @(& $Adb devices 2>$null | Select-Object -Skip 1 |
        Where-Object { $_ -and $_ -notmatch '^emulator-' })
    $listos = @($lineas | Where-Object { $_ -match '\sdevice$' } | ForEach-Object { ($_ -split '\s+')[0] })
    $pendientes = @($lineas | Where-Object { $_ -match '\sunauthorized$' } | ForEach-Object { ($_ -split '\s+')[0] })

    if ($Serie) {
        if ($listos -notcontains $Serie) { Salir "El telefono '$Serie' no esta conectado y autorizado." }
    } elseif ($listos.Count -eq 0) {
        if ($pendientes.Count -gt 0) {
            Mal "El telefono $($pendientes[0]) esta conectado pero no autorizado."
            Info "Desbloquealo y acepta 'Permitir depuracion USB' (marca 'Permitir siempre')."
            Info 'Si el aviso no aparece, desconecta y vuelve a conectar el cable.'
        } else {
            Mal 'No hay ningun telefono conectado.'
            Info "Conectalo por USB con la 'Depuracion USB' activada en Opciones de desarrollador."
            Info "Debe aparecer como 'device' en: adb devices. En Windows puede faltar el driver USB del fabricante."
        }
        exit 1
    } elseif ($listos.Count -gt 1) {
        Mal 'Hay mas de un telefono conectado:'
        $listos | ForEach-Object { Info "  $_" }
        Info 'Elige uno: scripts\levantar.ps1 -Telefono -Serie <serie>'
        exit 1
    } else {
        $Serie = $listos[0]
    }
    $modelo = (& $Adb -s $Serie shell getprop ro.product.model 2>$null | Out-String).Trim()
    Bien "$Serie ($modelo) conectado."
}

function EmuladorCorriendo {
    $lineas = & $Adb devices 2>$null
    return [bool]($lineas | Where-Object { $_ -match "^$Dispositivo\s" })
}

# --- 1. emulador (en segundo plano) ----------------------------------------
if (-not $SinEmulador) {
    Paso 'Emulador'
    & $Adb start-server 2>$null | Out-Null
    if (EmuladorCorriendo) {
        Bien "$Dispositivo ya estaba corriendo."
    } else {
        $disponibles = @(& $Emulator -list-avds 2>$null | Where-Object { $_ -and $_ -notmatch '^INFO' })
        if ($disponibles.Count -eq 0) {
            Mal 'No hay ningun emulador creado.'
            Info "Crea uno en Android Studio (Device Manager) o con 'flutter emulators --create'."
            exit 1
        }
        if ($Avd) {
            if ($disponibles -notcontains $Avd) {
                Mal "No existe el emulador '$Avd'. Los disponibles son:"
                $disponibles | ForEach-Object { Info "  $_" }
                exit 1
            }
        } elseif ($disponibles -contains 'Check-In-Obra_Pixel5') {
            $Avd = 'Check-In-Obra_Pixel5'
        } else {
            $Avd = $disponibles[0]
        }
        Info "Arrancando $Avd; bootea mientras se levanta Docker."
        # Proceso propio: sigue vivo cuando el script termina. Abre ademas una
        # consola con el log del emulador; cerrarla apaga el emulador.
        Start-Process -FilePath $Emulator -WindowStyle Minimized `
            -ArgumentList @('-avd', $Avd, '-port', $PuertoEmulador, '-netdelay', 'none', '-netspeed', 'full') | Out-Null
    }
}

# --- 2. Docker Desktop -----------------------------------------------------
function DockerResponde {
    & docker info *> $null
    return ($LASTEXITCODE -eq 0)
}

Paso 'Docker Desktop'
if (DockerResponde) {
    Bien 'Ya estaba encendido.'
} else {
    $desktop = Join-Path $env:ProgramFiles 'Docker\Docker\Docker Desktop.exe'
    if (-not (Test-Path $desktop)) {
        Salir "Docker no responde y no se encontro Docker Desktop en '$desktop'."
    }
    Info 'Encendiendo Docker Desktop...'
    Start-Process -FilePath $desktop | Out-Null
    $limite = (Get-Date).AddSeconds($EsperaDocker)
    while (-not (DockerResponde)) {
        if ((Get-Date) -gt $limite) {
            Salir "Docker Desktop no respondio en ${EsperaDocker}s. Revisa que WSL 2 este instalado y actualizado."
        }
        Start-Sleep -Seconds 3
    }
    Bien 'Docker Desktop responde.'
}

# --- 2b. secretos ------------------------------------------------------------
# La API no arranca sin JWT_SECRET ni sin las contrasenas de la base, y compose las
# lee del .env de la raiz, que no se versiona. Se generan una sola vez, nunca se
# imprimen, y se reemplaza cualquier valor de ejemplo ("CAMBIAR_...").
Paso 'Secretos (.env)'
$envRaiz = Join-Path $Raiz '.env'
function AsegurarSecreto([string]$Var, [int]$Bytes, [int]$Minimo = 32) {
    $lineas = @()
    if (Test-Path $envRaiz) { $lineas = @(Get-Content $envRaiz) }
    $valido = $lineas | Where-Object { $_ -match "^$Var=\S{$Minimo,}$" -and $_ -notmatch "^$Var=(?i)cambiar" }
    if ($valido) { Bien "$Var ya definido en .env."; return }
    $azar = New-Object byte[] $Bytes
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $rng.GetBytes($azar)
    $rng.Dispose()
    $valor = ([Convert]::ToBase64String($azar)) -replace '[+/=]', ''
    $resto = @($lineas | Where-Object { $_ -notmatch "^$Var=" })
    Set-Content -Path $envRaiz -Value ($resto + "$Var=$valor") -Encoding ascii
    Bien "Generado $Var nuevo en .env (no se versiona)."
}
AsegurarSecreto 'JWT_SECRET' 48
AsegurarSecreto 'POSTGRES_PASSWORD' 36
AsegurarSecreto 'DB_APP_PASSWORD' 36
AsegurarSecreto 'DB_MIGRADOR_PASSWORD' 36
AsegurarSecreto 'DB_PLATAFORMA_PASSWORD' 36
# Clave inicial del administrador: corta a proposito (se copia a mano en la app, que
# pide cambiarla en el primer ingreso). La migracion V11 anulo el PIN 0000.
AsegurarSecreto 'PRIMER_ADMIN_CLAVE' 12 12

# --- 3. imagenes y contenedores --------------------------------------------
Paso 'Construyendo las imagenes'
if ($SinCache) { & docker compose build --no-cache } else { & docker compose build }
if ($LASTEXITCODE -ne 0) { Salir 'Fallo la construccion de las imagenes.' }

Paso 'Levantando la base y creando sus roles'
# La API conecta como checkinobra_app (solo DML) y Flyway como checkinobra_migrador.
# En un volumen nuevo los crea el entrypoint de Postgres; en uno anterior a esto no
# corre solo, asi que se ejecuta siempre: es idempotente, y de paso sincroniza las
# contrasenas con las del .env y le pasa las tablas viejas al migrador.
& docker compose up -d --wait db
if ($LASTEXITCODE -ne 0) { Salir 'La base no quedo lista.' }
& docker compose exec -T db /docker-entrypoint-initdb.d/01-roles.sh
if ($LASTEXITCODE -ne 0) { Salir 'No se pudieron crear los roles de la base.' }

Paso 'Levantando los contenedores'
& docker compose up -d
if ($LASTEXITCODE -ne 0) { Salir 'No se pudieron levantar los contenedores.' }

function ApiResponde {
    try {
        $r = Invoke-WebRequest -Uri $Sonda -UseBasicParsing -TimeoutSec 5
        return ($r.StatusCode -eq 200)
    } catch {
        return $false
    }
}

Paso 'Esperando que la API responda'
$limite = (Get-Date).AddSeconds($EsperaApi)
while (-not (ApiResponde)) {
    if ((Get-Date) -gt $limite) {
        Mal "La API no respondio en ${EsperaApi}s. Ultimas lineas del backend:"
        & docker compose logs --tail=30 backend
        exit 1
    }
    Start-Sleep -Seconds 2
}
Bien "La API responde en $Api"

# --- 4. esperar el emulador ------------------------------------------------
if (-not $SinEmulador) {
    Paso 'Esperando que el emulador termine de bootear'
    $limite = (Get-Date).AddSeconds($EsperaEmulador)
    while ($true) {
        $booteado = (& $Adb -s $Dispositivo shell getprop sys.boot_completed 2>$null | Out-String).Trim()
        if ($booteado -eq '1') { break }
        if ((Get-Date) -gt $limite) {
            Mal "$Dispositivo no termino de bootear en ${EsperaEmulador}s."
            Info "Revisa la consola del emulador. Si falta aceleracion por hardware, activa 'Plataforma del hipervisor de Windows'."
            exit 1
        }
        Start-Sleep -Seconds 2
    }
    Bien "$Dispositivo listo."
}

# --- 4b. el telefono alcanza la API por el cable --------------------------
# adb reverse publica el 8081 del computador como localhost:8081 del telefono:
# no importa la WiFi ni la IP. Se pierde al desconectar el cable.
if ($Telefono) {
    Paso 'Conectando el telefono con la API'
    & $Adb -s $Serie reverse tcp:8081 tcp:8081 | Out-Null
    if ($LASTEXITCODE -ne 0) { Salir "No se pudo hacer adb reverse en $Serie." }
    Bien 'localhost:8081 del telefono llega a la API del computador.'
}

# La app lee la URL de la API de mobile\.env. Sin ese archivo igual arranca,
# pero conviene que exista para que quien lo edite sepa donde esta.
$envMovil = Join-Path $Raiz 'mobile\.env'
if (-not (Test-Path $envMovil)) {
    Copy-Item (Join-Path $Raiz 'mobile\.env.example') $envMovil
    Info 'Creado mobile\.env desde .env.example (API_BASE_URL=http://10.0.2.2:8081).'
}

# --- resumen ---------------------------------------------------------------
Paso 'Listo'
Info "API          $Api"
Info "Swagger      $Api/swagger-ui.html"
Info 'PostgreSQL   127.0.0.1:5433  (usuario checkinobra_app; la clave esta en .env como DB_APP_PASSWORD)'
Info 'Admin        admin@arauco-ltda.cl  clave inicial: PRIMER_ADMIN_CLAVE en .env (la app te pide cambiarla)'
if (-not $SinEmulador) { Info "Emulador     $Dispositivo" }
if ($Telefono) { Info "Telefono     $Serie" }
Info 'Cuentas de los cuatro roles: py scripts\cuentas_de_prueba.py'
Info 'Bajar todo:                  docker compose down'

if ($Telefono) {
    Paso "Corriendo la app en $Serie"
    Set-Location (Join-Path $Raiz 'mobile')
    & flutter pub get
    # La URL va al compilar y gana sobre mobile\.env (ver AppConfig), asi el
    # .env de cada quien queda como esta.
    & flutter run -d $Serie "--dart-define=API_BASE_URL=$Api"
} elseif ($App) {
    Paso "Corriendo la app en $Dispositivo"
    Set-Location (Join-Path $Raiz 'mobile')
    & flutter pub get
    & flutter run -d $Dispositivo
} elseif (-not $SinEmulador) {
    Info "Correr la app:               cd mobile; flutter run -d $Dispositivo"
}
