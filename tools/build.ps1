param([string]$OutputName = 'CZN_VietHoa_v1_3_2')
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$previousPythonPath = $env:PYTHONPATH
$androidSourceRoot = Join-Path $projectRoot 'czn_android_patcher'
if (-not (Test-Path -LiteralPath $androidSourceRoot)) { $androidSourceRoot = $projectRoot }
try {
    $env:PYTHONPATH = Join-Path $PSScriptRoot 'vendor'
    Copy-Item -LiteralPath (Join-Path $androidSourceRoot 'android/app/src/main/assets/update-public.der') -Destination (Join-Path $PSScriptRoot 'android_update_public.der')
    & python -m PyInstaller --noconfirm --clean --onefile --windowed --name $OutputName --distpath $projectRoot --workpath (Join-Path $PSScriptRoot 'pyinstaller-build') --specpath $PSScriptRoot --paths (Join-Path $PSScriptRoot 'vendor') --add-data ((Join-Path $PSScriptRoot 'android_metadata_crypto.ps1') + ';.') --add-data ((Join-Path $PSScriptRoot 'android_update_public.der') + ';.') (Join-Path $PSScriptRoot 'app.py')
    if ($LASTEXITCODE -ne 0) { throw 'Build EXE that bai.' }
    Write-Host "Da tao: $projectRoot\$OutputName.exe"
} finally {
    $env:PYTHONPATH = $previousPythonPath
}
