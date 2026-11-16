<#
.SYNOPSIS
  Compile one AL app with its code analyzers and summarise every diagnostic as JSON.

.DESCRIPTION
  Uses the compiler from the installed AL Language extension (or -AlcPath / $env:ALRIG_ALC).
  Analyzers and the ruleset come from the parameters, else from the app's .vscode/settings.json
  (al.codeAnalyzers, al.ruleSetPath), else the repository root's. Third-party analyzers the
  project already declares - LinterCop, ALCops and the like - are passed by path; nothing is
  downloaded.

  Writes no file inside the repository: the .app and the full diagnostic log go to -OutDir,
  a temporary directory by default. Report layouts are not regenerated.

  Prints one JSON object. status is OK (compiled, diagnostics summarised), ERRORS (the build
  failed - diagnostics still summarised) or UNVERIFIED (could not compile: no compiler, no
  symbols), with a reason.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$AppPath,
    [string]$AlcPath,
    [string[]]$Analyzers,
    [string]$RuleSet,
    [string]$PackageCachePath,
    [string]$OutDir,
    [switch]$ReportSuppressed,
    [int]$MaxFindings = 400
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'AlrigSecurity.psm1') -Force

function Out-Result($obj) { $obj | ConvertTo-Json -Depth 8; exit 0 }

$app = (Resolve-Path -LiteralPath $AppPath).Path
if (-not (Test-Path -LiteralPath (Join-Path $app 'app.json'))) {
    Out-Result @{ status = 'UNVERIFIED'; reason = "no app.json in $app" }
}

# ---------------------------------------------------------------- compiler

function Find-AlExtensionDirs {
    $homeDir = [Environment]::GetFolderPath('UserProfile')
    $dirs = @()
    foreach ($base in @('.vscode', '.vscode-insiders', '.vscode-server')) {
        $ext = Join-Path (Join-Path $homeDir $base) 'extensions'
        if (Test-Path -LiteralPath $ext) {
            $dirs += @(Get-ChildItem -LiteralPath $ext -Directory -Filter 'ms-dynamics-smb.al-*' -ErrorAction SilentlyContinue)
        }
    }
    # Newest extension first, by its version suffix.
    return @($dirs | Sort-Object -Descending -Property @{ Expression = {
        $v = $_.Name -replace '^ms-dynamics-smb\.al-', ''
        try { [version]$v } catch { [version]'0.0' } } })
}

$extDirs = Find-AlExtensionDirs
if (-not $AlcPath -and $env:ALRIG_ALC) { $AlcPath = $env:ALRIG_ALC }
if (-not $AlcPath) {
    # The native build for this OS first: an extension can ship several.
    $onWindows = ($env:OS -eq 'Windows_NT')
    $onMac = (-not $onWindows) -and (Test-Path -LiteralPath '/System/Library/CoreServices')
    if ($onWindows) { $candidates = @('bin/win32/alc.exe', 'bin/alc.exe') }
    elseif ($onMac) { $candidates = @('bin/darwin/alc', 'bin/alc') }
    else { $candidates = @('bin/linux/alc', 'bin/alc') }
    foreach ($d in $extDirs) {
        foreach ($c in $candidates) {
            $p = Join-Path $d.FullName $c
            if (Test-Path -LiteralPath $p) { $AlcPath = $p; break }
        }
        if ($AlcPath) { break }
    }
}
if (-not $AlcPath -or -not (Test-Path -LiteralPath $AlcPath)) {
    Out-Result @{ status = 'UNVERIFIED'; reason = 'no AL compiler found: install the AL Language extension, or pass -AlcPath / set ALRIG_ALC' }
}
$analyzerFolder = Split-Path -Parent $AlcPath
$cop = Get-ChildItem -LiteralPath (Split-Path -Parent $analyzerFolder) -Recurse -Filter 'Microsoft.Dynamics.Nav.CodeCop.dll' -ErrorAction SilentlyContinue | Select-Object -First 1
if ($cop) { $analyzerFolder = $cop.DirectoryName }

# ---------------------------------------------------------------- settings

$repoRoot = $app
$top = @(Invoke-AlrigGit $app rev-parse --show-toplevel)
if ($top.Count) { $repoRoot = (Resolve-Path -LiteralPath $top[0]).Path }

