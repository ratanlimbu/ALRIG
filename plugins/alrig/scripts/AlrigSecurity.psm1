# Shared by the write guard, the secret scan and the release check, so all three apply the
# same rules. Windows PowerShell 5.1 and PowerShell 7 both: no ?? / ?. / ternaries here.
#
# Nothing project-specific lives in this file. The URL allowlist below is platform hosts only
# (Microsoft help links and XML namespace URIs, which are identifiers rather than endpoints);
# a project adds its own hosts in .claude/alrig.json under security.urlAllowlist.
#
# Nothing here may ever return a secret value. Findings carry a rule, a line and a redaction.

Set-StrictMode -Version 2.0

$script:PlatformUrlHosts = @(
    'go.microsoft.com', 'learn.microsoft.com', 'docs.microsoft.com', 'aka.ms',
    'schemas.microsoft.com', 'schemas.xmlsoap.org', 'www.w3.org'
)

# Words that make an identifier secret-bearing. Kept narrow on purpose: every hit blocks a
# write, and a guard that cries wolf gets uninstalled. A bare `key` is deliberately absent:
# most identifiers ending in Key name a storage key, not a credential.
$script:SecretWordBody = 'password|passwd|passphrase|secret|apikey|api_key|accesskey|access_key|privatekey|private_key|sharedkey|subscriptionkey|encryptionkey|signingkey|hmackey|masterkey|functionkey|hostkey|clientsecret|client_secret|bearertoken|accesstoken|refreshtoken|authtoken|sastoken|connectionstring|token'

# Identifier suffixes that name something *about* a secret rather than the secret itself.
$script:NotASecretSuffix = '(?:url|uri|endpoint|type|name|caption|lbl|txt|tok|err|msg|qst|expir\w*|id|key(?:id|name)|storagekey|scope|header|field|setup|mgt|management|length|len|exists|count|set|valid\w*|format|pattern)$'

$script:Guid = '^\{?[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\}?$'
$script:Placeholder = '^(?:<.*>|\{.*\}|x+|\*+|\.+|changeme|placeholder|dummy|example|test\w*|[^A-Za-z0-9]*(?:%\d+[^A-Za-z0-9]*)+)$'

# Scope 'line'    — matched against the raw line, comments included: a key in a comment is
#                   still committed.
# Scope 'literal' — matched only inside string literals, so `if Password = Confirm then`
#                   is code, not a connection string.
# MinEntropy      — Shannon bits per character the captured value must reach.
$script:SecretRules = @(
    @{ Id = 'private-key';         Scope = 'line'; Regex = '-----BEGIN [A-Z ]*PRIVATE KEY-----' },
    @{ Id = 'aws-access-key';      Scope = 'line'; Regex = '\b(?:AKIA|ASIA)[0-9A-Z]{16}\b' },
    @{ Id = 'github-token';        Scope = 'line'; Regex = '\bgh[pousr]_[A-Za-z0-9]{36,}\b' },
    @{ Id = 'slack-token';         Scope = 'line'; Regex = '\bxox[abprs]-[A-Za-z0-9-]{10,}' },
    @{ Id = 'stripe-key';          Scope = 'line'; Regex = '\b[rs]k_live_[A-Za-z0-9]{16,}\b' },
    @{ Id = 'google-api-key';      Scope = 'line'; Regex = '\bAIza[0-9A-Za-z_-]{35}\b' },
    @{ Id = 'sendgrid-key';        Scope = 'line'; Regex = '\bSG\.[A-Za-z0-9_-]{22}\.[A-Za-z0-9_-]{43}\b' },
    @{ Id = 'entra-client-secret'; Scope = 'line'; Regex = '\b[A-Za-z0-9_~.-]{3}\dQ~[A-Za-z0-9_~.-]{31,34}\b' },
    @{ Id = 'jwt';                 Scope = 'line'; Regex = '\beyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}' },
    @{ Id = 'azure-storage-key';   Scope = 'line'; Regex = '(?i)AccountKey=[A-Za-z0-9+/=]{20,}' },
    @{ Id = 'sas-signature';       Scope = 'line'; Regex = '(?i)[?&;]sig=[A-Za-z0-9%+/=]{20,}' },
    @{ Id = 'auth-header-literal'; Scope = 'line'; Regex = '(?i)''(?:Bearer|Basic)\s+(?<value>[A-Za-z0-9._~+/=-]{16,})''' },
    # AL: SecretName := 'literal'
    @{ Id = 'al-secret-assignment'; Scope = 'line'; MinEntropy = 2.5
       Regex = ('(?i)\b(?<name>\w*(?:' + $script:SecretWordBody + ')\w*)\s*:=\s*''(?<value>[^''\s]{8,})''') },
    # AL: ApiKeyLbl: Label 'literal', Locked = true — the commonest way a key gets committed.
    @{ Id = 'al-secret-label';     Scope = 'line'; MinEntropy = 3.0; NeedsDigitAndLetter = $true
       Regex = ('(?i)\b(?<name>\w*(?:' + $script:SecretWordBody + ')\w*)\s*:\s*Label\s*''(?<value>[A-Za-z0-9+/=_.~-]{16,})''') },
    # AL: Headers.Add('Ocp-Apim-Subscription-Key', 'literal')
    @{ Id = 'header-secret-literal'; Scope = 'line'; MinEntropy = 2.5
       Regex = '(?i)\.(?:Add|TryAddWithoutValidation)\(\s*''[^'']*(?:key|token|secret|authorization|password|signature)[^'']*''\s*,\s*''(?:(?:Bearer|Basic)\s+)?(?<value>[^''\s]{8,})''' },
    # AL: IsolatedStorage.Set('ApiKey', 'literal') — storing a literal defeats the storage.
    @{ Id = 'isolatedstorage-literal'; Scope = 'line'; MinEntropy = 2.5
       Regex = '(?i)IsolatedStorage\.Set(?:Encrypted)?\(\s*''[^'']*''\s*,\s*''(?<value>[^'']{8,})''' },
    @{ Id = 'connection-string-password'; Scope = 'literal'; MinEntropy = 1.5
       Regex = '(?i)\b(?:password|pwd)\s*=\s*(?<value>[^;''"\s{}%$]{4,})' },
    # https://user:password@host — credentials in the URL itself.
    @{ Id = 'url-userinfo';        Scope = 'literal'; UserInfo = $true
       Regex = '(?i)\bhttps?://(?<value>[^@/\s''"]+)@' }
)

