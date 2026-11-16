<#
.SYNOPSIS
  Mechanical pre-release checks for one AL app: version bump, manifest identity, ID ranges,
  XLIFF completeness, and how secrets are held and handled.

.DESCRIPTION
  Each section reports status OK, GAP or UNVERIFIED with its details. The script decides
  nothing a human should: it does not know whether a missing EULA matters for a per-tenant
  extension, or whether a field named "Token" holds a secret. The release-check skill reads
  this output and makes those calls.

  -BaseRef is what this release is compared against: the last release tag by default, else
  origin/main, else main.

  Prints one JSON object. Writes nothing.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$AppPath,
    [string]$BaseRef
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'AlrigSecurity.psm1') -Force

$app = (Resolve-Path -LiteralPath $AppPath).Path
$manifestPath = Join-Path $app 'app.json'
$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
function Has($obj, $name) { return ($obj -and ($obj.PSObject.Properties.Name -contains $name) -and $obj.$name) }

$repoRoot = $null
$t = @(Invoke-AlrigGit $app rev-parse --show-toplevel)
if ($t.Count) { $repoRoot = (Resolve-Path -LiteralPath $t[0]).Path }
$alrigProfile = $null
if ($repoRoot) { $alrigProfile = Get-AlrigProfile $repoRoot }

$sections = [ordered]@{}
function Section($name, $status, $details) { $script:sections[$name] = [ordered]@{ status = $status; details = $details } }

# ---------------------------------------------------------------- 1 version and identity

