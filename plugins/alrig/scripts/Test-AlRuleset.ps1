<#
.SYNOPSIS
  Check that an AL ruleset has not been weakened, and audit in-source suppressions.

.DESCRIPTION
  Resolves the ruleset's includedRuleSets chain and computes each rule's effective action
  (an included set's own action overrides its rules unless it is Default; the including file's
  rules override both).

  With -Baseline - typically a shared ruleset the project's own ruleset includes - every rule
  the baseline sets is compared: the project may raise a rule's severity but not lower it, and
  the baseline must actually be in the include chain.

  With -Root, every #pragma warning disable in .al files under it is listed, and those with no
  rule ID (which disable everything) or no reason comment are flagged.

  Prints one JSON object. blocking is true when a baseline rule is weakened, the baseline is
  not included, an include does not resolve, generalAction silences unlisted rules, or a
  blanket pragma exists. -FailOnBlocking turns that into exit code 1, for CI.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$RuleSet,
    [string]$Baseline,
    [string]$Root,
    [switch]$FailOnBlocking
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'AlrigSecurity.psm1') -Force

$rank = @{ 'error' = 4; 'warning' = 3; 'info' = 2; 'hidden' = 1; 'none' = 0 }
function Get-Rank([string]$action) {
    if (-not $action) { return $null }
    $a = $action.ToLowerInvariant()
    if ($rank.ContainsKey($a)) { return $rank[$a] }
    return $null   # Default: the analyzer's own severity, which this script cannot know.
}

$findings = New-Object System.Collections.Generic.List[object]
function Add-Finding($kind, $blocking, $detail) {
    $script:findings.Add([pscustomobject]@{ kind = $kind; blocking = [bool]$blocking; detail = $detail })
}

function Resolve-RuleSet {
    # Returns @{ chain = [paths]; rules = @{ id -> @{ action; from; justification } }; general = action }
    # $Stack holds the rulesets on the current include path only, so a diamond (two sets that
    # both include one base) is fine and only a real cycle is reported.
    param([string]$Path, [hashtable]$Stack)
    $full = (Resolve-Path -LiteralPath $Path).Path
    $key = $full.ToLowerInvariant()
    $result = @{ chain = @($full); rules = @{}; general = $null }
    if ($Stack.ContainsKey($key)) {
        Add-Finding 'include-cycle' $true "ruleset $full includes itself"
        return $result
    }
    try { $json = Read-AlrigJsonc $full }
    catch {
        Add-Finding 'ruleset-unreadable' $true "$full does not parse - none of its rules apply: $($_.Exception.Message)"
        return $result
    }
    $Stack[$key] = $true
    try {
    $dir = Split-Path -Parent $full

    if ($json.PSObject.Properties.Name -contains 'includedRuleSets') {
        foreach ($inc in @($json.includedRuleSets)) {
            $incPath = [string]$inc.path
            if ($incPath -match '^https?://') {
                Add-Finding 'include-remote' $false "include $incPath is a URL; its rules are not checked here"
                continue
            }
            $p = $incPath
            if (-not [IO.Path]::IsPathRooted($p)) { $p = Join-Path $dir $p }
            if (-not (Test-Path -LiteralPath $p)) {
                Add-Finding 'include-unresolved' $true "$full includes '$incPath', which does not exist - the rules it carries are not being applied"
                continue
            }
            $sub = Resolve-RuleSet $p $Stack
            $result.chain += $sub.chain
            $override = $null
            if ($inc.PSObject.Properties.Name -contains 'action' -and $inc.action -and $inc.action -ne 'Default') { $override = [string]$inc.action }
            foreach ($k in $sub.rules.Keys) {
                $r = $sub.rules[$k]
                if ($override) { $r = @{ action = $override; from = $full; justification = "include action on $incPath" } }
                $result.rules[$k] = $r
            }
        }
    }
    if ($json.PSObject.Properties.Name -contains 'rules') {
        foreach ($r in @($json.rules)) {
            $j = $null
            if ($r.PSObject.Properties.Name -contains 'justification') { $j = [string]$r.justification }
            $result.rules[[string]$r.id] = @{ action = [string]$r.action; from = $full; justification = $j }
        }
    }
    if ($json.PSObject.Properties.Name -contains 'generalAction' -and $json.generalAction) { $result.general = [string]$json.generalAction }
    }
    finally { $Stack.Remove($key) }
    return $result
}

$project = Resolve-RuleSet $RuleSet @{}