function Get-AlrigProfile {
    param([string]$Root = '.')
    $path = Join-Path $Root '.claude/alrig.json'
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    try { return (Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json) }
    catch { return $null }
}

function Get-AlrigUrlAllowlist {
    param($AlrigProfile)
    $hosts = New-Object System.Collections.Generic.List[string]
    foreach ($h in $script:PlatformUrlHosts) { $hosts.Add($h) }
    if ($AlrigProfile -and ($AlrigProfile.PSObject.Properties.Name -contains 'security') -and
        $AlrigProfile.security -and ($AlrigProfile.security.PSObject.Properties.Name -contains 'urlAllowlist')) {
        foreach ($h in @($AlrigProfile.security.urlAllowlist)) {
            if ($h) { $hosts.Add(([string]$h).Trim().ToLowerInvariant()) }
        }
    }
    return ,$hosts.ToArray()
}

function Protect-AlrigSecret {
    # Never print a secret. A short value shows only its length; a long one also shows four
    # characters, which is enough to find it again and too little to use.
    param([string]$Value)
    if (-not $Value) { return '' }
    if ($Value.Length -ge 16) { return ($Value.Substring(0, 4) + '...(' + $Value.Length + ' chars)') }
    return ('(' + $Value.Length + ' chars)')
}

function Get-AlrigEntropy {
    param([string]$Value)
    if (-not $Value) { return 0.0 }
    $counts = @{}
    foreach ($ch in $Value.ToCharArray()) { if ($counts.ContainsKey($ch)) { $counts[$ch]++ } else { $counts[$ch] = 1 } }
    $e = 0.0
    foreach ($n in $counts.Values) { $p = $n / $Value.Length; $e -= $p * [Math]::Log($p, 2) }
    return $e
}

function Test-AlrigNotASecretName {
    param([string]$Name)
    if (-not $Name) { return $false }
    return ($Name -match ('(?i)' + $script:NotASecretSuffix))
}

