# LOOP-PERSONA-TEAM:LAUNCHER
param(
    [Parameter(Position = 0)]
    [string]$Command = "help",

    [Parameter(Position = 1, ValueFromRemainingArguments = $true)]
    [string[]]$CommandArgs = @()
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

$PersonaVersion = "1.0.0"
$AgentsStart = "<!-- LOOP-PERSONA-TEAM:START -->"
$AgentsEnd = "<!-- LOOP-PERSONA-TEAM:END -->"
$ManagedAgentMarker = "# Managed by Loop Persona Team"
$LauncherPsMarker = "# LOOP-PERSONA-TEAM:LAUNCHER"
$LauncherCmdMarker = "REM LOOP-PERSONA-TEAM:LAUNCHER"
$MissingValue = "__missing__"
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Fail([string]$Message) {
    throw [System.InvalidOperationException]::new("persona: 오류: $Message")
}

function Warn([string]$Message) {
    [Console]::Error.WriteLine("persona: 경고: $Message")
}

function Info([string]$Message) {
    [Console]::WriteLine("persona: $Message")
}

function Get-CodexDir {
    if ($env:PERSONA_CODEX_DIR) { return $env:PERSONA_CODEX_DIR }
    if ($env:CODEX_HOME) { return $env:CODEX_HOME }
    return (Join-Path $env:USERPROFILE ".codex")
}

function Get-BinDir {
    if ($env:PERSONA_BIN_DIR) { return $env:PERSONA_BIN_DIR }
    return (Join-Path (Get-CodexDir) "bin")
}

$CodexDir = Get-CodexDir
$StateDir = Join-Path $CodexDir "persona-team"
$StateFile = Join-Path $StateDir "state.conf"
$BackupDir = Join-Path $StateDir "backups"
$PendingFile = Join-Path $StateDir "pending-memory.txt"
$ProjectMap = Join-Path $StateDir "projects.tsv"

function Move-AtomicFile([string]$Source, [string]$Destination) {
    if ([System.IO.File]::Exists($Destination)) {
        [System.IO.File]::Replace($Source, $Destination, $null)
    } else {
        [System.IO.File]::Move($Source, $Destination)
    }
}

function Write-Utf8([string]$Path, [string]$Content) {
    $directory = [System.IO.Path]::GetDirectoryName($Path)
    if (-not $directory) { $directory = (Get-Location).Path }
    New-Item -ItemType Directory -Force -Path $directory | Out-Null
    $temporary = Join-Path $directory (".{0}.{1}.tmp" -f [System.IO.Path]::GetFileName($Path), [Guid]::NewGuid().ToString("N"))
    try {
        [System.IO.File]::WriteAllText($temporary, $Content, $Utf8NoBom)
        Move-AtomicFile $temporary $Path
    } finally {
        if ([System.IO.File]::Exists($temporary)) { Remove-Item -LiteralPath $temporary -Force }
    }
}

function Test-ReparsePoint([string]$Path) {
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    return ($null -ne $item -and (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0))
}

function Assert-NotLink([string]$Path, [string]$Label) {
    if (Test-ReparsePoint $Path) { Fail "$Label 심볼릭 링크는 안전하게 변경할 수 없어 중단했습니다: $Path" }
}

function Get-Timestamp {
    return [DateTime]::UtcNow.ToString("yyyyMMddTHHmmssZ")
}

function Get-State([string]$Key, [string]$Default = $null) {
    if (-not (Test-Path -LiteralPath $StateFile)) { return $Default }
    foreach ($line in [System.IO.File]::ReadAllLines($StateFile, $Utf8NoBom)) {
        if ($line.StartsWith("$Key=")) { return $line.Substring($Key.Length + 1) }
    }
    return $Default
}

function Set-State([string]$Key, [AllowEmptyString()][string]$Value) {
    if ($Key -notmatch '^[a-z0-9_]+$') { Fail "잘못된 상태 키입니다: $Key" }
    if ($Value.Contains("`n") -or $Value.Contains("`r")) { Fail "상태 값에는 줄바꿈을 넣을 수 없습니다." }
    Assert-NotLink $StateFile "상태 파일"
    New-Item -ItemType Directory -Force -Path $StateDir | Out-Null
    $lines = New-Object System.Collections.Generic.List[string]
    $written = $false
    if (Test-Path -LiteralPath $StateFile) {
        foreach ($line in [System.IO.File]::ReadAllLines($StateFile, $Utf8NoBom)) {
            if ($line.StartsWith("$Key=")) {
                if (-not $written) { $lines.Add("$Key=$Value") }
                $written = $true
            } else {
                $lines.Add($line)
            }
        }
    }
    if (-not $written) { $lines.Add("$Key=$Value") }
    Write-Utf8 $StateFile (($lines -join "`n") + "`n")
}

function Invoke-WithStateRollback([scriptblock]$Action) {
    $hadState = Test-Path -LiteralPath $StateFile
    $snapshot = if ($hadState) { [System.IO.File]::ReadAllText($StateFile, $Utf8NoBom) } else { $null }
    try {
        & $Action
    } catch {
        if ($hadState) { Write-Utf8 $StateFile $snapshot }
        elseif (Test-Path -LiteralPath $StateFile) { Remove-Item -LiteralPath $StateFile -Force }
        throw
    }
}

function Get-RepoRoot {
    if ($env:PERSONA_SOURCE_ROOT) {
        $candidate = $env:PERSONA_SOURCE_ROOT
    } else {
        $candidate = Get-State "repo_root"
        if (-not $candidate) {
            $candidate = Split-Path -Parent $PSScriptRoot
        }
    }
    $candidate = [System.IO.Path]::GetFullPath($candidate)
    if (-not (Test-Path -LiteralPath (Join-Path $candidate "canon")) -or
        -not (Test-Path -LiteralPath (Join-Path $candidate "templates")) -or
        -not (Test-Path -LiteralPath (Join-Path (Join-Path $candidate "skills") "persona-council"))) {
        Fail "Persona 저장소를 찾을 수 없습니다: $candidate"
    }
    return $candidate.TrimEnd([System.IO.Path]::DirectorySeparatorChar)
}

function Get-TomlRootValue([string]$Path, [string]$Key, [string]$Default = $null) {
    if (-not (Test-Path -LiteralPath $Path)) { return $Default }
    foreach ($line in [System.IO.File]::ReadAllLines($Path, $Utf8NoBom)) {
        if ($line -match '^\s*\[') { break }
        if ($line -match ('^\s*' + [regex]::Escape($Key) + '\s*=\s*"([^\"]*)"')) { return $Matches[1] }
    }
    return $Default
}

function Set-ConfigPair([string]$Model, [string]$Effort) {
    $config = Join-Path $CodexDir "config.toml"
    Assert-NotLink $config "config.toml"
    New-Item -ItemType Directory -Force -Path $CodexDir | Out-Null
    New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
    $hadConfig = Test-Path -LiteralPath $config
    $backup = $null
    $sourceLines = @()
    if ($hadConfig) {
        $sourceLines = [System.IO.File]::ReadAllLines($config, $Utf8NoBom)
        $backup = Join-Path $BackupDir ("config.toml.{0}.{1}.bak" -f (Get-Timestamp), $PID)
        Copy-Item -LiteralPath $config -Destination $backup -Force
    }
    $result = New-Object System.Collections.Generic.List[string]
    $root = $true
    $modelSeen = $false
    $effortSeen = $false
    $inserted = $false

    foreach ($line in $sourceLines) {
        if ($root -and $line -match '^\s*\[') {
            if (-not $modelSeen -and $Model -ne $MissingValue) { $result.Add("model = `"$Model`"") }
            if (-not $effortSeen -and $Effort -ne $MissingValue) { $result.Add("model_reasoning_effort = `"$Effort`"") }
            $inserted = $true
            $root = $false
        }
        if ($root -and $line -match '^\s*model\s*=') {
            if (-not $modelSeen -and $Model -ne $MissingValue) { $result.Add("model = `"$Model`"") }
            $modelSeen = $true
            continue
        }
        if ($root -and $line -match '^\s*model_reasoning_effort\s*=') {
            if (-not $effortSeen -and $Effort -ne $MissingValue) { $result.Add("model_reasoning_effort = `"$Effort`"") }
            $effortSeen = $true
            continue
        }
        $result.Add($line)
    }
    if (-not $inserted) {
        if (-not $modelSeen -and $Model -ne $MissingValue) { $result.Add("model = `"$Model`"") }
        if (-not $effortSeen -and $Effort -ne $MissingValue) { $result.Add("model_reasoning_effort = `"$Effort`"") }
    }
    Write-Utf8 $config (($result -join "`n") + "`n")

    if ($env:PERSONA_SKIP_CODEX_VALIDATE -ne "1" -and (Get-Command codex -ErrorAction SilentlyContinue)) {
        & codex --strict-config --version *> $null
        if ($LASTEXITCODE -ne 0) {
            if ($hadConfig) { Copy-Item -LiteralPath $backup -Destination $config -Force }
            else { Remove-Item -LiteralPath $config -Force -ErrorAction SilentlyContinue }
            Fail "Codex 설정 검증에 실패해 기존 config.toml을 복원했습니다."
        }
    }
}

function Get-ProfileValue([string]$Profile, [string]$Persona, [string]$Field) {
    if ($Field -eq "effort") { return "max" }
    switch ($Profile) {
        "economy" { return "gpt-5.6-luna" }
        "balanced" { if ($Persona -eq "loop") { return "gpt-5.6-terra" }; return "gpt-5.6-luna" }
        "max" { return "gpt-5.6-sol" }
        default { Fail "알 수 없는 프로필입니다: $Profile" }
    }
}

function Get-EffectiveValue([string]$Persona, [string]$Field) {
    $override = Get-State "override_${Persona}_${Field}" ""
    if ($override) { return $override }
    return Get-ProfileValue (Get-State "profile" "economy") $Persona $Field
}

function Assert-Persona([string]$Persona) {
    if (@("loop", "soul", "core") -notcontains $Persona) { Fail "페르소나는 loop, soul, core 중 하나여야 합니다." }
}

function Normalize-Model([string]$Model) {
    switch ($Model) {
        { $_ -in @("luna", "gpt-5.6-luna") } { return "gpt-5.6-luna" }
        { $_ -in @("terra", "gpt-5.6-terra") } { return "gpt-5.6-terra" }
        { $_ -in @("sol", "gpt-5.6-sol", "gpt-5.6") } { return "gpt-5.6-sol" }
        default { Fail "모델은 luna, terra, sol 중 하나여야 합니다." }
    }
}

function Assert-Effort([string]$Model, [string]$Effort) {
    if (@("low", "medium", "high", "xhigh", "max") -contains $Effort) { return }
    if ($Effort -eq "ultra") {
        if ($Model -eq "gpt-5.6-luna") { Fail "Luna는 ultra를 지원하지 않습니다. low, medium, high, xhigh, max 중에서 선택하세요." }
        return
    }
    Fail "추론 강도는 low, medium, high, xhigh, max, ultra 중 하나여야 합니다."
}

function Render-Agent([string]$Repo, [string]$Persona, [string]$Model, [string]$Effort) {
    $source = Join-Path (Join-Path (Join-Path $Repo "templates") "agents") "$Persona.toml.in"
    $agentDir = Join-Path $CodexDir "agents"
    $target = Join-Path $agentDir "$Persona.toml"
    Assert-NotLink $target "에이전트 파일"
    New-Item -ItemType Directory -Force -Path $agentDir | Out-Null
    New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
    if (Test-Path -LiteralPath $target) {
        Copy-Item -LiteralPath $target -Destination (Join-Path $BackupDir ("{0}.toml.{1}.{2}.bak" -f $Persona, (Get-Timestamp), $PID)) -Force
    }
    $content = [System.IO.File]::ReadAllText($source, $Utf8NoBom).Replace("@@MODEL@@", $Model).Replace("@@EFFORT@@", $Effort)
    Write-Utf8 $target $content
}

function Apply-Models {
    $repo = Get-RepoRoot
    $loopModel = Get-EffectiveValue "loop" "model"
    $loopEffort = Get-EffectiveValue "loop" "effort"
    Set-ConfigPair $loopModel $loopEffort
    Render-Agent $repo "soul" (Get-EffectiveValue "soul" "model") (Get-EffectiveValue "soul" "effort")
    Render-Agent $repo "core" (Get-EffectiveValue "core" "model") (Get-EffectiveValue "core" "effort")
    Set-State "last_written_loop_model" $loopModel
    Set-State "last_written_loop_effort" $loopEffort
}

function Remove-ManagedBlock([string]$Text, [string]$Start, [string]$End) {
    $startCount = ([regex]::Matches($Text, [regex]::Escape($Start))).Count
    $endCount = ([regex]::Matches($Text, [regex]::Escape($End))).Count
    if ($startCount -ne $endCount -or $startCount -gt 1) { Fail "관리 마커가 손상되어 변경을 중단했습니다." }
    if ($startCount -eq 0) { return $Text }
    $pattern = '(?ms)^' + [regex]::Escape($Start) + '\r?\n.*?^' + [regex]::Escape($End) + '(?:\r?\n)?'
    return [regex]::Replace($Text, $pattern, "")
}

function Install-AgentsBlock([string]$Repo) {
    $target = Join-Path $CodexDir "AGENTS.md"
    $blockPath = Join-Path (Join-Path $Repo "templates") "AGENTS.block.md"
    Assert-NotLink $target "AGENTS.md"
    New-Item -ItemType Directory -Force -Path $CodexDir | Out-Null
    New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
    $existing = ""
    if (Test-Path -LiteralPath $target) {
        $existing = [System.IO.File]::ReadAllText($target, $Utf8NoBom)
        Copy-Item -LiteralPath $target -Destination (Join-Path $BackupDir ("AGENTS.md.{0}.{1}.bak" -f (Get-Timestamp), $PID)) -Force
    }
    $clean = (Remove-ManagedBlock $existing $AgentsStart $AgentsEnd).TrimEnd()
    $block = [System.IO.File]::ReadAllText($blockPath, $Utf8NoBom).Trim()
    if ($clean) { Write-Utf8 $target ($clean + "`n`n" + $block + "`n") }
    else { Write-Utf8 $target ($block + "`n") }
}

function Install-Skill([string]$Repo) {
    $source = Join-Path (Join-Path $Repo "skills") "persona-council"
    $skillsDir = Join-Path $CodexDir "skills"
    $target = Join-Path $skillsDir "persona-council"
    Assert-NotLink $target "persona-council 스킬"
    New-Item -ItemType Directory -Force -Path $skillsDir | Out-Null
    New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
    $temporary = Join-Path $skillsDir (".persona-council.{0}" -f [Guid]::NewGuid().ToString("N"))
    try {
        Copy-Item -LiteralPath $source -Destination $temporary -Recurse -Force
        $tick = [char]96
        $runtime = "# Installed runtime paths`n`n- Persona command: {0}{1}{0}`n- Canonical repository: {0}{2}{0}`n`nThese paths are generated locally and are not synchronized to Git.`n" -f $tick, (Join-Path (Get-BinDir) 'persona.cmd'), $Repo
        Write-Utf8 (Join-Path (Join-Path $temporary "references") "runtime-paths.md") $runtime
        if (Test-Path -LiteralPath $target) {
            if (-not (Test-Path -LiteralPath (Join-Path $target ".persona-team-managed"))) { Fail "기존 persona-council 스킬이 이 설치기의 관리 대상이 아닙니다." }
            Move-Item -LiteralPath $target -Destination (Join-Path $BackupDir ("persona-council.{0}.{1}" -f (Get-Timestamp), $PID))
        }
        Move-Item -LiteralPath $temporary -Destination $target
    } finally {
        if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Recurse -Force }
    }
}

function Install-Launcher([string]$Repo) {
    $bin = Get-BinDir
    New-Item -ItemType Directory -Force -Path $bin | Out-Null
    $psTarget = Join-Path $bin "persona.ps1"
    $cmdTarget = Join-Path $bin "persona.cmd"
    Assert-NotLink $psTarget "persona.ps1 런처"
    Assert-NotLink $cmdTarget "persona.cmd 런처"
    New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
    foreach ($target in @($psTarget, $cmdTarget)) {
        if (Test-Path -LiteralPath $target) {
            Copy-Item -LiteralPath $target -Destination (Join-Path $BackupDir ("{0}.{1}.{2}.bak" -f [System.IO.Path]::GetFileName($target), (Get-Timestamp), $PID)) -Force
        }
    }
    $psTemporary = Join-Path $bin (".persona.ps1.{0}.tmp" -f [Guid]::NewGuid().ToString("N"))
    try {
        Copy-Item -LiteralPath (Join-Path (Join-Path $Repo "scripts") "persona.ps1") -Destination $psTemporary -Force
        Move-AtomicFile $psTemporary $psTarget
    } finally {
        if ([System.IO.File]::Exists($psTemporary)) { Remove-Item -LiteralPath $psTemporary -Force }
    }
    $cmd = $LauncherCmdMarker + "`r`n" + '@echo off' + "`r`n" + 'powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0persona.ps1" %*' + "`r`n"
    Write-Utf8 $cmdTarget $cmd
    Set-State "bin_dir" $bin
    if ($env:PERSONA_SKIP_PATH_UPDATE -ne "1") {
        $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
        $parts = @($userPath -split ';' | Where-Object { $_ })
        if ($parts -notcontains $bin) {
            $newPath = if ($userPath) { "$bin;$userPath" } else { $bin }
            [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
            Set-State "path_added" "true"
        }
        if (($env:Path -split ';') -notcontains $bin) { $env:Path = "$bin;$env:Path" }
    }
}

function Assert-NoInstallConflict {
    foreach ($target in @(
        $StateFile,
        (Join-Path $CodexDir "config.toml"),
        (Join-Path $CodexDir "AGENTS.md"),
        (Join-Path (Join-Path $CodexDir "agents") "soul.toml"),
        (Join-Path (Join-Path $CodexDir "agents") "core.toml"),
        (Join-Path (Join-Path $CodexDir "skills") "persona-council"),
        (Join-Path (Get-BinDir) "persona.ps1"),
        (Join-Path (Get-BinDir) "persona.cmd")
    )) { Assert-NotLink $target "관리 대상" }
    foreach ($persona in @("soul", "core")) {
        $target = Join-Path (Join-Path $CodexDir "agents") "$persona.toml"
        if (Test-Path -LiteralPath $target) {
            $text = [System.IO.File]::ReadAllText($target, $Utf8NoBom)
            if (-not $text.Contains($ManagedAgentMarker)) { Fail "기존 파일과 충돌합니다: $target" }
        }
    }
    $skill = Join-Path (Join-Path $CodexDir "skills") "persona-council"
    if ((Test-Path -LiteralPath $skill) -and -not (Test-Path -LiteralPath (Join-Path $skill ".persona-team-managed"))) {
        Fail "기존 스킬과 충돌합니다: $skill"
    }
    $agentsPath = Join-Path $CodexDir "AGENTS.md"
    if (Test-Path -LiteralPath $agentsPath) {
        Remove-ManagedBlock ([System.IO.File]::ReadAllText($agentsPath, $Utf8NoBom)) $AgentsStart $AgentsEnd | Out-Null
    }
    $psLauncher = Join-Path (Get-BinDir) "persona.ps1"
    if (Test-Path -LiteralPath $psLauncher) {
        $text = [System.IO.File]::ReadAllText($psLauncher, $Utf8NoBom)
        if (-not $text.Contains($LauncherPsMarker)) { Fail "기존 persona.ps1 명령과 충돌합니다: $psLauncher" }
    }
    $cmdLauncher = Join-Path (Get-BinDir) "persona.cmd"
    if (Test-Path -LiteralPath $cmdLauncher) {
        $text = [System.IO.File]::ReadAllText($cmdLauncher, $Utf8NoBom)
        if (-not $text.Contains($LauncherCmdMarker)) { Fail "기존 persona.cmd 명령과 충돌합니다: $cmdLauncher" }
    }
}

function Save-InstallTarget([string]$Transaction, [string]$Name, [string]$Path) {
    if ([System.IO.File]::Exists($Path) -or [System.IO.Directory]::Exists($Path)) {
        Copy-Item -LiteralPath $Path -Destination (Join-Path $Transaction $Name) -Recurse -Force
        [System.IO.File]::WriteAllText((Join-Path $Transaction "$Name.present"), "", $Utf8NoBom)
    } else {
        [System.IO.File]::WriteAllText((Join-Path $Transaction "$Name.absent"), "", $Utf8NoBom)
    }
}

function Remove-InstallTarget([string]$Path) {
    if ([System.IO.File]::Exists($Path)) { Remove-Item -LiteralPath $Path -Force }
    elseif ([System.IO.Directory]::Exists($Path)) { Remove-Item -LiteralPath $Path -Recurse -Force }
}

function Restore-InstallTarget([string]$Transaction, [string]$Name, [string]$Path) {
    if (-not $Path -or $Path -eq [System.IO.Path]::GetPathRoot($Path)) { Fail "복구 대상 경로가 안전하지 않습니다." }
    $present = Join-Path $Transaction "$Name.present"
    $absent = Join-Path $Transaction "$Name.absent"
    if ([System.IO.File]::Exists($present)) {
        Remove-InstallTarget $Path
        $parent = [System.IO.Path]::GetDirectoryName($Path)
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
        Copy-Item -LiteralPath (Join-Path $Transaction $Name) -Destination $Path -Recurse -Force
    } elseif ([System.IO.File]::Exists($absent)) {
        Remove-InstallTarget $Path
    }
}

function Install-Persona {
    $repo = Get-RepoRoot
    Assert-NoInstallConflict
    New-Item -ItemType Directory -Force -Path $StateDir | Out-Null
    New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
    $config = Join-Path $CodexDir "config.toml"
    $targets = @(
        [pscustomobject]@{ Name = "state"; Path = $StateFile },
        [pscustomobject]@{ Name = "config"; Path = $config },
        [pscustomobject]@{ Name = "agents"; Path = (Join-Path $CodexDir "AGENTS.md") },
        [pscustomobject]@{ Name = "soul"; Path = (Join-Path (Join-Path $CodexDir "agents") "soul.toml") },
        [pscustomobject]@{ Name = "core"; Path = (Join-Path (Join-Path $CodexDir "agents") "core.toml") },
        [pscustomobject]@{ Name = "skill"; Path = (Join-Path (Join-Path $CodexDir "skills") "persona-council") },
        [pscustomobject]@{ Name = "launcher_ps1"; Path = (Join-Path (Get-BinDir) "persona.ps1") },
        [pscustomobject]@{ Name = "launcher_cmd"; Path = (Join-Path (Get-BinDir) "persona.cmd") }
    )
    $transaction = Join-Path $StateDir (".install-transaction.{0}" -f [Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Force -Path $transaction | Out-Null
    $oldUserPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $oldProcessPath = $env:Path
    try {
        foreach ($target in $targets) { Save-InstallTarget $transaction $target.Name $target.Path }
        $freshInstall = (Get-State "installed" "false") -ne "true"
        if ($freshInstall) {
            Set-State "original_model" (Get-TomlRootValue $config "model" $MissingValue)
            Set-State "original_effort" (Get-TomlRootValue $config "model_reasoning_effort" $MissingValue)
            Set-State "path_added" "false"
        }
        Set-State "repo_root" $repo
        if ($null -eq (Get-State "profile" $null)) { Set-State "profile" "economy" }
        foreach ($persona in @("loop", "soul", "core")) {
            foreach ($field in @("model", "effort")) {
                $key = "override_${persona}_${field}"
                if ($null -eq (Get-State $key $null)) { Set-State $key "" }
            }
        }
        Apply-Models
        Install-AgentsBlock $repo
        Install-Skill $repo
        Install-Launcher $repo
        Set-State "installed" "true"
        Set-State "version" $PersonaVersion
    } catch {
        $reason = $_.Exception.Message
        for ($index = $targets.Count - 1; $index -ge 0; $index--) {
            $target = $targets[$index]
            Restore-InstallTarget $transaction $target.Name $target.Path
        }
        [Environment]::SetEnvironmentVariable("Path", $oldUserPath, "User")
        $env:Path = $oldProcessPath
        Remove-Item -LiteralPath $transaction -Recurse -Force -ErrorAction SilentlyContinue
        Fail "설치에 실패해 관리 대상 파일을 이전 상태로 복구했습니다. 원인: $reason"
    } finally {
        if (Test-Path -LiteralPath $transaction) { Remove-Item -LiteralPath $transaction -Recurse -Force }
    }
    Info "설치가 완료되었습니다. 활성 프로필: $(Get-State 'profile')"
}

function Set-Profile([string[]]$Args) {
    if ($Args.Count -ne 1 -or @("economy", "balanced", "max") -notcontains $Args[0]) { Fail "사용법: persona profile economy|balanced|max" }
    $profile = $Args[0]
    Invoke-WithStateRollback {
        Set-State "profile" $profile
        foreach ($persona in @("loop", "soul", "core")) {
            Set-State "override_${persona}_model" ""
            Set-State "override_${persona}_effort" ""
        }
        Apply-Models
    }
    Info "프로필을 $profile 로 변경했습니다. 열린 작업의 모델은 데스크톱 UI에서 별도로 바꾸세요."
}

function Set-PersonaModel([string[]]$Args) {
    if ($Args.Count -lt 1) { Fail "사용법: persona model set ... | persona model reset ..." }
    if ($Args[0] -eq "set") {
        if ($Args.Count -ne 4) { Fail "사용법: persona model set loop|soul|core luna|terra|sol <effort>" }
        $persona = $Args[1]
        Assert-Persona $persona
        $model = Normalize-Model $Args[2]
        $effort = $Args[3]
        Assert-Effort $model $effort
        Invoke-WithStateRollback {
            Set-State "override_${persona}_model" $model
            Set-State "override_${persona}_effort" $effort
            Apply-Models
        }
        Info "$persona 모델을 $model / $effort 로 재정의했습니다."
    } elseif ($Args[0] -eq "reset") {
        if ($Args.Count -ne 2) { Fail "사용법: persona model reset loop|soul|core" }
        $persona = $Args[1]
        Assert-Persona $persona
        Invoke-WithStateRollback {
            Set-State "override_${persona}_model" ""
            Set-State "override_${persona}_effort" ""
            Apply-Models
        }
        Info "$persona 모델을 현재 프로필 값으로 되돌렸습니다."
    } else {
        Fail "사용법: persona model set ... | persona model reset ..."
    }
}

function Get-Sha12([string]$Text) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
        $hash = ($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString("x2") }) -join ""
        return $hash.Substring(0, 12)
    } finally { $sha.Dispose() }
}

function Normalize-Remote([string]$Remote) {
    $value = $Remote -replace '\.git$', '' -replace '/$', ''
    $value = $value -replace '^[A-Za-z]+://(?:[^/@]+@)?', ''
    $value = $value -replace '^git@([^:]+):', '$1/'
    return $value.ToLowerInvariant()
}

function Get-MappedProject {
    if (-not (Test-Path -LiteralPath $ProjectMap)) { return $null }
    $here = (Get-Location).Path.TrimEnd('\', '/')
    $best = $null
    $bestLength = -1
    foreach ($line in [System.IO.File]::ReadAllLines($ProjectMap, $Utf8NoBom)) {
        $parts = $line -split "`t", 2
        if ($parts.Count -ne 2) { continue }
        $path = $parts[0].TrimEnd('\', '/')
        if ($here -eq $path -or $here.StartsWith($path + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
            if ($path.Length -gt $bestLength) { $best = $parts[1]; $bestLength = $path.Length }
        }
    }
    return $best
}

function Get-AutoProjectId {
    $remote = (& git remote get-url origin 2>$null)
    if ($LASTEXITCODE -eq 0 -and $remote) {
        $normalized = Normalize-Remote ($remote | Select-Object -First 1)
        $slug = [System.IO.Path]::GetFileName($normalized) -replace '[^A-Za-z0-9._-]', ''
        if (-not $slug) { $slug = "project" }
        return ($slug.ToLowerInvariant() + "-" + (Get-Sha12 $normalized))
    }
    return Get-MappedProject
}

function Set-Project([string[]]$Args) {
    if ($Args.Count -ne 2 -or $Args[0] -ne "use") { Fail "사용법: persona project use <slug>" }
    $slug = $Args[1]
    if ($slug -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$') { Fail "프로젝트 slug 형식이 올바르지 않습니다." }
    $root = (& git rev-parse --show-toplevel 2>$null)
    if ($LASTEXITCODE -ne 0 -or -not $root) { $root = (Get-Location).Path }
    $root = ($root | Select-Object -First 1).TrimEnd('\', '/')
    New-Item -ItemType Directory -Force -Path $StateDir | Out-Null
    $lines = New-Object System.Collections.Generic.List[string]
    if (Test-Path -LiteralPath $ProjectMap) {
        foreach ($line in [System.IO.File]::ReadAllLines($ProjectMap, $Utf8NoBom)) {
            if (-not $line.StartsWith($root + "`t", [System.StringComparison]::OrdinalIgnoreCase)) { $lines.Add($line) }
        }
    }
    $lines.Add("$root`t$slug")
    Write-Utf8 $ProjectMap (($lines -join "`n") + "`n")
    Info "현재 프로젝트를 $slug 로 연결했습니다."
}

function Get-MemoryFiles([string]$Repo, [string]$Persona, [string]$ProjectId) {
    $dirs = New-Object System.Collections.Generic.List[string]
    $dirs.Add((Join-Path (Join-Path (Join-Path $Repo "memory") "global") "shared\entries"))
    $dirs.Add((Join-Path (Join-Path (Join-Path (Join-Path $Repo "memory") "global") "journals") $Persona))
    if ($ProjectId) {
        $projectBase = Join-Path (Join-Path (Join-Path $Repo "memory") "projects") $ProjectId
        $dirs.Add((Join-Path $projectBase "shared"))
        $dirs.Add((Join-Path (Join-Path $projectBase "journals") $Persona))
    }
    $files = @()
    foreach ($dir in $dirs) {
        if (Test-Path -LiteralPath $dir) { $files += Get-ChildItem -LiteralPath $dir -Filter "*.md" -File }
    }
    return @($files | Sort-Object FullName)
}

function Get-MemorySummary([string]$Path) {
    foreach ($line in [System.IO.File]::ReadAllLines($Path, $Utf8NoBom)) {
        if ($line -match '^summary:\s*"(.*)"$') { return $Matches[1] }
    }
    return "승인된 기억"
}

function Show-Context([string[]]$Args) {
    if ($Args.Count -ne 1) { Fail "사용법: persona context loop|soul|core" }
    $persona = $Args[0]
    Assert-Persona $persona
    $repo = Get-RepoRoot
    $projectId = Get-AutoProjectId
    [Console]::WriteLine("# Persona canonical context`n")
    [Console]::WriteLine([System.IO.File]::ReadAllText((Join-Path (Join-Path $repo "canon") "team.md"), $Utf8NoBom))
    [Console]::WriteLine([System.IO.File]::ReadAllText((Join-Path (Join-Path $repo "canon") "$persona.md"), $Utf8NoBom))
    $profile = Join-Path (Join-Path (Join-Path (Join-Path $repo "memory") "global") "shared") "profile.md"
    [Console]::WriteLine([System.IO.File]::ReadAllText($profile, $Utf8NoBom))
    if ($projectId) {
        [Console]::WriteLine([Environment]::NewLine + '## Current project' + [Environment]::NewLine + [Environment]::NewLine + '- id: `' + $projectId + '`')
        $memoryRoot = Join-Path $repo "memory"
        $projectsRoot = Join-Path $memoryRoot "projects"
        $projectRoot = Join-Path $projectsRoot $projectId
        $projectShared = Join-Path $projectRoot "shared"
        $projectProfile = Join-Path $projectShared "profile.md"
        if (Test-Path -LiteralPath $projectProfile) { [Console]::WriteLine([System.IO.File]::ReadAllText($projectProfile, $Utf8NoBom)) }
    }
    $active = @()
    foreach ($file in (Get-MemoryFiles $repo $persona $projectId)) {
        $id = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
        $retraction = Join-Path (Join-Path (Join-Path $repo "memory") "retractions") "$id.md"
        if (-not (Test-Path -LiteralPath $retraction)) { $active += $file }
    }
    if ($active.Count -gt 0) {
        [Console]::WriteLine([Environment]::NewLine + "## Active memory index" + [Environment]::NewLine)
        foreach ($file in $active) {
            $id = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
            $tick = [char]96
            [Console]::WriteLine("- " + $tick + $id + $tick + ": " + (Get-MemorySummary $file.FullName))
        }
        [Console]::WriteLine([Environment]::NewLine + "## Recent memory details")
        foreach ($file in @($active | Select-Object -Last 8)) {
            [Console]::WriteLine([Environment]::NewLine + [System.IO.File]::ReadAllText($file.FullName, $Utf8NoBom))
        }
    }
}

function Assert-NoSecret([string]$Text) {
    $pattern = '(?i)(BEGIN\s+.*PRIVATE KEY|api[_ -]?key|access[_ -]?token|refresh[_ -]?token|session[_ -]?cookie|password\s*[:=]|secret\s*[:=]|recovery[_ -]?code|sk-[A-Za-z0-9_-]{12,}|비밀번호\s*[:=]|API\s*키\s*[:=]|(?:접근|갱신)?\s*토큰\s*[:=]|개인\s*키\s*[:=]|복구\s*코드\s*[:=])'
    if ($Text -match $pattern) { Fail "비밀정보로 보이는 내용은 공식 기억에 저장할 수 없습니다." }
}

function Get-FileSha256([string]$Path) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $stream = [System.IO.File]::OpenRead($Path)
    try {
        return (($sha.ComputeHash($stream) | ForEach-Object { $_.ToString("x2") }) -join "")
    } finally {
        $stream.Dispose()
        $sha.Dispose()
    }
}

function Add-Pending([string]$Repo, [string]$Path) {
    New-Item -ItemType Directory -Force -Path $StateDir | Out-Null
    $relative = $Path.Substring($Repo.Length).TrimStart('\', '/').Replace('\', '/')
    $lines = @()
    if (Test-Path -LiteralPath $PendingFile) {
        $lines = @([System.IO.File]::ReadAllLines($PendingFile, $Utf8NoBom) | Where-Object {
            $parts = $_ -split "`t", 2
            $parts.Count -lt 2 -or $parts[1] -ne $relative
        })
    }
    $lines += "$(Get-FileSha256 $Path)`t$relative"
    Write-Utf8 $PendingFile (($lines -join "`n") + "`n")
}

function Assert-PendingMemory([string]$Repo, [string]$ExpectedHash, [string]$Relative) {
    $expectedScope = ""
    $expectedAudience = ""
    if ($Relative -match '^memory/global/shared/entries/') { $expectedScope = "global"; $expectedAudience = "shared" }
    elseif ($Relative -match '^memory/global/journals/(loop|soul|core)/') { $expectedScope = "global"; $expectedAudience = $Matches[1] }
    elseif ($Relative -match '^memory/projects/[A-Za-z0-9._-]+/shared/') { $expectedScope = "project"; $expectedAudience = "shared" }
    elseif ($Relative -match '^memory/projects/[A-Za-z0-9._-]+/journals/(loop|soul|core)/') { $expectedScope = "project"; $expectedAudience = $Matches[1] }
    elseif ($Relative -notmatch '^memory/retractions/') { Fail "허용되지 않은 기억 경로가 동기화 대기열에 있습니다: $Relative" }
    if ($Relative -notmatch '^memory/(?:global/(?:shared/entries|journals/(?:loop|soul|core))|projects/[A-Za-z0-9._-]+/(?:shared|journals/(?:loop|soul|core))|retractions)/[A-Za-z0-9._:-]+\.md$') {
        Fail "안전하지 않은 기억 경로가 동기화 대기열에 있습니다: $Relative"
    }
    $path = Join-Path $Repo ($Relative.Replace('/', [System.IO.Path]::DirectorySeparatorChar))
    if (-not [System.IO.File]::Exists($path) -or (Test-ReparsePoint $path)) { Fail "대기 중인 기억 파일이 없거나 심볼릭 링크입니다: $Relative" }
    $id = [System.IO.Path]::GetFileNameWithoutExtension($path)
    $lines = [System.IO.File]::ReadAllLines($path, $Utf8NoBom)
    if ($lines -notcontains "id: `"$id`"") { Fail "기억 ID 메타데이터가 파일명과 다릅니다: $Relative" }
    if ($lines -notcontains 'approved_by: "creator"') { Fail "승인 메타데이터가 없는 기억입니다: $Relative" }
    if ($expectedScope) {
        if ($lines -notcontains "scope: `"$expectedScope`"") { Fail "기억 범위 메타데이터가 경로와 다릅니다: $Relative" }
        if ($lines -notcontains "audience: `"$expectedAudience`"") { Fail "기억 대상 메타데이터가 경로와 다릅니다: $Relative" }
        if ($lines -notcontains 'status: "active"') { Fail "활성 상태 메타데이터가 없는 기억입니다: $Relative" }
    }
    Assert-NoSecret ([System.IO.File]::ReadAllText($path, $Utf8NoBom))
    if ((Get-FileSha256 $path) -ne $ExpectedHash) { Fail "승인 뒤 변경된 기억은 다시 승인해야 합니다: $Relative" }
}

function Add-Memory([string[]]$Args) {
    $scope = ""; $audience = ""; $summary = ""; $body = ""; $kind = "note"; $approved = $false
    for ($i = 0; $i -lt $Args.Count; $i++) {
        switch ($Args[$i]) {
            "--scope" { if (++$i -ge $Args.Count) { Fail "--scope 값이 필요합니다." }; $scope = $Args[$i] }
            "--audience" { if (++$i -ge $Args.Count) { Fail "--audience 값이 필요합니다." }; $audience = $Args[$i] }
            "--summary" { if (++$i -ge $Args.Count) { Fail "--summary 값이 필요합니다." }; $summary = $Args[$i] }
            "--text" { if (++$i -ge $Args.Count) { Fail "--text 값이 필요합니다." }; $body = $Args[$i] }
            "--kind" { if (++$i -ge $Args.Count) { Fail "--kind 값이 필요합니다." }; $kind = $Args[$i] }
            "--approved" { $approved = $true }
            default { Fail "알 수 없는 memory add 옵션입니다: $($Args[$i])" }
        }
    }
    if (-not $approved) { Fail "창작자님의 명시적 승인 뒤 --approved를 지정해야 합니다." }
    if (@("global", "project") -notcontains $scope) { Fail "--scope는 global 또는 project여야 합니다." }
    if (@("shared", "loop", "soul", "core") -notcontains $audience) { Fail "--audience 값이 올바르지 않습니다." }
    if (@("note", "fact", "decision", "preference", "journal", "reflection") -notcontains $kind) { Fail "지원하지 않는 기억 종류입니다." }
    if (-not $summary -or -not $body) { Fail "--summary와 --text는 비워둘 수 없습니다." }
    Assert-NoSecret "$summary`n$body"
    $repo = Get-RepoRoot
    $projectId = ""
    if ($scope -eq "project") {
        $projectId = Get-AutoProjectId
        if (-not $projectId) { Fail "프로젝트를 식별할 수 없습니다. 먼저 persona project use <slug>를 실행하세요." }
        $base = Join-Path (Join-Path (Join-Path (Join-Path $repo "memory") "projects") $projectId) $(if ($audience -eq "shared") { "shared" } else { "journals\$audience" })
    } else {
        $base = Join-Path (Join-Path (Join-Path $repo "memory") "global") $(if ($audience -eq "shared") { "shared\entries" } else { "journals\$audience" })
    }
    New-Item -ItemType Directory -Force -Path $base | Out-Null
    $created = Get-Timestamp
    $id = "$created-$([Guid]::NewGuid().ToString().ToLowerInvariant())"
    $file = Join-Path $base "$id.md"
    $safeSummary = $summary.Replace('\', '\\').Replace('"', '\"').Replace("`r", ' ').Replace("`n", ' ')
    $front = @(
        "---",
        "id: `"$id`"",
        "created_at: `"$created`"",
        "scope: `"$scope`""
    )
    if ($projectId) { $front += "project: `"$projectId`"" }
    $front += @(
        "audience: `"$audience`"",
        "kind: `"$kind`"",
        "summary: `"$safeSummary`"",
        "approved_by: `"creator`"",
        "status: `"active`"",
        "---",
        "",
        $body,
        ""
    )
    Write-Utf8 $file ($front -join "`n")
    Add-Pending $repo $file
    Info "기억을 기록했습니다: $id"
}

function Retract-Memory([string[]]$Args) {
    if ($Args.Count -ne 2 -or $Args[1] -ne "--approved") { Fail "사용법: persona memory retract <id> --approved" }
    $id = $Args[0]
    if ($id -notmatch '^[A-Za-z0-9._:-]+$') { Fail "잘못된 기억 ID입니다." }
    $repo = Get-RepoRoot
    $original = Get-ChildItem -LiteralPath (Join-Path $repo "memory") -Filter "$id.md" -File -Recurse | Where-Object { $_.DirectoryName -notmatch '[\\/]retractions$' } | Select-Object -First 1
    if (-not $original) { Fail "기억 ID를 찾을 수 없습니다: $id" }
    $retractions = Join-Path (Join-Path $repo "memory") "retractions"
    $tombstone = Join-Path $retractions "$id.md"
    if (Test-Path -LiteralPath $tombstone) { Fail "이미 철회된 기억입니다: $id" }
    New-Item -ItemType Directory -Force -Path $retractions | Out-Null
    $content = "---`nid: `"$id`"`nretracted_at: `"$(Get-Timestamp)`"`napproved_by: `"creator`"`n---`n`nThis memory is excluded from active persona context.`n"
    Write-Utf8 $tombstone $content
    Add-Pending $repo $tombstone
    Info "기억을 활성 문맥에서 철회했습니다: $id"
}

function Manage-Memory([string[]]$Args) {
    if ($Args.Count -lt 1) { Fail "사용법: persona memory add ... | persona memory retract ..." }
    if ($Args[0] -eq "add") { Add-Memory @($Args | Select-Object -Skip 1) }
    elseif ($Args[0] -eq "retract") { Retract-Memory @($Args | Select-Object -Skip 1) }
    else { Fail "사용법: persona memory add ... | persona memory retract ..." }
}

function Deploy-FromRepo {
    $repo = Get-RepoRoot
    Assert-NoInstallConflict
    Install-AgentsBlock $repo
    Install-Skill $repo
    Install-Launcher $repo
    Apply-Models
}

function Sync-Persona {
    $repo = Get-RepoRoot
    & git -C $repo rev-parse --is-inside-work-tree *> $null
    if ($LASTEXITCODE -ne 0) { Fail "저장소가 아직 Git 저장소가 아닙니다." }
    $branch = (& git -C $repo symbolic-ref --quiet --short HEAD 2>$null | Select-Object -First 1)
    if ($LASTEXITCODE -ne 0 -or -not $branch) { Fail "detached HEAD에서는 기억을 안전하게 동기화할 수 없습니다. 브랜치로 전환하세요." }
    & git -C $repo diff --cached --quiet '--'
    if ($LASTEXITCODE -ne 0) { Fail "기존 staged 변경이 있어 기억 동기화를 중단했습니다. 먼저 stage를 비우거나 커밋하세요." }
    if (Test-Path -LiteralPath $PendingFile) {
        $pending = @([System.IO.File]::ReadAllLines($PendingFile, $Utf8NoBom) | Where-Object { $_ })
        $pendingPaths = @()
        foreach ($entry in $pending) {
            $parts = $entry -split "`t", 3
            if ($parts.Count -ne 2 -or -not $parts[0] -or -not $parts[1]) { Fail "이전 형식이거나 손상된 기억 대기열입니다. 해당 기억을 다시 승인해 주세요." }
            Assert-PendingMemory $repo $parts[0] $parts[1]
            $pendingPaths += $parts[1]
        }
        foreach ($relative in $pendingPaths) {
            & git -C $repo add '--' $relative
            if ($LASTEXITCODE -ne 0) {
                & git -C $repo reset --quiet '--' @pendingPaths 2>$null
                Fail "기억 파일을 stage하지 못했습니다: $relative"
            }
        }
        if ($pendingPaths.Count -gt 0) {
            & git -C $repo -c user.name="Persona Memory" -c user.email="persona-memory@local" commit --only -m "memory: sync approved persona memories $(Get-Timestamp)" '--' @pendingPaths
            if ($LASTEXITCODE -ne 0) {
                & git -C $repo reset --quiet '--' @pendingPaths 2>$null
                Fail "기억 커밋에 실패했습니다. 대기 중인 파일은 보존했습니다."
            }
            Write-Utf8 $PendingFile ""
        }
    }
    $dirty = (& git -C $repo status --porcelain) -join "`n"
    if ($dirty) { Fail "기억 외의 커밋되지 않은 변경이 있어 pull/push를 중단했습니다." }
    & git -C $repo remote get-url origin *> $null
    if ($LASTEXITCODE -ne 0) {
        Deploy-FromRepo
        Warn "origin 원격이 없어 로컬 커밋까지만 완료했습니다."
        return
    }
    $remoteHeads = (& git -C $repo ls-remote --heads origin $branch)
    if ($LASTEXITCODE -ne 0) { Fail "원격 저장소에 연결하지 못했습니다. 로컬 커밋은 보존되어 있습니다." }
    if ($remoteHeads) {
        & git -C $repo pull --rebase origin $branch
        if ($LASTEXITCODE -ne 0) { Fail "리베이스가 중단되었습니다. 충돌을 직접 확인하세요." }
    }
    & git -C $repo push -u origin $branch
    if ($LASTEXITCODE -ne 0) { Fail "push에 실패했습니다. 로컬 커밋은 보존되어 있습니다." }
    Deploy-FromRepo
    Info "공식 기억과 페르소나 자료를 동기화했습니다."
}

function Show-Status {
    $profile = Get-State "profile" "not-installed"
    [Console]::WriteLine("Persona Team $PersonaVersion")
    [Console]::WriteLine("profile: $profile")
    if ($profile -ne "not-installed") {
        foreach ($persona in @("loop", "soul", "core")) {
            $override = Get-State "override_${persona}_model" ""
            $source = if ($override) { "local override" } else { "profile $profile" }
            [Console]::WriteLine("${persona}: $(Get-EffectiveValue $persona 'model') / $(Get-EffectiveValue $persona 'effort') (source: $source)")
        }
    }
    $config = Join-Path $CodexDir "config.toml"
    [Console]::WriteLine("config loop: $(Get-TomlRootValue $config 'model' '<unset>') / $(Get-TomlRootValue $config 'model_reasoning_effort' '<unset>')")
    $projectRoot = (& git rev-parse --show-toplevel 2>$null | Select-Object -First 1)
    $projectConfig = $null
    if ($LASTEXITCODE -eq 0 -and $projectRoot) {
        $candidate = Join-Path (Join-Path $projectRoot ".codex") "config.toml"
        if (Test-Path -LiteralPath $candidate) { $projectConfig = $candidate }
    }
    if (-not $projectConfig) {
        $candidate = Join-Path (Join-Path (Get-Location).Path ".codex") "config.toml"
        if (Test-Path -LiteralPath $candidate) { $projectConfig = $candidate }
    }
    if ($projectConfig) {
        $projectModel = Get-TomlRootValue $projectConfig "model" ""
        if ($projectModel) { [Console]::WriteLine("project override: $projectModel (전역 Loop 기본값보다 우선)") }
    }
    [Console]::WriteLine("active desktop task: 작업별 UI 모델 선택이 위 값보다 우선할 수 있습니다.")
    [Console]::WriteLine("repository: $(Get-State 'repo_root' '<unset>')")
    $project = Get-AutoProjectId
    if (-not $project) { $project = "<unmapped>" }
    [Console]::WriteLine("project memory: $project")
}

function Invoke-Doctor {
    $failures = 0
    $codex = Get-Command codex -ErrorAction SilentlyContinue
    if ($codex) {
        & codex --version
        if ($env:PERSONA_SKIP_CODEX_VALIDATE -ne "1") {
            & codex --strict-config --version *> $null
            if ($LASTEXITCODE -ne 0) { Warn "config.toml 엄격 검증 실패"; $failures++ }
        }
    } else { Warn "codex 명령을 PATH에서 찾지 못했습니다."; $failures++ }
    $agentsPath = Join-Path $CodexDir "AGENTS.md"
    $agentText = if (Test-Path -LiteralPath $agentsPath) { [System.IO.File]::ReadAllText($agentsPath, $Utf8NoBom) } else { "" }
    if (([regex]::Matches($agentText, [regex]::Escape($AgentsStart))).Count -ne 1) { Warn "전역 AGENTS 관리 블록 개수가 1이 아닙니다."; $failures++ }
    foreach ($path in @(
        (Join-Path (Join-Path $CodexDir "agents") "soul.toml"),
        (Join-Path (Join-Path $CodexDir "agents") "core.toml"),
        (Join-Path (Join-Path (Join-Path $CodexDir "skills") "persona-council") "SKILL.md")
    )) {
        if (-not (Test-Path -LiteralPath $path)) { Warn "설치 파일 누락: $path"; $failures++ }
    }
    $repo = Get-State "repo_root" ""
    if (-not $repo -or -not (Test-Path -LiteralPath (Join-Path $repo ".git"))) { Warn "Git 저장소 상태를 확인하세요: $repo"; $failures++ }
    if ($failures -gt 0) { Fail "진단에서 ${failures}개 문제를 찾았습니다." }
    Info "진단을 통과했습니다."
}

function Uninstall-Persona {
    New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
    $agentsPath = Join-Path $CodexDir "AGENTS.md"
    if (Test-Path -LiteralPath $agentsPath) {
        Assert-NotLink $agentsPath "AGENTS.md"
        Copy-Item -LiteralPath $agentsPath -Destination (Join-Path $BackupDir ("AGENTS.md.uninstall.{0}.{1}.bak" -f (Get-Timestamp), $PID)) -Force
        $clean = Remove-ManagedBlock ([System.IO.File]::ReadAllText($agentsPath, $Utf8NoBom)) $AgentsStart $AgentsEnd
        Write-Utf8 $agentsPath $clean
    }
    foreach ($persona in @("soul", "core")) {
        $path = Join-Path (Join-Path $CodexDir "agents") "$persona.toml"
        if (Test-Path -LiteralPath $path) {
            $text = [System.IO.File]::ReadAllText($path, $Utf8NoBom)
            if ($text.Contains($ManagedAgentMarker)) { Remove-Item -LiteralPath $path -Force }
        }
    }
    $skill = Join-Path (Join-Path $CodexDir "skills") "persona-council"
    if ((Test-Path -LiteralPath $skill) -and (Test-Path -LiteralPath (Join-Path $skill ".persona-team-managed"))) {
        Move-Item -LiteralPath $skill -Destination (Join-Path $BackupDir ("persona-council.uninstall.{0}.{1}" -f (Get-Timestamp), $PID))
    }
    $config = Join-Path $CodexDir "config.toml"
    $currentModel = Get-TomlRootValue $config "model" $MissingValue
    $currentEffort = Get-TomlRootValue $config "model_reasoning_effort" $MissingValue
    $restoreModel = $currentModel
    $restoreEffort = $currentEffort
    if ($currentModel -eq (Get-State "last_written_loop_model" "__unknown__")) { $restoreModel = Get-State "original_model" $MissingValue }
    else { Warn "Loop 모델이 설치 후 변경되어 현재 값을 보존했습니다." }
    if ($currentEffort -eq (Get-State "last_written_loop_effort" "__unknown__")) { $restoreEffort = Get-State "original_effort" $MissingValue }
    else { Warn "Loop 추론 강도가 설치 후 변경되어 현재 값을 보존했습니다." }
    Set-ConfigPair $restoreModel $restoreEffort
    Info "변경되지 않은 Loop 기본 설정을 설치 전 값으로 복원했습니다."
    $bin = Get-State "bin_dir" (Get-BinDir)
    if ((Get-State "path_added" "false") -eq "true") {
        $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
        $newParts = @($userPath -split ';' | Where-Object { $_ -and $_ -ne $bin })
        [Environment]::SetEnvironmentVariable("Path", ($newParts -join ';'), "User")
    }
    foreach ($name in @("persona.cmd", "persona.ps1")) {
        $path = Join-Path $bin $name
        if (Test-Path -LiteralPath $path) {
            $marker = if ($name -eq "persona.cmd") { $LauncherCmdMarker } else { $LauncherPsMarker }
            $text = [System.IO.File]::ReadAllText($path, $Utf8NoBom)
            if ($text.Contains($marker)) { Remove-Item -LiteralPath $path -Force }
            else { Warn "설치 후 변경된 런처를 보존했습니다: $path" }
        }
    }
    Set-State "installed" "false"
    Info "전역 설치를 제거했습니다. 저장소, 기억과 백업은 보존했습니다."
}

function Show-Usage {
    @"
Loop · Soul · Core persona manager

Usage:
  persona profile economy|balanced|max
  persona model set loop|soul|core luna|terra|sol low|medium|high|xhigh|max|ultra
  persona model reset loop|soul|core
  persona status
  persona doctor
  persona project use <slug>
  persona context loop|soul|core
  persona memory add ... --approved
  persona memory retract <id> --approved
  persona sync
  persona uninstall
"@
}

try {
    switch ($Command) {
        "__install" { Install-Persona }
        "profile" { Set-Profile $CommandArgs }
        "model" { Set-PersonaModel $CommandArgs }
        "status" { Show-Status }
        "doctor" { Invoke-Doctor }
        "project" { Set-Project $CommandArgs }
        "context" { Show-Context $CommandArgs }
        "memory" { Manage-Memory $CommandArgs }
        "sync" { if ($CommandArgs.Count -ne 0) { Fail "사용법: persona sync" }; Sync-Persona }
        "uninstall" { if ($CommandArgs.Count -ne 0) { Fail "사용법: persona uninstall" }; Uninstall-Persona }
        { $_ -in @("help", "-h", "--help") } { Show-Usage }
        { $_ -in @("version", "--version") } { [Console]::WriteLine($PersonaVersion) }
        default { Show-Usage; Fail "알 수 없는 명령입니다: $Command" }
    }
} catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
}