$settings = $null
$settingsDir = $null
foreach ($dir in @($app, $repoRoot)) {
    $s = Join-Path $dir '.vscode/settings.json'
    if (Test-Path -LiteralPath $s) {
        # An unreadable settings file must not quietly become "no analyzers, all clear".
        try { $settings = Read-AlrigJsonc $s; $settingsDir = $dir; break }
        catch { Out-Result @{ status = 'UNVERIFIED'; reason = "settings.json unreadable at ${s}: $($_.Exception.Message) - analyzers and ruleset unknown; fix it or pass -Analyzers and -RuleSet" } }
    }
}
function Get-Setting($name) {
    if ($settings -and ($settings.PSObject.Properties.Name -contains $name)) { return $settings.$name }
    return $null
}
function Expand-Token([string]$value) {
    $v = $value.Replace('${workspaceFolder}', $settingsDir).Replace('${analyzerFolder}', ($analyzerFolder + [IO.Path]::DirectorySeparatorChar))
    foreach ($n in 'CodeCop', 'AppSourceCop', 'UICop', 'PerTenantExtensionCop') {
        $v = $v.Replace('${' + $n + '}', (Join-Path $analyzerFolder "Microsoft.Dynamics.Nav.$n.dll"))
    }
    if (-not [IO.Path]::IsPathRooted($v) -and $settingsDir) { $v = Join-Path $settingsDir $v }
    return $v
}