function Get-AlrigLineLiterals {
    <#
      One pass over the text that knows about strings and comments together, so a /* inside a
      string or a // comment cannot hide the code after it. Returns, per line, the contents of
      its string literals.

      AL mode (default): '...' with '' as the escaped quote; // and /* */ comments. "..." is an
      identifier in AL, not a string.
      -Plain mode (JSON, YAML, scripts): '...' and "..." with backslash escapes; no comments.
    #>
    param([string[]]$Lines, [switch]$Plain)
    $result = New-Object System.Collections.Generic.List[object]
    $inBlock = $false
    foreach ($line in $Lines) {
        $lits = New-Object System.Collections.Generic.List[string]
        $i = 0; $len = $line.Length
        while ($i -lt $len) {
            if ($inBlock) {
                $end = $line.IndexOf('*/', $i)
                if ($end -lt 0) { $i = $len } else { $i = $end + 2; $inBlock = $false }
                continue
            }
            $ch = $line[$i]
            $next = [char]0; if ($i + 1 -lt $len) { $next = $line[$i + 1] }
            if (-not $Plain -and $ch -eq '/' -and $next -eq '/') { break }
            if (-not $Plain -and $ch -eq '/' -and $next -eq '*') { $inBlock = $true; $i += 2; continue }
            if ($ch -eq "'" -or ($Plain -and $ch -eq '"')) {
                $q = $ch; $sb = New-Object System.Text.StringBuilder; $j = $i + 1
                while ($j -lt $len) {
                    $c = $line[$j]
                    if ($Plain -and $c -eq '\' -and $j + 1 -lt $len) { [void]$sb.Append($line[$j + 1]); $j += 2; continue }
                    if ($c -eq $q) {
                        if (-not $Plain -and $j + 1 -lt $len -and $line[$j + 1] -eq $q) { [void]$sb.Append($q); $j += 2; continue }
                        break
                    }
                    [void]$sb.Append($c); $j++
                }
                $lits.Add($sb.ToString()); $i = $j + 1; continue
            }
            $i++
        }
        $result.Add($lits.ToArray())
    }
    return ,$result
}

function Test-AlrigCandidate {
    param($Rule, $Match)
    if ($Match.Groups['name'].Success) {
        $name = $Match.Groups['name'].Value
        # A label's own suffix (ApiKeyLbl) is its naming convention, not a hint that it holds
        # something other than the key.
        if ($Rule.Id -eq 'al-secret-label') { $name = $name -replace '(?i)(?:lbl|txt|tok)$', '' }
        if (Test-AlrigNotASecretName $name) { return $null }
    }
    $value = $Match.Value
    if ($Match.Groups['value'].Success) {
        $value = $Match.Groups['value'].Value
        if ($value -match $script:Placeholder -or $value -match $script:Guid -or $value -match '^(?i)https?://') { return $null }
        if ($Rule.ContainsKey('MinEntropy') -and (Get-AlrigEntropy $value) -lt $Rule.MinEntropy) { return $null }
        if ($Rule.ContainsKey('NeedsDigitAndLetter') -and -not ($value -match '[0-9]' -and $value -match '[A-Za-z]')) { return $null }
        # user:password@ always; a bare user@ only when it looks like a token, not a host name.
        if ($Rule.ContainsKey('UserInfo') -and -not ($value.Contains(':') -or ($value.Length -ge 16 -and -not $value.Contains('.')))) { return $null }
    }
    return $value
}

function Find-AlrigSecrets {
    <#
      Scans text for hardcoded credentials. Returns objects with Line (1-based, within the text),
      Rule and Redacted. A line carrying `alrig:allow-secret` is skipped; the release check lists
      every such marker, so a suppression is always visible to a reviewer. -Plain for non-AL files.
    #>
    param([string]$Text, [switch]$Plain)
    $out = New-Object System.Collections.Generic.List[object]
    if (-not $Text) { return ,$out.ToArray() }
    $lines = $Text -split "`r?`n"
    $literals = Get-AlrigLineLiterals -Lines $lines -Plain:$Plain
    for ($i = 0; $i -lt $lines.Length; $i++) {
        $line = $lines[$i]
        if ($line -match 'alrig:allow-secret') { continue }
        $hit = $null
        foreach ($rule in $script:SecretRules) {
            $targets = @($line)
            if ($rule.Scope -eq 'literal') { $targets = @($literals[$i]) }
            foreach ($t in $targets) {
                foreach ($m in [regex]::Matches([string]$t, $rule.Regex)) {
                    $v = Test-AlrigCandidate $rule $m
                    if ($v) { $hit = [pscustomobject]@{ Line = $i + 1; Rule = $rule.Id; Redacted = (Protect-AlrigSecret $v) }; break }
                }
                if ($hit) { break }
            }
            if ($hit) { break }
        }
        if ($hit) { $out.Add($hit) }
    }
    return ,$out.ToArray()
}

function Test-AlrigHostAllowed {
    param([string]$UrlHost, [string[]]$Allowlist)
    $h = $UrlHost.ToLowerInvariant().TrimEnd('.')
    foreach ($a in $Allowlist) {
        $a = $a.ToLowerInvariant().TrimStart('*').TrimStart('.')
        if ($h -eq $a -or $h.EndsWith('.' + $a)) { return $true }
    }
    return $false
}

function Find-AlrigUrls {
    <#
      Hardcoded endpoints in AL string literals. Comments are skipped (a link in a comment is
      documentation, not a call). The host is taken after any user:password@ part, so neither a
      credential nor an allowlisted name in front of the @ is mistaken for the host. A line
      carrying `alrig:allow-url` is skipped.
    #>
    param([string]$Text, [string[]]$Allowlist)
    $out = New-Object System.Collections.Generic.List[object]
    if (-not $Text) { return ,$out.ToArray() }
    $lines = $Text -split "`r?`n"
    $literals = Get-AlrigLineLiterals -Lines $lines
    for ($i = 0; $i -lt $lines.Length; $i++) {
        if ($lines[$i] -match 'alrig:allow-url') { continue }
        foreach ($lit in @($literals[$i])) {
            foreach ($m in [regex]::Matches([string]$lit, '(?i)\bhttps?://(?:[^@/\s]*@)?(?<host>[A-Za-z0-9.-]+)')) {
                $urlHost = $m.Groups['host'].Value.ToLowerInvariant()
                if (Test-AlrigHostAllowed $urlHost $Allowlist) { continue }
                $out.Add([pscustomobject]@{ Line = $i + 1; Rule = 'hardcoded-url'; Host = $urlHost })
            }
        }
    }
    return ,$out.ToArray()
}

function Get-AlrigAlFiles {
    param([string]$Path)
    $skip = '[\\/](?:\.alpackages|\.snapshots|\.output|\.artifacts|\.git|node_modules)[\\/]'
    return @(Get-ChildItem -LiteralPath $Path -Recurse -File -Filter '*.al' -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch $skip })
}

