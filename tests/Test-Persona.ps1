$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

$root = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("persona-test-" + [Guid]::NewGuid().ToString("N"))
$source = Join-Path $testRoot "source"
$testCodex = Join-Path $testRoot "codex"
$testBin = Join-Path $testRoot "bin"
$utf8 = New-Object System.Text.UTF8Encoding($false)

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw "ASSERTION FAILED: $Message" }
}

function Read-Text([string]$Path) {
    return [System.IO.File]::ReadAllText($Path, $utf8)
}

function Invoke-Persona([string[]]$PersonaArgs) {
    Push-Location $source
    try {
        & pwsh -NoLogo -NoProfile -File (Join-Path (Join-Path $source "scripts") "persona.ps1") @PersonaArgs
        if ($LASTEXITCODE -ne 0) { throw "persona failed: $($PersonaArgs -join ' ')" }
    } finally { Pop-Location }
}

try {
    New-Item -ItemType Directory -Force -Path $source, $testCodex, $testBin | Out-Null
    Copy-Item -Path (Join-Path $root "*") -Destination $source -Recurse -Force
    $copiedGit = Join-Path $source ".git"
    if (Test-Path -LiteralPath $copiedGit) { Remove-Item -LiteralPath $copiedGit -Recurse -Force }
    & git -C $source init -b main *> $null
    & git -C $source add .
    & git -C $source -c user.name="Persona Test" -c user.email="persona-test@local" commit -m "test fixture" *> $null

    [System.IO.File]::WriteAllText((Join-Path $testCodex "config.toml"), "notify = [`"keep-me`"]`nmodel = `"user-model`"`nmodel_reasoning_effort = `"high`"`n`n[features]`nmemories = true`n", $utf8)
    [System.IO.File]::WriteAllText((Join-Path $testCodex "AGENTS.md"), "# Existing global instruction`n", $utf8)

    $env:PERSONA_CODEX_DIR = $testCodex
    $env:PERSONA_BIN_DIR = $testBin
    $env:PERSONA_SKIP_PATH_UPDATE = "1"
    $env:PERSONA_SKIP_CODEX_VALIDATE = "1"
    $env:PERSONA_SOURCE_ROOT = $source

    # A mid-install launcher failure must restore all earlier managed files.
    $blockedBin = Join-Path $testRoot "blocked-bin"
    [System.IO.File]::WriteAllText($blockedBin, "not a directory`n", $utf8)
    $env:PERSONA_BIN_DIR = $blockedBin
    & pwsh -NoLogo -NoProfile -File (Join-Path (Join-Path $source "scripts") "install.ps1") *> $null
    Assert-True ($LASTEXITCODE -ne 0) "broken launcher path did not fail installation"
    Assert-True ((Read-Text (Join-Path $testCodex "config.toml")).Contains('model = "user-model"')) "failed install changed config"
    Assert-True (-not (Read-Text (Join-Path $testCodex "AGENTS.md")).Contains("<!-- LOOP-PERSONA-TEAM:START -->")) "failed install left AGENTS block"
    Remove-Item -LiteralPath $blockedBin -Force

    # An unrelated launcher with the same name must never be overwritten.
    $env:PERSONA_BIN_DIR = $testBin
    [System.IO.File]::WriteAllText((Join-Path $testBin "persona.ps1"), "Write-Output 'mine'`n", $utf8)
    & pwsh -NoLogo -NoProfile -File (Join-Path (Join-Path $source "scripts") "install.ps1") *> $null
    Assert-True ($LASTEXITCODE -ne 0) "unmanaged launcher was overwritten"
    Assert-True ((Read-Text (Join-Path $testBin "persona.ps1")).Contains("mine")) "unmanaged launcher content changed"
    Remove-Item -LiteralPath (Join-Path $testBin "persona.ps1") -Force

    & (Join-Path (Join-Path $source "scripts") "install.ps1")
    if ($LASTEXITCODE -ne 0) { throw "install failed" }
    Remove-Item Env:PERSONA_SOURCE_ROOT -ErrorAction SilentlyContinue

    Assert-True ((Read-Text (Join-Path $testCodex "AGENTS.md")).Contains("# Existing global instruction")) "existing AGENTS content was lost"
    Assert-True ((Read-Text (Join-Path $testCodex "AGENTS.md")).Contains("<!-- LOOP-PERSONA-TEAM:START -->")) "managed AGENTS block missing"
    Assert-True (Test-Path -LiteralPath (Join-Path (Join-Path $testCodex "agents") "soul.toml")) "Soul agent missing"
    Assert-True (Test-Path -LiteralPath (Join-Path (Join-Path (Join-Path $testCodex "skills") "persona-council") "SKILL.md")) "skill missing"
    Assert-True ((Read-Text (Join-Path $testCodex "config.toml")).Contains('model = "gpt-5.6-luna"')) "economy model not applied"

    $firstAgents = Read-Text (Join-Path $testCodex "AGENTS.md")
    $env:PERSONA_SOURCE_ROOT = $source
    & (Join-Path (Join-Path $source "scripts") "install.ps1")
    if ($LASTEXITCODE -ne 0) { throw "reinstall failed" }
    Remove-Item Env:PERSONA_SOURCE_ROOT -ErrorAction SilentlyContinue
    Assert-True ((Read-Text (Join-Path $testCodex "AGENTS.md")) -eq $firstAgents) "reinstall changed AGENTS content"

    Invoke-Persona @("profile", "balanced")
    Assert-True ((Read-Text (Join-Path $testCodex "config.toml")).Contains('model = "gpt-5.6-terra"')) "balanced Loop model not applied"
    Invoke-Persona @("model", "set", "soul", "terra", "high")
    Assert-True ((Read-Text (Join-Path (Join-Path $testCodex "agents") "soul.toml")).Contains('model_reasoning_effort = "high"')) "Soul override not applied"
    Invoke-Persona @("model", "reset", "soul")

    $rejectedEffort = $false
    try { Invoke-Persona @("model", "set", "soul", "luna", "ultra") }
    catch { $rejectedEffort = $true }
    Assert-True $rejectedEffort "unsupported Luna effort was accepted"
    Invoke-Persona @("model", "set", "soul", "terra", "ultra")
    Assert-True ((Read-Text (Join-Path (Join-Path $testCodex "agents") "soul.toml")).Contains('model_reasoning_effort = "ultra"')) "supported Terra effort was rejected"
    Invoke-Persona @("model", "reset", "soul")

    $rejected = $false
    try { Invoke-Persona @("memory", "add", "--scope", "global", "--audience", "soul", "--summary", "미승인", "--text", "기록되면 안 됨") }
    catch { $rejected = $true }
    Assert-True $rejected "unapproved memory was accepted"

    $output = Invoke-Persona @("memory", "add", "--scope", "global", "--audience", "soul", "--kind", "reflection", "--summary", "첫 승인 기억", "--text", "소울의 승인된 Windows 테스트 기억입니다.", "--approved") | Out-String
    $match = [regex]::Match($output, '기록했습니다:\s*(\S+)')
    Assert-True $match.Success "memory id missing"
    $memoryId = $match.Groups[1].Value
    $context = Invoke-Persona @("context", "soul") | Out-String
    Assert-True $context.Contains($memoryId) "memory missing from context"
    Invoke-Persona @("memory", "retract", $memoryId, "--approved")
    $context = Invoke-Persona @("context", "soul") | Out-String
    Assert-True (-not $context.Contains($memoryId)) "retracted memory remains active"

    Invoke-Persona @("project", "use", "game-one")
    $projectOutput = Invoke-Persona @("memory", "add", "--scope", "project", "--audience", "shared", "--kind", "decision", "--summary", "프로젝트 결정", "--text", "Windows에서도 같은 프로젝트 기억을 사용합니다.", "--approved") | Out-String
    $projectMatch = [regex]::Match($projectOutput, '기록했습니다:\s*(\S+)')
    Assert-True $projectMatch.Success "project memory id missing"
    $projectMemoryId = $projectMatch.Groups[1].Value
    $projectMemoryFile = Get-ChildItem -LiteralPath (Join-Path $source "memory") -Filter "$projectMemoryId.md" -File -Recurse | Select-Object -First 1
    $approvedBytes = [System.IO.File]::ReadAllBytes($projectMemoryFile.FullName)

    [System.IO.File]::AppendAllText($projectMemoryFile.FullName, "`n승인 뒤 바뀐 내용`n", $utf8)
    $modifiedRejected = $false
    try { Invoke-Persona @("sync") } catch { $modifiedRejected = $true }
    Assert-True $modifiedRejected "modified approved memory was synchronized"
    [System.IO.File]::WriteAllBytes($projectMemoryFile.FullName, $approvedBytes)

    [System.IO.File]::AppendAllText($projectMemoryFile.FullName, "`napi_key=changed-after-approval`n", $utf8)
    $secretRejected = $false
    try { Invoke-Persona @("sync") } catch { $secretRejected = $true }
    Assert-True $secretRejected "secret added after approval was synchronized"
    [System.IO.File]::WriteAllBytes($projectMemoryFile.FullName, $approvedBytes)

    $stagedPath = Join-Path $source "staged-user.txt"
    [System.IO.File]::WriteAllText($stagedPath, "user staged work`n", $utf8)
    & git -C $source add staged-user.txt
    $stagedRejected = $false
    try { Invoke-Persona @("sync") } catch { $stagedRejected = $true }
    Assert-True $stagedRejected "sync accepted pre-existing staged changes"
    & git -C $source restore --staged staged-user.txt
    Remove-Item -LiteralPath $stagedPath -Force

    & git -C $source switch --detach *> $null
    $detachedRejected = $false
    try { Invoke-Persona @("sync") } catch { $detachedRejected = $true }
    Assert-True $detachedRejected "sync accepted detached HEAD"
    & git -C $source switch main *> $null

    Invoke-Persona @("sync")
    $lastCommitOutput = & git -C $source log -1 '--pretty=%s'
    $lastCommit = $lastCommitOutput | Select-Object -First 1
    $hasMemoryCommit = $lastCommit.StartsWith("memory: sync approved persona memories")
    Assert-True $hasMemoryCommit "sync commit missing"

    Invoke-Persona @("uninstall")
    Assert-True (-not (Read-Text (Join-Path $testCodex "AGENTS.md")).Contains("<!-- LOOP-PERSONA-TEAM:START -->")) "managed AGENTS block remains"
    Assert-True ((Read-Text (Join-Path $testCodex "config.toml")).Contains('model = "user-model"')) "original model not restored"

    # A later install captures new defaults; an edited model does not prevent
    # the untouched effort key from being restored independently.
    [System.IO.File]::WriteAllText((Join-Path $testCodex "config.toml"), "notify = [`"second-install`"]`nmodel = `"user-model-two`"`nmodel_reasoning_effort = `"medium`"`n", $utf8)
    $env:PERSONA_SOURCE_ROOT = $source
    & (Join-Path (Join-Path $source "scripts") "install.ps1")
    if ($LASTEXITCODE -ne 0) { throw "second install failed" }
    Remove-Item Env:PERSONA_SOURCE_ROOT -ErrorAction SilentlyContinue
    $changedConfig = (Read-Text (Join-Path $testCodex "config.toml")) -replace '(?m)^model = .*$', 'model = "changed-after-install"'
    [System.IO.File]::WriteAllText((Join-Path $testCodex "config.toml"), $changedConfig, $utf8)
    Invoke-Persona @("uninstall")
    Assert-True ((Read-Text (Join-Path $testCodex "config.toml")).Contains('model = "changed-after-install"')) "user-edited model was not preserved"
    Assert-True ((Read-Text (Join-Path $testCodex "config.toml")).Contains('model_reasoning_effort = "medium"')) "untouched effort was not restored"
    Write-Host "All Windows persona tests passed."
} finally {
    Remove-Item Env:PERSONA_CODEX_DIR -ErrorAction SilentlyContinue
    Remove-Item Env:PERSONA_BIN_DIR -ErrorAction SilentlyContinue
    Remove-Item Env:PERSONA_SKIP_PATH_UPDATE -ErrorAction SilentlyContinue
    Remove-Item Env:PERSONA_SKIP_CODEX_VALIDATE -ErrorAction SilentlyContinue
    Remove-Item Env:PERSONA_SOURCE_ROOT -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
}
