<#
.SYNOPSIS
  Scan a repository for committed credentials with gitleaks, or a built-in fallback.

.DESCRIPTION
  gitleaks (https://github.com/gitleaks/gitleaks) scans the git history by default, because a
  secret removed in a later commit is still published. -NoHistory scans only the working tree.
  The configuration is the repository's own .gitleaks.toml when it has one, else the one
  shipped with ALRIG (gitleaks' defaults plus AL rules). Output is always redacted.

  Without gitleaks, a built-in scan of the tracked files runs instead. It has fewer rules and
  no history, and the result says engine = builtin so nobody mistakes it for the real thing.

  -ReportDir writes a dated Markdown report there. The directory must already exist; this
  script never creates one. Without it, nothing is written.

  Prints one JSON object. Never prints a secret.
#>
[CmdletBinding()]
param(
    [string]$Root = '.',
    [string]$ReportDir,
    [string]$Config,
    [switch]$NoHistory,
    [switch]$FailOnFindings
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'AlrigSecurity.psm1') -Force
$Root = (Resolve-Path -LiteralPath $Root).Path

if ($ReportDir -and -not (Test-Path -LiteralPath $ReportDir -PathType Container)) {
    throw "ReportDir '$ReportDir' does not exist. Point it at an existing directory; it is never created."
}

$isGit = $false
$isGit = (@(Invoke-AlrigGit $Root rev-parse --is-inside-work-tree).Count -gt 0)

$result = [ordered]@{ engine = $null; engineVersion = $null; mode = $null; config = $null; findings = @(); report = $null; notes = @() }
$findings = New-Object System.Collections.Generic.List[object]

$gitleaks = Get-Command gitleaks -ErrorAction SilentlyContinue
if ($gitleaks) {
    $ErrorActionPreference = 'Continue'
    $ver = ((& gitleaks version 2>$null) | Out-String).Trim().TrimStart('v')
    $ErrorActionPreference = 'Stop'
    $result.engine = 'gitleaks'; $result.engineVersion = $ver
    $modern = $false
    try { $modern = ([version]($ver -replace '[^0-9.].*$', '')) -ge [version]'8.19' } catch { }

    if (-not $Config) {
        $own = Join-Path $Root '.gitleaks.toml'
        if (Test-Path -LiteralPath $own) { $Config = $own }
        else { $Config = Join-Path (Split-Path -Parent $PSScriptRoot) 'config/gitleaks-al.toml' }
    }
    $result.config = $Config

    function Invoke-GitleaksPass([bool]$History) {
        # One gitleaks run. History = commits (`git log -p`); otherwise the files on disk, which
        # is the only way to see uncommitted and untracked work.
        $tmp = Join-Path ([IO.Path]::GetTempPath()) ('alrig-gitleaks-' + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.json')
        $common = @('--redact', '--no-banner', '--report-format', 'json', '--report-path', $tmp, '--config', $Config, '--exit-code', '0')
        if ($History) {
            if ($modern) { $gargs = @('git') + $common + @($Root) } else { $gargs = @('detect', '--source', $Root) + $common }
        } else {
            if ($modern) { $gargs = @('dir') + $common + @($Root) } else { $gargs = @('detect', '--no-git', '--source', $Root) + $common }
        }
        # gitleaks logs to stderr; Windows PowerShell would turn that into a terminating error.
        $ErrorActionPreference = 'Continue'
        $log = & gitleaks @gargs 2>&1 | ForEach-Object { [string]$_ }
        $code = $LASTEXITCODE
        $ErrorActionPreference = 'Stop'
        if ($code -ne 0) { throw "gitleaks exited ${code}: $(($log | Select-Object -Last 3) -join ' ')" }
        $found = @()
        if (Test-Path -LiteralPath $tmp) {
            $raw = Get-Content -LiteralPath $tmp -Raw -Encoding UTF8
            Remove-Item -LiteralPath $tmp -Force
            if ($raw -and $raw.Trim()) {
                # 5.1 emits a JSON array as one object: enumerate the parsed value, never wrap it in @().
                $parsed = $raw | ConvertFrom-Json
                foreach ($g in $parsed) {
                    $commit = $null
                    if ($g.PSObject.Properties.Name -contains 'Commit' -and $g.Commit) { $commit = ([string]$g.Commit).Substring(0, [Math]::Min(12, ([string]$g.Commit).Length)) }
                    $date = $null
                    if ($g.PSObject.Properties.Name -contains 'Date' -and $g.Date) { $date = [string]$g.Date }
                    $file = ([string]$g.File) -replace '\\', '/'
                    $rootFwd = ($Root -replace '\\', '/').TrimEnd('/')
                    if ($file.StartsWith($rootFwd, [StringComparison]::OrdinalIgnoreCase)) { $file = $file.Substring($rootFwd.Length).TrimStart('/') }
                    if ($file -match '^\.git/') { continue }
                    $found += [pscustomobject]@{
                        rule = [string]$g.RuleID; file = $file; line = [int]$g.StartLine
                        inTree = (-not $History); commit = $commit; date = $date; fingerprint = [string]$g.Fingerprint
                    }
                }
            }
        }
        return ,$found
    }

    # The working tree is always scanned. History is added unless -NoHistory or not a git repo.
    $tree = Invoke-GitleaksPass $false
    foreach ($f in $tree) { $findings.Add($f) }
    if ($isGit -and -not $NoHistory) {
        $result.mode = 'working-tree+git-history'
        foreach ($h in (Invoke-GitleaksPass $true)) {
            # Still in the tree at the same place: one finding, with the commit that added it.
            $same = @($tree | Where-Object { $_.file -eq $h.file -and $_.rule -eq $h.rule -and $_.line -eq $h.line })
            if ($same.Count) { foreach ($s in $same) { if (-not $s.commit) { $s.commit = $h.commit; $s.date = $h.date } } }
            else { $findings.Add($h) }
        }
    } else {
        $result.mode = 'working-tree'
    }
} else {
    $result.engine = 'builtin'; $result.mode = 'working-tree'
    $result.notes += 'gitleaks is not installed: built-in patterns only, tracked and new files only, no git history. Install gitleaks for a real scan.'
    if ($isGit) {
        $files = @(foreach ($p in @(Invoke-AlrigGit $Root ls-files --cached --others --exclude-standard)) { if ($p) { Join-Path $Root $p } })
    } else {
        $files = @(Get-ChildItem -LiteralPath $Root -Recurse -File | ForEach-Object { $_.FullName })
    }
    $textExt = '\.(al|json|jsonc|xml|xlf|ps1|psm1|psd1|yml|yaml|config|txt|md|cs|js|ts|env|ini|toml|sh|cmd|bat)$'
    foreach ($f in $files) {
        if ($f -notmatch $textExt -or $f -match '[\\/](?:\.alpackages|\.snapshots|\.output)[\\/]' -or $f -match '\.g\.xlf$') { continue }
        if (-not (Test-Path -LiteralPath $f -PathType Leaf)) { continue }
        # A multi-megabyte text file is generated or data; reading it whole is the cost of a hang.
        if ((Get-Item -LiteralPath $f).Length -gt 2MB) { $result.notes += "skipped (over 2 MB): $f"; continue }
        $text = $null
        try { $text = [IO.File]::ReadAllText($f) } catch { continue }
        if ($text.IndexOf([char]0) -ge 0) { continue }   # binary
        foreach ($s in (Find-AlrigSecrets $text -Plain:($f -notmatch '\.al$'))) {
            $rel = $f.Substring($Root.Length).TrimStart('\', '/') -replace '\\', '/'
            $findings.Add([pscustomobject]@{ rule = $s.Rule; file = $rel; line = $s.Line; inTree = $true; commit = $null; date = $null; fingerprint = $null })
        }
    }
}

# Anything still in the working tree first: that is what a release would ship.
$result.findings = @($findings | Sort-Object @{ Expression = { -not $_.inTree } }, file, line)

if ($ReportDir) {
    $stamp = Get-Date -Format 'yyyy-MM-dd'
    $path = Join-Path $ReportDir "secret-scan-$stamp.md"
    if (Test-Path -LiteralPath $path) { $path = Join-Path $ReportDir ("secret-scan-$stamp-" + (Get-Date -Format 'HHmm') + '.md') }
    $md = New-Object System.Collections.Generic.List[string]
    $md.Add("# Secret scan - $stamp"); $md.Add('')
    $md.Add("- Engine: $($result.engine) $($result.engineVersion)")
    $md.Add("- Scope: $($result.mode)")
    if ($result.config) { $md.Add("- Configuration: $([IO.Path]::GetFileName($result.config))") }
    $md.Add("- Findings: $($findings.Count)")
    foreach ($n in $result.notes) { $md.Add("- Note: $n") }
    $md.Add(''); $md.Add('Values are redacted. A finding in history stays published until the credential is rotated;')
    $md.Add('removing it from the tree does not un-leak it.'); $md.Add('')
    if ($findings.Count -gt 0) {
        $md.Add('| Rule | File | Line | Where | Commit | Date |'); $md.Add('|---|---|---|---|---|---|')
        foreach ($f in $result.findings) { $w = 'history only'; if ($f.inTree) { $w = 'working tree' }; $md.Add("| $($f.rule) | $($f.file) | $($f.line) | $w | $($f.commit) | $($f.date) |") }
    } else { $md.Add('No findings.') }
    $md | Set-Content -LiteralPath $path -Encoding UTF8
    $result.report = $path
}

$result | ConvertTo-Json -Depth 5
if ($FailOnFindings -and $findings.Count -gt 0) { exit 1 }
exit 0