function Read-AlrigJsonc {
    <#
      .vscode/settings.json and rulesets allow // and /* */ comments and trailing commas. One
      string-aware pass, so "**/*.app" or "https://..." inside a value survives. Throws when the
      result still does not parse; callers decide how loudly to degrade.
    #>
    param([string]$Path)
    $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    $sb = New-Object System.Text.StringBuilder
    $i = 0; $len = $raw.Length; $inStr = $false
    while ($i -lt $len) {
        $ch = $raw[$i]
        $next = [char]0; if ($i + 1 -lt $len) { $next = $raw[$i + 1] }
        if ($inStr) {
            [void]$sb.Append($ch)
            if ($ch -eq '\' -and $i + 1 -lt $len) { [void]$sb.Append($next); $i += 2; continue }
            if ($ch -eq '"') { $inStr = $false }
            $i++; continue
        }
        if ($ch -eq '"') { $inStr = $true; [void]$sb.Append($ch); $i++; continue }
        if ($ch -eq '/' -and $next -eq '/') { $nl = $raw.IndexOf("`n", $i); if ($nl -lt 0) { $i = $len } else { $i = $nl }; continue }
        if ($ch -eq '/' -and $next -eq '*') { $end = $raw.IndexOf('*/', $i + 2); if ($end -lt 0) { $i = $len } else { $i = $end + 2 }; continue }
        if ($ch -eq ',') {
            # A trailing comma: the next significant character closes the object or array.
            $k = $i + 1
            while ($k -lt $len) {
                if ([char]::IsWhiteSpace($raw[$k])) { $k++; continue }
                if ($raw[$k] -eq '/' -and $k + 1 -lt $len -and $raw[$k + 1] -eq '/') { $nl = $raw.IndexOf("`n", $k); if ($nl -lt 0) { $k = $len } else { $k = $nl }; continue }
                if ($raw[$k] -eq '/' -and $k + 1 -lt $len -and $raw[$k + 1] -eq '*') { $e = $raw.IndexOf('*/', $k + 2); if ($e -lt 0) { $k = $len } else { $k = $e + 2 }; continue }
                break
            }
            if ($k -lt $len -and ($raw[$k] -eq '}' -or $raw[$k] -eq ']')) { $i++; continue }
        }
        [void]$sb.Append($ch); $i++
    }
    return ($sb.ToString() | ConvertFrom-Json)
}

function Invoke-AlrigGit {
    # Windows PowerShell turns a native command's stderr into a terminating error under
    # ErrorActionPreference Stop, even with 2>$null. Returns stdout lines; nothing on failure.
    # Wrap calls in @().
    param([string]$Dir, [Parameter(ValueFromRemainingArguments = $true)][string[]]$GitArgs)
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $out = & git -C $Dir @GitArgs 2>$null
        if ($LASTEXITCODE -ne 0) { return }
        return $out
    } catch { return }
    finally { $ErrorActionPreference = $prev }
}

Export-ModuleMember -Function Invoke-AlrigGit, Get-AlrigProfile, Get-AlrigUrlAllowlist, Protect-AlrigSecret,
    Find-AlrigSecrets, Find-AlrigUrls, Test-AlrigHostAllowed, Test-AlrigNotASecretName,
    Get-AlrigAlFiles, Read-AlrigJsonc, Get-AlrigEntropy, Get-AlrigLineLiterals