$base = $null
if ($repoRoot) {
    $refs = @()
    if ($BaseRef) { $refs = @($BaseRef) }
    else {
        $tag = @(Invoke-AlrigGit $repoRoot describe --tags --abbrev=0)
        if ($tag.Count) { $refs += $tag[0] }
        $refs += 'origin/main', 'main', 'origin/master', 'master'
    }
    $relManifest = ($manifestPath.Substring($repoRoot.Length).TrimStart('\', '/')) -replace '\\', '/'
    foreach ($r in $refs) {
        $content = @(Invoke-AlrigGit $repoRoot show "${r}:$relManifest")
        if ($content.Count) {
            try { $base = @{ ref = $r; manifest = (($content -join "`n") | ConvertFrom-Json) }; break } catch { }
        }
    }
}
if (-not $base) {
    Section 'version' 'UNVERIFIED' @{ current = $manifest.version; reason = 'no base to compare against: no release tag, no main branch, or the app is new' }
    Section 'identity' 'UNVERIFIED' @{ reason = 'no base manifest' }
} else {
    # [version] rejects a one-part version and anything malformed in an old manifest; that is
    # an unverifiable comparison, not a crash.
    $cur = $null; $old = $null
    try { $cur = [version]([string]$manifest.version) } catch { }
    try { $old = [version]([string]$base.manifest.version) } catch { }
    if (-not $cur -or -not $old) {
        Section 'version' 'UNVERIFIED' @{ base = $base.ref; previous = $base.manifest.version; current = $manifest.version; reason = 'a version is not in major.minor[.build[.revision]] form' }
    } else {
        $vstatus = 'OK'; if ($cur -le $old) { $vstatus = 'GAP' }
        Section 'version' $vstatus @{ base = $base.ref; previous = $base.manifest.version; current = $manifest.version }
    }

    $changed = @()
    foreach ($k in 'id', 'name', 'publisher') {
        if ((Has $base.manifest $k) -and ([string]$base.manifest.$k -ne [string]$manifest.$k)) {
            $changed += [ordered]@{ field = $k; previous = $base.manifest.$k; current = $manifest.$k }
        }
    }
    $istatus = 'OK'; if ($changed.Count) { $istatus = 'GAP' }
    Section 'identity' $istatus @{ changed = $changed; note = 'a changed id is a different app to every tenant that has it installed' }
}

# ---------------------------------------------------------------- 2 manifest fields

$fields = 'id', 'name', 'publisher', 'version', 'brief', 'description', 'privacyStatement', 'EULA', 'help', 'url', 'logo', 'application', 'platform', 'runtime', 'idRanges'
$missing = @($fields | Where-Object { -not (Has $manifest $_) })
if (-not (Has $manifest 'idRanges') -and (Has $manifest 'idRange')) { $missing = @($missing | Where-Object { $_ -ne 'idRanges' }) }
$features = @(); if (Has $manifest 'features') { $features = @($manifest.features) }
$mstatus = 'OK'; if ($missing.Count) { $mstatus = 'GAP' }
Section 'manifest' $mstatus @{ missing = $missing; target = $(if (Has $manifest 'target') { $manifest.target } else { 'Cloud' }); runtime = $manifest.runtime; features = $features }

# ---------------------------------------------------------------- 3 ID ranges

$ranges = @()
if (Has $manifest 'idRanges') { foreach ($r in @($manifest.idRanges)) { $ranges += , @([int]$r.from, [int]$r.to) } }
elseif (Has $manifest 'idRange') { $ranges += , @([int]$manifest.idRange.from, [int]$manifest.idRange.to) }

$objRegex = '^\s*(?<type>table|tableextension|page|pageextension|codeunit|report|reportextension|query|xmlport|enum|enumextension|permissionset|permissionsetextension)\s+(?<id>\d+)\s+(?<name>"[^"]+"|\w+)'
$objects = @()
$alFiles = Get-AlrigAlFiles $app
foreach ($f in $alFiles) {
    $n = 0
    foreach ($line in [IO.File]::ReadAllLines($f.FullName)) {
        $n++
        $m = [regex]::Match($line, $objRegex, 'IgnoreCase')
        if ($m.Success) {
            $objects += [pscustomobject]@{ type = $m.Groups['type'].Value.ToLowerInvariant(); id = [int]$m.Groups['id'].Value; name = $m.Groups['name'].Value.Trim('"'); file = ($f.FullName.Substring($app.Length).TrimStart('\', '/') -replace '\\', '/'); line = $n }
        }
    }
}
$outside = @($objects | Where-Object { $o = $_; -not ($ranges | Where-Object { $o.id -ge $_[0] -and $o.id -le $_[1] }) })
$dupes = @($objects | Group-Object type, id | Where-Object { $_.Count -gt 1 } | ForEach-Object { [ordered]@{ object = $_.Name; files = @($_.Group | ForEach-Object { $_.file }) } })
$usage = @($ranges | ForEach-Object { $r = $_; $used = @($objects | Where-Object { $_.id -ge $r[0] -and $_.id -le $r[1] } | Select-Object -ExpandProperty id -Unique).Count
    [ordered]@{ range = "$($r[0])..$($r[1])"; used = $used; size = ($r[1] - $r[0] + 1) } })
$rstatus = 'OK'; if ($outside.Count -or $dupes.Count -or -not $ranges.Count) { $rstatus = 'GAP' }
Section 'idRanges' $rstatus @{ objects = $objects.Count; outside = $outside; duplicates = $dupes; usage = $usage }

# ---------------------------------------------------------------- 4 XLIFF

$transDir = Join-Path $app 'Translations'
if ($features -notcontains 'TranslationFile') {
    Section 'xliff' 'OK' @{ note = 'TranslationFile feature is off: no XLIFF is generated, so there is nothing to translate' }
} else {
    $gxlf = @(Get-ChildItem -LiteralPath $transDir -Filter '*.g.xlf' -ErrorAction SilentlyContinue)
    if (-not $gxlf.Count) {
        Section 'xliff' 'UNVERIFIED' @{ reason = 'TranslationFile is on but no .g.xlf exists - build the app to generate it, then rerun' }
    } else {
        function Read-Units($path) {
            $x = New-Object System.Xml.XmlDocument; $x.PreserveWhitespace = $false; $x.Load($path)
            $ns = New-Object System.Xml.XmlNamespaceManager($x.NameTable); $ns.AddNamespace('x', 'urn:oasis:names:tc:xliff:document:1.2')
            $units = @{}
            foreach ($u in $x.SelectNodes('//x:trans-unit', $ns)) {
                $t = $u.SelectSingleNode('x:target', $ns)
                $state = $null; $text = $null
                if ($t) { $text = $t.InnerText; if ($t.Attributes['state']) { $state = $t.Attributes['state'].Value } }
                $units[$u.GetAttribute('id')] = @{ target = $text; state = $state }
            }
            return $units
        }
        $gen = Read-Units $gxlf[0].FullName
        $langs = @()
        foreach ($f in @(Get-ChildItem -LiteralPath $transDir -Filter '*.xlf' | Where-Object { $_.Name -notmatch '\.g\.xlf$' })) {
            $u = Read-Units $f.FullName
            $missingUnits = @($gen.Keys | Where-Object { -not $u.ContainsKey($_) }).Count
            $untranslated = @($u.Keys | Where-Object { $gen.ContainsKey($_) -and (-not $u[$_].target -or $u[$_].state -in 'needs-translation', 'new', 'needs-adaptation') }).Count
            $stale = @($u.Keys | Where-Object { -not $gen.ContainsKey($_) }).Count
            $langs += [ordered]@{ file = $f.Name; missing = $missingUnits; untranslated = $untranslated; obsolete = $stale }
        }
        $xstatus = 'OK'
        if (@($langs | Where-Object { $_.missing -or $_.untranslated }).Count) { $xstatus = 'GAP' }
        Section 'xliff' $xstatus @{ generated = $gxlf[0].Name; units = $gen.Count; languages = $langs; generatedAt = $gxlf[0].LastWriteTime.ToString('s'); note = 'a .g.xlf older than the last source change is stale - rebuild before trusting these counts' }
    }
}

# ---------------------------------------------------------------- 5 secrets and keys

$secretName = '(?i)\b(?<name>\w*(?:password|passwd|passphrase|secret|apikey|api_key|accesskey|privatekey|sharedkey|subscriptionkey|clientsecret|token|credential)\w*)\s*:\s*(?<type>Text|Code|SecretText)\b'
$runtime = $null; try { $runtime = [version]([string]$manifest.runtime) } catch { }
$hasSecretText = ($runtime -and $runtime -ge [version]'12.0')

$hardcoded = @(); $urls = @(); $textHeld = @(); $notNonDebuggable = @(); $tableFields = @(); $isoPlain = @(); $authHeaders = @(); $suppressions = @()
$allow = Get-AlrigUrlAllowlist $alrigProfile
foreach ($f in $alFiles) {
    $rel = $f.FullName.Substring($app.Length).TrimStart('\', '/') -replace '\\', '/'
    $text = [IO.File]::ReadAllText($f.FullName)
    foreach ($s in (Find-AlrigSecrets $text)) { $hardcoded += [ordered]@{ file = $rel; line = $s.Line; rule = $s.Rule; value = $s.Redacted } }
    foreach ($u in (Find-AlrigUrls $text $allow)) { $urls += [ordered]@{ file = $rel; line = $u.Line; host = $u.Host } }
    $lines = $text -split "`r?`n"
    $attrs = @()
    for ($i = 0; $i -lt $lines.Length; $i++) {
        $l = $lines[$i]
        if ($l -match 'alrig:allow-(secret|url)') {
            # The reason only. The rest of the line is the very value being suppressed.
            $kind = $Matches[1]
            $reason = ($l -replace '^.*alrig:allow-(?:secret|url)\s*', '').Trim()
            $suppressions += [ordered]@{ file = $rel; line = $i + 1; kind = $kind; reason = $reason }
        }
        if ($l -match '^\s*\[') { $attrs += $l; continue }
        $isProc = $l -match '^\s*(?:local\s+|internal\s+|protected\s+)?procedure\s+'
        foreach ($m in [regex]::Matches($l, $secretName)) {
            $name = $m.Groups['name'].Value; $type = $m.Groups['type'].Value
            if (Test-AlrigNotASecretName $name) { continue }
            if ($type -ne 'SecretText') { $textHeld += [ordered]@{ file = $rel; line = $i + 1; name = $name; type = $type } }
            if ($isProc -and $type -ne 'SecretText' -and -not ($attrs -match 'NonDebuggable')) {
                $notNonDebuggable += [ordered]@{ file = $rel; line = $i + 1; procedure = ($l.Trim() -replace '\(.*$', '') }
            }
        }
        $fm = [regex]::Match($l, '^\s*field\(\s*\d+\s*;\s*(?<name>"[^"]+"|\w+)\s*;\s*(?<type>Text|Code|Blob)', 'IgnoreCase')
        if ($fm.Success) {
            $fname = $fm.Groups['name'].Value.Trim('"')
            $compact = $fname -replace '[\s_-]', ''
            if ($compact -match '(?i)(password|secret|apikey|accesskey|privatekey|sharedkey|subscriptionkey|token|credential)' -and -not (Test-AlrigNotASecretName $compact)) {
                $tableFields += [ordered]@{ file = $rel; line = $i + 1; field = $fname; type = $fm.Groups['type'].Value }
            }
        }
        if ($l -match '(?i)IsolatedStorage\.Set\s*\(' -and $l -match '(?i)(password|secret|key|token|credential)') {
            $isoPlain += [ordered]@{ file = $rel; line = $i + 1 }
        }
        if ($l -match '(?i)\.Add\s*\(\s*''Authorization''') { $authHeaders += [ordered]@{ file = $rel; line = $i + 1 } }
        # Attributes survive blank lines and comments between them and the procedure.
        if ($l.Trim() -and $l -notmatch '^\s*(?:\[|//)') { $attrs = @() }
    }
}

$manifestSecrets = @()
$manifestText = Get-Content -LiteralPath $manifestPath -Raw
foreach ($s in (Find-AlrigSecrets $manifestText -Plain)) { $manifestSecrets += [ordered]@{ line = $s.Line; rule = $s.Rule } }
$keyVault = @(); if (Has $manifest 'keyVaultUrls') { $keyVault = @($manifest.keyVaultUrls) }

$sstatus = 'OK'
if ($hardcoded.Count -or $manifestSecrets.Count -or $tableFields.Count) { $sstatus = 'GAP' }
elseif ($textHeld.Count -or $notNonDebuggable.Count -or $isoPlain.Count -or $urls.Count) { $sstatus = 'GAP' }
Section 'secrets' $sstatus ([ordered]@{
    runtime = [string]$manifest.runtime
    secretTextAvailable = [bool]$hasSecretText
    hardcoded = $hardcoded
    hardcodedUrls = $urls
    manifestSecrets = $manifestSecrets
    heldAsText = $textHeld
    procedureWithoutNonDebuggable = $notNonDebuggable
    secretTableFields = $tableFields
    isolatedStorageSetNotEncrypted = $isoPlain
    authorizationHeaders = $authHeaders
    keyVaultUrls = $keyVault
    suppressions = $suppressions
})

[ordered]@{ app = $app; name = $manifest.name; version = $manifest.version; sections = $sections } | ConvertTo-Json -Depth 8
exit 0