$analyzerDlls = @()
$missing = @()
# `-File` hands a comma list over as one string.
if ($Analyzers) { $Analyzers = @($Analyzers | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }
if ($Analyzers) {
    foreach ($a in $Analyzers) {
        if ($a -match '\.dll$') { $analyzerDlls += (Expand-Token $a) }
        else { $analyzerDlls += (Join-Path $analyzerFolder "Microsoft.Dynamics.Nav.$a.dll") }
    }
} elseif (Get-Setting 'al.codeAnalyzers') {
    foreach ($a in @(Get-Setting 'al.codeAnalyzers')) { $analyzerDlls += (Expand-Token ([string]$a)) }
}
$analyzerDlls = @($analyzerDlls | Where-Object {
    if (Test-Path -LiteralPath $_) { $true } else { $script:missing += $_; $false } })

if (-not $RuleSet -and (Get-Setting 'al.ruleSetPath')) { $RuleSet = Expand-Token ([string](Get-Setting 'al.ruleSetPath')) }
if ($RuleSet -and -not (Test-Path -LiteralPath $RuleSet)) { $missing += $RuleSet; $RuleSet = $null }

if (-not $PackageCachePath -and (Get-Setting 'al.packageCachePath')) {
    $pc = @(Get-Setting 'al.packageCachePath')[0]
    # Expand-Token resolves ${workspaceFolder} and roots a relative path at the settings folder.
    $PackageCachePath = Expand-Token ([string]$pc)
}
if (-not $PackageCachePath) { $PackageCachePath = Join-Path $app '.alpackages' }
if (-not (Test-Path -LiteralPath $PackageCachePath) -or
    -not (Get-ChildItem -LiteralPath $PackageCachePath -Filter '*.app' -ErrorAction SilentlyContinue)) {
    Out-Result @{ status = 'UNVERIFIED'; reason = "no symbol packages in $PackageCachePath - download symbols first (VS Code: AL: Download symbols, or the al MCP server)" }
}

# ---------------------------------------------------------------- compile

if (-not $OutDir) { $OutDir = Join-Path ([IO.Path]::GetTempPath()) ('alrig-scan-' + [guid]::NewGuid().ToString('N').Substring(0, 8)) }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$errorLog = Join-Path $OutDir 'errorlog.json'

$argList = @("/project:$app", "/packagecachepath:$PackageCachePath", ('/out:' + (Join-Path $OutDir 'scan.app')),
    "/errorlog:$errorLog", '/generatereportlayout-', '/continuebuildonerror+')
foreach ($d in $analyzerDlls) { $argList += "/analyzer:$d" }
if ($RuleSet) { $argList += "/ruleset:$RuleSet" }
if ($ReportSuppressed) { $argList += '/reportsuppresseddiagnostics' }

# Windows PowerShell turns any stderr line into a terminating error under Stop.
$ErrorActionPreference = 'Continue'
$stdout = & $AlcPath @argList 2>&1 | ForEach-Object { [string]$_ }
$exit = $LASTEXITCODE
$ErrorActionPreference = 'Stop'
$stdout | Set-Content -LiteralPath (Join-Path $OutDir 'alc-output.txt') -Encoding UTF8

# ---------------------------------------------------------------- parse

$findings = New-Object System.Collections.Generic.List[object]
$seen = @{}
function Add-Finding($file, $line, $sev, $rule, $msg) {
    if (-not $rule) { return }
    $rel = [string]$file
    if ($rel -and $rel.StartsWith($repoRoot, [StringComparison]::OrdinalIgnoreCase)) { $rel = $rel.Substring($repoRoot.Length).TrimStart('\', '/') }
    $rel = $rel -replace '\\', '/'
    $key = "$rel|$line|$rule|$msg"
    if ($script:seen.ContainsKey($key)) { return }
    $script:seen[$key] = $true
    $script:findings.Add([pscustomobject]@{ file = $rel; line = [int]$line; severity = ([string]$sev).ToLowerInvariant(); rule = $rule; message = $msg })
}

# The error log is authoritative: it carries info-level and suppressed diagnostics the console
# does not show. The console is parsed only when there is no usable log.
$suppressed = 0
$logParsed = $false
if (Test-Path -LiteralPath $errorLog) {
    try {
        $log = Get-Content -LiteralPath $errorLog -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($log.PSObject.Properties.Name -contains 'issues') {
            $logParsed = $true
            foreach ($i in @($log.issues)) {
                $file = $null; $line = 0
                try { $loc = $i.locations[0].analysisTarget[0]; $file = $loc.uri; $line = $loc.region.startLine } catch { }
                $sev = 'warning'; try { $sev = $i.properties.severity } catch { }
                try { if ($i.properties.isSuppressedInSource -eq 'True') { $suppressed++; continue } } catch { }
                $msg = ''
                foreach ($p in 'fullMessage', 'shortMessage') {
                    if (-not $msg -and $i.PSObject.Properties.Name -contains $p) { $msg = [string]$i.$p }
                }
                Add-Finding $file $line $sev $i.ruleId $msg
            }
        } elseif ($log.PSObject.Properties.Name -contains 'runs') {
            $logParsed = $true
            foreach ($r in @($log.runs[0].results)) {
                $file = $null; $line = 0
                try { $pl = $r.locations[0].physicalLocation; $file = $pl.artifactLocation.uri; $line = $pl.region.startLine } catch { }
                $lvl = 'warning'; if ($r.level -eq 'error') { $lvl = 'error' } elseif ($r.level -eq 'note') { $lvl = 'info' }
                Add-Finding $file $line $lvl $r.ruleId ([string]$r.message.text)
            }
        }
    } catch { $logParsed = $false }
}
if (-not $logParsed) {
    # <file>(<line>,<col>[,<endline>,<endcol>]): <severity> <RULE>: <message>
    foreach ($l in $stdout) {
        $m = [regex]::Match($l, '^(?<file>.+?)\((?<line>\d+),\d+(?:,\d+,\d+)?\):\s*(?<sev>error|warning|info)\s+(?<rule>[A-Za-z]+\d+):\s*(?<msg>.*)$')
        if ($m.Success) { Add-Finding $m.Groups['file'].Value $m.Groups['line'].Value $m.Groups['sev'].Value $m.Groups['rule'].Value $m.Groups['msg'].Value.Trim() }
    }
}

function Get-Source([string]$rule) {
    switch -regex ($rule) {
        '^AA' { 'CodeCop'; break }
        '^AS' { 'AppSourceCop'; break }
        '^AW' { 'UICop'; break }
        '^PTE' { 'PerTenantExtensionCop'; break }
        '^AL' { 'compiler'; break }
        '^LC' { 'LinterCop'; break }
        default { 'third-party' }
    }
}

$bySeverity = [ordered]@{ error = 0; warning = 0; info = 0 }
foreach ($f in $findings) { if ($bySeverity.Contains($f.severity)) { $bySeverity[$f.severity]++ } }
$byRule = @($findings | Group-Object rule | Sort-Object Count -Descending | ForEach-Object {
    $first = $_.Group[0]
    [pscustomobject]@{ rule = $_.Name; source = (Get-Source $_.Name); severity = $first.severity; count = $_.Count; example = $first.message }
})
$bySource = [ordered]@{}
foreach ($r in $byRule) { if (-not $bySource.Contains($r.source)) { $bySource[$r.source] = 0 }; $bySource[$r.source] += $r.count }

$findings | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $OutDir 'findings.json') -Encoding UTF8

$status = 'OK'
$reason = $null
if ($exit -ne 0 -or $bySeverity.error -gt 0) { $status = 'ERRORS' }
# A missing symbol package means the analyzers never saw a resolvable program: every other
# number in this report is a floor, not a count.
if (@($findings | Where-Object { $_.rule -eq 'AL1022' }).Count -gt 0) {
    $status = 'UNVERIFIED'; $reason = "symbol packages missing from $PackageCachePath (AL1022) - download symbols and rerun"
}
Out-Result ([ordered]@{
    status = $status
    reason = $reason
    suppressedInSource = $suppressed
    compilerExitCode = $exit
    compiler = $AlcPath
    analyzers = @($analyzerDlls | ForEach-Object { [IO.Path]::GetFileNameWithoutExtension($_) })
    missing = @($missing)
    ruleset = $RuleSet
    counts = $bySeverity
    bySource = $bySource
    byRule = $byRule
    findings = @($findings | Sort-Object @{ Expression = { @{ error = 0; warning = 1; info = 2 }[$_.severity] } }, file, line | Select-Object -First $MaxFindings)
    truncated = ($findings.Count -gt $MaxFindings)
    outDir = $OutDir
})
