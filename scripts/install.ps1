$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

$repoRoot = [System.IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$env:PERSONA_SOURCE_ROOT = $repoRoot
try {
    & (Join-Path $PSScriptRoot "persona.ps1") __install
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
} finally {
    Remove-Item Env:PERSONA_SOURCE_ROOT -ErrorAction SilentlyContinue
}