# Rules switched off in the effective set.
$disabled = @()
foreach ($k in ($project.rules.Keys | Sort-Object)) {
    $r = $project.rules[$k]
    $rk = Get-Rank $r.action
    if ($rk -ne $null -and $rk -le 1) {
        $disabled += [pscustomobject]@{ rule = $k; action = $r.action; from = $r.from; justification = $r.justification }
        if (-not $r.justification) { Add-Finding 'disabled-without-justification' $false "$k is $($r.action) in $($r.from) with no justification" }
    }
}
if ($project.general) {
    $g = Get-Rank $project.general
    if ($g -ne $null -and $g -le 1) { Add-Finding 'general-action-silences' $true "generalAction is $($project.general): every rule not listed is silenced" }
}

# Baseline: nothing it sets may be weakened.
$weakened = @()
if ($Baseline -and -not [IO.Path]::IsPathRooted($Baseline)) {
    # The profile records the baseline relative to the repository root, not to wherever this
    # script happens to be run from.
    $top = @(Invoke-AlrigGit (Split-Path -Parent (Resolve-Path -LiteralPath $RuleSet).Path) rev-parse --show-toplevel)
    if ($top.Count) { $Baseline = Join-Path $top[0] $Baseline }
}
if ($Baseline -and -not (Test-Path -LiteralPath $Baseline)) {
    Add-Finding 'baseline-missing' $true "the baseline ruleset $Baseline does not exist - weakening could not be checked"
    $Baseline = $null
}
if ($Baseline) {
    $base = Resolve-RuleSet $Baseline @{}
    $baseFull = (Resolve-Path -LiteralPath $Baseline).Path
    $included = @($project.chain | Where-Object { $_ -ieq $baseFull }).Count -gt 0
    if (-not $included) {
        Add-Finding 'baseline-not-included' $true "the project ruleset does not include $baseFull - none of its rules are enforced by the build"
    }
    foreach ($k in $base.rules.Keys) {
        $want = Get-Rank $base.rules[$k].action
        if ($want -eq $null) { continue }
        if (-not $project.rules.ContainsKey($k)) {
            if (-not $included) { $weakened += [pscustomobject]@{ rule = $k; baseline = $base.rules[$k].action; effective = '(absent)' } }
            continue
        }
        $have = Get-Rank $project.rules[$k].action
        if ($have -eq $null -or $have -lt $want) {
            $weakened += [pscustomobject]@{ rule = $k; baseline = $base.rules[$k].action; effective = $project.rules[$k].action; from = $project.rules[$k].from }
        }
    }
    foreach ($w in $weakened) { Add-Finding 'baseline-weakened' $true "$($w.rule): baseline $($w.baseline), effective $($w.effective)" }
}

# In-source suppressions.
$pragmas = @()
if ($Root) {
    foreach ($f in (Get-AlrigAlFiles $Root)) {
        $n = 0
        foreach ($line in [IO.File]::ReadAllLines($f.FullName)) {
            $n++
            $m = [regex]::Match($line, '^\s*#pragma\s+warning\s+disable\b(?<rest>.*)$', 'IgnoreCase')
            if (-not $m.Success) { continue }
            # Comments of either kind are the reason; what is left is the rule list. A pragma
            # whose only argument is a /* comment */ is still a blanket disable.
            $rest = $m.Groups['rest'].Value
            $why = (@([regex]::Matches($rest, '/\*(.*?)\*/|//(.*)$') | ForEach-Object { ($_.Groups[1].Value + $_.Groups[2].Value).Trim() }) -join ' ').Trim()
            $ids = ([regex]::Replace($rest, '/\*.*?\*/|//.*$', '')).Trim().TrimEnd(',').Trim()
            $rel = $f.FullName.Substring((Resolve-Path -LiteralPath $Root).Path.Length).TrimStart('\', '/') -replace '\\', '/'
            $pragmas += [pscustomobject]@{ file = $rel; line = $n; rules = $ids; reason = $why }
            if (-not $ids) { Add-Finding 'blanket-pragma' $true "${rel}:$n disables every warning" }
            elseif (-not $why) { Add-Finding 'pragma-without-reason' $false "${rel}:$n disables $ids with no reason" }
        }
    }
}

$blocking = @($findings | Where-Object { $_.blocking }).Count -gt 0
[ordered]@{
    ruleset = (Resolve-Path -LiteralPath $RuleSet).Path
    chain = $project.chain
    effectiveRules = $project.rules.Count
    generalAction = $project.general
    baseline = $Baseline
    weakened = $weakened
    disabled = $disabled
    pragmas = $pragmas
    findings = $findings
    blocking = $blocking
} | ConvertTo-Json -Depth 6

if ($FailOnBlocking -and $blocking) { exit 1 }
exit 0
