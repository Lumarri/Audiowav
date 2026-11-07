param([switch]$SkipBuild)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
Push-Location $projectRoot
try {
    if (-not $SkipBuild) {
        & flutter build windows --release
        if ($LASTEXITCODE -ne 0) { throw 'Windows build failed.' }
    }
    $versionLine = Get-Content -LiteralPath (Join-Path $projectRoot 'pubspec.yaml') | Where-Object { $_ -match '^version:' }
    if ($versionLine -notmatch '^version:\s*([0-9]+\.[0-9]+\.[0-9]+)') { throw 'Version not found.' }
    $version = $Matches[1]
    $releaseRoot = Join-Path $projectRoot 'build/windows/x64/runner/Release'
    if (-not (Test-Path -LiteralPath (Join-Path $releaseRoot 'audiowav.exe'))) { throw 'Windows executable not found.' }
    $destination = Join-Path $projectRoot "dist/Audiowav-$version-windows-x64"
    $archive = "$destination.zip"
    if ((Test-Path -LiteralPath $destination) -or (Test-Path -LiteralPath $archive)) {
        throw 'Package already exists. Preserve or move the previous package before creating another.'
    }
    New-Item -ItemType Directory -Path $destination -Force | Out-Null
    Get-ChildItem -LiteralPath $releaseRoot | Copy-Item -Destination $destination -Recurse
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
    $visualStudio = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    if (-not $visualStudio) { throw 'Visual C++ redistributable directory not found.' }
    $redistRoot = Join-Path $visualStudio 'VC/Redist/MSVC'
    $runtime = Get-ChildItem -LiteralPath $redistRoot -Directory | Sort-Object Name -Descending |
        ForEach-Object { Join-Path $_.FullName 'x64/Microsoft.VC143.CRT' } |
        Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    if (-not $runtime) { throw 'Visual C++ x64 runtime DLLs not found.' }
    Get-ChildItem -LiteralPath $runtime -Filter '*.dll' | Copy-Item -Destination $destination
    Copy-Item -LiteralPath (Join-Path $projectRoot 'LICENSE') -Destination $destination
    Copy-Item -LiteralPath (Join-Path $projectRoot 'docs/windows.md') -Destination (Join-Path $destination 'Windows-guide.md')
    $flutterRoot = (Get-Content -LiteralPath (Join-Path $projectRoot 'windows/flutter/ephemeral/generated_config.cmake') |
        Select-String -Pattern 'file\(TO_CMAKE_PATH "(.+)" FLUTTER_ROOT\)').Matches.Groups[1].Value.Replace('\\', '\')
    if ($flutterRoot -and (Test-Path -LiteralPath (Join-Path $flutterRoot 'LICENSE'))) {
        Copy-Item -LiteralPath (Join-Path $flutterRoot 'LICENSE') -Destination (Join-Path $destination 'LICENSE-Flutter.txt')
    }
    @"
Audiowav $version - Windows x64

Extrae toda esta carpeta y abre audiowav.exe.
Conserva las DLL y la carpeta data junto al EXE.

Archivo local: abre audio y activa el DSP. Incluye EQ, graves,
ganancia, balance y doce controles de reverberacion.

Otras aplicaciones: elige un proceso con audio y pulsa Activar DSP.
La captura directa puede usar solo un retorno WET si Windows no permite
silenciar el original sin silenciar tambien la captura.

Ruta completa: instala por separado un cable virtual compatible, envia
la app a CABLE Input desde Windows, elige ese cable como fuente de Audiowav
y tus altavoces como salida del DSP. Al detenerlo, devuelve la salida
de la app a sus altavoces en Windows. El controlador no viene incluido.

Consulta Windows-guide.md para arquitectura, limites y pruebas.
El DSP externo agrega retardo. No se graba ni se transmite audio.
Esta compilacion de pruebas no tiene firma Authenticode.

Codigo: https://github.com/Lumarri/Audiowav
Audiowav: MIT. Flutter y el runtime de Microsoft conservan sus licencias.
No incluye el algoritmo propietario de Fruity Reeverb 2.
"@ | Set-Content -LiteralPath (Join-Path $destination 'LEEME.txt') -Encoding UTF8
    Compress-Archive -LiteralPath $destination -DestinationPath $archive -CompressionLevel Optimal
    $digest = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
    "$digest  $([IO.Path]::GetFileName($archive))" | Set-Content -LiteralPath "$archive.sha256" -Encoding ASCII
    Write-Output $destination
    Write-Output $archive
    Write-Output "SHA256: $digest"
} finally {
    Pop-Location
}
